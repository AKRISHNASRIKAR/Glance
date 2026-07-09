import GlanceKit
import SwiftUI

/// The Now Playing Screen. Two appearances:
/// - Minimal: pure black notch background, compact artwork + controls.
/// - Artwork: the album art becomes the blurred, contrast-managed background
///   of the whole Screen.
struct NowPlayingScreenView: View {
    @EnvironmentObject var nowPlaying: NowPlayingProvider
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var viewModel: NotchViewModel

    // Artwork-appearance background is rendered by NotchRootView across the
    // whole shape; this view is content only.
    var body: some View {
        let config = settings.settings.nowPlaying
        Group {
            if let state = nowPlaying.state {
                playerContent(state: state, config: config)
            } else {
                emptyState
            }
        }
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            Text("Nothing playing")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            Text("Play something in Music or Spotify")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Player

    private func playerContent(state: MediaState, config: NowPlayingSettings) -> some View {
        HStack(spacing: 13) {
            if config.showAlbumArtwork {
                LargeArtworkView(artworkID: state.artworkID)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(state.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let artist = state.artist {
                    Text(artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer(minLength: 2)

                controls(state: state, config: config)

                if config.showPlaybackProgress {
                    PlaybackProgressView(state: state)
                        .padding(.top, 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.top, 2)
        .padding(.bottom, 12)
    }

    private func controls(state: MediaState, config: NowPlayingSettings) -> some View {
        HStack(spacing: 14) {
            if config.showPreviousNextControls {
                NotchIconButton(systemName: "backward.fill", size: 13) {
                    nowPlaying.perform(.previousTrack)
                }
                .accessibilityLabel("Previous track")
            }
            NotchIconButton(
                systemName: state.playbackState == .playing ? "pause.fill" : "play.fill",
                size: 17
            ) {
                nowPlaying.perform(.playPause)
            }
            .accessibilityLabel(state.playbackState == .playing ? "Pause" : "Play")
            if config.showPreviousNextControls {
                NotchIconButton(systemName: "forward.fill", size: 13) {
                    nowPlaying.perform(.nextTrack)
                }
                .accessibilityLabel("Next track")
            }
            Spacer(minLength: 0)
            Text(state.source.displayName)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}

// MARK: - Large artwork (square, crossfades on track change)

private struct LargeArtworkView: View {
    @EnvironmentObject var nowPlaying: NowPlayingProvider
    @EnvironmentObject var viewModel: NotchViewModel
    let artworkID: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
            if let cgImage = nowPlaying.artwork {
                Image(decorative: cgImage, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .id(artworkID)
                    .transition(.opacity)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .frame(width: 82, height: 82)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(viewModel.reduceMotion ? nil : .easeInOut(duration: 0.45), value: artworkID)
        .accessibilityLabel("Album artwork")
    }
}

// MARK: - Artwork background (Artwork appearance)

/// Pipeline: artwork → aspect fill → slight scale → blur → translucent
/// material → adaptive contrast overlay → foreground content.
/// The contrast overlay strength comes from the cached ArtworkAnalyzer
/// result, so no image analysis happens during rendering.
struct ArtworkBackgroundView: View {
    @EnvironmentObject var nowPlaying: NowPlayingProvider
    @EnvironmentObject var viewModel: NotchViewModel
    let config: NowPlayingSettings

    var body: some View {
        ZStack {
            Color.black
            if let cgImage = nowPlaying.artwork {
                GeometryReader { proxy in
                    Image(decorative: cgImage, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(1.12)
                        .blur(radius: blurRadius)
                        .opacity(config.backgroundIntensity)
                }
                .id(nowPlaying.state?.artworkID ?? "")
                .transition(.opacity)
                // Translucent material layer keeps colors atmospheric
                // rather than loud.
                .overlay(Color.black.opacity(0.12))
                // Adaptive contrast layer.
                .overlay(Color.black.opacity(overlayOpacity))
            }
        }
        .animation(
            viewModel.reduceMotion ? nil : .easeInOut(duration: 0.5),
            value: nowPlaying.state?.artworkID
        )
        .accessibilityHidden(true)
    }

    /// Settings blur 0…1 maps to a 6…30 pt radius: recognizable at the low
    /// end, atmospheric at the top, never a flat gradient.
    private var blurRadius: CGFloat {
        6 + CGFloat(config.artworkBlur) * 24
    }

    private var overlayOpacity: Double {
        if config.adaptiveContrast, let analysis = nowPlaying.artworkAnalysis {
            return analysis.recommendedOverlayOpacity
        }
        return 0.40 // fixed fallback keeps text readable without analysis
    }
}

// MARK: - Progress

/// Interpolates the honest reported position once per second while playing.
struct PlaybackProgressView: View {
    let state: MediaState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let elapsed = state.interpolatedElapsed(at: timeline.date) ?? 0
            VStack(spacing: 3) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        if let duration = state.duration, duration > 0 {
                            Capsule()
                                .fill(Color.white.opacity(0.85))
                                .frame(width: max(proxy.size.width * min(elapsed / duration, 1), 2))
                        }
                    }
                }
                .frame(height: 3)
                if let duration = state.duration {
                    HStack {
                        Text(TimeFormatting.minutesSeconds(elapsed))
                        Spacer()
                        Text(TimeFormatting.minutesSeconds(duration))
                    }
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .accessibilityLabel("Playback progress")
    }
}
