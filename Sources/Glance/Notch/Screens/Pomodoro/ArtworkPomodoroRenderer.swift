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
        ClassicPomodoroRenderer(state: state, actions: actions, reduceMotion: reduceMotion)
    }
}
