import CoreGraphics
import Foundation

public enum PlaybackState: String, Sendable, Equatable {
    case playing
    case paused
    case stopped
}

public enum MediaSourceKind: String, Sendable, Equatable, CaseIterable {
    case appleMusic
    case spotify

    public var displayName: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        }
    }
}

/// Normalized now-playing state. The Now Playing UI consumes only this type —
/// it never knows which application produced it.
///
/// Progress honesty: `elapsed` is the position reported by the source at
/// `elapsedCapturedAt`. While `playbackState == .playing`, the UI may display
/// `elapsed + (now - elapsedCapturedAt)`; that is interpolation of a real
/// reported position, clamped to `duration`, never invented data.
public struct MediaState: Equatable, Sendable {
    public var title: String
    public var artist: String?
    public var album: String?
    public var duration: TimeInterval?
    public var elapsed: TimeInterval?
    public var elapsedCapturedAt: Date?
    public var playbackState: PlaybackState
    public var source: MediaSourceKind
    /// Identifier for artwork caching (persistent track id or title+album hash).
    public var artworkID: String

    public init(
        title: String,
        artist: String? = nil,
        album: String? = nil,
        duration: TimeInterval? = nil,
        elapsed: TimeInterval? = nil,
        elapsedCapturedAt: Date? = nil,
        playbackState: PlaybackState,
        source: MediaSourceKind,
        artworkID: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.elapsedCapturedAt = elapsedCapturedAt
        self.playbackState = playbackState
        self.source = source
        self.artworkID = artworkID ?? "\(source.rawValue)|\(title)|\(album ?? "")|\(artist ?? "")"
    }

    /// Current interpolated position (see progress-honesty note above).
    public func interpolatedElapsed(at now: Date) -> TimeInterval? {
        guard let elapsed else { return nil }
        guard playbackState == .playing, let captured = elapsedCapturedAt else { return elapsed }
        let value = elapsed + now.timeIntervalSince(captured)
        if let duration { return min(value, duration) }
        return value
    }
}

/// Playback commands the UI can issue, routed to the active source.
public enum MediaCommand: Sendable {
    case playPause
    case nextTrack
    case previousTrack
}
