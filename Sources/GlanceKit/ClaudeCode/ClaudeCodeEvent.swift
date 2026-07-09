import Foundation

/// Normalized Claude Code hook events.
///
/// Glance integrates with Claude Code exclusively through its official hooks
/// (https://docs.anthropic.com/en/docs/claude-code/hooks). Hooks write small
/// files into a private spool directory; Glance watches the directory,
/// normalizes each file into one of these events, and deletes the file.
///
/// Privacy: the installed hooks are designed so prompt text and tool inputs
/// never reach disk — `UserPromptSubmit` and `PreToolUse` hooks discard
/// stdin and write empty marker files. See ClaudeCodeHookInstaller.
public enum ClaudeCodeEventKind: String, Sendable, Equatable {
    /// SessionStart hook — a session opened.
    case sessionStart
    /// Empty marker from UserPromptSubmit — Claude began working.
    case promptSubmitted
    /// Empty marker from PreToolUse — Claude is actively using tools.
    case toolActivity
    /// Notification hook — Claude needs input or permission.
    case notification
    /// Stop hook — Claude finished responding.
    case stop
    /// SessionEnd hook — the session closed.
    case sessionEnd
}

public struct ClaudeCodeEvent: Sendable, Equatable {
    public var kind: ClaudeCodeEventKind
    public var sessionID: String?
    /// Present only for `.notification`: the short system message such as
    /// "Claude needs your permission to use Bash". Never a user prompt.
    public var message: String?
    public var receivedAt: Date

    public init(kind: ClaudeCodeEventKind, sessionID: String? = nil, message: String? = nil, receivedAt: Date = Date()) {
        self.kind = kind
        self.sessionID = sessionID
        self.message = message
        self.receivedAt = receivedAt
    }
}

/// Parses spool files into events. Pure and testable.
public enum ClaudeCodeEventNormalizer {
    /// Spool file names follow `<event>-<random>.<json|marker>`.
    public static func normalize(fileName: String, contents: Data?, at date: Date = Date()) -> ClaudeCodeEvent? {
        let base = fileName.split(separator: "-").first.map(String.init) ?? ""
        let kind: ClaudeCodeEventKind?
        switch base {
        case "sessionstart": kind = .sessionStart
        case "prompt": kind = .promptSubmitted
        case "tool": kind = .toolActivity
        case "notification": kind = .notification
        case "stop": kind = .stop
        case "sessionend": kind = .sessionEnd
        default: kind = nil
        }
        guard let kind else { return nil }

        var sessionID: String?
        var message: String?
        if let contents, !contents.isEmpty,
           let json = try? JSONSerialization.jsonObject(with: contents) as? [String: Any] {
            sessionID = json["session_id"] as? String
            if kind == .notification {
                message = json["message"] as? String
            }
        }
        return ClaudeCodeEvent(kind: kind, sessionID: sessionID, message: message, receivedAt: date)
    }
}

// MARK: - State machine

/// The reliable Claude Code states derivable from official hooks.
///
/// Deliberately small: hooks do not report granular activity ("editing
/// file X", "running tests") or failures, so Glance does not pretend to
/// know them. `failed` exists in the model for future use but is never
/// produced by the current hook integration (documented limitation).
public enum ClaudeCodeState: String, Sendable, Equatable {
    case idle
    case working
    case needsInput
    case permissionRequired
    case completed
    case failed
}

/// Folds events into the current state. Pure and testable.
public struct ClaudeCodeStateMachine: Sendable, Equatable {
    public private(set) var state: ClaudeCodeState = .idle
    public private(set) var sessionID: String?
    public private(set) var sessionStartedAt: Date?
    public private(set) var workingSince: Date?
    public private(set) var lastCompletedAt: Date?
    /// Duration of the last completed working stretch.
    public private(set) var lastCompletedDuration: TimeInterval?

    public init() {}

    public mutating func apply(_ event: ClaudeCodeEvent) {
        if let id = event.sessionID { sessionID = id }
        switch event.kind {
        case .sessionStart:
            state = .idle
            sessionStartedAt = event.receivedAt
            workingSince = nil
        case .promptSubmitted, .toolActivity:
            if state != .working {
                state = .working
                workingSince = event.receivedAt
            }
            if sessionStartedAt == nil { sessionStartedAt = event.receivedAt }
        case .notification:
            let message = event.message?.lowercased() ?? ""
            state = message.contains("permission") ? .permissionRequired : .needsInput
        case .stop:
            if let since = workingSince {
                lastCompletedDuration = event.receivedAt.timeIntervalSince(since)
            }
            workingSince = nil
            lastCompletedAt = event.receivedAt
            state = .completed
        case .sessionEnd:
            state = .idle
            sessionID = nil
            sessionStartedAt = nil
            workingSince = nil
        }
    }
}
