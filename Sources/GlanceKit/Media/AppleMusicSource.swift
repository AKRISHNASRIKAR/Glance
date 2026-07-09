import AppKit
import Foundation

/// Apple Music (Music.app) media source.
///
/// State changes arrive via the `com.apple.Music.playerInfo` distributed
/// notification. Position, artwork, and commands use Music's scripting
/// interface (Automation permission).
@MainActor
public final class AppleMusicSource: MediaSource {
    public let kind: MediaSourceKind = .appleMusic
    public var onStateChange: (@MainActor (MediaState?) -> Void)?

    static let bundleID = "com.apple.Music"
    private let scripts = ScriptRunner.shared
    private var observer: NSObjectProtocol?
    private var snapshotTask: Task<Void, Never>?

    public init() {}

    public func start() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            // Normalize to a Sendable value before hopping to the main actor.
            let state = MediaNotificationNormalizer.normalizeAppleMusic(userInfo: note.userInfo ?? [:])
            MainActor.assumeIsolated {
                self?.handleNotificationState(state)
            }
        }
        // Initial snapshot in case music is already playing.
        refreshNowPlaying()
    }

    public func refreshNowPlaying() {
        snapshotTask?.cancel()
        snapshotTask = Task { [weak self] in
            await self?.loadInitialSnapshot()
        }
    }

    public func stop() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        snapshotTask?.cancel()
        snapshotTask = nil
    }

    private var lastNotifiedState: MediaState?

    private func handleNotificationState(_ normalized: MediaState?) {
        var state = normalized
        if state?.playbackState == .stopped { state = nil }
        lastNotifiedState = state
        onStateChange?(state)
        // The notification carries no position; sample it once so progress
        // is anchored to a real value.
        guard let current = state else { return }
        let artworkID = current.artworkID
        Task { [weak self] in
            guard let self else { return }
            guard let position = await self.fetchPosition() else { return }
            guard var updated = self.lastNotifiedState, updated.artworkID == artworkID else { return }
            updated.elapsed = position
            updated.elapsedCapturedAt = Date()
            self.lastNotifiedState = updated
            self.onStateChange?(updated)
        }
    }

    // MARK: Scripting

    private func loadInitialSnapshot() async {
        guard isApplicationRunning(bundleIdentifier: Self.bundleID) else { return }
        let script = """
        tell application "Music"
            set sep to character id 31
            if player state is stopped then return "stopped"
            set st to "paused"
            if player state is playing then set st to "playing"
            set t to current track
            return st & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & (duration of t as text) & sep & (player position as text) & sep & (persistent ID of t)
        end tell
        """
        guard let descriptor = try? await scripts.run(script),
              let raw = descriptor.stringValue else { return }
        let parts = raw.components(separatedBy: String(UnicodeScalar(31)!))
        guard parts.count >= 7, parts[0] != "stopped", !parts[1].isEmpty else {
            onStateChange?(nil)
            return
        }
        let state = MediaState(
            title: parts[1],
            artist: parts[2].isEmpty ? nil : parts[2],
            album: parts[3].isEmpty ? nil : parts[3],
            duration: Double(parts[4].replacingOccurrences(of: ",", with: ".")),
            elapsed: Double(parts[5].replacingOccurrences(of: ",", with: ".")),
            elapsedCapturedAt: Date(),
            playbackState: parts[0] == "playing" ? .playing : .paused,
            source: .appleMusic,
            artworkID: "appleMusic|\(parts[6])"
        )
        onStateChange?(state)
    }

    public func perform(_ command: MediaCommand) {
        guard isApplicationRunning(bundleIdentifier: Self.bundleID) else { return }
        let verb: String
        switch command {
        case .playPause: verb = "playpause"
        case .nextTrack: verb = "next track"
        case .previousTrack: verb = "previous track"
        }
        Task { await scripts.runIgnoringResult("tell application \"Music\" to \(verb)") }
    }

    public func fetchPosition() async -> TimeInterval? {
        guard isApplicationRunning(bundleIdentifier: Self.bundleID) else { return nil }
        guard let descriptor = try? await scripts.run("tell application \"Music\" to return player position"),
              let value = descriptor.stringValue else { return nil }
        return Double(value.replacingOccurrences(of: ",", with: "."))
    }

    public func fetchArtwork(for state: MediaState) async -> Data? {
        guard isApplicationRunning(bundleIdentifier: Self.bundleID) else { return nil }
        let script = """
        tell application "Music"
            try
                return data of artwork 1 of current track
            on error
                return ""
            end try
        end tell
        """
        guard let descriptor = try? await scripts.run(script) else { return nil }
        let data = descriptor.data
        return data.isEmpty ? nil : data
    }
}
