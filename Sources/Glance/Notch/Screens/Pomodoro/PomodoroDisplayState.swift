import GlanceKit
import SwiftUI

/// Immutable snapshot of everything a Pomodoro renderer needs to draw the
/// screen, computed once per render from the single `PomodoroEngine` +
/// `PomodoroSettings`. Renderers only ever read this snapshot — never
/// `PomodoroEngine` or `SettingsStore` directly — so the timer/business
/// logic they draw from exists in exactly one place. See docs/POMODORO.md.
struct PomodoroDisplayState: Equatable {
    var phase: PomodoroPhase
    var runState: PomodoroRunState
    var remaining: TimeInterval
    var progress: Double
    var completedFocusSessions: Int
    var sessionsBeforeLongBreak: Int
    var currentDurationMinutes: Int

    /// The ring/accent color every appearance but Artwork uses.
    var phaseColor: Color {
        phase == .focus
            ? Color(red: 1, green: 0.65, blue: 0.39)
            : Color(red: 0.43, green: 0.85, blue: 0.72)
    }

    /// Artwork's background wash is the one place break phases need to read
    /// as visually distinct from each other (short break vs. long break),
    /// per the brief's cool blue / soft green / purple mapping — kept
    /// separate from `phaseColor` rather than replacing it everywhere. A
    /// pure function of `phase` alone (not a full state snapshot) so
    /// callers that only need the tint — like `NotchRootView`'s full-bleed
    /// background — don't have to build one just to read it.
    static func artworkTint(for phase: PomodoroPhase) -> Color {
        switch phase {
        case .focus: return Color(red: 0.42, green: 0.66, blue: 0.52)
        case .shortBreak: return Color(red: 0.42, green: 0.64, blue: 0.78)
        case .longBreak: return Color(red: 0.65, green: 0.52, blue: 0.78)
        }
    }

    var artworkTint: Color { Self.artworkTint(for: phase) }

    var timeText: String { TimeFormatting.minutesSeconds(remaining) }

    /// A break can always be skipped; focus cannot.
    var canSkipBreak: Bool { phase != .focus }

    /// One segment per focus session before the next long break — reads
    /// `sessionsBeforeLongBreak` directly since every call site already
    /// wants this state's own value, not an arbitrary total.
    var filledSessions: Int {
        let total = sessionsBeforeLongBreak
        let mod = completedFocusSessions % total
        return mod == 0 && completedFocusSessions > 0 ? total : mod
    }

    @MainActor
    init(engine: PomodoroEngine, settings: PomodoroSettings) {
        phase = engine.phase
        runState = engine.runState
        remaining = engine.remaining
        progress = engine.progress
        completedFocusSessions = engine.completedFocusSessions
        sessionsBeforeLongBreak = max(settings.sessionsBeforeLongBreak, 1)
        currentDurationMinutes = Int(engine.phaseDuration / 60)
    }
}

/// Everything a renderer can do to the timer. Every renderer wires its
/// buttons/gestures to these closures instead of touching `PomodoroEngine`
/// or `SettingsStore` directly — this is the only path through which any
/// appearance can affect the timer, keeping that logic in one place.
struct PomodoroActions {
    var start: @MainActor @Sendable () -> Void
    var pause: @MainActor @Sendable () -> Void
    var resume: @MainActor @Sendable () -> Void
    var reset: @MainActor @Sendable () -> Void
    var skipBreak: @MainActor @Sendable () -> Void
    var selectPhase: @MainActor @Sendable (PomodoroPhase) -> Void
    /// +1 / -1 through `PomodoroSettings.durationPresetsMinutes`.
    var adjustDuration: @MainActor @Sendable (Int) -> Void
    var adjustMinimalDuration: @MainActor @Sendable (Int) -> Void

    @MainActor
    init(engine: PomodoroEngine, settings: SettingsStore) {
        start = { engine.start() }
        pause = { engine.pause() }
        resume = { engine.resume() }
        reset = { engine.reset() }
        skipBreak = { engine.skipBreak() }
        selectPhase = { engine.selectPhase($0) }
        adjustDuration = { direction in
            Self.adjustDuration(by: direction, engine: engine, settings: settings)
        }
        adjustMinimalDuration = { direction in
            Self.adjustDuration(by: direction, engine: engine, settings: settings, fixedPresets: [300, 900, 1500, 3000])
        }
    }

    @MainActor
    private static func presetsSeconds(_ settings: SettingsStore) -> [TimeInterval] {
        let minutes = Set(settings.settings.pomodoro.durationPresetsMinutes.filter { $0 > 0 })
        guard !minutes.isEmpty else { return [300, 900, 1500, 3000] }
        return minutes.sorted().map { TimeInterval($0 * 60) }
    }

    @MainActor
    private static func setDuration(_ value: TimeInterval, engine: PomodoroEngine, settings: SettingsStore) {
        settings.update { s in
            switch engine.phase {
            case .focus: s.pomodoro.focusDuration = value
            case .shortBreak: s.pomodoro.shortBreakDuration = value
            case .longBreak: s.pomodoro.longBreakDuration = value
            }
        }
    }

    /// Moves to the next/previous preset. If the current duration isn't
    /// exactly one of the presets (e.g. set via the Settings slider), the
    /// first step snaps to the nearest preset in that direction.
    @MainActor
    private static func adjustDuration(by direction: Int, engine: PomodoroEngine, settings: SettingsStore, fixedPresets: [TimeInterval]? = nil) {
        let pool = fixedPresets ?? presetsSeconds(settings)
        let current = engine.phaseDuration
        if let exactIndex = pool.firstIndex(of: current) {
            let target = min(max(exactIndex + direction, 0), pool.count - 1)
            setDuration(pool[target], engine: engine, settings: settings)
        } else if direction > 0 {
            setDuration(pool.first(where: { $0 > current }) ?? pool[pool.count - 1], engine: engine, settings: settings)
        } else {
            setDuration(pool.last(where: { $0 < current }) ?? pool[0], engine: engine, settings: settings)
        }
    }
}

/// The primary button's label/icon/handler for the current run state —
/// centralized so "what does the main button say and do" (Start → Pause →
/// Resume) lives in one place rather than being re-derived by every
/// renderer's own switch statement.
struct PomodoroPrimaryActionSpec {
    let title: String
    let systemImage: String
    let handler: @MainActor @Sendable () -> Void

    @MainActor
    init(runState: PomodoroRunState, actions: PomodoroActions) {
        switch runState {
        case .idle:
            title = "Start"
            systemImage = "play.fill"
            handler = actions.start
        case .running:
            title = "Pause"
            systemImage = "pause.fill"
            handler = actions.pause
        case .paused:
            title = "Resume"
            systemImage = "play.fill"
            handler = actions.resume
        }
    }
}
