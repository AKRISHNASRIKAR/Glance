import Foundation
import Testing
@testable import GlanceKit

@MainActor
struct InterruptionEngineTests {
    private func makeEngine() -> (InterruptionEngine, TestClock) {
        let clock = TestClock()
        let engine = InterruptionEngine(scheduler: clock, timeSource: clock)
        return (engine, clock)
    }

    private func interruption(
        provider: String = "test",
        kind: String = "event",
        priority: InterruptionPriority = .normal,
        duration: TimeInterval = 4,
        persistent: Bool = false,
        createdAt: Date? = nil
    ) -> NotchInterruption {
        NotchInterruption(
            provider: provider, kind: kind, title: kind,
            priority: priority, createdAt: createdAt ?? Date(timeIntervalSince1970: 1_700_000_000),
            displayDuration: duration, isPersistent: persistent
        )
    }

    @Test func displaysWhenIdle() {
        let (engine, _) = makeEngine()
        engine.present(interruption(kind: "a"))
        #expect(engine.current?.kind == "a")
    }

    @Test func expiresAfterDisplayDuration() {
        let (engine, clock) = makeEngine()
        engine.present(interruption(kind: "a", duration: 4))
        clock.advance(by: 3.9)
        #expect(engine.current?.kind == "a")
        clock.advance(by: 0.2)
        #expect(engine.current == nil)
    }

    @Test func higherPriorityPreempts() {
        let (engine, _) = makeEngine()
        engine.present(interruption(kind: "normal", priority: .normal))
        engine.present(interruption(kind: "urgent", priority: .urgent))
        #expect(engine.current?.kind == "urgent")
    }

    @Test func equalPriorityQueuesInsteadOfPreempting() {
        let (engine, clock) = makeEngine()
        engine.present(interruption(kind: "first", priority: .normal, duration: 4))
        engine.present(interruption(kind: "second", priority: .normal, duration: 4))
        #expect(engine.current?.kind == "first")
        clock.advance(by: 4.5)
        #expect(engine.current?.kind == "second")
    }

    @Test func lowerPriorityNeverStealsTheSurface() {
        let (engine, _) = makeEngine()
        engine.present(interruption(kind: "important", priority: .important))
        engine.present(interruption(kind: "passive", priority: .passive))
        #expect(engine.current?.kind == "important")
    }

    @Test func preemptedPersistentInterruptionReturns() {
        let (engine, clock) = makeEngine()
        engine.present(interruption(kind: "claude", priority: .important, persistent: true))
        engine.present(interruption(kind: "battery", priority: .urgent, duration: 3))
        #expect(engine.current?.kind == "battery")
        clock.advance(by: 3.5)
        // The persistent interruption comes back after the urgent one expires.
        #expect(engine.current?.kind == "claude")
    }

    @Test func preemptedTransientInterruptionIsDropped() {
        let (engine, clock) = makeEngine()
        engine.present(interruption(kind: "track", priority: .passive, duration: 3))
        engine.present(interruption(kind: "critical", priority: .urgent, duration: 3))
        clock.advance(by: 3.5)
        #expect(engine.current == nil)
    }

    @Test func debounceDropsRepeatedKind() {
        let (engine, clock) = makeEngine()
        engine.present(interruption(kind: "track-changed", priority: .passive, duration: 2))
        clock.advance(by: 2.5) // expired, but within the 8 s debounce window
        engine.present(interruption(kind: "track-changed", priority: .passive))
        #expect(engine.current == nil)
        clock.advance(by: 6)   // now outside the debounce window
        engine.present(interruption(kind: "track-changed", priority: .passive))
        #expect(engine.current?.kind == "track-changed")
    }

    @Test func staleQueuedInterruptionIsSkipped() {
        let (engine, clock) = makeEngine()
        engine.present(interruption(kind: "current", priority: .normal, duration: 40, createdAt: clock.now))
        engine.present(interruption(kind: "stale", priority: .normal, duration: 4, createdAt: clock.now))
        clock.advance(by: 41) // queued "stale" is now past the 30 s queue TTL
        #expect(engine.current == nil)
    }

    @Test func persistentInterruptionSurvivesUntilResolved() {
        let (engine, clock) = makeEngine()
        engine.present(interruption(provider: "claude-code", kind: "needs-input", priority: .important, persistent: true))
        clock.advance(by: 300)
        #expect(engine.current?.kind == "needs-input")
        engine.resolve(provider: "claude-code", kind: "needs-input")
        #expect(engine.current == nil)
    }

    @Test func dismissCurrentShowsNextInQueue() {
        let (engine, _) = makeEngine()
        engine.present(interruption(kind: "first", priority: .normal, duration: 60))
        engine.present(interruption(kind: "second", priority: .normal, duration: 60))
        engine.dismissCurrent()
        #expect(engine.current?.kind == "second")
        engine.dismissCurrent()
        #expect(engine.current == nil)
    }

    @Test func queueOrdersByPriorityThenArrival() {
        let (engine, clock) = makeEngine()
        engine.present(interruption(kind: "showing", priority: .urgent, duration: 2))
        engine.present(interruption(kind: "low", priority: .normal, duration: 10, createdAt: clock.now))
        engine.present(interruption(kind: "high", priority: .important, duration: 10, createdAt: clock.now))
        clock.advance(by: 2.5)
        #expect(engine.current?.kind == "high")
    }

    @Test func removeAllFromProviderClearsQueueAndCurrent() {
        let (engine, _) = makeEngine()
        engine.present(interruption(provider: "battery", kind: "low", priority: .important, persistent: true))
        engine.present(interruption(provider: "battery", kind: "critical", priority: .normal))
        engine.removeAll(fromProvider: "battery")
        #expect(engine.current == nil)
    }
}
