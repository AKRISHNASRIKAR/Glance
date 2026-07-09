import Foundation
@testable import GlanceKit

/// Deterministic clock + scheduler for engine tests. `advance(by:)` moves
/// time forward and fires due scheduled work in order.
final class TestClock: GlanceScheduler, TimeSource, @unchecked Sendable {
    private let lock = NSLock()
    private var _now = Date(timeIntervalSince1970: 1_700_000_000)
    private var items: [Item] = []
    private var nextID = 0

    private struct Item {
        let id: Int
        let fireAt: Date
        let action: @MainActor @Sendable () -> Void
    }

    private final class Cancellable: GlanceCancellable, @unchecked Sendable {
        let id: Int
        weak var clock: TestClock?
        init(id: Int, clock: TestClock) { self.id = id; self.clock = clock }
        func cancel() { clock?.remove(id: id) }
    }

    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return _now
    }

    @discardableResult
    func schedule(after interval: TimeInterval, _ action: @escaping @MainActor @Sendable () -> Void) -> GlanceCancellable {
        lock.lock(); defer { lock.unlock() }
        nextID += 1
        items.append(Item(id: nextID, fireAt: _now.addingTimeInterval(interval), action: action))
        return Cancellable(id: nextID, clock: self)
    }

    private func remove(id: Int) {
        lock.lock(); defer { lock.unlock() }
        items.removeAll { $0.id == id }
    }

    @MainActor
    func advance(by interval: TimeInterval) {
        let target = now.addingTimeInterval(interval)
        while true {
            lock.lock()
            guard let next = items.filter({ $0.fireAt <= target }).min(by: { $0.fireAt < $1.fireAt }) else {
                _now = target
                lock.unlock()
                return
            }
            _now = max(_now, next.fireAt)
            items.removeAll { $0.id == next.id }
            lock.unlock()
            next.action()
        }
    }
}

/// A settings store backed by a unique temp file.
@MainActor
func makeTestSettingsStore(clock: TestClock = TestClock()) -> (SettingsStore, URL) {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("glance-tests-\(UUID().uuidString)/settings.json")
    return (SettingsStore(fileURL: url, scheduler: clock), url)
}

func makeTempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("glance-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
