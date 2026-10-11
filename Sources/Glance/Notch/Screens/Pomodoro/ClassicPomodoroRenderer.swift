import GlanceKit
import SwiftUI

/// Classic — the default, balanced appearance: ring left, stepper beside it
/// while idle, phase/progress/controls in a right-hand column. The same
/// left-visual/right-text grammar as Now Playing, so the two default
/// Screens read as one family. Built from `PomodoroRingHeaderLayout`, the
/// same composite Artwork uses — the two differ only in accent color.
struct ClassicPomodoroRenderer: View {
    let state: PomodoroDisplayState
    let actions: PomodoroActions
    var reduceMotion: Bool = false

    var body: some View {
        PomodoroRingHeaderLayout(
            state: state,
            actions: actions,
            accentColor: state.phaseColor,
            ringSize: 76,
            lineWidth: 5,
            glow: state.runState == .running,
            reduceMotion: reduceMotion
        )
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: state.phase)
    }
}
