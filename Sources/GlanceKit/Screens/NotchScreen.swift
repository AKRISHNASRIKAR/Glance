import Foundation

/// The kind of experience a Screen renders. Extensible: new cases can be
/// added without breaking persisted configurations (unknown types are
/// dropped on decode rather than crashing).
public enum ScreenType: String, Codable, CaseIterable, Sendable {
    case nowPlaying
    case pomodoro
    case claudeCode
    case codingContext

    /// Screens that exist on first launch.
    public static let defaultTypes: [ScreenType] = [.nowPlaying, .pomodoro]

    /// Screens the user may only add after enabling the backing provider.
    public var requiresProvider: Bool {
        switch self {
        case .nowPlaying, .pomodoro: return false
        case .claudeCode, .codingContext: return true
        }
    }

    public var displayName: String {
        switch self {
        case .nowPlaying: return "Now Playing"
        case .pomodoro: return "Pomodoro"
        case .claudeCode: return "Claude Code"
        case .codingContext: return "Coding Context"
        }
    }
}

/// One configured Screen in the horizontal pager.
/// Position is the index within `ScreenStore.screens`.
public struct NotchScreen: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var type: ScreenType
    public var isEnabled: Bool

    public init(id: UUID = UUID(), type: ScreenType, isEnabled: Bool = true) {
        self.id = id
        self.type = type
        self.isEnabled = isEnabled
    }

    /// Tolerant decoding: a screen persisted by a future version with an
    /// unknown type decodes as nil and is filtered out by the store.
    public static func decodeTolerantly(from decoder: Decoder) -> NotchScreen? {
        try? NotchScreen(from: decoder)
    }
}
