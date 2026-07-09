import Foundation
import os

/// Unified logging categories for Glance.
///
/// Privacy rule: never log track titles, project names, window titles,
/// prompts, or any user content at levels persisted to disk. Use `.public`
/// only for structural information (state names, counts, durations).
public enum GlanceLog {
    public static let subsystem = "app.glance.Glance"

    public static let application = Logger(subsystem: subsystem, category: "Application")
    public static let activityEngine = Logger(subsystem: subsystem, category: "ActivityEngine")
    public static let interruptionEngine = Logger(subsystem: subsystem, category: "InterruptionEngine")
    public static let screenSystem = Logger(subsystem: subsystem, category: "ScreenSystem")
    public static let contextEngine = Logger(subsystem: subsystem, category: "ContextEngine")
    public static let provider = Logger(subsystem: subsystem, category: "Provider")
    public static let nowPlaying = Logger(subsystem: subsystem, category: "NowPlaying")
    public static let pomodoro = Logger(subsystem: subsystem, category: "Pomodoro")
    public static let claudeCode = Logger(subsystem: subsystem, category: "ClaudeCode")
    public static let network = Logger(subsystem: subsystem, category: "Network")
    public static let battery = Logger(subsystem: subsystem, category: "Battery")
    public static let persistence = Logger(subsystem: subsystem, category: "Persistence")
}
