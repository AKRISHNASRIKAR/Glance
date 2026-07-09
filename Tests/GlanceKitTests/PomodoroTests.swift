import Foundation
import Testing
@testable import GlanceKit

@MainActor
struct PomodoroTests {
    private func makeEngine(_ mutate: (inout PomodoroSettings) -> Void = { _ in }) -> (PomodoroEngine, TestClock) {
        var config = PomodoroSettings()
        mutate(&config)
        let clock = TestClock()
        return (PomodoroEngine(configuration: config, scheduler: clock, timeSource: clock), clock)
    }

    @Test func startsIdleWithFullFocusDuration() {
        let (engine, _) = makeEngine()
        #expect(engine.runState == .idle)
        #expect(engine.phase == .focus)
        #expect(engine.remaining == 25 * 60)
    }

    @Test func runningCountsDownWithWallClock() {
        let (engine, clock) = makeEngine()
        engine.start()
        clock.advance(by: 60)
        #expect(abs(engine.remaining - 24 * 60) < 1.5)
        #expect(engine.progress > 0.03 && engine.progress < 0.05)
    }

    @Test func pauseFreezesAndResumeContinues() {
        let (engine, clock) = makeEngine()
        engine.start()
        clock.advance(by: 5 * 60)
        engine.pause()
        let frozen = engine.remaining
        clock.advance(by: 10 * 60)
        #expect(engine.remaining == frozen)
        #expect(engine.runState == .paused)
        engine.resume()
        clock.advance(by: 60)
        #expect(abs(engine.remaining - (frozen - 60)) < 1.5)
    }

    @Test func focusCompletionAdvancesToShortBreak() {
        let (engine, clock) = makeEngine()
        engine.start()
        clock.advance(by: 25 * 60 + 2)
        #expect(engine.phase == .shortBreak)
        #expect(engine.runState == .idle) // autoStartBreak defaults off
        #expect(engine.completedFocusSessions == 1)
    }

    @Test func completionFiresCallback() {
        let (engine, clock) = makeEngine()
        var completed: [PomodoroPhase] = []
        engine.onPhaseCompleted = { completed.append($0) }
        engine.start()
        clock.advance(by: 25 * 60 + 2)
        #expect(completed == [.focus])
    }

    @Test func longBreakAfterConfiguredSessions() {
        let (engine, clock) = makeEngine { $0.sessionsBeforeLongBreak = 2; $0.autoStartBreak = true; $0.autoStartFocus = true }
        engine.start()
        // Session 1 focus → short break → session 2 focus → long break.
        clock.advance(by: 25 * 60 + 2)
        #expect(engine.phase == .shortBreak)
        clock.advance(by: 5 * 60 + 2)
        #expect(engine.phase == .focus)
        clock.advance(by: 25 * 60 + 2)
        #expect(engine.phase == .longBreak)
    }

    @Test func autoStartBreakBeginsCountdown() {
        let (engine, clock) = makeEngine { $0.autoStartBreak = true }
        engine.start()
        clock.advance(by: 25 * 60 + 2)
        #expect(engine.phase == .shortBreak)
        #expect(engine.runState == .running)
    }

    @Test func resetReturnsToIdleFocus() {
        let (engine, clock) = makeEngine()
        engine.start()
        clock.advance(by: 10 * 60)
        engine.reset()
        #expect(engine.runState == .idle)
        #expect(engine.phase == .focus)
        #expect(engine.remaining == 25 * 60)
        #expect(engine.completedFocusSessions == 0)
    }

    @Test func skipBreakReturnsToFocus() {
        let (engine, clock) = makeEngine()
        engine.start()
        clock.advance(by: 25 * 60 + 2)
        #expect(engine.phase == .shortBreak)
        engine.skipBreak()
        #expect(engine.phase == .focus)
        #expect(engine.runState == .idle)
    }

    @Test func configurationChangeAppliesWhenIdle() {
        let (engine, _) = makeEngine()
        var config = PomodoroSettings()
        config.focusDuration = 50 * 60
        engine.updateConfiguration(config)
        #expect(engine.remaining == 50 * 60)
    }

    @Test func configurationChangeDoesNotDisruptRunningPhase() {
        let (engine, clock) = makeEngine()
        engine.start()
        clock.advance(by: 60)
        var config = PomodoroSettings()
        config.focusDuration = 50 * 60
        engine.updateConfiguration(config)
        #expect(engine.remaining < 25 * 60)
    }
}

@MainActor
struct PomodoroProviderTests {
    @Test func focusCompletionEmitsImportantInterruption() {
        let clock = TestClock()
        let (settings, _) = makeTestSettingsStore(clock: clock)
        let provider = PomodoroProvider(settings: settings, scheduler: clock, timeSource: clock)
        var emitted: [NotchInterruption] = []
        provider.emitInterruption = { emitted.append($0) }
        provider.start()
        provider.engine.start()
        clock.advance(by: 25 * 60 + 2)
        #expect(emitted.count == 1)
        #expect(emitted.first?.kind == "focus-complete")
        #expect(emitted.first?.priority == .important)
    }

    @Test func completionInterruptionRespectsSetting() {
        let clock = TestClock()
        let (settings, _) = makeTestSettingsStore(clock: clock)
        settings.update { $0.pomodoro.interruptionOnCompletion = false }
        let provider = PomodoroProvider(settings: settings, scheduler: clock, timeSource: clock)
        var emitted: [NotchInterruption] = []
        provider.emitInterruption = { emitted.append($0) }
        provider.start()
        provider.engine.start()
        clock.advance(by: 25 * 60 + 2)
        #expect(emitted.isEmpty)
    }
}
