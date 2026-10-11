import GlanceKit
import SwiftUI

/// The Pomodoro Screen. A thin dispatcher: it builds one `PomodoroDisplayState`
/// snapshot and one `PomodoroActions` bundle from the single `PomodoroEngine`
/// + `SettingsStore` each render, then hands both to whichever renderer
/// `PomodoroSettings.appearance` selects. No renderer touches the engine or
/// settings directly, and none of them implement timer logic — that exists
/// exactly once, in `PomodoroEngine`. Adding a new appearance means adding a
/// new renderer + one enum case + one switch arm here; see docs/POMODORO.md.
struct PomodoroScreenView: View {
    @EnvironmentObject var engine: PomodoroEngine
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var viewModel: NotchViewModel

    var body: some View {
        let state = PomodoroDisplayState(engine: engine, settings: settings.settings.pomodoro)
        let actions = PomodoroActions(engine: engine, settings: settings)
        let reduceMotion = viewModel.reduceMotion

        Group {
            switch settings.settings.pomodoro.appearance {
            case .classic:
                ClassicPomodoroRenderer(state: state, actions: actions, reduceMotion: reduceMotion)
            case .minimal:
                MinimalPomodoroRenderer(state: state, actions: actions, reduceMotion: reduceMotion)
            case .artwork:
                ArtworkPomodoroRenderer(state: state, actions: actions, reduceMotion: reduceMotion)
            }
        }
        .transition(reduceMotion ? .identity : .opacity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: settings.settings.pomodoro.appearance)
    }
}
