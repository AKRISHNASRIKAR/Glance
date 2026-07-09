import Foundation

/// Pure normalization of the distributed notifications Apple Music and
/// Spotify broadcast on playback changes. Kept free of side effects so the
/// mapping is unit-testable.
///
/// These notifications are public, documented-by-convention broadcast APIs
/// that both players have shipped for many years:
/// - `com.apple.Music.playerInfo` (Music.app)
/// - `com.spotify.client.PlaybackStateChanged` (Spotify)
public enum MediaNotificationNormalizer {

    // MARK: Apple Music

    /// Music.app `playerInfo` userInfo keys (observed, stable since iTunes):
    /// "Name", "Artist", "Album", "Total Time" (ms), "Player State"
    /// ("Playing"/"Paused"/"Stopped"), "PersistentID".
    /// The notification does not include playback position; position is
    /// sampled separately via Scripting when the Now Playing Screen is open.
    public static func normalizeAppleMusic(userInfo: [AnyHashable: Any], at date: Date = Date()) -> MediaState? {
        let stateString = (userInfo["Player State"] as? String)?.lowercased()
        let playback: PlaybackState
        switch stateString {
        case "playing": playback = .playing
        case "paused": playback = .paused
        case "stopped", .none: playback = .stopped
        default: playback = .stopped
        }

        guard let title = userInfo["Name"] as? String, !title.isEmpty else {
            // Stopped with no track: report nil so the provider clears state.
            return nil
        }

        var duration: TimeInterval?
        if let totalMS = userInfo["Total Time"] as? Double {
            duration = totalMS / 1000
        } else if let totalMS = userInfo["Total Time"] as? Int {
            duration = Double(totalMS) / 1000
        }

        var artworkID: String?
        if let pid = userInfo["PersistentID"] {
            artworkID = "appleMusic|\(pid)"
        }

        return MediaState(
            title: title,
            artist: nonEmpty(userInfo["Artist"] as? String),
            album: nonEmpty(userInfo["Album"] as? String),
            duration: duration,
            playbackState: playback,
            source: .appleMusic,
            artworkID: artworkID
        )
    }

    // MARK: Spotify

    /// Spotify `PlaybackStateChanged` userInfo keys (documented by Spotify's
    /// AppleScript integration): "Name", "Artist", "Album", "Duration" (ms),
    /// "Playback Position" (s), "Player State", "Track ID".
    public static func normalizeSpotify(userInfo: [AnyHashable: Any], at date: Date = Date()) -> MediaState? {
        let stateString = (userInfo["Player State"] as? String)?.lowercased()
        let playback: PlaybackState
        switch stateString {
        case "playing": playback = .playing
        case "paused": playback = .paused
        default: playback = .stopped
        }

        guard let title = userInfo["Name"] as? String, !title.isEmpty else { return nil }

        var duration: TimeInterval?
        if let ms = userInfo["Duration"] as? Double {
            // Spotify reports milliseconds.
            duration = ms > 30000 ? ms / 1000 : ms
        } else if let ms = userInfo["Duration"] as? Int {
            duration = ms > 30000 ? Double(ms) / 1000 : Double(ms)
        }

        var elapsed: TimeInterval?
        if let pos = userInfo["Playback Position"] as? Double {
            elapsed = pos
        } else if let pos = userInfo["Playback Position"] as? Int {
            elapsed = Double(pos)
        }

        var artworkID: String?
        if let trackID = userInfo["Track ID"] as? String {
            artworkID = "spotify|\(trackID)"
        }

        return MediaState(
            title: title,
            artist: nonEmpty(userInfo["Artist"] as? String),
            album: nonEmpty(userInfo["Album"] as? String),
            duration: duration,
            elapsed: elapsed,
            elapsedCapturedAt: elapsed != nil ? date : nil,
            playbackState: playback,
            source: .spotify,
            artworkID: artworkID
        )
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }
}
