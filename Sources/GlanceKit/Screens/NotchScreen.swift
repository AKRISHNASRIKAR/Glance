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

/// How much of the expanded notch a Screen occupies. Two consecutive
/// half-width Screens share one page (left / right).
public enum ScreenWidth: String, Codable, Sendable {
    case full
    case half
}

/// One configured Screen in the horizontal pager.
/// Position is the index within `ScreenStore.screens`.
public struct NotchScreen: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var type: ScreenType
    public var isEnabled: Bool
    public var width: ScreenWidth

    public init(id: UUID = UUID(), type: ScreenType, isEnabled: Bool = true, width: ScreenWidth = .full) {
        self.id = id
        self.type = type
        self.isEnabled = isEnabled
        self.width = width
    }

    /// Tolerant decoding: settings written before `width` existed default to
    /// full-width; a future unknown type fails decode and is filtered out.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        type = try c.decode(ScreenType.self, forKey: .type)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        width = try c.decodeIfPresent(ScreenWidth.self, forKey: .width) ?? .full
    }
}
