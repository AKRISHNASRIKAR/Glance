import GlanceKit
import SwiftUI

/// The Pomodoro Screen. Deliberately minimal: phase, time, one primary
/// action. While idle, a Focus / Break selector lets you jump straight to
/// either phase; the automatic cycle (focus → short break → focus → long
/// break by default) still runs on its own.
struct PomodoroScreenView: View {
    @EnvironmentObject var engine: PomodoroEngine

    var body: some View {
        HStack(spacing: 16) {
            ring
            VStack(alignment: .leading, spacing: 8) {
                if engine.runState == .idle {
                    phaseSelector
                } else {
                    Text(engine.phase.displayName.uppercased())
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(phaseColor.opacity(0.9))
                }
                controls
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var phaseColor: Color {
        engine.phase == .focus ? .orange : .mint
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 3)
            Circle()
                .trim(from: 0, to: engine.progress)
                .stroke(phaseColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(TimeFormatting.minutesSeconds(engine.remaining))
                .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(width: 74, height: 74)
        .accessibilityLabel("\(engine.phase.displayName), \(TimeFormatting.minutesSeconds(engine.remaining)) remaining")
    }

    /// Idle-only phase picker: Focus or Break (breaks longer than the short
    /// break still come from the automatic cycle).
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
