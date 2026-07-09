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

    private let sources: [any MediaSource]
    private var sourceStates: [MediaSourceKind: MediaState] = [:]
    private var lastChangeAt: [MediaSourceKind: Date] = [:]
    private let analyzer = ArtworkAnalyzer()
    private var artworkTask: Task<Void, Never>?
    private var positionPollHandle: GlanceCancellable?
    private var detailVisible = false
    private var lastAnnouncedTrackID: String?
    private let scheduler: GlanceScheduler
    private let timeSource: TimeSource

    public init(
        sources: [any MediaSource]? = nil,
        scheduler: GlanceScheduler = TimerScheduler(),
        timeSource: TimeSource = SystemTimeSource()
    ) {
        self.scheduler = scheduler
        self.timeSource = timeSource
        self.sources = sources ?? [AppleMusicSource(), SpotifySource()]
        for source in self.sources {
            let kind = source.kind
            source.onStateChange = { [weak self] newState in
                self?.sourceDidChange(kind: kind, newState: newState)
            }
        }
    }

    public func start() {
        status = .running
        sources.forEach { $0.start() }
        // The launch snapshot can race the Automation permission prompt or a
        // still-starting player; retry a few times until we know a state.
        scheduleSnapshotRetry(attempt: 0)
    }

    private var snapshotRetryHandle: GlanceCancellable?

    private func scheduleSnapshotRetry(attempt: Int) {
        let delays: [TimeInterval] = [2, 5, 12]
        guard attempt < delays.count else { return }
        snapshotRetryHandle?.cancel()
        snapshotRetryHandle = scheduler.schedule(after: delays[attempt]) { [weak self] in
            guard let self, self.status.isRunning, self.state == nil else { return }
            self.sources.forEach { $0.refreshNowPlaying() }
            self.scheduleSnapshotRetry(attempt: attempt + 1)
        }
    }

    public func stop() {
        sources.forEach { $0.stop() }
        sourceStates = [:]
        state = nil
        artwork = nil
        artworkAnalysis = nil
        artworkTask?.cancel()
        positionPollHandle?.cancel()
        positionPollHandle = nil
        snapshotRetryHandle?.cancel()
        snapshotRetryHandle = nil
        status = .disabled
    }

    // MARK: Source arbitration

    /// Pick the active source: a playing source wins over a paused one; ties
    /// break to the most recent change. This is testable via injected fake
    /// sources.
    func sourceDidChange(kind: MediaSourceKind, newState: MediaState?) {
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
                announceTrackChange(winner)
            }
        } else {
            artwork = nil
            artworkAnalysis = nil
        }
        updatePositionPolling()
    }

    /// Passive peek when the track changes — never steals the surface from
    /// anything more important, and is debounced by the interruption engine.
    private func announceTrackChange(_ state: MediaState) {
        guard state.playbackState == .playing, state.artworkID != lastAnnouncedTrackID else { return }
        // Skip the very first observation (app launch / provider start):
        // announcing what was already playing is noise.
        let isFirstObservation = lastAnnouncedTrackID == nil
        lastAnnouncedTrackID = state.artworkID
        guard !isFirstObservation else { return }
        emitInterruption?(NotchInterruption(
            provider: id,
            kind: "track-changed",
            title: state.title,
            subtitle: state.artist,
            symbolName: "music.note",
            priority: .passive,
            displayDuration: 3
        ))
    }

    // MARK: Commands

    public func perform(_ command: MediaCommand) {
        guard let active = state else { return }
        sources.first { $0.kind == active.source }?.perform(command)
    }

    // MARK: Artwork

    private func loadArtwork(for state: MediaState) {
        artworkTask?.cancel()
        let artworkID = state.artworkID
        artworkTask = Task { [weak self] in
            guard let self else { return }
            guard let source = self.sources.first(where: { $0.kind == state.source }) else { return }
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
              let source = sources.first(where: { $0.kind == active.source }) else { return }
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
