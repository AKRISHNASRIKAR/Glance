import AppKit
import Combine
import Foundation
import GlanceKit

/// Composition root: builds the stores, engines, and providers, and wires
/// providers into the Activity Engine. Owns nothing UI-specific — the notch
/// window and settings window consume this object.
@MainActor
final class AppCoordinator: ObservableObject {
    let settings: SettingsStore
    let screens: ScreenStore
    let interruptions: InterruptionEngine
    let activity: ActivityEngine

    let nowPlaying: NowPlayingProvider
    let pomodoro: PomodoroProvider
    let battery: BatteryProvider
    let network: NetworkProvider
    let context: ContextProvider
    let codingContext: CodingContextProvider
    let claudeCode: ClaudeCodeProvider

    private var cancellables: Set<AnyCancellable> = []

    init() {
        let settings = SettingsStore()
        self.settings = settings
        self.screens = ScreenStore(settings: settings)
        self.interruptions = InterruptionEngine()
        self.activity = ActivityEngine(settings: settings, interruptions: interruptions)

        self.nowPlaying = NowPlayingProvider()
        self.pomodoro = PomodoroProvider(settings: settings)
        self.battery = BatteryProvider(settings: settings)
        self.network = NetworkProvider(settings: settings)
        self.context = ContextProvider(settings: settings)
        self.codingContext = CodingContextProvider(settings: settings)
        self.claudeCode = ClaudeCodeProvider(settings: settings)

        activity.register(nowPlaying) { $0.nowPlaying.isEnabled }
        activity.register(pomodoro) { _ in true } // Pomodoro is a core Screen.
        activity.register(battery) { $0.battery.isEnabled }
        activity.register(network) { $0.network.isEnabled }
        activity.register(context) { $0.context.isEnabled }
        activity.register(codingContext) { $0.codingContext.isEnabled }
        activity.register(claudeCode) { $0.claudeCode.isEnabled }

        wireCrossProviderSignals()
        wireSounds()
    }

    /// Context signals flow through the coordinator so providers never talk
    /// to each other directly.
    private func wireCrossProviderSignals() {
        nowPlaying.$state
            .map { $0?.playbackState == .playing }
            .removeDuplicates()
            .sink { [weak self] playing in self?.context.setMediaPlaying(playing) }
            .store(in: &cancellables)

        pomodoro.engine.$runState
            .combineLatest(pomodoro.engine.$phase)
            .map { runState, phase in runState == .running && phase == .focus }
            .removeDuplicates()
            .sink { [weak self] running in self?.context.setPomodoroFocusRunning(running) }
            .store(in: &cancellables)
    }

    private func wireSounds() {
        interruptions.$current
            .compactMap { $0 }
            .filter { $0.provider == "pomodoro" }
            .sink { [weak self] _ in
                guard let self, self.settings.settings.pomodoro.soundEnabled else { return }
                NSSound(named: "Glass")?.play()
            }
            .store(in: &cancellables)
    }

    func shutdown() {
        activity.stopAll()
        settings.saveNow()
    }
}
