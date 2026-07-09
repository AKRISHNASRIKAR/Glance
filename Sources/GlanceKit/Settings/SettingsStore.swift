import Combine
import Foundation

/// Centralized, typed settings persistence.
///
/// - Single source of truth: `settings` (a value type). Mutations go through
///   `update(_:)`, which persists atomically and publishes the change.
/// - No stringly-typed UserDefaults keys anywhere in the app.
/// - Saves are debounced (250 ms) so slider drags don't hammer the disk.
@MainActor
public final class SettingsStore: ObservableObject {
    @Published public private(set) var settings: GlanceSettings

    private let fileURL: URL
    private let scheduler: GlanceScheduler
    private var pendingSave: GlanceCancellable?

    /// Default on-disk location: `~/Library/Application Support/Glance/settings.json`.
    nonisolated public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Glance/settings.json")
    }

    public init(fileURL: URL = SettingsStore.defaultFileURL(), scheduler: GlanceScheduler = TimerScheduler()) {
        self.fileURL = fileURL
        self.scheduler = scheduler
        self.settings = Self.load(from: fileURL)
    }

    // MARK: Mutation

    /// Apply a mutation to the settings value, publish it, and persist.
    public func update(_ mutate: (inout GlanceSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        guard copy != settings else { return }
        settings = copy
        scheduleSave()
    }

    /// Persist immediately (used on app termination).
    public func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        persist(settings)
    }

    // MARK: Loading & migration

    private static func load(from url: URL) -> GlanceSettings {
        guard let data = try? Data(contentsOf: url) else {
            GlanceLog.persistence.info("No settings file; using first-launch defaults")
            return GlanceSettings()
        }
        do {
            var decoded = try JSONDecoder().decode(GlanceSettings.self, from: data)
            decoded = migrate(decoded)
            decoded = sanitize(decoded)
            return decoded
        } catch {
            GlanceLog.persistence.error("Settings decode failed; using defaults: \(String(describing: error), privacy: .public)")
            return GlanceSettings()
        }
    }

    /// Schema migrations. Each step upgrades one version; steps run in order.
    static func migrate(_ input: GlanceSettings) -> GlanceSettings {
        var s = input
        // Version 1 is the initial schema — nothing to do yet. Future
        // migrations follow this pattern:
        // if s.schemaVersion < 2 { ...transform... ; s.schemaVersion = 2 }
        s.schemaVersion = GlanceSettings.currentSchemaVersion
        return s
    }

    /// Structural invariants that must hold regardless of what was on disk.
    static func sanitize(_ input: GlanceSettings) -> GlanceSettings {
        var s = input
        // At least the default screens must exist; an empty pager is broken.
        if s.screens.isEmpty {
            s.screens = ScreenType.defaultTypes.map { NotchScreen(type: $0) }
        }
        // Selected screen must reference an existing screen.
        if s.selectedScreenID == nil || !s.screens.contains(where: { $0.id == s.selectedScreenID }) {
            s.selectedScreenID = s.screens.first?.id
        }
        return s
    }

    // MARK: Persistence

    private func scheduleSave() {
        pendingSave?.cancel()
        let snapshot = settings
        pendingSave = scheduler.schedule(after: 0.25) { [weak self] in
            self?.persist(snapshot)
        }
    }

    private func persist(_ value: GlanceSettings) {
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(value)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            GlanceLog.persistence.error("Settings save failed: \(String(describing: error), privacy: .public)")
        }
    }
}
