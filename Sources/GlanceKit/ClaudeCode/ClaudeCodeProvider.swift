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

    public init(
        settings: SettingsStore,
        installer: ClaudeCodeHookInstaller = ClaudeCodeHookInstaller(),
        timeSource: TimeSource = SystemTimeSource()
    ) {
        self.settings = settings
        self.installer = installer
        self.timeSource = timeSource
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
                subtitle: "Claude is waiting for you",
                symbolName: "bubble.left.and.exclamationmark.bubble.right",
                priority: .important,
                isPersistent: true,
                actions: [openTerminalAction()]
            ))
        case .permissionRequired:
            guard config.interruptOnPermissionRequired else { return }
            emitInterruption?(NotchInterruption(
                provider: id, kind: "permission-required",
                title: "Claude · Permission",
                subtitle: event.message ?? "Claude needs your permission",
                symbolName: "lock.shield",
                priority: .important,
                isPersistent: true,
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
