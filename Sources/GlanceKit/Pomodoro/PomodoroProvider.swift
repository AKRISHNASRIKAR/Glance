import Combine
import Foundation

/// Wraps the PomodoroEngine as an activity provider: keeps its configuration
/// in sync with settings and turns phase completions into IMPORTANT
/// Notch Interruptions.
@MainActor
public final class PomodoroProvider: ActivityProvider, ObservableObject {
    public let id = "pomodoro"
    public private(set) var status: ProviderStatus = .disabled

    public var emitInterruption: (@MainActor (NotchInterruption) -> Void)?
    public var resolveInterruption: (@MainActor (String?) -> Void)?

    public let engine: PomodoroEngine

    private let settings: SettingsStore
    private var cancellable: AnyCancellable?

    public init(settings: SettingsStore, scheduler: GlanceScheduler = TimerScheduler(), timeSource: TimeSource = SystemTimeSource()) {
        self.settings = settings
        self.engine = PomodoroEngine(
            configuration: settings.settings.pomodoro,
            scheduler: scheduler,
            timeSource: timeSource
        )
        engine.onPhaseCompleted = { [weak self] phase in
            self?.phaseCompleted(phase)
        }
    }

    public func start() {
        status = .running
        cancellable = settings.$settings
            .map(\.pomodoro)
            .removeDuplicates()
            .sink { [weak self] config in self?.engine.updateConfiguration(config) }
    }

    public func stop() {
        cancellable = nil
        engine.reset()
        status = .disabled
    }

    private func phaseCompleted(_ phase: PomodoroPhase) {
        guard settings.settings.pomodoro.interruptionOnCompletion else { return }
        let interruption: NotchInterruption
        switch phase {
        case .focus:
            interruption = NotchInterruption(
                provider: id,
                kind: "focus-complete",
                title: "Focus complete",
                subtitle: "Time for a break",
                symbolName: "checkmark.circle.fill",
                priority: .important,
                displayDuration: 6
            )
        case .shortBreak, .longBreak:
            interruption = NotchInterruption(
                provider: id,
                kind: "break-complete",
                title: "Break over",
                subtitle: "Ready to focus?",
                symbolName: "timer",
                priority: .important,
                displayDuration: 6
            )
        }
        emitInterruption?(interruption)
    }
}
