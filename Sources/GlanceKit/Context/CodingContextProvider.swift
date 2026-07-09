import AppKit
import Combine
import Foundation

/// Optional coding-session tracker for the Coding Context Screen.
///
/// Independent of the general ContextEngine (provider isolation): it only
/// watches frontmost-app activations against the user's configured coding
/// applications, and measures continuous coding time.
///
/// Project detection honesty: with `applicationOnly` (the default) no
/// project is detected — the Screen shows time + application. `gitRepository`
/// detection from window titles requires opt-in Accessibility access and is
/// Planned, not implemented; the setting only offers what works today.
@MainActor
public final class CodingContextProvider: ActivityProvider, ObservableObject {
    public let id = "coding-context"
    public private(set) var status: ProviderStatus = .disabled

    public var emitInterruption: (@MainActor (NotchInterruption) -> Void)?
    public var resolveInterruption: (@MainActor (String?) -> Void)?

    /// Non-nil while the user has been in a coding app continuously for at
    /// least `displayAfterSeconds`.
    @Published public private(set) var session: CodingSession?

    public struct CodingSession: Equatable, Sendable {
        public var appName: String
        public var startedAt: Date
    }

    private var candidateStart: Date?
    private var candidateApp: String?
    private var workspaceObserver: NSObjectProtocol?
    private var promoteHandle: GlanceCancellable?
    private let settings: SettingsStore
    private let scheduler: GlanceScheduler
    private let timeSource: TimeSource

    public init(settings: SettingsStore, scheduler: GlanceScheduler = TimerScheduler(), timeSource: TimeSource = SystemTimeSource()) {
        self.settings = settings
        self.scheduler = scheduler
        self.timeSource = timeSource
    }

    public func start() {
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
        status = .running
    }

    public func stop() {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        workspaceObserver = nil
        promoteHandle?.cancel()
        promoteHandle = nil
        session = nil
        candidateStart = nil
        candidateApp = nil
        status = .disabled
    }

    private func frontmostChanged(bundleID: String?, name: String?) {
        let config = settings.settings.codingContext
        let excluded = settings.settings.privacy.neverTrackBundleIdentifiers
        let isCodingApp = bundleID.map {
            config.codingApplications.contains($0) && !excluded.contains($0)
        } ?? false

        if isCodingApp {
            let appName = name ?? "Editor"
            if candidateStart == nil {
                candidateStart = timeSource.now
                candidateApp = appName
                schedulePromotion(after: config.displayAfterSeconds)
            } else {
                candidateApp = appName
                session?.appName = appName
            }
        } else {
            // Left coding apps entirely — end the session. Brief switches
            // between coding apps don't reset the clock.
            candidateStart = nil
            candidateApp = nil
            promoteHandle?.cancel()
            promoteHandle = nil
            session = nil
        }
    }

    private func schedulePromotion(after delay: TimeInterval) {
        promoteHandle?.cancel()
        promoteHandle = scheduler.schedule(after: max(delay, 0)) { [weak self] in
            guard let self, let start = self.candidateStart, let app = self.candidateApp else { return }
            self.session = CodingSession(appName: app, startedAt: start)
        }
    }
}
