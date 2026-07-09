import Foundation

/// Local-only storage for finished context sessions.
///
/// JSON file in Application Support. No analytics, no cloud sync. Retention
/// is enforced on every append and on load.
@MainActor
public final class ContextHistoryStore: ObservableObject {
    @Published public private(set) var sessions: [ContextSession] = []

    private let fileURL: URL
    private let timeSource: TimeSource
    private var retention: HistoryRetention

    nonisolated public static func defaultFileURL() -> URL {
        SettingsStore.defaultFileURL().deletingLastPathComponent()
            .appendingPathComponent("context-history.json")
    }

    public init(
        fileURL: URL = ContextHistoryStore.defaultFileURL(),
        retention: HistoryRetention = .sevenDays,
        timeSource: TimeSource = SystemTimeSource()
    ) {
        self.fileURL = fileURL
        self.retention = retention
        self.timeSource = timeSource
        load()
        prune()
    }

    public func setRetention(_ retention: HistoryRetention) {
        self.retention = retention
        prune()
        persist()
    }

    public func append(_ session: ContextSession) {
        sessions.append(session)
        prune()
        persist()
    }

    public func clear() {
        sessions = []
        persist()
    }

    // MARK: Summaries

    /// Total duration per context kind for sessions overlapping today.
    public func todaySummary(calendar: Calendar = .current) -> [(kind: ContextKind, label: String?, duration: TimeInterval)] {
        let startOfDay = calendar.startOfDay(for: timeSource.now)
        var totals: [String: (ContextKind, String?, TimeInterval)] = [:]
        for session in sessions where session.end > startOfDay {
            let clippedStart = max(session.start, startOfDay)
            let duration = session.end.timeIntervalSince(clippedStart)
            let key = "\(session.kind.rawValue)|\(session.label ?? "")"
            let existing = totals[key]?.2 ?? 0
            totals[key] = (session.kind, session.label, existing + duration)
        }
        return totals.values.sorted { $0.2 > $1.2 }.map { (kind: $0.0, label: $0.1, duration: $0.2) }
    }

    // MARK: Internals

    private func prune() {
        guard let maxAge = retention.maxAge else { return }
        let cutoff = timeSource.now.addingTimeInterval(-maxAge)
        sessions.removeAll { $0.end < cutoff }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            sessions = try JSONDecoder().decode([ContextSession].self, from: data)
        } catch {
            GlanceLog.persistence.error("Context history decode failed: \(String(describing: error), privacy: .public)")
            sessions = []
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            GlanceLog.persistence.error("Context history save failed: \(String(describing: error), privacy: .public)")
        }
    }
}
