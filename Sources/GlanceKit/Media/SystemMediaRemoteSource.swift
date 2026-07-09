import AppKit
import Foundation

/// Experimental system-wide Now Playing source: sees what's playing in ANY
/// app (browser tabs, VLC, podcast apps, ...) via Apple's private
/// MediaRemote framework — the same source Control Center's widget reads.
/// See `MediaRemoteBridge` for the full rationale and risk, and
/// docs/NOW_PLAYING.md for the user-facing explanation.
///
/// Off by default. Nothing in this type touches the private framework until
/// `start()` is called, which only happens when the user enables
/// `NowPlayingSettings.enableSystemMediaRemote`.
@MainActor
public final class SystemMediaRemoteSource: MediaSource {
    public let kind: MediaSourceKind = .systemMediaRemote
    public var onStateChange: (@MainActor (MediaState?) -> Void)?

    /// False if the private framework or a required symbol failed to load —
    /// the feature degrades to Unavailable rather than crashing or faking.
    public var isAvailable: Bool { MediaRemoteBridge.shared.isAvailable }

    private var observer: NSObjectProtocol?
    private var lastArtworkData: Data?
    private var lastArtworkID: String?

    public init() {}

    public func start() {
        guard MediaRemoteBridge.shared.isAvailable else { return }
        observer = NotificationCenter.default.addObserver(
            forName: MediaRemoteBridge.nowPlayingInfoDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshNowPlaying()
            }
        }
        MediaRemoteBridge.shared.register()
        refreshNowPlaying()
    }

    public func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        MediaRemoteBridge.shared.unregister()
        lastArtworkData = nil
        lastArtworkID = nil
    }

    public func refreshNowPlaying() {
        guard MediaRemoteBridge.shared.isAvailable else { return }
        MediaRemoteBridge.shared.getNowPlayingInfo { [weak self] info in
            MainActor.assumeIsolated {
                self?.apply(info)
            }
        }
    }

    private func apply(_ info: CFDictionary?) {
        guard let info = info as? [String: Any], !info.isEmpty,
              let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String, !title.isEmpty else {
            onStateChange?(nil)
            lastArtworkData = nil
            lastArtworkID = nil
            return
        }

        let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String
        let album = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String
        let duration = info["kMRMediaRemoteNowPlayingInfoDuration"] as? Double
        let elapsed = info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double
        let timestamp = info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date
        let rate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0
        let uniqueID = (info["kMRMediaRemoteNowPlayingInfoUniqueIdentifier"] as? NSNumber)?.stringValue

        let artworkID = uniqueID ?? "systemMedia|\(title)|\(album ?? "")|\(artist ?? "")"
        if let artworkData = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
            lastArtworkData = artworkData
            lastArtworkID = artworkID
        } else if artworkID != lastArtworkID {
            lastArtworkData = nil
            lastArtworkID = artworkID
        }

        var state = MediaState(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            elapsed: elapsed,
            elapsedCapturedAt: timestamp,
            playbackState: rate > 0 ? .playing : .paused,
            source: .systemMediaRemote,
            artworkID: artworkID
        )

        onStateChange?(state)

        // App identity is best-effort and resolved separately so it never
        // blocks the metadata update; republish once it's known.
        MediaRemoteBridge.shared.getNowPlayingClientBundleIdentifier { [weak self] bundleID in
            MainActor.assumeIsolated {
                guard let self, let bundleID else { return }
                state.sourceAppName = Self.appName(forBundleIdentifier: bundleID)
                self.onStateChange?(state)
            }
        }
    }

    public func perform(_ command: MediaCommand) {
        switch command {
        case .playPause: MediaRemoteBridge.shared.send(.togglePlayPause)
        case .nextTrack: MediaRemoteBridge.shared.send(.nextTrack)
        case .previousTrack: MediaRemoteBridge.shared.send(.previousTrack)
        }
    }

    public func fetchPosition() async -> TimeInterval? {
        // MediaRemote has no separate "sample position now" call distinct
        // from the info dictionary; the elapsed time already published via
        // the last update is the best available and is not re-fetched here.
        nil
    }

    public func fetchArtwork(for state: MediaState) async -> Data? {
        state.artworkID == lastArtworkID ? lastArtworkData : nil
    }

    private static func appName(forBundleIdentifier bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: url) else { return bundleID }
        return bundle.infoDictionary?["CFBundleName"] as? String
            ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
            ?? bundleID
    }
}
