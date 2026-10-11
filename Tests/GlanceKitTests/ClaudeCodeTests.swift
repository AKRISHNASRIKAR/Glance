import Foundation
import Testing
@testable import GlanceKit

struct ClaudeCodeNormalizerTests {
    @Test func fileNamesMapToEventKinds() {
        #expect(ClaudeCodeEventNormalizer.normalize(fileName: "sessionstart-Ab12Cd.json", contents: nil)?.kind == .sessionStart)
        #expect(ClaudeCodeEventNormalizer.normalize(fileName: "prompt-Xy98Zw.marker", contents: nil)?.kind == .promptSubmitted)
        #expect(ClaudeCodeEventNormalizer.normalize(fileName: "tool-Qq11Ww.marker", contents: nil)?.kind == .toolActivity)
        #expect(ClaudeCodeEventNormalizer.normalize(fileName: "notification-Ee22Rr.json", contents: nil)?.kind == .notification)
        #expect(ClaudeCodeEventNormalizer.normalize(fileName: "stop-Tt33Yy.json", contents: nil)?.kind == .stop)
        #expect(ClaudeCodeEventNormalizer.normalize(fileName: "sessionend-Uu44Ii.json", contents: nil)?.kind == .sessionEnd)
        #expect(ClaudeCodeEventNormalizer.normalize(fileName: "garbage-Oo55Pp.json", contents: nil) == nil)
    }

    @Test func jsonPayloadYieldsSessionAndMessage() {
        let payload = Data(#"{"session_id": "abc-123", "message": "Claude needs your permission to use Bash"}"#.utf8)
        let event = ClaudeCodeEventNormalizer.normalize(fileName: "notification-Aa00Bb.json", contents: payload)
        #expect(event?.sessionID == "abc-123")
        #expect(event?.message == "Claude needs your permission to use Bash")
    }

    @Test func messageIsOnlyKeptForNotifications() {
        let payload = Data(#"{"session_id": "abc", "message": "should be ignored"}"#.utf8)
        let event = ClaudeCodeEventNormalizer.normalize(fileName: "stop-Aa00Bb.json", contents: payload)
        #expect(event?.message == nil)
    }
}

struct ClaudeCodeStateMachineTests {
    private func event(_ kind: ClaudeCodeEventKind, message: String? = nil, at seconds: TimeInterval = 0) -> ClaudeCodeEvent {
        ClaudeCodeEvent(kind: kind, message: message, receivedAt: Date(timeIntervalSince1970: 1_700_000_000 + seconds))
    }

    @Test func workingThenStopIsCompletedWithDuration() {
        var machine = ClaudeCodeStateMachine()
        machine.apply(event(.sessionStart, at: 0))
        machine.apply(event(.promptSubmitted, at: 10))
        #expect(machine.state == .working)
        machine.apply(event(.toolActivity, at: 60))
        #expect(machine.state == .working)
        machine.apply(event(.stop, at: 192))
        #expect(machine.state == .completed)
        #expect(machine.lastCompletedDuration == 182)
    }

    @Test func notificationMessageDistinguishesPermissionFromInput() {
        var machine = ClaudeCodeStateMachine()
        machine.apply(event(.notification, message: "Claude needs your permission to use Bash"))
        #expect(machine.state == .permissionRequired)
        machine.apply(event(.notification, message: "Claude is waiting for your input"))
        #expect(machine.state == .needsInput)
    }

    @Test func sessionEndResetsToIdle() {
        var machine = ClaudeCodeStateMachine()
        machine.apply(event(.promptSubmitted))
        machine.apply(event(.sessionEnd))
        #expect(machine.state == .idle)
        #expect(machine.sessionID == nil)
    }

    /// A SessionEnd from an unrelated, concurrent Claude Code session (a
    /// different terminal/project — the documented "multiple sessions" v0
    /// limitation) must never reset the session Glance is actually
    /// following, or silently drop its still-pending persistent alert.
    @Test func sessionEndFromADifferentSessionIsIgnored() {
        var machine = ClaudeCodeStateMachine()
        machine.apply(ClaudeCodeEvent(kind: .sessionStart, sessionID: "session-A"))
        machine.apply(ClaudeCodeEvent(kind: .notification, sessionID: "session-A", message: "Claude needs your permission to use Bash"))
        #expect(machine.state == .permissionRequired)

        machine.apply(ClaudeCodeEvent(kind: .sessionEnd, sessionID: "session-B"))
        #expect(machine.state == .permissionRequired, "an unrelated session's end must not clear this one's pending alert")
        #expect(machine.sessionID == "session-A")

        machine.apply(ClaudeCodeEvent(kind: .sessionEnd, sessionID: "session-A"))
        #expect(machine.state == .idle)
        #expect(machine.sessionID == nil)
    }

    /// The cross-session guard isn't SessionEnd-specific: any event kind
    /// from an unrelated concurrent session must be a complete no-op,
    /// otherwise a stray Notification/Stop/marker from session B could
    /// still silently reassign which session Glance is tracking (and, by
    /// extension, misdirect the staleness fallback at the wrong session).
    @Test func eventsFromADifferentSessionAreCompletelyIgnored() {
        var machine = ClaudeCodeStateMachine()
        machine.apply(ClaudeCodeEvent(kind: .sessionStart, sessionID: "session-A"))
        machine.apply(ClaudeCodeEvent(kind: .notification, sessionID: "session-A", message: "waiting for your input"))
        #expect(machine.state == .needsInput)

        machine.apply(ClaudeCodeEvent(kind: .promptSubmitted, sessionID: "session-B"))
        #expect(machine.state == .needsInput, "session B's activity must not touch session A's tracked state")
        #expect(machine.sessionID == "session-A")

        machine.apply(ClaudeCodeEvent(kind: .notification, sessionID: "session-B", message: "needs your permission"))
        #expect(machine.state == .needsInput, "session B's notification must not override session A's pending state")
        #expect(machine.sessionID == "session-A")

        // Session A resuming normally still works.
        machine.apply(ClaudeCodeEvent(kind: .promptSubmitted, sessionID: "session-A"))
        #expect(machine.state == .working)
    }

    /// A Notification originating inside a subagent (agent_id present)
    /// should be labeled as such, not surfaced as an ambiguous "Claude needs
    /// you" — the user needs to know it's a spawned subagent waiting, not
    /// the main conversation.
    @Test func notificationFromSubagentIsLabeled() {
        var machine = ClaudeCodeStateMachine()
        machine.apply(ClaudeCodeEvent(kind: .notification, agentID: "sub-1", agentType: "Explore", message: "needs your permission"))
        #expect(machine.state == .permissionRequired)
        #expect(machine.attentionAgentType == "Explore")

        machine.apply(ClaudeCodeEvent(kind: .notification, message: "waiting for your input"))
        #expect(machine.attentionAgentType == nil, "main-session notifications carry no agent_id")
    }
}

@MainActor
struct ClaudeCodeProviderTests {
    /// "Needs input" grabs attention (important priority, a generous 60 s
    /// window) but is deliberately bounded rather than persistent forever —
    /// see `ClaudeCodeProvider.attentionDisplayDuration`: a user who's
    /// stepped away for good shouldn't have the notch stuck wide open
    /// indefinitely. The Claude Screen still reflects the real state for as
    /// long as it's true; only this attention-grabbing notch surface times out.
    @Test func needsInputEmitsBoundedImportantInterruption() {
        let clock = TestClock()
        let (settings, _) = makeTestSettingsStore(clock: clock)
        let provider = ClaudeCodeProvider(settings: settings, timeSource: clock, scheduler: clock)
        var emitted: [NotchInterruption] = []
        provider.emitInterruption = { emitted.append($0) }
        provider.apply(ClaudeCodeEvent(kind: .notification, message: "Claude is waiting for your input"))
        #expect(emitted.count == 1)
        #expect(emitted.first?.kind == "needs-input")
        #expect(emitted.first?.priority == .important)
        #expect(emitted.first?.isPersistent == false)
        #expect(emitted.first?.displayDuration == ClaudeCodeProvider.attentionDisplayDuration)
        #expect(emitted.first?.actions.first?.title == "Open Claude")
    }

    /// The notch's peek surface must actually recede after the bounded
    /// window — not just carry the right flag — even if nobody ever
    /// resolves the underlying condition.
    @Test func needsInputRecedesFromTheNotchAfterItsWindow() {
        let clock = TestClock()
        let (settings, _) = makeTestSettingsStore(clock: clock)
        let provider = ClaudeCodeProvider(settings: settings, timeSource: clock, scheduler: clock)
        let interruptions = InterruptionEngine(scheduler: clock, timeSource: clock)
        provider.emitInterruption = { interruptions.present($0) }
        provider.apply(ClaudeCodeEvent(kind: .notification, message: "Claude is waiting for your input"))
        #expect(interruptions.current?.kind == "needs-input")
        clock.advance(by: ClaudeCodeProvider.attentionDisplayDuration + 1)
        #expect(interruptions.current == nil)
    }

    @Test func needsInputFromSubagentNamesItInTheSubtitle() {
        let clock = TestClock()
        let (settings, _) = makeTestSettingsStore(clock: clock)
        let provider = ClaudeCodeProvider(settings: settings, timeSource: clock, scheduler: clock)
        var emitted: [NotchInterruption] = []
        provider.emitInterruption = { emitted.append($0) }
        provider.apply(ClaudeCodeEvent(kind: .notification, agentID: "sub-1", agentType: "Explore", message: "waiting for your input"))
        #expect(emitted.first?.subtitle == "Explore is waiting for you")
    }

    /// The real bug this guards against: the terminal gets force-closed (or
    /// the machine sleeps through it) instead of Claude Code exiting
    /// gracefully, so SessionEnd never fires — without a fallback,
    /// "needs your input" would say that forever even though no session is
    /// running any more.
    @Test func needsInputFallsBackToIdleWhenTheSessionGoesSilent() {
        let clock = TestClock()
        let (settings, _) = makeTestSettingsStore(clock: clock)
        let provider = ClaudeCodeProvider(settings: settings, timeSource: clock, scheduler: clock)
        provider.emitInterruption = { _ in }
        var resolved: [String?] = []
        provider.resolveInterruption = { resolved.append($0) }

        provider.apply(ClaudeCodeEvent(kind: .notification, sessionID: "abc", message: "waiting for your input"))
        #expect(provider.machine.state == .needsInput)

        clock.advance(by: ClaudeCodeProvider.stalenessTimeout - 1)
        #expect(provider.machine.state == .needsInput, "must not fire early")

        clock.advance(by: 2)
        #expect(provider.machine.state == .idle)
        #expect(resolved == ["needs-input"])
    }

    /// Any hook event at all — even one that doesn't change the reported
    /// state — is fresh proof the session is still alive and must push the
    /// staleness fallback back out, not just events that cause a transition.
    @Test func repeatedNotificationsPostponeTheStalenessFallback() {
        let clock = TestClock()
        let (settings, _) = makeTestSettingsStore(clock: clock)
        let provider = ClaudeCodeProvider(settings: settings, timeSource: clock, scheduler: clock)
        provider.emitInterruption = { _ in }

        provider.apply(ClaudeCodeEvent(kind: .notification, sessionID: "abc", message: "waiting for your input"))
        clock.advance(by: ClaudeCodeProvider.stalenessTimeout - 1)
        provider.apply(ClaudeCodeEvent(kind: .notification, sessionID: "abc", message: "waiting for your input"))
        clock.advance(by: ClaudeCodeProvider.stalenessTimeout - 1)
        #expect(provider.machine.state == .needsInput, "the second notification should have reset the clock")
    }

    /// `.working` is deliberately exempt: a single long tool call can
    /// legitimately produce no hook activity for a long stretch, and that
    /// alone isn't evidence the session is gone.
    @Test func workingNeverFallsBackToIdleFromSilenceAlone() {
        let clock = TestClock()
        let (settings, _) = makeTestSettingsStore(clock: clock)
        let provider = ClaudeCodeProvider(settings: settings, timeSource: clock, scheduler: clock)
        provider.emitInterruption = { _ in }
        provider.apply(ClaudeCodeEvent(kind: .promptSubmitted, sessionID: "abc"))
        clock.advance(by: ClaudeCodeProvider.stalenessTimeout * 3)
        #expect(provider.machine.state == .working)
    }

    @Test func resolvingHappensWhenClaudeResumesWorking() {
        let clock = TestClock()
        let (settings, _) = makeTestSettingsStore(clock: clock)
        let provider = ClaudeCodeProvider(settings: settings, timeSource: clock, scheduler: clock)
        var resolved: [String?] = []
        provider.emitInterruption = { _ in }
        provider.resolveInterruption = { resolved.append($0) }
        provider.apply(ClaudeCodeEvent(kind: .notification, message: "waiting for input"))
        provider.apply(ClaudeCodeEvent(kind: .promptSubmitted))
        #expect(resolved == ["needs-input"])
    }

    @Test func completionInterruptionIncludesDuration() {
        let clock = TestClock()
        let (settings, _) = makeTestSettingsStore(clock: clock)
        let provider = ClaudeCodeProvider(settings: settings, timeSource: clock, scheduler: clock)
        var emitted: [NotchInterruption] = []
        provider.emitInterruption = { emitted.append($0) }
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        provider.apply(ClaudeCodeEvent(kind: .promptSubmitted, receivedAt: base))
        provider.apply(ClaudeCodeEvent(kind: .stop, receivedAt: base.addingTimeInterval(192)))
        #expect(emitted.count == 1)
        #expect(emitted.first?.kind == "completed")
        #expect(emitted.first?.subtitle == "Finished in 3m 12s")
    }

    @Test func settingsGateEachInterruptionKind() {
        let clock = TestClock()
        let (settings, _) = makeTestSettingsStore(clock: clock)
        settings.update { $0.claudeCode.interruptOnCompleted = false }
        let provider = ClaudeCodeProvider(settings: settings, timeSource: clock, scheduler: clock)
        var emitted: [NotchInterruption] = []
        provider.emitInterruption = { emitted.append($0) }
        provider.apply(ClaudeCodeEvent(kind: .promptSubmitted))
        provider.apply(ClaudeCodeEvent(kind: .stop))
        #expect(emitted.isEmpty)
    }

    @Test func spoolDrainNormalizesAndDeletesFiles() throws {
        let clock = TestClock()
        let (settings, _) = makeTestSettingsStore(clock: clock)
        let spool = makeTempDirectory()
        let installer = ClaudeCodeHookInstaller(
            claudeSettingsURL: makeTempDirectory().appendingPathComponent("settings.json"),
            spoolDirectoryURL: spool
        )
        let provider = ClaudeCodeProvider(settings: settings, installer: installer, timeSource: clock, scheduler: clock)
        var emitted: [NotchInterruption] = []
        provider.emitInterruption = { emitted.append($0) }

        try Data().write(to: spool.appendingPathComponent("prompt-Aa11.marker"))
        provider.drainSpool()
        #expect(provider.machine.state == .working)
        #expect(try FileManager.default.contentsOfDirectory(atPath: spool.path).isEmpty)
    }
}

struct HookInstallerTests {
    private func makeInstaller() -> (ClaudeCodeHookInstaller, URL) {
        let dir = makeTempDirectory()
        let installer = ClaudeCodeHookInstaller(
            claudeSettingsURL: dir.appendingPathComponent("settings.json"),
            spoolDirectoryURL: dir.appendingPathComponent("spool", isDirectory: true)
        )
        return (installer, dir)
    }

    private func readJSON(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    @Test func installCreatesHooksInFreshSettings() throws {
        let (installer, _) = makeInstaller()
        try installer.install()
        #expect(installer.isInstalled)
        let root = try readJSON(installer.claudeSettingsURL)
        let hooks = root["hooks"] as! [String: Any]
        for event in ["SessionStart", "UserPromptSubmit", "PreToolUse", "Notification", "Stop", "SessionEnd"] {
            #expect(hooks[event] != nil, "missing hook for \(event)")
        }
    }

    @Test func installPreservesExistingSettingsAndBacksUp() throws {
        let (installer, dir) = makeInstaller()
        let existing: [String: Any] = [
            "model": "opus",
            "hooks": [
                "Stop": [["hooks": [["type": "command", "command": "echo user-hook"]]]]
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: existing)
        try data.write(to: installer.claudeSettingsURL)

        let backupURL = try installer.install()
        #expect(backupURL != nil)
        #expect(FileManager.default.fileExists(atPath: backupURL!.path))

        let root = try readJSON(installer.claudeSettingsURL)
        #expect(root["model"] as? String == "opus")
        let stopMatchers = (root["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
        #expect(stopMatchers.count == 2) // user's hook + ours
        let commands = stopMatchers.flatMap { ($0["hooks"] as! [[String: Any]]).compactMap { $0["command"] as? String } }
        #expect(commands.contains("echo user-hook"))
        _ = dir
    }

    @Test func installIsIdempotent() throws {
        let (installer, _) = makeInstaller()
        try installer.install()
        try installer.install()
        let root = try readJSON(installer.claudeSettingsURL)
        let stopMatchers = (root["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
        #expect(stopMatchers.count == 1)
    }

    @Test func uninstallRemovesOnlyGlanceHooks() throws {
        let (installer, _) = makeInstaller()
        let existing: [String: Any] = [
            "hooks": [
                "Stop": [["hooks": [["type": "command", "command": "echo user-hook"]]]]
            ],
        ]
        try JSONSerialization.data(withJSONObject: existing).write(to: installer.claudeSettingsURL)
        try installer.install()
        try installer.uninstall()
        #expect(!installer.isInstalled)
        let root = try readJSON(installer.claudeSettingsURL)
        let stopMatchers = (root["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
        #expect(stopMatchers.count == 1)
        let command = ((stopMatchers[0]["hooks"] as! [[String: Any]])[0]["command"] as! String)
        #expect(command == "echo user-hook")
    }

    @Test func promptAndToolHooksDiscardStdin() {
        let (installer, _) = makeInstaller()
        for definition in installer.hookDefinitions() where ["UserPromptSubmit", "PreToolUse"].contains(definition.event) {
            #expect(definition.command.contains("cat > /dev/null"), "\(definition.event) must not persist stdin")
            #expect(definition.command.contains(".marker"), "\(definition.event) should write empty markers")
        }
    }

    @Test func formatDurationIsHumanReadable() {
        #expect(ClaudeCodeProvider.formatDuration(45) == "45s")
        #expect(ClaudeCodeProvider.formatDuration(192) == "3m 12s")
        #expect(ClaudeCodeProvider.formatDuration(3900) == "1h 5m")
    }
}

@MainActor
struct ProviderIsolationTests {
    /// A provider whose start() reports an error — the engine must keep
    /// other providers running.
    @MainActor
    final class BrokenProvider: ActivityProvider {
        let id = "broken"
        var status: ProviderStatus = .disabled
        var emitInterruption: (@MainActor (NotchInterruption) -> Void)?
        var resolveInterruption: (@MainActor (String?) -> Void)?
        func start() { status = .error("simulated failure") }
        func stop() { status = .disabled }
    }

    @MainActor
    final class HealthyProvider: ActivityProvider {
        let id = "healthy"
        var status: ProviderStatus = .disabled
        var emitInterruption: (@MainActor (NotchInterruption) -> Void)?
        var resolveInterruption: (@MainActor (String?) -> Void)?
        var started = false
        func start() { started = true; status = .running }
        func stop() { started = false; status = .disabled }
    }

    @Test func brokenProviderDoesNotAffectHealthyOne() {
        let clock = TestClock()
        let (settings, _) = makeTestSettingsStore(clock: clock)
        let engine = ActivityEngine(settings: settings, interruptions: InterruptionEngine(scheduler: clock, timeSource: clock), scheduler: clock)
        let broken = BrokenProvider()
        let healthy = HealthyProvider()
        engine.register(broken) { _ in true }
        engine.register(healthy) { _ in true }
        #expect(healthy.started)
        #expect(engine.providerStatuses["broken"] == .error("simulated failure"))
        #expect(engine.providerStatuses["healthy"] == .running)
    }

    @Test func providersStartAndStopWithSettingsToggle() {
        let clock = TestClock()
        let (settings, _) = makeTestSettingsStore(clock: clock)
        let engine = ActivityEngine(settings: settings, interruptions: InterruptionEngine(scheduler: clock, timeSource: clock), scheduler: clock)
        let provider = HealthyProvider()
        engine.register(provider) { $0.battery.isEnabled }
        #expect(!provider.started)
        settings.update { $0.battery.isEnabled = true }
        #expect(provider.started)
        settings.update { $0.battery.isEnabled = false }
        #expect(!provider.started)
        #expect(engine.providerStatuses["healthy"] == .disabled)
    }

    @Test func stoppingProviderClearsItsInterruptions() {
        let clock = TestClock()
        let (settings, _) = makeTestSettingsStore(clock: clock)
        let interruptions = InterruptionEngine(scheduler: clock, timeSource: clock)
        let engine = ActivityEngine(settings: settings, interruptions: interruptions, scheduler: clock)
        let provider = HealthyProvider()
        engine.register(provider) { $0.battery.isEnabled }
        settings.update { $0.battery.isEnabled = true }
        provider.emitInterruption?(NotchInterruption(
            provider: "healthy", kind: "x", title: "X", priority: .important, isPersistent: true
        ))
        #expect(interruptions.current != nil)
        settings.update { $0.battery.isEnabled = false }
        #expect(interruptions.current == nil)
    }
}
