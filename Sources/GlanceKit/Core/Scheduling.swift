import Foundation

/// A cancellable handle returned by `GlanceScheduler.schedule`.
public protocol GlanceCancellable: Sendable {
    func cancel()
}

/// Abstraction over deferred execution so the engines are testable without
/// real timers. All work is scheduled onto the main actor.
public protocol GlanceScheduler: Sendable {
    @discardableResult
    func schedule(after interval: TimeInterval, _ action: @escaping @MainActor @Sendable () -> Void) -> GlanceCancellable
}

/// Abstraction over "now" so time-dependent logic is testable.
public protocol TimeSource: Sendable {
    var now: Date { get }
}

public struct SystemTimeSource: TimeSource {
    public init() {}
    public var now: Date { Date() }
}

/// Production scheduler backed by `Timer` on the main run loop.
/// Timers use 10% tolerance to allow the system to coalesce wakeups.
public struct TimerScheduler: GlanceScheduler {
    public init() {}

    private final class Handle: GlanceCancellable, @unchecked Sendable {
        // Lock-protected; the timer itself is only touched on the main thread.
        private let lock = NSLock()
        private var timer: Timer?
        private var cancelled = false

        func adopt(_ timer: Timer) {
            lock.lock()
            let wasCancelled = cancelled
            if !wasCancelled { self.timer = timer }
            lock.unlock()
            if wasCancelled { timer.invalidate() } // adopt() runs on main
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let t = timer
            timer = nil
            lock.unlock()
            guard let t else { return }
            if Thread.isMainThread {
                t.invalidate()
            } else {
                DispatchQueue.main.async { t.invalidate() }
            }
        }
    }

    @discardableResult
    public func schedule(after interval: TimeInterval, _ action: @escaping @MainActor @Sendable () -> Void) -> GlanceCancellable {
        let handle = Handle()
        let installOnMain: @Sendable () -> Void = {
            let timer = Timer(timeInterval: max(interval, 0), repeats: false) { _ in
                MainActor.assumeIsolated { action() }
            }
            timer.tolerance = max(interval * 0.1, 0.05)
            RunLoop.main.add(timer, forMode: .common)
            handle.adopt(timer)
        }
        if Thread.isMainThread {
            installOnMain()
        } else {
            DispatchQueue.main.async(execute: installOnMain)
        }
        return handle
    }
}
