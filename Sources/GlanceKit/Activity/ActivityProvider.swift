import Foundation

/// Health of a provider, surfaced in Settings.
public enum ProviderStatus: Equatable, Sendable {
    case running
    case disabled
    case notConfigured
    case permissionRequired(String)
    case unavailable(String)
    case error(String)

    public var isRunning: Bool { self == .running }
}

/// A source of activity. Providers publish state and events to the Activity
/// Engine — they never touch the notch UI and never talk to each other.
///
/// Isolation contract: `start()` must not throw out of the engine's control;
/// failures are reported through `status`. One broken provider must never
/// affect another.
@MainActor
public protocol ActivityProvider: AnyObject {
    /// Stable identifier, e.g. "battery", "claude-code".
    var id: String { get }
    var status: ProviderStatus { get }

    /// Interruptions flow through this sink; the engine wires it before start.
    var emitInterruption: (@MainActor (NotchInterruption) -> Void)? { get set }
    /// Resolve a previously emitted persistent interruption.
    var resolveInterruption: (@MainActor (_ kind: String?) -> Void)? { get set }

    func start()
    func stop()
}
