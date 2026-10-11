import GlanceKit
import SwiftUI

/// Artwork — the expressive appearance. `PomodoroArtworkBackgroundView`
/// (wired into `NotchRootView`) paints the full-bleed translucent color
/// wash behind the whole shape; this is just the foreground content, built
/// from the same `PomodoroRingHeaderLayout` Classic uses but in white so it
/// reads clearly over any of the three tints.
struct ArtworkPomodoroRenderer: View {
    let state: PomodoroDisplayState
    let actions: PomodoroActions
    var reduceMotion: Bool = false

    var body: some View {
        PomodoroRingHeaderLayout(
            state: state,
            actions: actions,
            accentColor: .white,
            ringSize: 78,
            lineWidth: 4.5,
            trackOpacity: 0.18,
            labelOpacity: 0.85,
            reduceMotion: reduceMotion
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: state.phase)
    }
}
