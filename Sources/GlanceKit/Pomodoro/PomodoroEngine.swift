import Combine
import Foundation

public enum PomodoroPhase: String, Sendable, Equatable {
    case focus
    case shortBreak
    case longBreak

    public var displayName: String {
        switch self {
        case .focus: return "Focus"
        case .shortBreak: return "Break"
        case .longBreak: return "Long Break"
        }
    }
}

public enum PomodoroRunState: String, Sendable, Equatable {
    case idle      // phase not started
    case running
    case paused
}

/// Deliberately simple Pomodoro state machine. Not a task manager.
///
/// Time is computed from wall-clock anchors (`phaseEndDate`), not by
/// decrementing a counter, so a missed timer tick (App Nap, sleep) cannot
/// drift the timer. The 1 Hz tick only exists to refresh the UI.
@MainActor
public final class PomodoroEngine: ObservableObject {
    @Published public private(set) var phase: PomodoroPhase = .focus
    @Published public private(set) var runState: PomodoroRunState = .idle
    /// Seconds remaining in the current phase.
    @Published public private(set) var remaining: TimeInterval = 0
    /// Completed focus sessions in the current cycle.
    @Published public private(set) var completedFocusSessions: Int = 0

    /// Fired when a phase completes naturally (not on reset/skip-to-idle).
    public var onPhaseCompleted: (@MainActor (PomodoroPhase) -> Void)?

    private var configuration: PomodoroSettings
    private var phaseEndDate: Date?
    private var pausedRemaining: TimeInterval?
    private var tickHandle: GlanceCancellable?
    private let scheduler: GlanceScheduler
    private let timeSource: TimeSource

    public init(
        configuration: PomodoroSettings,
        scheduler: GlanceScheduler = TimerScheduler(),
        timeSource: TimeSource = SystemTimeSource()
    ) {
        self.configuration = configuration
        self.scheduler = scheduler
        self.timeSource = timeSource
        self.remaining = configuration.focusDuration
    }

    public func updateConfiguration(_ newValue: PomodoroSettings) {
        configuration = newValue
        // Only apply new durations to phases that haven't started.
        if runState == .idle {
            remaining = duration(of: phase)
        }
    }

    public var phaseDuration: TimeInterval { duration(of: phase) }

    /// 0...1 progress through the current phase.
    public var progress: Double {
        let total = duration(of: phase)
        guard total > 0 else { return 0 }
        return min(max(1 - remaining / total, 0), 1)
    }

    // MARK: Controls

    public func start() {
        guard runState == .idle else { return }
        beginPhase(phase)
    }

    public func pause() {
        guard runState == .running, let end = phaseEndDate else { return }
        pausedRemaining = max(end.timeIntervalSince(timeSource.now), 0)
        remaining = pausedRemaining ?? 0
        phaseEndDate = nil
        runState = .paused
        stopTicking()
    }

    public func resume() {
        guard runState == .paused, let left = pausedRemaining else { return }
        pausedRemaining = nil
        phaseEndDate = timeSource.now.addingTimeInterval(left)
        runState = .running
        startTicking()
        tick()
    }

    /// Reset the current phase to idle (does not fire completion).
    public func reset() {
        stopTicking()
        phaseEndDate = nil
        pausedRemaining = nil
        runState = .idle
        phase = .focus
        completedFocusSessions = 0
        remaining = duration(of: .focus)
    }

    /// Skip the current break and return to an idle focus phase (or start it
    /// if auto-start focus is on).
    public func skipBreak() {
        guard phase != .focus else { return }
        stopTicking()
        phaseEndDate = nil
        pausedRemaining = nil
        advance(to: .focus, autoStart: configuration.autoStartFocus)
    }

    /// Advance simulated/real time. In production this is invoked by the
    /// 1 Hz tick; tests call it directly after moving a fake TimeSource.
    public func tick() {
        guard runState == .running, let end = phaseEndDate else { return }
        let left = end.timeIntervalSince(timeSource.now)
        if left <= 0 {
            completeCurrentPhase()
        } else {
            remaining = left
        }
    }

    // MARK: Phase machine

    private func beginPhase(_ newPhase: PomodoroPhase) {
        phase = newPhase
        let total = duration(of: newPhase)
        remaining = total
        phaseEndDate = timeSource.now.addingTimeInterval(total)
        runState = .running
        startTicking()
    }

    private func completeCurrentPhase() {
        let finished = phase
        stopTicking()
        phaseEndDate = nil
        remaining = 0

        if finished == .focus {
            completedFocusSessions += 1
        }

        onPhaseCompleted?(finished)

        switch finished {
        case .focus:
            let isLong = completedFocusSessions % max(configuration.sessionsBeforeLongBreak, 1) == 0
            advance(to: isLong ? .longBreak : .shortBreak, autoStart: configuration.autoStartBreak)
        case .shortBreak, .longBreak:
            if finished == .longBreak { completedFocusSessions = 0 }
            advance(to: .focus, autoStart: configuration.autoStartFocus)
        }
    }

    private func advance(to newPhase: PomodoroPhase, autoStart: Bool) {
        phase = newPhase
        remaining = duration(of: newPhase)
        if autoStart {
            beginPhase(newPhase)
        } else {
            runState = .idle
        }
    }

    private func duration(of phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .focus: return configuration.focusDuration
        case .shortBreak: return configuration.shortBreakDuration
        case .longBreak: return configuration.longBreakDuration
        }
    }

    // MARK: Ticking (UI refresh only — state derives from wall clock)

    private func startTicking() {
        stopTicking()
        scheduleNextTick()
    }

    private func scheduleNextTick() {
        tickHandle = scheduler.schedule(after: 1.0) { [weak self] in
            guard let self, self.runState == .running else { return }
            self.tick()
            if self.runState == .running { self.scheduleNextTick() }
        }
    }

    private func stopTicking() {
        tickHandle?.cancel()
        tickHandle = nil
    }
}
