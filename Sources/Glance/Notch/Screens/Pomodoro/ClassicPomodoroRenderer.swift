import GlanceKit
import SwiftUI

/// Centered timer: the countdown owns the ring; controls stay symmetrical
/// around it so the same composition fits full and paired notch screens.
struct ClassicPomodoroRenderer: View {
    let state: PomodoroDisplayState
    let actions: PomodoroActions
    var reduceMotion: Bool = false

    private var accent: Color {
        state.phase == .focus
            ? Color(red: 0.66, green: 0.79, blue: 0.65)
            : Color(red: 0.69, green: 0.81, blue: 0.86)
    }

    var body: some View {
        VStack(spacing: 4) {
            phaseControl.frame(height: 12)
            HStack(spacing: 16) {
                durationControl
                    .frame(width: 28)
                timer
                primaryControl
                    .frame(width: 28)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            sessionDots
        }
        .padding(.top, 4)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: state.runState)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: state.phase)
    }

    private var sessionDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<state.sessionsBeforeLongBreak, id: \.self) { index in
                Circle()
                    .fill(index < state.filledSessions ? accent : Color.white.opacity(0.16))
                    .frame(width: 4, height: 4)
            }
        }
        .frame(height: 5)
        .accessibilityLabel("\(state.filledSessions) of \(state.sessionsBeforeLongBreak) focus sessions completed")
    }

    private var timer: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [accent.opacity(0.08), .clear], center: .center, startRadius: 5, endRadius: 42))
            PomodoroRingView(
                progress: state.progress, color: accent,
                lineWidth: 2.5, trackOpacity: 0.12,
                glow: state.runState == .running, reduceMotion: reduceMotion
            )
            VStack(spacing: 3) {
                Text(state.timeText)
                    .font(.system(size: 22, weight: .medium, design: .rounded).monospacedDigit())
                    .tracking(-0.8)
                    .foregroundStyle(Color(red: 0.94, green: 0.96, blue: 0.91))
                    .contentTransition(.numericText(countsDown: true))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: state.timeText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(state.runState == .paused ? "PAUSED" : state.phase == .focus ? "WORK MODE" : "REST")
                    .font(.system(size: 6.5, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(accent.opacity(0.8))
            }
            .padding(.horizontal, 5)
        }
        .frame(width: 72, height: 72)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(state.phase.displayName), \(state.timeText) remaining, \(state.runState == .paused ? "paused" : state.runState == .running ? "running" : "ready")")
    }

    private var durationControl: some View {
        VStack(spacing: 4) {
            if state.runState == .idle {
                Button { actions.adjustDuration(1) } label: {
                    Image(systemName: "plus").font(.system(size: 10, weight: .medium))
                }
                .accessibilityLabel("Increase duration")
                Text("\(state.currentDurationMinutes)m")
                    .font(.system(size: 8, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
                Button { actions.adjustDuration(-1) } label: {
                    Image(systemName: "minus").font(.system(size: 10, weight: .medium))
                }
                .accessibilityLabel("Decrease duration")
            } else {
                Button(action: actions.reset) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.05)))
                }
                .accessibilityLabel("Reset timer")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(accent.opacity(0.7))
    }

    private var primaryControl: some View {
        let primary = PomodoroPrimaryActionSpec(runState: state.runState, actions: actions)
        return Button(action: primary.handler) {
            Image(systemName: primary.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 0.16, green: 0.24, blue: 0.18))
                .frame(width: 28, height: 28)
                .background(Circle().fill(accent))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(primary.title)
        .help(primary.title)
    }

    private var phaseControl: some View {
        HStack(spacing: 12) {
            Button("Focus") { actions.selectPhase(.focus) }
                .foregroundStyle(state.phase == .focus ? accent : .white.opacity(0.35))
                .disabled(state.runState != .idle)
            Circle().fill(Color.white.opacity(0.2)).frame(width: 2, height: 2)
            if state.canSkipBreak && state.runState != .idle {
                Button("Skip rest", action: actions.skipBreak).foregroundStyle(accent)
            } else {
                Button("Rest") { actions.selectPhase(.shortBreak) }
                    .foregroundStyle(state.phase != .focus ? accent : .white.opacity(0.35))
                    .disabled(state.runState != .idle)
            }
        }
        .font(.system(size: 8.5, weight: .medium))
        .buttonStyle(.plain)
        .disabled(state.runState != .idle && !state.canSkipBreak)
    }
}
