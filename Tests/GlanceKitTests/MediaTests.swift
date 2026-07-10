import CoreGraphics
import Foundation
import Testing
@testable import GlanceKit

struct MediaNormalizationTests {
    @Test func appleMusicPlayingNotification() {
        let state = MediaNotificationNormalizer.normalizeAppleMusic(userInfo: [
            "Name": "Karma Police",
            "Artist": "Radiohead",
            "Album": "OK Computer",
            "Total Time": 261_000.0,
            "Player State": "Playing",
            "PersistentID": 123456789,
        ])
        #expect(state?.title == "Karma Police")
        #expect(state?.artist == "Radiohead")
        #expect(state?.album == "OK Computer")
        #expect(state?.duration == 261)
        #expect(state?.playbackState == .playing)
        #expect(state?.source == .appleMusic)
        #expect(state?.artworkID == "appleMusic|123456789")
    }

    @Test func appleMusicStoppedWithoutTrackIsNil() {
        let state = MediaNotificationNormalizer.normalizeAppleMusic(userInfo: [
            "Player State": "Stopped",
        ])
        #expect(state == nil)
    }

    @Test func spotifyNotificationIncludesPosition() {
        let captured = Date(timeIntervalSince1970: 1_700_000_000)
        let state = MediaNotificationNormalizer.normalizeSpotify(userInfo: [
            "Name": "Weird Fishes / Arpeggi",
            "Artist": "Radiohead",
            "Album": "In Rainbows",
            "Duration": 318_000,
            "Playback Position": 42.5,
            "Player State": "Playing",
            "Track ID": "spotify:track:abc123",
        ], at: captured)
        #expect(state?.duration == 318)
        #expect(state?.elapsed == 42.5)
        #expect(state?.elapsedCapturedAt == captured)
        #expect(state?.artworkID == "spotify|spotify:track:abc123")
    }

    @Test func interpolationOnlyWhilePlayingAndClampedToDuration() {
        let captured = Date(timeIntervalSince1970: 1_700_000_000)
        var state = MediaState(
            title: "Track", duration: 100, elapsed: 90, elapsedCapturedAt: captured,
            playbackState: .playing, source: .spotify
        )
        #expect(state.interpolatedElapsed(at: captured.addingTimeInterval(5)) == 95)
        #expect(state.interpolatedElapsed(at: captured.addingTimeInterval(30)) == 100) // clamped
        state.playbackState = .paused
        #expect(state.interpolatedElapsed(at: captured.addingTimeInterval(30)) == 90) // frozen
    }
}

struct ArtworkAnalyzerTests {
    private func solidImage(white: CGFloat, size: Int = 32) -> CGImage {
        let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: white, green: white, blue: white, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()!
    }

    private func pngData(_ image: CGImage) -> Data {
        let mutable = NSMutableData()
        let dest = CGImageDestinationCreateWithData(mutable, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return mutable as Data
    }

    @Test func brightArtworkGetsStrongerOverlayThanDark() {
        let bright = ArtworkAnalyzer.analyze(image: solidImage(white: 0.95))
        let dark = ArtworkAnalyzer.analyze(image: solidImage(white: 0.08))
        #expect(bright.averageLuminance > 0.85)
        #expect(dark.averageLuminance < 0.15)
        #expect(bright.recommendedOverlayOpacity > dark.recommendedOverlayOpacity + 0.2)
    }

    @Test func overlayOpacityStaysWithinReadableBounds() {
        for luminance in stride(from: 0.0, through: 1.0, by: 0.1) {
            let opacity = ArtworkAnalyzer.overlayOpacity(forLuminance: luminance, variance: 0.5)
            #expect(opacity >= 0.15 && opacity <= 0.75)
        }
    }

    @Test func analysisIsCachedByArtworkID() {
        let analyzer = ArtworkAnalyzer()
        let data = pngData(solidImage(white: 0.5))
        #expect(analyzer.cachedAnalysis(for: "track-1") == nil)
        let first = analyzer.analyze(artworkID: "track-1", data: data)
        #expect(first != nil)
        #expect(analyzer.cachedAnalysis(for: "track-1") == first)
        // Same ID with different bytes returns the cached result — analysis
        // keys on the artwork identifier, not the payload.
        let differentBytes = pngData(solidImage(white: 0.9))
        #expect(analyzer.analyze(artworkID: "track-1", data: differentBytes) == first)
    }

    @Test func cacheEvictsOldestBeyondLimit() {
        let analyzer = ArtworkAnalyzer(cacheLimit: 2)
        let data = pngData(solidImage(white: 0.5))
        _ = analyzer.analyze(artworkID: "a", data: data)
        _ = analyzer.analyze(artworkID: "b", data: data)
        _ = analyzer.analyze(artworkID: "c", data: data)
        #expect(analyzer.cachedAnalysis(for: "a") == nil)
        #expect(analyzer.cachedAnalysis(for: "c") != nil)
    }
}

import ImageIO

@MainActor
struct NowPlayingArbitrationTests {
    /// Fake source for testing arbitration without real media apps.
    @MainActor
    final class FakeSource: MediaSource {
        let kind: MediaSourceKind
        var onStateChange: (@MainActor (MediaState?) -> Void)?
        var performed: [MediaCommand] = []
        var refreshCount = 0
        init(kind: MediaSourceKind) { self.kind = kind }
        func start() {}
        func stop() {}
        func refreshNowPlaying() { refreshCount += 1 }
        func perform(_ command: MediaCommand) { performed.append(command) }
        func fetchPosition() async -> TimeInterval? { nil }
        func fetchArtwork(for state: MediaState) async -> Data? { nil }
    }

    @Test func playingSourceBeatsPausedSource() {
        let clock = TestClock()
        let music = FakeSource(kind: .appleMusic)
        let spotify = FakeSource(kind: .spotify)
        let provider = NowPlayingProvider(sources: [music, spotify], scheduler: clock, timeSource: clock)
        provider.start()

        music.onStateChange?(MediaState(title: "Paused Song", playbackState: .paused, source: .appleMusic))
        spotify.onStateChange?(MediaState(title: "Playing Song", playbackState: .playing, source: .spotify))
        #expect(provider.state?.title == "Playing Song")

        // Commands route to the active source.
        provider.perform(.playPause)
        #expect(spotify.performed == [.playPause])
        #expect(music.performed.isEmpty)
    }

    @Test func trackChangeNeverEmitsAnInterruption() {
        let clock = TestClock()
        let music = FakeSource(kind: .appleMusic)
        let provider = NowPlayingProvider(sources: [music], scheduler: clock, timeSource: clock)
        var emitted: [NotchInterruption] = []
        provider.emitInterruption = { emitted.append($0) }
        provider.start()

        music.onStateChange?(MediaState(title: "First", playbackState: .playing, source: .appleMusic))
        music.onStateChange?(MediaState(title: "Second", playbackState: .playing, source: .appleMusic))

        // Track changes are natural — no notch notification/dismiss prompt.
        #expect(emitted.isEmpty)
        #expect(provider.state?.title == "Second")
    }

    @Test func startupRetriesSnapshotUntilStateIsKnown() {
        let clock = TestClock()
        let music = FakeSource(kind: .appleMusic)
        let provider = NowPlayingProvider(sources: [music], systemMediaSource: nil, scheduler: clock, timeSource: clock)
        provider.start()
        clock.advance(by: 8) // first two retries fire while state is unknown
        #expect(music.refreshCount == 2)
        // Once a state arrives, remaining retries stop.
        music.onStateChange?(MediaState(title: "Song", playbackState: .playing, source: .appleMusic))
        clock.advance(by: 30)
        #expect(music.refreshCount == 2)
    }

    @Test func systemMediaRemoteStaysOffUntilEnabled() {
        let clock = TestClock()
        let music = FakeSource(kind: .appleMusic)
        let system = FakeSource(kind: .systemMediaRemote)
        let provider = NowPlayingProvider(sources: [music], systemMediaSource: system, scheduler: clock, timeSource: clock)
        provider.start()
        system.onStateChange?(MediaState(title: "Browser Video", playbackState: .playing, source: .systemMediaRemote))
        // Not enabled yet: arbitration must ignore it entirely.
        #expect(provider.state == nil)

        provider.setSystemMediaRemoteEnabled(true)
        system.onStateChange?(MediaState(title: "Browser Video", playbackState: .playing, source: .systemMediaRemote))
        #expect(provider.state?.title == "Browser Video")

        provider.setSystemMediaRemoteEnabled(false)
        #expect(provider.state == nil)
    }

    @Test func sourceAppNameOverridesDisplayName() {
        var state = MediaState(title: "Video", playbackState: .playing, source: .systemMediaRemote)
        #expect(state.displaySourceName == "System Media")
        state.sourceAppName = "Safari"
        #expect(state.displaySourceName == "Safari")
    }
}
