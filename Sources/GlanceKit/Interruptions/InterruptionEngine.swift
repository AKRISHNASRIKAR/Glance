import Combine
import Foundation

/// Coordinates temporary, priority-driven notch events.
///
/// Rules (all covered by tests):
/// - **Debouncing**: an interruption with the same `provider` + `kind` as one
///   shown within `debounceInterval` is dropped. Passive events cannot
///   repeatedly steal the surface.
/// - **Priority preemption**: a strictly higher-priority interruption
///   replaces the current one immediately. A preempted *persistent*
///   interruption returns to the queue; a preempted transient one is dropped
///   (it had its moment).
/// - **Minimum display duration**: equal/lower priority arrivals never cut
///   an interruption short; they queue.
/// - **Expiration**: transient interruptions end after `displayDuration`.
///   Queued interruptions that go stale (older than `queueTTL`) are skipped.
/// - **Persistence**: persistent interruptions stay until dismissed or
///   resolved by their provider via `resolve(provider:kind:)`.
/// - **Return to previous Screen**: the engine only occupies the surface
///   temporarily; when `current` becomes nil the UI returns to whatever
///   Screen was selected. The engine never mutates Screen selection.
@MainActor
public final class InterruptionEngine: ObservableObject {
    @Published public private(set) var current: NotchInterruption?

    public var debounceInterval: TimeInterval = 8
    public var queueTTL: TimeInterval = 30

    private var queue: [NotchInterruption] = []
    private var lastShownAt: [String: Date] = [:]
    private var expiryHandle: GlanceCancellable?

    private let scheduler: GlanceScheduler
    private let timeSource: TimeSource

    public init(scheduler: GlanceScheduler = TimerScheduler(), timeSource: TimeSource = SystemTimeSource()) {
        self.scheduler = scheduler
        self.timeSource = timeSource
    }

    // MARK: Presenting

    public func present(_ interruption: NotchInterruption) {
        let key = debounceKey(interruption)
        if let last = lastShownAt[key], timeSource.now.timeIntervalSince(last) < debounceInterval {
            GlanceLog.interruptionEngine.debug("Debounced \(key, privacy: .public)")
            return
        }

        guard let showing = current else {
            display(interruption)
            return
        }

        if interruption.priority > showing.priority {
            // Preempt. Persistent interruptions survive preemption.
            if showing.isPersistent {
                queue.append(showing)
            }
            display(interruption)
        } else {
            enqueue(interruption)
        }
    }

    /// A provider resolved its own persistent condition (e.g. Claude got its
    /// input). Removes matching interruptions wherever they are.
    public func resolve(provider: String, kind: String? = nil) {
        queue.removeAll { $0.provider == provider && (kind == nil || $0.kind == kind) }
        if let showing = current, showing.provider == provider, kind == nil || showing.kind == kind {
            endCurrent()
        }
    }

    /// User dismissal of the current interruption.
    public func dismissCurrent() {
        guard current != nil else { return }
        endCurrent()
    }

    public func performAction(_ action: InterruptionAction) {
        action.handler()
        endCurrent()
    }

    /// Remove everything (used when the app resets or a provider stops).
    public func removeAll(fromProvider provider: String? = nil) {
        if let provider {
            queue.removeAll { $0.provider == provider }
            if current?.provider == provider { endCurrent() }
        } else {
            queue.removeAll()
            if current != nil { endCurrent() }
        }
    }

    // MARK: Internals

    private func debounceKey(_ i: NotchInterruption) -> String { "\(i.provider)/\(i.kind)" }

    private func enqueue(_ interruption: NotchInterruption) {
        queue.append(interruption)
        // Highest priority first; FIFO within a priority.
        queue.sort { lhs, rhs in
            lhs.priority == rhs.priority ? lhs.createdAt < rhs.createdAt : lhs.priority > rhs.priority
        }
    }

    private func display(_ interruption: NotchInterruption) {
        expiryHandle?.cancel()
        expiryHandle = nil
        current = interruption
        lastShownAt[debounceKey(interruption)] = timeSource.now
        GlanceLog.interruptionEngine.info(
            "Displaying \(interruption.provider, privacy: .public)/\(interruption.kind, privacy: .public) priority=\(interruption.priority.rawValue, privacy: .public)"
        )
        if !interruption.isPersistent {
            let id = interruption.id
            expiryHandle = scheduler.schedule(after: interruption.displayDuration) { [weak self] in
                guard let self, self.current?.id == id else { return }
                self.endCurrent()
            }
        }
    }

    private func endCurrent() {
        expiryHandle?.cancel()
        expiryHandle = nil
        current = nil
        showNextFromQueue()
    }

    private func showNextFromQueue() {
        let now = timeSource.now
        while !queue.isEmpty {
            let next = queue.removeFirst()
            // Skip stale transient events; persistent ones never go stale.
            if !next.isPersistent, now.timeIntervalSince(next.createdAt) > queueTTL {
                continue
            }
            display(next)
            return
        }
    }
}
