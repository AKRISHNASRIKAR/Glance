import Foundation

/// Priority of a Notch Interruption. Higher priorities may preempt lower ones.
public enum InterruptionPriority: Int, Codable, Comparable, Sendable, CaseIterable {
    case passive = 0
    case normal = 1
    case important = 2
    case urgent = 3

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Whether an interruption's content is safe to show while the screen is
/// shared. `sensitive` interruptions render a redacted subtitle when the
/// privacy layer requests hiding.
public enum PrivacyClassification: String, Codable, Sendable {
    case ordinary
    case sensitive
}

/// A user-visible action attached to an interruption (e.g. "Open Claude").
public struct InterruptionAction: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let handler: @MainActor @Sendable () -> Void

    public init(id: String, title: String, handler: @escaping @MainActor @Sendable () -> Void) {
        self.id = id
        self.title = title
        self.handler = handler
    }
}

/// A temporary, priority-driven notch event. Interruptions are generated
/// only by this app's activity providers — Glance never intercepts macOS
/// notifications.
public struct NotchInterruption: Identifiable, Sendable {
    public let id: UUID
    /// Provider identifier, e.g. "battery", "claude-code".
    public let provider: String
    /// Debounce key within a provider, e.g. "charger-connected".
    public let kind: String
    public let title: String
    public let subtitle: String?
    /// SF Symbol name for the compact and expanded presentation.
    public let symbolName: String?
    public let priority: InterruptionPriority
    public let createdAt: Date
    /// How long the interruption stays visible once displayed.
    public let displayDuration: TimeInterval
    /// Persistent interruptions stay until dismissed or resolved by the
    /// provider (e.g. "Claude needs input").
    public let isPersistent: Bool
    public let actions: [InterruptionAction]
    public let privacy: PrivacyClassification

    public init(
        id: UUID = UUID(),
        provider: String,
        kind: String,
        title: String,
        subtitle: String? = nil,
        symbolName: String? = nil,
        priority: InterruptionPriority,
        createdAt: Date = Date(),
        displayDuration: TimeInterval = 4,
        isPersistent: Bool = false,
        actions: [InterruptionAction] = [],
        privacy: PrivacyClassification = .ordinary
    ) {
        self.id = id
        self.provider = provider
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.priority = priority
        self.createdAt = createdAt
        self.displayDuration = displayDuration
        self.isPersistent = isPersistent
        self.actions = actions
        self.privacy = privacy
    }
}
