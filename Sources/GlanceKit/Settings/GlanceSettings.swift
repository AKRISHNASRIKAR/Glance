import Foundation

/// The complete, typed settings schema. Persisted as JSON in
/// `~/Library/Application Support/Glance/settings.json`.
///
/// Every field has a default so partially-written or older settings files
/// decode cleanly. Schema changes bump `schemaVersion` and add a migration
/// step in `SettingsStore.migrate`.
public struct GlanceSettings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int

    // MARK: Screens

    public var screens: [NotchScreen]
    public var selectedScreenID: UUID?

    // MARK: Feature areas

    public var general: GeneralSettings
    public var nowPlaying: NowPlayingSettings
    public var pomodoro: PomodoroSettings
    public var battery: BatterySettings
    public var network: NetworkSettings
    public var context: ContextSettings
    public var codingContext: CodingContextSettings
    public var claudeCode: ClaudeCodeSettings
    public var privacy: PrivacySettings

    public init() {
        schemaVersion = Self.currentSchemaVersion
        // First-launch experience: exactly Now Playing + Pomodoro.
        screens = ScreenType.defaultTypes.map { NotchScreen(type: $0) }
        selectedScreenID = screens.first?.id
        general = GeneralSettings()
        nowPlaying = NowPlayingSettings()
        pomodoro = PomodoroSettings()
        battery = BatterySettings()
        network = NetworkSettings()
        context = ContextSettings()
        codingContext = CodingContextSettings()
        claudeCode = ClaudeCodeSettings()
        privacy = PrivacySettings()
    }

    /// Tolerant decode: missing keys fall back to defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = GlanceSettings()
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? defaults.schemaVersion
        screens = try c.decodeIfPresent([NotchScreen].self, forKey: .screens) ?? defaults.screens
        selectedScreenID = try c.decodeIfPresent(UUID.self, forKey: .selectedScreenID)
        general = try c.decodeIfPresent(GeneralSettings.self, forKey: .general) ?? defaults.general
        nowPlaying = try c.decodeIfPresent(NowPlayingSettings.self, forKey: .nowPlaying) ?? defaults.nowPlaying
        pomodoro = try c.decodeIfPresent(PomodoroSettings.self, forKey: .pomodoro) ?? defaults.pomodoro
        battery = try c.decodeIfPresent(BatterySettings.self, forKey: .battery) ?? defaults.battery
        network = try c.decodeIfPresent(NetworkSettings.self, forKey: .network) ?? defaults.network
        context = try c.decodeIfPresent(ContextSettings.self, forKey: .context) ?? defaults.context
        codingContext = try c.decodeIfPresent(CodingContextSettings.self, forKey: .codingContext) ?? defaults.codingContext
        claudeCode = try c.decodeIfPresent(ClaudeCodeSettings.self, forKey: .claudeCode) ?? defaults.claudeCode
        privacy = try c.decodeIfPresent(PrivacySettings.self, forKey: .privacy) ?? defaults.privacy
    }
}

// MARK: - General

public struct GeneralSettings: Codable, Equatable, Sendable {
    /// Launch Glance when the user logs in.
    public var launchAtLogin: Bool = false
    /// Show a compact top-center surface on displays without a physical notch.
    public var showOnNotchlessDisplays: Bool = true
    /// After this many seconds of the notch being closed, reopening returns
    /// to the first Screen instead of the last selected one.
    /// Documented behavior: 30 minutes.
    public var screenResetAfterSeconds: TimeInterval = 30 * 60

    public init() {}
}

// MARK: - Now Playing

public enum PlayerAppearance: String, Codable, CaseIterable, Sendable {
    /// Black notch background, compact square artwork.
    case minimal
    /// Blurred translucent album artwork fills the expanded Screen.
    case artwork
}

public struct NowPlayingSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool = true
    public var appearance: PlayerAppearance = .minimal
    /// 0...1, mapped to a blur radius range in the UI layer.
    public var artworkBlur: Double = 0.55
    /// 0...1, how strongly the artwork shows through (inverse of dimming floor).
    public var backgroundIntensity: Double = 0.7
    /// Adaptive contrast: brighter artwork gets a stronger dark overlay.
    public var adaptiveContrast: Bool = true
    public var showAlbumArtwork: Bool = true
    public var showPlaybackProgress: Bool = true
    public var showPreviousNextControls: Bool = true
    /// Experimental: system-wide Now Playing via Apple's private
    /// MediaRemote framework (sees any app's media, e.g. browser tabs).
    /// Off by default. See docs/NOW_PLAYING.md.
    public var enableSystemMediaRemote: Bool = false

    public init() {}

    /// Tolerant decode: a settings file written before `enableSystemMediaRemote`
    /// existed (or any other field here) must still decode instead of
    /// throwing and resetting the whole settings file to defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NowPlayingSettings()
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? d.isEnabled
        appearance = try c.decodeIfPresent(PlayerAppearance.self, forKey: .appearance) ?? d.appearance
        artworkBlur = try c.decodeIfPresent(Double.self, forKey: .artworkBlur) ?? d.artworkBlur
        backgroundIntensity = try c.decodeIfPresent(Double.self, forKey: .backgroundIntensity) ?? d.backgroundIntensity
        adaptiveContrast = try c.decodeIfPresent(Bool.self, forKey: .adaptiveContrast) ?? d.adaptiveContrast
        showAlbumArtwork = try c.decodeIfPresent(Bool.self, forKey: .showAlbumArtwork) ?? d.showAlbumArtwork
        showPlaybackProgress = try c.decodeIfPresent(Bool.self, forKey: .showPlaybackProgress) ?? d.showPlaybackProgress
        showPreviousNextControls = try c.decodeIfPresent(Bool.self, forKey: .showPreviousNextControls) ?? d.showPreviousNextControls
        enableSystemMediaRemote = try c.decodeIfPresent(Bool.self, forKey: .enableSystemMediaRemote) ?? d.enableSystemMediaRemote
    }
}

// MARK: - Pomodoro

public struct PomodoroSettings: Codable, Equatable, Sendable {
    public var focusDuration: TimeInterval = 25 * 60
    public var shortBreakDuration: TimeInterval = 5 * 60
    public var longBreakDuration: TimeInterval = 15 * 60
    /// Default cycle: focus → short break → focus → long break.
    public var sessionsBeforeLongBreak: Int = 2
    public var autoStartBreak: Bool = false
    public var autoStartFocus: Bool = false
    public var soundEnabled: Bool = true
    public var interruptionOnCompletion: Bool = true

    public init() {}
}

// MARK: - Battery

public struct BatterySettings: Codable, Equatable, Sendable {
    /// Optional provider — off by default.
    public var isEnabled: Bool = false
    public var notifyChargerConnected: Bool = true
    public var notifyChargerDisconnected: Bool = false
    public var notifyEightyPercent: Bool = true
    public var notifyFullyCharged: Bool = true
    public var notifyLowBattery: Bool = true
    public var notifyCriticalBattery: Bool = true
    public var lowBatteryThreshold: Int = 20
    public var criticalBatteryThreshold: Int = 10

    public init() {}
}

// MARK: - Network

public enum NetworkVisibilityMode: String, Codable, CaseIterable, Sendable {
    case highActivity
    case downloadingOnly
    case always
}

public enum NetworkFormat: String, Codable, CaseIterable, Sendable {
    case compact
    case detailed
}

public struct NetworkSettings: Codable, Equatable, Sendable {
    /// Optional provider — off by default.
    public var isEnabled: Bool = false
    public var visibilityMode: NetworkVisibilityMode = .highActivity
    /// Bytes/second above which throughput counts as "high activity".
    public var activityThresholdBytesPerSecond: Double = 5 * 1_000_000
    /// High activity must be sustained this long before surfacing.
    public var sustainSeconds: TimeInterval = 3
    public var showDownloadSpeed: Bool = true
    public var showUploadSpeed: Bool = true
    public var format: NetworkFormat = .compact
    public var notifyConnectivityChanges: Bool = true

    public init() {}
}

// MARK: - Context

public struct ContextSettings: Codable, Equatable, Sendable {
    /// Context awareness master switch — off by default.
    public var isEnabled: Bool = false
    /// Local history retention.
    public var retention: HistoryRetention = .sevenDays

    // Always-allowed signals (still gated by isEnabled).
    public var trackActiveApplications: Bool = true
    public var trackApplicationTime: Bool = true

    // Privacy-sensitive signals — explicit opt-in, off by default.
    public var trackWindowTitles: Bool = false
    public var trackBrowserDomains: Bool = false
    public var trackTerminalProcesses: Bool = false

    public init() {}
}

public enum HistoryRetention: String, Codable, CaseIterable, Sendable {
    case todayOnly
    case sevenDays
    case thirtyDays
    case forever

    public var maxAge: TimeInterval? {
        switch self {
        case .todayOnly: return 24 * 3600
        case .sevenDays: return 7 * 24 * 3600
        case .thirtyDays: return 30 * 24 * 3600
        case .forever: return nil
        }
    }
}

// MARK: - Coding Context

public enum ProjectDetectionMode: String, Codable, CaseIterable, Sendable {
    /// Only the frontmost application identifies the coding session.
    case applicationOnly
    /// Detect the project from the document/window path where the app
    /// exposes it via public APIs (Implemented for apps that publish a
    /// document URL; window-title reading is opt-in and Planned).
    case gitRepository
}

public struct CodingContextSettings: Codable, Equatable, Sendable {
    /// Optional provider — off by default.
    public var isEnabled: Bool = false
    public var showTimeSpentCoding: Bool = true
    public var showCurrentProject: Bool = false
    public var showCurrentApplication: Bool = true
    public var showGitBranch: Bool = false
    /// Bundle identifiers treated as coding applications.
    public var codingApplications: [String] = CodingContextSettings.defaultCodingApps
    public var projectDetection: ProjectDetectionMode = .applicationOnly
    /// Only surface a coding session after this much continuous activity.
    public var displayAfterSeconds: TimeInterval = 5 * 60
    /// Hide project names while screen sharing (when detection is reliable).
    public var hideProjectDuringScreenSharing: Bool = true

    public static let defaultCodingApps: [String] = [
        "com.microsoft.VSCode",
        "com.apple.dt.Xcode",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.zed.Zed",
        "com.jetbrains.intellij",
        "com.sublimetext.4",
        "com.github.GitHubClient",
        "com.todesktop.230313mzl4w4u92", // Cursor
    ]

    public init() {}
}

// MARK: - Claude Code

public struct ClaudeCodeSettings: Codable, Equatable, Sendable {
    /// Optional provider — off by default.
    public var isEnabled: Bool = false
    public var interruptOnNeedsInput: Bool = true
    public var interruptOnPermissionRequired: Bool = true
    public var interruptOnCompleted: Bool = true
    public var interruptOnFailed: Bool = true
    /// Session durations may be stored in local history. Prompts never are.
    public var storeSessionDurations: Bool = true

    public init() {}
}

// MARK: - Privacy

public struct PrivacySettings: Codable, Equatable, Sendable {
    /// Applications Glance must never observe, even when context tracking
    /// is enabled. Bundle identifiers.
    public var neverTrackBundleIdentifiers: [String] = []
    /// Hide sensitive activity metadata while the screen is shared/recorded.
    public var hideSensitiveWhileScreenSharing: Bool = true

    public init() {}
}
