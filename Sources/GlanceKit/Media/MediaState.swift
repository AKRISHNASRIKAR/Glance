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
    /// Experimental system-wide source (any app, via Apple's private
    /// MediaRemote framework). See docs/NOW_PLAYING.md.
    case systemMediaRemote

    public var displayName: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        case .systemMediaRemote: return "System Media"
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
    /// Real application name for system-wide sources (e.g. "Safari"), when
    /// it could be resolved. Nil for Apple Music/Spotify — their source
    /// already names them accurately — or when resolution fails; never a
    /// guess.
    public var sourceAppName: String?

    public init(
        title: String,
        artist: String? = nil,
        album: String? = nil,
        duration: TimeInterval? = nil,
        elapsed: TimeInterval? = nil,
        elapsedCapturedAt: Date? = nil,
        playbackState: PlaybackState,
        source: MediaSourceKind,
        artworkID: String? = nil,
        sourceAppName: String? = nil
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
        self.sourceAppName = sourceAppName
    }

    /// The name to display for where this is playing from — the real app
    /// name when known (system-wide source), otherwise the source's own name.
    public var displaySourceName: String { sourceAppName ?? source.displayName }

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
