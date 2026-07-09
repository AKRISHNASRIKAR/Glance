import AppKit
import Combine
import CoreGraphics
import Foundation

/// Feeds real system signals into the ContextEngine when Context Awareness
/// is enabled.
///
/// Signals used (all local, all public APIs):
/// - Frontmost app: `NSWorkspace.didActivateApplicationNotification`
///   (event-driven).
/// - Idle time: `CGEventSource.secondsSinceLastEventType` sampled every 30 s
///   (one cheap call; needed to detect "away").
/// - Pomodoro focus + media playing: pushed in by the app coordinator.
///
/// Privacy: apps on the Never Track list are reported as no-app. Window
/// titles, browser domains, and terminal processes are opt-in settings that
/// are honored by *not reading them at all* — the current classifier only
/// uses bundle identifiers and app names. (Deeper signals are Planned.)
@MainActor
public final class ContextProvider: ActivityProvider, ObservableObject {
    public let id = "context"
    public private(set) var status: ProviderStatus = .disabled

    public var emitInterruption: (@MainActor (NotchInterruption) -> Void)?
    public var resolveInterruption: (@MainActor (String?) -> Void)?

    @Published public private(set) var currentKind: ContextKind = .general
    @Published public private(set) var currentLabel: String?
    @Published public private(set) var currentSince: Date?

    public let history: ContextHistoryStore

    private var engine: ContextEngine
    private var signals = ContextSignals()
    private var workspaceObserver: NSObjectProtocol?
    private var idlePollHandle: GlanceCancellable?
    private let settings: SettingsStore
    private let scheduler: GlanceScheduler
    private let timeSource: TimeSource
    private var settingsCancellable: AnyCancellable?

    public init(
        settings: SettingsStore,
        history: ContextHistoryStore? = nil,
        scheduler: GlanceScheduler = TimerScheduler(),
        timeSource: TimeSource = SystemTimeSource()
    ) {
        self.settings = settings
        self.scheduler = scheduler
        self.timeSource = timeSource
        self.history = history ?? ContextHistoryStore(
            retention: settings.settings.context.retention,
            timeSource: timeSource
        )
        self.engine = ContextEngine(codingBundleIDs: settings.settings.codingContext.codingApplications)
    }

    public func start() {
        engine = ContextEngine(codingBundleIDs: settings.settings.codingContext.codingApplications)
        history.setRetention(settings.settings.context.retention)
        settingsCancellable = settings.$settings
            .map(\.context.retention)
            .removeDuplicates()
            .sink { [weak self] retention in self?.history.setRetention(retention) }

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            let name = app?.localizedName
            MainActor.assumeIsolated {
                self?.frontmostChanged(bundleID: bundleID, name: name)
            }
        }
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            frontmostChanged(bundleID: frontmost.bundleIdentifier, name: frontmost.localizedName)
        }
        scheduleIdlePoll()
        status = .running
    }

    public func stop() {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        workspaceObserver = nil
        idlePollHandle?.cancel()
        idlePollHandle = nil
        settingsCancellable = nil
        if let finished = engine.closeCurrentSession(at: timeSource.now) {
            history.append(finished)
        }
        status = .disabled
    }

    // MARK: Signal inputs

    private func frontmostChanged(bundleID: String?, name: String?) {
        let excluded = settings.settings.privacy.neverTrackBundleIdentifiers
        if let bundleID, excluded.contains(bundleID) {
            signals.frontmostBundleID = nil
            signals.frontmostAppName = nil
        } else {
            signals.frontmostBundleID = bundleID
            signals.frontmostAppName = name
        }
        apply()
    }

    /// Pushed by the app coordinator so providers stay decoupled.
    public func setMediaPlaying(_ playing: Bool) {
        guard signals.isMediaPlaying != playing else { return }
        signals.isMediaPlaying = playing
        apply()
    }

    public func setPomodoroFocusRunning(_ running: Bool) {
        guard signals.isPomodoroFocusRunning != running else { return }
        signals.isPomodoroFocusRunning = running
        apply()
    }

    private func scheduleIdlePoll() {
        idlePollHandle = scheduler.schedule(after: 30) { [weak self] in
            guard let self, self.status.isRunning else { return }
            self.signals.idleSeconds = CGEventSource.secondsSinceLastEventType(
                .combinedSessionState,
                eventType: CGEventType(rawValue: ~0)! // any event
            )
            self.apply()
            self.scheduleIdlePoll()
        }
    }

    private func apply() {
        if let finished = engine.update(signals: signals, at: timeSource.now) {
            history.append(finished)
        }
        currentKind = engine.currentKind
        currentLabel = engine.currentLabel
        currentSince = engine.currentStart
    }
}
