import Foundation

/// Broad, local-first classification of what the user is doing.
public enum ContextKind: String, Codable, CaseIterable, Sendable {
    case coding
    case studying
    case meeting
    case designing
    case entertainment
    case focus
    case away
    case general

    public var displayName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// Everything the classifier is allowed to look at. Built from opt-in
/// signals only; anything the user hasn't enabled stays nil/false.
public struct ContextSignals: Equatable, Sendable {
    public var frontmostBundleID: String?
    public var frontmostAppName: String?
    public var isMediaPlaying: Bool
    public var isPomodoroFocusRunning: Bool
    public var idleSeconds: TimeInterval

    public init(
        frontmostBundleID: String? = nil,
        frontmostAppName: String? = nil,
        isMediaPlaying: Bool = false,
        isPomodoroFocusRunning: Bool = false,
        idleSeconds: TimeInterval = 0
    ) {
        self.frontmostBundleID = frontmostBundleID
        self.frontmostAppName = frontmostAppName
        self.isMediaPlaying = isMediaPlaying
        self.isPomodoroFocusRunning = isPomodoroFocusRunning
        self.idleSeconds = idleSeconds
    }
}

/// One completed span of time in a context. Stored locally, never uploaded.
public struct ContextSession: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: ContextKind
    /// Coarse label (application name); never a window title unless the
    /// user opted into window-title tracking.
    public var label: String?
    public var start: Date
    public var end: Date

    public var duration: TimeInterval { end.timeIntervalSince(start) }

    public init(id: UUID = UUID(), kind: ContextKind, label: String? = nil, start: Date, end: Date) {
        self.id = id
        self.kind = kind
        self.label = label
        self.start = start
        self.end = end
    }
}

/// Pure classification + session tracking. No system APIs — signals are
/// pushed in by ContextProvider, sessions are pushed out to the history
/// store. Fully unit-testable.
public struct ContextEngine: Sendable {
    /// Minimum session length worth recording; shorter blips are dropped.
    public var minimumSessionDuration: TimeInterval = 60
    /// Idle time after which the user counts as away.
    public var awayAfterIdleSeconds: TimeInterval = 5 * 60

    public var codingBundleIDs: Set<String>
    public var meetingBundleIDs: Set<String> = [
        "us.zoom.xos", "com.microsoft.teams2", "com.cisco.webexmeetingsapp",
        "com.apple.FaceTime", "com.google.meet",
    ]
    public var designBundleIDs: Set<String> = [
        "com.figma.Desktop", "com.bohemiancoding.sketch3", "com.adobe.Photoshop",
        "com.adobe.illustrator", "com.linearity.curve",
    ]
    public var studyBundleIDs: Set<String> = [
        "com.apple.iBooksX", "com.apple.Preview", "md.obsidian", "notion.id",
    ]
    public var entertainmentBundleIDs: Set<String> = [
        "com.apple.TV", "com.netflix.Netflix", "com.google.Chrome.app.youtube",
    ]

    public private(set) var currentKind: ContextKind = .general
    public private(set) var currentLabel: String?
    public private(set) var currentStart: Date?

    public init(codingBundleIDs: [String] = CodingContextSettings.defaultCodingApps) {
        self.codingBundleIDs = Set(codingBundleIDs)
    }

    /// Classification order is a priority ladder: absence (away) beats
    /// intent (focus) beats activity type.
    public func classify(_ signals: ContextSignals) -> ContextKind {
        if signals.idleSeconds >= awayAfterIdleSeconds { return .away }
        if signals.isPomodoroFocusRunning { return .focus }
        if let bundle = signals.frontmostBundleID {
            if codingBundleIDs.contains(bundle) { return .coding }
            if meetingBundleIDs.contains(bundle) { return .meeting }
            if designBundleIDs.contains(bundle) { return .designing }
            if studyBundleIDs.contains(bundle) { return .studying }
            if entertainmentBundleIDs.contains(bundle) { return .entertainment }
        }
        if signals.isMediaPlaying && signals.frontmostBundleID == nil { return .entertainment }
        return .general
    }

    /// Feed new signals. Returns a finished session when the context
    /// transitioned and the previous span was long enough to record.
    public mutating func update(signals: ContextSignals, at now: Date) -> ContextSession? {
        let kind = classify(signals)
        let label = kind == .coding || kind == .meeting || kind == .designing || kind == .studying
            ? signals.frontmostAppName
            : nil

        if kind == currentKind && label == currentLabel { return nil }

        let finished = closeCurrentSession(at: now)
        currentKind = kind
        currentLabel = label
        currentStart = now
        return finished
    }

    /// Close the running session (e.g. on shutdown). Returns it if it was
    /// long enough to record.
    public mutating func closeCurrentSession(at now: Date) -> ContextSession? {
        defer { currentStart = now }
        guard let start = currentStart, now.timeIntervalSince(start) >= minimumSessionDuration else {
            return nil
        }
        // Away and general time is not interesting history.
        guard currentKind != .away, currentKind != .general else { return nil }
        return ContextSession(kind: currentKind, label: currentLabel, start: start, end: now)
    }

    /// Elapsed time in the current context.
    public func currentDuration(at now: Date) -> TimeInterval {
        guard let start = currentStart else { return 0 }
        return now.timeIntervalSince(start)
    }
}
