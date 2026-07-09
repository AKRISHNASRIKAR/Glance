import Combine
import Foundation

extension Array {
    /// Same semantics as SwiftUI's `move(fromOffsets:toOffset:)`, provided
    /// here so GlanceKit stays UI-framework-free.
    mutating func moveElements(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.compactMap { indices.contains($0) ? self[$0] : nil }
        guard !moving.isEmpty else { return }
        let adjustedDestination = destination - source.filter { $0 < destination }.count
        for index in source.sorted(by: >) where indices.contains(index) {
            remove(at: index)
        }
        insert(contentsOf: moving, at: Swift.min(Swift.max(adjustedDestination, 0), count))
    }
}

/// Owns the horizontal Screen pager state: which Screens exist, their order,
/// and which one is selected.
///
/// Restoration behavior (documented):
/// - The last selected Screen is remembered across open/close and relaunch.
/// - If the notch is reopened more than `screenResetAfterSeconds` (default
///   30 minutes) after it was last closed, selection returns to the first
///   Screen. A stale deep position in the pager is worse than a predictable
///   home Screen.
@MainActor
public final class ScreenStore: ObservableObject {
    @Published public private(set) var screens: [NotchScreen] = []
    @Published public private(set) var selectedScreenID: UUID?

    private let settings: SettingsStore
    private let timeSource: TimeSource
    private var lastClosedAt: Date?
    private var cancellable: AnyCancellable?

    public init(settings: SettingsStore, timeSource: TimeSource = SystemTimeSource()) {
        self.settings = settings
        self.timeSource = timeSource
        sync(from: settings.settings)
        cancellable = settings.$settings.sink { [weak self] value in
            self?.sync(from: value)
        }
    }

    private func sync(from value: GlanceSettings) {
        if screens != value.screens { screens = value.screens }
        if selectedScreenID != value.selectedScreenID { selectedScreenID = value.selectedScreenID }
    }

    // MARK: Derived state

    public var enabledScreens: [NotchScreen] { screens.filter(\.isEnabled) }

    public var selectedScreen: NotchScreen? {
        enabledScreens.first { $0.id == selectedScreenID } ?? enabledScreens.first
    }

    public var selectedIndex: Int {
        guard let id = selectedScreen?.id else { return 0 }
        return enabledScreens.firstIndex { $0.id == id } ?? 0
    }

    // MARK: Selection & navigation

    public func select(id: UUID) {
        guard enabledScreens.contains(where: { $0.id == id }) else { return }
        settings.update { $0.selectedScreenID = id }
    }

    /// Move selection horizontally. Clamped at the ends — the pager does not
    /// wrap, so spatial position stays predictable.
    public func navigate(by delta: Int) {
        let screens = enabledScreens
        guard !screens.isEmpty else { return }
        let target = min(max(selectedIndex + delta, 0), screens.count - 1)
        select(id: screens[target].id)
    }

    // MARK: Restoration

    /// Call when the expanded notch closes.
    public func notchDidClose() {
        lastClosedAt = timeSource.now
    }

    /// Call when the expanded notch is about to open. Applies the
    /// long-idle reset described above.
    public func notchWillOpen() {
        let resetAfter = settings.settings.general.screenResetAfterSeconds
        if let closed = lastClosedAt,
           timeSource.now.timeIntervalSince(closed) > resetAfter,
           let first = enabledScreens.first {
            settings.update { $0.selectedScreenID = first.id }
        }
        lastClosedAt = nil
    }

    // MARK: Configuration (Settings → Notch Screens)

    /// Screen types that can currently be added: implemented types that are
    /// not already present, and whose provider (if required) is enabled.
    public func addableScreenTypes(providerEnabled: (ScreenType) -> Bool) -> [ScreenType] {
        ScreenType.allCases.filter { type in
            !screens.contains { $0.type == type } && (!type.requiresProvider || providerEnabled(type))
        }
    }

    public func addScreen(type: ScreenType) {
        guard !screens.contains(where: { $0.type == type }) else { return }
        settings.update { $0.screens.append(NotchScreen(type: type)) }
    }

    public func removeScreen(id: UUID) {
        settings.update { s in
            s.screens.removeAll { $0.id == id }
            if s.screens.isEmpty {
                // Never allow an empty pager.
                s.screens = ScreenType.defaultTypes.map { NotchScreen(type: $0) }
            }
            if s.selectedScreenID == id { s.selectedScreenID = s.screens.first?.id }
        }
    }

    public func moveScreen(fromOffsets: IndexSet, toOffset: Int) {
        settings.update { $0.screens.moveElements(fromOffsets: fromOffsets, toOffset: toOffset) }
    }

    public func setScreen(id: UUID, enabled: Bool) {
        settings.update { s in
            guard let idx = s.screens.firstIndex(where: { $0.id == id }) else { return }
            s.screens[idx].isEnabled = enabled
            let enabledScreens = s.screens.filter(\.isEnabled)
            if !enabledScreens.contains(where: { $0.id == s.selectedScreenID }) {
                s.selectedScreenID = enabledScreens.first?.id ?? s.screens.first?.id
            }
        }
    }

    /// Remove Screens whose backing provider was disabled (e.g. the user
    /// turned off Claude Code integration).
    public func removeScreens(ofType type: ScreenType) {
        guard screens.contains(where: { $0.type == type }) else { return }
        settings.update { s in
            s.screens.removeAll { $0.type == type }
            if s.screens.isEmpty {
                s.screens = ScreenType.defaultTypes.map { NotchScreen(type: $0) }
            }
            if !s.screens.contains(where: { $0.id == s.selectedScreenID }) {
                s.selectedScreenID = s.screens.first?.id
            }
        }
    }
}
