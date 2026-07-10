import GlanceKit
import SwiftUI

/// The Pomodoro Screen. One compact row — ring, optional stepper, and a
/// side column — so nothing competes with the physical notch above it or
/// the page-indicator dots below it. While idle, arrows beside the ring
/// step through the duration presets configured in Settings (5/15/25/30/50
/// min by default) instead of requiring a trip to Settings, and a Focus /
/// Break selector jumps straight to either phase; the automatic cycle
/// (focus → short break → focus → long break by default) still runs on its
/// own once started.
struct PomodoroScreenView: View {
    @EnvironmentObject var engine: PomodoroEngine
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ring
            if engine.runState == .idle {
                stepper
            }
            VStack(alignment: .leading, spacing: 6) {
                if engine.runState == .idle {
                    phaseSelector
                } else {
                    HStack(spacing: 7) {
                        Text(engine.phase.displayName.uppercased())
                            .font(.system(size: 9.5, weight: .semibold))
                            .tracking(1.5)
                            .foregroundStyle(phaseColor.opacity(0.9))
                        sessionDots
                    }
                }
                controls
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        // Top-anchored (not the frame default of centered): this screen's
        // content sits in a fixed-height box that already clears the
        // physical notch above and the page-indicator dots below, but
        // center-alignment would let any overflow spill both directions —
        // straight into the notch on top. Anchoring to the top means any
        // slack lands safely at the bottom instead.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var phaseColor: Color {
        engine.phase == .focus ? .orange : .mint
    }

    // MARK: Ring

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 4)
            Circle()
                .trim(from: 0, to: engine.progress)
                .stroke(phaseColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: engine.progress)
            Text(TimeFormatting.minutesSeconds(engine.remaining))
                .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(width: 68, height: 68)
        .accessibilityLabel("\(engine.phase.displayName), \(TimeFormatting.minutesSeconds(engine.remaining)) remaining")
    }

    // MARK: Duration stepper (idle only)

    /// Steps through `PomodoroSettings.durationPresetsMinutes` — the same
    /// pool editable in Settings — rather than a freeform +/- minute, so the
    /// arrows always land on one of the user's chosen durations.
    private var stepper: some View {
        VStack(spacing: 4) {
            stepperButton("chevron.up") { adjustDuration(by: 1) }
            stepperButton("chevron.down") { adjustDuration(by: -1) }
        }
    }

    private func stepperButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 20, height: 16)
                .background(Capsule().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "chevron.up" ? "Increase duration" : "Decrease duration")
    }

    private func presetsSeconds() -> [TimeInterval] {
        let minutes = Set(settings.settings.pomodoro.durationPresetsMinutes.filter { $0 > 0 })
        guard !minutes.isEmpty else { return [300, 900, 1500, 1800, 3000] }
        return minutes.sorted().map { TimeInterval($0 * 60) }
    }

    private func currentDuration() -> TimeInterval {
        switch engine.phase {
        case .focus: return settings.settings.pomodoro.focusDuration
        case .shortBreak: return settings.settings.pomodoro.shortBreakDuration
        case .longBreak: return settings.settings.pomodoro.longBreakDuration
        }
    }

    private func setDuration(_ value: TimeInterval) {
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
    private func adjustDuration(by direction: Int) {
        let pool = presetsSeconds()
        let current = currentDuration()
        if let exactIndex = pool.firstIndex(of: current) {
            let target = min(max(exactIndex + direction, 0), pool.count - 1)
            setDuration(pool[target])
        } else if direction > 0 {
            setDuration(pool.first(where: { $0 > current }) ?? pool[pool.count - 1])
        } else {
            setDuration(pool.last(where: { $0 < current }) ?? pool[0])
        }
    }

    // MARK: Phase selector (idle only)

    private var phaseSelector: some View {
        HStack(spacing: 4) {
            selectorChip("Focus", isSelected: engine.phase == .focus) {
                engine.selectPhase(.focus)
            }
            selectorChip("Break", isSelected: engine.phase != .focus) {
                engine.selectPhase(.shortBreak)
            }
        }
    }

    private func selectorChip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(isSelected ? .black : .white.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Session progress (running/paused only)

    /// One dot per focus session before the next long break; filled dots
    /// count completed sessions in the current cycle.
    @ViewBuilder
    private var sessionDots: some View {
        let total = max(settings.settings.pomodoro.sessionsBeforeLongBreak, 1)
        if total > 1 {
            HStack(spacing: 5) {
                ForEach(0..<total, id: \.self) { index in
                    Circle()
                        .fill(index < filledSessions(total: total) ? phaseColor.opacity(0.85) : Color.white.opacity(0.15))
                        .frame(width: 5, height: 5)
                }
            }
        }
    }

    private func filledSessions(total: Int) -> Int {
        let completed = engine.completedFocusSessions
        let mod = completed % total
        return mod == 0 && completed > 0 ? total : mod
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 8) {
            switch engine.runState {
            case .idle:
                Button("Start") { engine.start() }
                    .buttonStyle(NotchCapsuleButtonStyle(prominent: true))
                if engine.phase != .focus {
                    Button("Skip") { engine.skipBreak() }
                        .buttonStyle(NotchCapsuleButtonStyle(prominent: false))
                }
            case .running:
                Button("Pause") { engine.pause() }
                    .buttonStyle(NotchCapsuleButtonStyle(prominent: true))
                resetButton
            case .paused:
                Button("Resume") { engine.resume() }
                    .buttonStyle(NotchCapsuleButtonStyle(prominent: true))
                resetButton
            }
        }
    }

    private var resetButton: some View {
        NotchIconButton(systemName: "arrow.counterclockwise", size: 11) {
            engine.reset()
        }
        .accessibilityLabel("Reset timer")
    }
}
