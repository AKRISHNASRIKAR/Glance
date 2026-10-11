import SwiftUI

/// Full-bleed background for the Artwork appearance: two large, heavily
/// blurred washes of the phase's tint color over black, the same
/// blur/material/translucent-layer language as Now Playing's Artwork
/// appearance (`ArtworkBackgroundView`) — but color-only, since there is no
/// album art to derive it from. Wired into `NotchRootView.fullBleedArtwork`
/// so it covers the whole expanded shape, not just this Screen's content
/// area.
///
/// Kept deliberately subtle: a fixed dark scrim on top, not an adaptive
/// per-pixel contrast analysis like artwork gets — the three tints are
/// known and bounded ahead of time, so there's nothing to analyze.
struct PomodoroArtworkBackgroundView: View {
    let tint: Color
    var reduceMotion: Bool = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                Circle()
                    .fill(tint)
                    .frame(width: proxy.size.width * 0.9)
                    .offset(x: -proxy.size.width * 0.22, y: -proxy.size.height * 0.22)
                    .blur(radius: 60)
                    .opacity(0.5)
                Circle()
                    .fill(tint)
                    .frame(width: proxy.size.width * 0.7)
                    .offset(x: proxy.size.width * 0.28, y: proxy.size.height * 0.3)
                    .blur(radius: 55)
                    .opacity(0.35)
            }
        }
        // Atmospheric translucent layer, then a fixed contrast scrim so
        // white text stays reliably readable regardless of tint.
        .overlay(Color.black.opacity(0.12))
        .overlay(Color.black.opacity(0.28))
        .transition(.opacity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: tint)
        .accessibilityHidden(true)
    }
}
