import GlanceKit
import SwiftUI

/// Shared visual atoms every Pomodoro renderer draws from, so the five
/// appearances read as one product (same ring math, same session-progress
/// language, same stepper) while still looking distinct. See docs/POMODORO.md.

// MARK: - Ring

/// The circular progress ring used by every appearance except Minimal
/// (pure typography) and Ambient (its own hairline variant below).
/// Parameterized rather than redrawn per-appearance.
struct PomodoroRingView: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 5
    var trackOpacity: Double = 0.10
    var glow: Bool = false
    var reduceMotion: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !glow || reduceMotion)) { timeline in
            let pulse = glow && !reduceMotion
                ? (sin(timeline.date.timeIntervalSinceReferenceDate * .pi / 2) + 1) / 2
                : 0.0
            GeometryReader { proxy in
                let diameter = min(proxy.size.width, proxy.size.height)
                let radius = diameter / 2
                let fraction = min(max(progress, 0.004), 1)
                let angle = fraction * 2 * .pi - .pi / 2
                ZStack {
                    Circle()
                        .stroke(color.opacity(glow ? 0.08 + pulse * 0.06 : 0), lineWidth: lineWidth + 5)
                        .blur(radius: 4)
                        .scaleEffect(1 + pulse * 0.035)
                    Circle().stroke(Color.white.opacity(trackOpacity), lineWidth: lineWidth)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(
                            AngularGradient(colors: [color.opacity(0.45), color], center: .center),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .shadow(color: color.opacity(glow ? 0.3 + pulse * 0.25 : 0), radius: 4 + pulse * 3)
                    Circle()
                        .fill(color)
                        .frame(width: lineWidth + 1, height: lineWidth + 1)
                        .shadow(color: color.opacity(glow ? 0.8 : 0), radius: 5)
                        .position(x: radius + radius * cos(angle), y: radius + radius * sin(angle))
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: progress)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Session progress

/// One segment per focus session before the next long break; filled
/// segments count completed sessions in the current cycle. Small bars
/// rather than dots — reads as a mini progress track, not decoration.
struct PomodoroSessionTrack: View {
    let total: Int
    let filled: Int
    var color: Color
    var barSize: CGSize = CGSize(width: 9, height: 3.5)
    var spacing: CGFloat = 3

    @ViewBuilder
    var body: some View {
        if total > 1 {
            HStack(spacing: spacing) {
                ForEach(0..<total, id: \.self) { index in
                    Capsule()
                        .fill(index < filled ? color.opacity(0.9) : Color.white.opacity(0.14))
                        .frame(width: barSize.width, height: barSize.height)
                }
            }
        }
    }
}

// MARK: - Duration stepper (idle only)

/// Steps through `PomodoroSettings.durationPresetsMinutes` — grouped into
/// one pill (rather than two floating buttons) with the target minutes
/// shown between the arrows, so the control reads as a single unit.
struct PomodoroStepperPill: View {
    let minutes: Int
    let onAdjust: (Int) -> Void

    var body: some View {
        VStack(spacing: 3) {
            stepperButton("chevron.up") { onAdjust(1) }
            Text("\(minutes)")
                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
            stepperButton("chevron.down") { onAdjust(-1) }
        }
        .padding(.vertical, 6)
        .frame(width: 22)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private func stepperButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 16, height: 12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "chevron.up" ? "Increase duration" : "Decrease duration")
    }
}

// MARK: - Phase selector (idle only)

/// Focus/Break segmented chooser, shared by every appearance that shows
/// one while idle.
struct PomodoroPhaseSelector: View {
    let phase: PomodoroPhase
    let onSelect: (PomodoroPhase) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) { phaseChips }
            VStack(alignment: .leading, spacing: 4) { phaseChips }
        }
    }

    @ViewBuilder
    private var phaseChips: some View {
        chip("Focus", isSelected: phase == .focus) { onSelect(.focus) }
        chip("Break", isSelected: phase != .focus) { onSelect(.shortBreak) }
    }

    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(isSelected ? .black : .white.opacity(0.7))
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .background(Capsule().fill(isSelected ? Color.white.opacity(0.92) : Color.white.opacity(0.1)))
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Ring + header composite

/// The "stepper (idle) + ring + phase header + controls" composite shared
/// by Classic and Artwork — the two appearances rich enough to want all of
/// it. They differ only in accent color and a couple of size/opacity
/// constants, which is exactly what's parameterized here; layout-level
/// concerns (outer padding, top-alignment) stay in each renderer's own body.
struct PomodoroRingHeaderLayout: View {
    let state: PomodoroDisplayState
    let actions: PomodoroActions
    var accentColor: Color
    var ringSize: CGFloat
    var lineWidth: CGFloat
    var trackOpacity: Double = 0.10
    var glow: Bool = false
    var labelOpacity: Double = 0.78
    var reduceMotion: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ringZone
            VStack(alignment: .leading, spacing: 10) {
                header
                PomodoroControlsRow(state: state, actions: actions)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var ringZone: some View {
        HStack(spacing: 6) {
            if state.runState == .idle {
                PomodoroStepperPill(minutes: state.currentDurationMinutes, onAdjust: actions.adjustDuration)
            }
            ZStack {
                PomodoroRingView(
                    progress: state.progress,
                    color: accentColor,
                    lineWidth: lineWidth,
                    trackOpacity: trackOpacity,
                    glow: glow,
                    reduceMotion: reduceMotion
                )
                VStack(spacing: 3) {
                    Text(state.timeText)
                        .font(.system(size: 21, weight: .medium, design: .rounded).monospacedDigit())
                        .tracking(-0.6)
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: state.timeText)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(state.runState == .paused ? "PAUSED" : state.phase.displayName.uppercased())
                        .font(.system(size: 7, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(accentColor.opacity(0.8))
                }
                .padding(.horizontal, 4)
            }
            .frame(width: ringSize, height: ringSize)
            .accessibilityLabel("\(state.phase.displayName), \(state.timeText) remaining")
        }
    }

    private var header: some View {
        Group {
            if state.runState == .idle {
                VStack(alignment: .leading, spacing: 9) {
                    PomodoroPhaseSelector(phase: state.phase, onSelect: actions.selectPhase)
                    PomodoroSessionTrack(total: state.sessionsBeforeLongBreak, filled: state.filledSessions, color: accentColor)
                }
            } else {
                HStack(spacing: 7) {
                    Circle().fill(accentColor).frame(width: 5, height: 5)
                    Text(state.phase.displayName.uppercased())
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(labelOpacity))
                    Spacer(minLength: 0)
                    PomodoroSessionTrack(total: state.sessionsBeforeLongBreak, filled: state.filledSessions, color: accentColor)
                }
            }
        }
    }
}

// MARK: - Primary + reset controls

/// The Start/Pause/Resume + Reset/Skip row shared by Classic and Artwork
/// (Compact and Minimal use their own, sparer variants of the same spec).
struct PomodoroControlsRow: View {
    let state: PomodoroDisplayState
    let actions: PomodoroActions

    var body: some View {
        let primary = PomodoroPrimaryActionSpec(runState: state.runState, actions: actions)
        HStack(spacing: 8) {
            Button(action: primary.handler) {
                Label(primary.title, systemImage: primary.systemImage)
            }
            .buttonStyle(NotchCapsuleButtonStyle(prominent: true))

            switch state.runState {
            case .idle:
                if state.canSkipBreak {
                    Button("Skip", action: actions.skipBreak)
                        .buttonStyle(NotchCapsuleButtonStyle(prominent: false))
                }
            case .running, .paused:
                NotchIconButton(systemName: "arrow.counterclockwise", size: 11, action: actions.reset)
                    .accessibilityLabel("Reset timer")
            }
        }
    }
}
