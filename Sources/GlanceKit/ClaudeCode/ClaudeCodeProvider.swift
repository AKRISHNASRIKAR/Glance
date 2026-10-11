import Foundation

/// Claude Code activity provider.
///
///     Claude Code → official hook → spool file → this provider →
///     Activity Engine → Claude Screen / Notch Interruption
///
/// Watches the spool directory with a dispatch file-system source
/// (event-driven, no polling), normalizes events, folds them through the
/// state machine, and emits interruptions per the user's settings.
/// Spool files are deleted immediately after normalization; only the typed
/// state and session durations remain in memory.
@MainActor
public final class ClaudeCodeProvider: ActivityProvider, ObservableObject {
    public let id = "claude-code"
    public private(set) var status: ProviderStatus = .disabled

    public var emitInterruption: (@MainActor (NotchInterruption) -> Void)?
    public var resolveInterruption: (@MainActor (String?) -> Void)?

    @Published public private(set) var machine = ClaudeCodeStateMachine()

    public let installer: ClaudeCodeHookInstaller

    private var directorySource: DispatchSourceFileSystemObject?
    private var directoryDescriptor: CInt = -1
    private let settings: SettingsStore
    private let timeSource: TimeSource
    private let scheduler: GlanceScheduler
    private var stalenessHandle: GlanceCancellable?

    public init(
        settings: SettingsStore,
        installer: ClaudeCodeHookInstaller = ClaudeCodeHookInstaller(),
        timeSource: TimeSource = SystemTimeSource(),
        scheduler: GlanceScheduler = TimerScheduler()
    ) {
        self.settings = settings
        self.installer = installer
        self.timeSource = timeSource
        self.scheduler = scheduler
    }

    public func start() {
        guard installer.isInstalled else {
            status = .notConfigured
            return
        }
        do {
            try FileManager.default.createDirectory(at: installer.spoolDirectoryURL, withIntermediateDirectories: true)
        } catch {
            status = .error("Cannot create event directory")
            return
        }
        startWatching()
        drainSpool()
        status = .running
    }

    public func stop() {
        directorySource?.cancel()
        directorySource = nil
        machine = ClaudeCodeStateMachine()
        stalenessHandle?.cancel()
        stalenessHandle = nil
        status = .disabled
    }

    /// Re-check configuration after the user runs the installer.
    public func refreshConfiguration() {
        if status == .notConfigured, installer.isInstalled {
            start()
        } else if status.isRunning, !installer.isInstalled {
            stop()
            status = .notConfigured
        }
    }

    // MARK: Spool watching (event-driven)

    private func startWatching() {
        let path = installer.spoolDirectoryURL.path
        directoryDescriptor = open(path, O_EVTONLY)
        guard directoryDescriptor >= 0 else {
            status = .error("Cannot watch event directory")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryDescriptor,
            eventMask: .write,
            queue: .main
        )
        let descriptor = directoryDescriptor
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.drainSpool() }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        directorySource = source
    }

    /// Read, normalize, and delete all spooled event files in name order
    /// (mktemp prefixes preserve event kind; order within a burst is
    /// resolved by file creation date).
    func drainSpool() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: installer.spoolDirectoryURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let sorted = entries.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return l < r
        }

        for file in sorted {
            let contents = try? Data(contentsOf: file)
            try? fm.removeItem(at: file)
            guard let event = ClaudeCodeEventNormalizer.normalize(
                fileName: file.lastPathComponent,
                contents: contents,
                at: timeSource.now
            ) else { continue }
            apply(event)
        }
    }

    /// Testable event application: state transitions + interruption policy.
    public func apply(_ event: ClaudeCodeEvent) {
        let previous = machine.state
        machine.apply(event)
        let current = machine.state
        // Runs on every event, not just ones that change state: any hook
        // activity at all — even a repeated Notification — is fresh proof
        // the session is still alive, and should push the staleness
        // fallback back out.
        scheduleStalenessFallback()
        guard current != previous else { return }

        let config = settings.settings.claudeCode

        // Leaving an attention state resolves its persistent interruption.
        if previous == .needsInput { resolveInterruption?("needs-input") }
        if previous == .permissionRequired { resolveInterruption?("permission-required") }

        switch current {
        case .needsInput:
            guard config.interruptOnNeedsInput else { return }
            emitInterruption?(NotchInterruption(
                provider: id, kind: "needs-input",
                title: "Claude · Needs input",
                subtitle: machine.attentionAgentType.map { "\($0) is waiting for you" } ?? "Claude is waiting for you",
                symbolName: "bubble.left.and.exclamationmark.bubble.right",
                priority: .important,
                // Bounded, not persistent: if Claude resumes first, the
                // transition away from .needsInput resolves this immediately
                // (see above). If nobody responds, it should still recede on
                // its own after a while rather than holding the notch open
                // indefinitely — the Claude Screen still shows "Needs input"
                // for as long as it's actually true; only this attention-
                // grabbing surface times out.
                displayDuration: Self.attentionDisplayDuration,
                actions: [openTerminalAction()]
            ))
        case .permissionRequired:
            guard config.interruptOnPermissionRequired else { return }
            let subtitle = event.message ?? machine.attentionAgentType.map { "\($0) needs your permission" }
                ?? "Claude needs your permission"
            emitInterruption?(NotchInterruption(
                provider: id, kind: "permission-required",
                title: "Claude · Permission",
                subtitle: subtitle,
                symbolName: "lock.shield",
                priority: .important,
                displayDuration: Self.attentionDisplayDuration,
                actions: [openTerminalAction()],
                privacy: .sensitive
            ))
        case .completed:
            guard config.interruptOnCompleted else { return }
            let duration = machine.lastCompletedDuration.map(Self.formatDuration)
            emitInterruption?(NotchInterruption(
                provider: id, kind: "completed",
                title: "Claude · Completed",
                subtitle: duration.map { "Finished in \($0)" } ?? "Task finished",
                symbolName: "checkmark.circle.fill",
                priority: .important,
                displayDuration: 5
            ))
        case .failed:
            // Never produced by the current hook integration; kept for a
            // future hook that reports failures reliably.
            guard config.interruptOnFailed else { return }
            emitInterruption?(NotchInterruption(
                provider: id, kind: "failed",
                title: "Claude · Failed",
                subtitle: "Task requires attention",
                symbolName: "exclamationmark.triangle.fill",
                priority: .important,
                displayDuration: 6
            ))
        case .idle, .working:
            break
        }
    }

    /// How long "needs input" / "permission required" hold the notch's
    /// attention-grabbing surface before receding on their own.
    static let attentionDisplayDuration: TimeInterval = 60

    /// If Claude Code goes completely silent — no further hook events of
    /// any kind — while sitting in one of these states, the most likely
    /// explanation is that the session ended without ever firing
    /// SessionEnd (the terminal was force-closed, the process crashed, or
    /// the machine slept through it) rather than that Claude has genuinely
    /// been waiting on the user, done, or idle for this long. Hooks are the
    /// only signal Glance has — there's no process to check — so after this
    /// long with nothing at all, treat the session as gone and fall back to
    /// idle instead of showing a stale "needs your input"/"permission
    /// required"/"completed" forever. `.working` is deliberately excluded:
    /// a single long-running tool call can legitimately produce no hook
    /// activity for a while, and that's not a sign the session is gone.
    static let stalenessTimeout: TimeInterval = 20 * 60

    private func scheduleStalenessFallback() {
        stalenessHandle?.cancel()
        stalenessHandle = nil
        switch machine.state {
        case .needsInput, .permissionRequired, .completed:
            let trackedSessionID = machine.sessionID
            stalenessHandle = scheduler.schedule(after: Self.stalenessTimeout) { [weak self] in
                guard let self, self.machine.sessionID == trackedSessionID else { return }
                self.apply(ClaudeCodeEvent(kind: .sessionEnd, sessionID: trackedSessionID, receivedAt: self.timeSource.now))
            }
        case .idle, .working, .failed:
            break
        }
    }

    private func openTerminalAction() -> InterruptionAction {
        InterruptionAction(id: "open-claude", title: "Open Claude") {
            // Claude Code runs in the user's terminal; activate it.
            ClaudeCodeProvider.activateTerminalApplication()
        }
    }

    nonisolated public static func formatDuration(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded())
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m \(seconds % 60)s" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

#if canImport(AppKit)
import AppKit

extension ClaudeCodeProvider {
    /// Bring the frontmost running terminal app forward (the app can't know
    /// which window hosts Claude Code; activating the terminal is the honest
    /// best effort).
    public static func activateTerminalApplication() {
        let terminalBundleIDs = [
            "com.googlecode.iterm2", "com.apple.Terminal", "dev.warp.Warp-Stable",
            "com.github.wez.wezterm", "net.kovidgoyal.kitty", "com.mitchellh.ghostty",
        ]
        for bundleID in terminalBundleIDs {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                app.activate()
                return
            }
        }
    }
}
#endif
