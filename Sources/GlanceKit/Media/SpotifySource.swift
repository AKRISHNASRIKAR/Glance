import AppKit
import Foundation

/// Spotify media source.
///
/// State changes arrive via `com.spotify.client.PlaybackStateChanged`
/// (which includes the playback position). Commands and the initial snapshot
/// use Spotify's scripting interface. Artwork comes from the track's
/// `artwork url` — fetching it is the one network request this integration
/// performs, against Spotify's own image CDN (documented in docs/PRIVACY.md).
@MainActor
public final class SpotifySource: MediaSource {
    public let kind: MediaSourceKind = .spotify
    public var onStateChange: (@MainActor (MediaState?) -> Void)?

    static let bundleID = "com.spotify.client"
    private let scripts = ScriptRunner.shared
    private var observer: NSObjectProtocol?
    private var snapshotTask: Task<Void, Never>?

    public init() {}

    public func start() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            // Normalize to a Sendable value before hopping to the main actor.
            var state = MediaNotificationNormalizer.normalizeSpotify(userInfo: note.userInfo ?? [:])
            if state?.playbackState == .stopped { state = nil }
            let normalized = state
            MainActor.assumeIsolated {
                self?.onStateChange?(normalized)
            }
        }
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

    private func loadInitialSnapshot() async {
        guard isApplicationRunning(bundleIdentifier: Self.bundleID) else { return }
        let script = """
        tell application "Spotify"
            set sep to character id 31
            if player state is stopped then return "stopped"
            set st to "paused"
            if player state is playing then set st to "playing"
            set t to current track
            return st & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & (duration of t as text) & sep & (player position as text) & sep & (id of t)
        end tell
        """
        guard let descriptor = try? await scripts.run(script),
              let raw = descriptor.stringValue else { return }
        let parts = raw.components(separatedBy: String(UnicodeScalar(31)!))
        guard parts.count >= 7, parts[0] != "stopped", !parts[1].isEmpty else {
            onStateChange?(nil)
            return
        }
        var duration: TimeInterval?
        if let ms = Double(parts[4].replacingOccurrences(of: ",", with: ".")) {
            duration = ms / 1000 // Spotify reports milliseconds.
        }
        let state = MediaState(
            title: parts[1],
            artist: parts[2].isEmpty ? nil : parts[2],
            album: parts[3].isEmpty ? nil : parts[3],
            duration: duration,
            elapsed: Double(parts[5].replacingOccurrences(of: ",", with: ".")),
            elapsedCapturedAt: Date(),
            playbackState: parts[0] == "playing" ? .playing : .paused,
            source: .spotify,
            artworkID: "spotify|\(parts[6])"
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
        Task { await scripts.runIgnoringResult("tell application \"Spotify\" to \(verb)") }
    }

    public func fetchPosition() async -> TimeInterval? {
        guard isApplicationRunning(bundleIdentifier: Self.bundleID) else { return nil }
        guard let descriptor = try? await scripts.run("tell application \"Spotify\" to return player position"),
              let value = descriptor.stringValue else { return nil }
        return Double(value.replacingOccurrences(of: ",", with: "."))
    }

    public func fetchArtwork(for state: MediaState) async -> Data? {
        guard isApplicationRunning(bundleIdentifier: Self.bundleID) else { return nil }
        guard let descriptor = try? await scripts.run("tell application \"Spotify\" to return artwork url of current track"),
              let urlString = descriptor.stringValue,
              let url = URL(string: urlString),
              url.scheme == "https" else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return data
        } catch {
            GlanceLog.nowPlaying.debug("Spotify artwork fetch failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
