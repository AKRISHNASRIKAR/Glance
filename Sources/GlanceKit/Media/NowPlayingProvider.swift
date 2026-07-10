import AppKit
import Combine
import CoreGraphics
import Foundation
import ImageIO

/// Coordinates the media sources and exposes one normalized now-playing
/// state to the UI, plus artwork bytes and adaptive-contrast analysis.
///
/// The UI never talks to Music or Spotify — it consumes `state`, `artwork`,
/// and `artworkAnalysis`, and issues `MediaCommand`s.
@MainActor
public final class NowPlayingProvider: ActivityProvider, ObservableObject {
    public let id = "now-playing"
    public private(set) var status: ProviderStatus = .disabled

    public var emitInterruption: (@MainActor (NotchInterruption) -> Void)?
    public var resolveInterruption: (@MainActor (String?) -> Void)?

    @Published public private(set) var state: MediaState?
    @Published public private(set) var artwork: CGImage?
    @Published public private(set) var artworkAnalysis: ArtworkAnalysis?
    /// Whether the experimental system-wide (MediaRemote) source is active.
    @Published public private(set) var systemMediaRemoteEnabled = false

    /// False if the private MediaRemote framework or a required symbol
    /// failed to load. Only meaningful once the feature has been enabled at
    /// least once (the framework is not probed before then).
    public var systemMediaRemoteAvailable: Bool {
        (systemMediaSource as? SystemMediaRemoteSource)?.isAvailable ?? false
    }

    private let sources: [any MediaSource]
    /// Experimental, opt-in — kept separate from `sources` so it is never
    /// started unless explicitly enabled via `setSystemMediaRemoteEnabled`.
    private let systemMediaSource: (any MediaSource)?
    private var sourceStates: [MediaSourceKind: MediaState] = [:]
    private var lastChangeAt: [MediaSourceKind: Date] = [:]
    private let analyzer = ArtworkAnalyzer()
    private var artworkTask: Task<Void, Never>?
    private var positionPollHandle: GlanceCancellable?
    private var detailVisible = false
    private let scheduler: GlanceScheduler
    private let timeSource: TimeSource
    private var wakeObserver: NSObjectProtocol?
    private var activateObserver: NSObjectProtocol?

    public init(
        sources: [any MediaSource]? = nil,
        systemMediaSource: (any MediaSource)? = SystemMediaRemoteSource(),
        scheduler: GlanceScheduler = TimerScheduler(),
        timeSource: TimeSource = SystemTimeSource()
    ) {
        self.scheduler = scheduler
        self.timeSource = timeSource
        self.sources = sources ?? [AppleMusicSource(), SpotifySource()]
        self.systemMediaSource = systemMediaSource
        for source in self.sources {
            let kind = source.kind
            source.onStateChange = { [weak self] newState in
                self?.sourceDidChange(kind: kind, newState: newState)
            }
        }
        if let systemMediaSource {
            systemMediaSource.onStateChange = { [weak self] newState in
                self?.sourceDidChange(kind: .systemMediaRemote, newState: newState)
            }
        }
    }

    public func start() {
        status = .running
        sources.forEach { $0.start() }
        if systemMediaRemoteEnabled {
            systemMediaSource?.start()
        }
        // The launch snapshot can race the Automation permission prompt or a
        // still-starting player; retry a few times until we know a state.
        scheduleSnapshotRetry(attempt: 0)
        observeSystemEvents()
    }

    /// Distributed notifications are the normal update path, but they're
    /// silently lost across two real "interruptions": the process is asleep
    /// during system sleep (nothing arrives to catch up on later), and the
    /// notch can sit idle long enough that a missed notification never gets
    /// retried. Both hooks below are event-driven — no polling, negligible
    /// battery cost — and directly address already-playing media not being
    /// picked up after a wake or a relaunch.
    private func observeSystemEvents() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAllSources() }
        }
        activateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state == nil else { return }
                self.refreshAllSources()
            }
        }
    }

    private func refreshAllSources() {
        sources.forEach { $0.refreshNowPlaying() }
        if systemMediaRemoteEnabled { systemMediaSource?.refreshNowPlaying() }
    }

    /// Turn the experimental system-wide source on or off at runtime (the
    /// Settings toggle). A no-op if the private framework failed to load.
    public func setSystemMediaRemoteEnabled(_ enabled: Bool) {
        guard enabled != systemMediaRemoteEnabled, let systemMediaSource else { return }
        systemMediaRemoteEnabled = enabled
        guard status.isRunning else { return } // applied when start() runs
        if enabled {
            systemMediaSource.start()
        } else {
            systemMediaSource.stop()
            // Bypasses sourceDidChange's enabled-gate below (it would no-op
            // now that the flag just flipped to false) to actively clear any
            // state the source already published.
            sourceStates[.systemMediaRemote] = nil
            lastChangeAt[.systemMediaRemote] = nil
            recomputeActiveState()
        }
    }

    private var snapshotRetryHandle: GlanceCancellable?

    private func scheduleSnapshotRetry(attempt: Int) {
        let delays: [TimeInterval] = [2, 5, 12]
        guard attempt < delays.count else { return }
        snapshotRetryHandle?.cancel()
        snapshotRetryHandle = scheduler.schedule(after: delays[attempt]) { [weak self] in
            guard let self, self.status.isRunning, self.state == nil else { return }
            self.refreshAllSources()
            self.scheduleSnapshotRetry(attempt: attempt + 1)
        }
    }

    public func stop() {
        sources.forEach { $0.stop() }
        systemMediaSource?.stop()
        sourceStates = [:]
        state = nil
        artwork = nil
        artworkAnalysis = nil
        artworkTask?.cancel()
        positionPollHandle?.cancel()
        positionPollHandle = nil
        snapshotRetryHandle?.cancel()
        snapshotRetryHandle = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        if let activateObserver { NotificationCenter.default.removeObserver(activateObserver) }
        activateObserver = nil
        status = .disabled
    }

    // MARK: Source arbitration

    /// Pick the active source: a playing source wins over a paused one; ties
    /// break to the most recent change. This is testable via injected fake
    /// sources.
    func sourceDidChange(kind: MediaSourceKind, newState: MediaState?) {
        // Guards against any stray callback reaching arbitration before the
        // experimental source has been explicitly enabled.
        if kind == .systemMediaRemote && !systemMediaRemoteEnabled { return }
        sourceStates[kind] = newState
        lastChangeAt[kind] = timeSource.now
        recomputeActiveState()
    }

    private func recomputeActiveState() {
        let candidates = sourceStates.values.compactMap { $0 }
        let changeDates = lastChangeAt
        func rank(_ s: MediaState) -> (Int, Date) {
            (s.playbackState == .playing ? 1 : 0, changeDates[s.source] ?? .distantPast)
        }
        let winner = candidates.max { lhs, rhs in
            let l = rank(lhs), r = rank(rhs)
            return l.0 == r.0 ? l.1 < r.1 : l.0 < r.0
        }

        let previousArtworkID = state?.artworkID
        state = winner

        if let winner {
            if winner.artworkID != previousArtworkID {
                loadArtwork(for: winner)
            }
        } else {
            artwork = nil
            artworkAnalysis = nil
        }
        updatePositionPolling()
    }

    /// Looks up the live source object for a kind, across both the always-on
    /// sources and the experimental system-wide one.
    private func activeSource(for kind: MediaSourceKind) -> (any MediaSource)? {
        if let match = sources.first(where: { $0.kind == kind }) { return match }
        return systemMediaSource?.kind == kind ? systemMediaSource : nil
    }

    // MARK: Commands

    public func perform(_ command: MediaCommand) {
        guard let active = state else { return }
        activeSource(for: active.source)?.perform(command)
    }

    // MARK: Artwork

    private func loadArtwork(for state: MediaState) {
        artworkTask?.cancel()
        let artworkID = state.artworkID
        artworkTask = Task { [weak self] in
            guard let self else { return }
            guard let source = self.activeSource(for: state.source) else { return }
            let data = await source.fetchArtwork(for: state)
            guard !Task.isCancelled, self.state?.artworkID == artworkID else { return }
            guard let data else {
                self.artwork = nil
                self.artworkAnalysis = nil
                return
            }
            let analyzer = self.analyzer
            // Decode + analyze off the main actor.
            let result: (CGImage, ArtworkAnalysis)? = await Task.detached(priority: .utility) {
                guard let image = ArtworkAnalyzer.downsampledImage(from: data, maxPixel: 600) else { return nil }
                guard let analysis = analyzer.analyze(artworkID: artworkID, data: data) else { return nil }
                return (image, analysis)
            }.value
            guard !Task.isCancelled, self.state?.artworkID == artworkID else { return }
            self.artwork = result?.0
            self.artworkAnalysis = result?.1
        }
    }

    // MARK: Position accuracy

    /// The UI calls this when the Now Playing Screen becomes visible or
    /// hidden. While visible and playing, the true position is re-sampled
    /// every 5 s to correct interpolation drift; while hidden there is no
    /// polling at all.
    public func setDetailVisible(_ visible: Bool) {
        detailVisible = visible
        updatePositionPolling()
        if visible {
            if state == nil {
                // Opening the screen with no known state: ask the players.
                sources.forEach { $0.refreshNowPlaying() }
                if systemMediaRemoteEnabled { systemMediaSource?.refreshNowPlaying() }
            }
            samplePositionNow()
        }
    }

    private func updatePositionPolling() {
        let shouldPoll = detailVisible && state?.playbackState == .playing
        if shouldPoll, positionPollHandle == nil {
            scheduleNextPositionSample()
        } else if !shouldPoll {
            positionPollHandle?.cancel()
            positionPollHandle = nil
        }
    }

    private func scheduleNextPositionSample() {
        positionPollHandle = scheduler.schedule(after: 5) { [weak self] in
            guard let self, self.detailVisible, self.state?.playbackState == .playing else {
                self?.positionPollHandle = nil
                return
            }
            self.samplePositionNow()
            self.scheduleNextPositionSample()
        }
    }

    private func samplePositionNow() {
        guard let active = state, active.playbackState == .playing,
              let source = activeSource(for: active.source) else { return }
        let artworkID = active.artworkID
        Task { [weak self] in
            guard let position = await source.fetchPosition() else { return }
            guard let self, var current = self.state, current.artworkID == artworkID else { return }
            current.elapsed = position
            current.elapsedCapturedAt = self.timeSource.now
            self.state = current
            self.sourceStates[current.source] = current
        }
    }
}
