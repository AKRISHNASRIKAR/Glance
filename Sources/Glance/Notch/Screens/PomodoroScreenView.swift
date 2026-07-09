import GlanceKit
import SwiftUI

/// The Pomodoro Screen. Deliberately minimal: phase, time, one primary
/// action. No tasks, no analytics.
struct PomodoroScreenView: View {
    @EnvironmentObject var engine: PomodoroEngine

    var body: some View {
        let engine = self.engine
        VStack(spacing: 8) {
            Text(engine.phase.displayName.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.2)
                .foregroundStyle(phaseColor.opacity(0.9))

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: engine.progress)
                    .stroke(phaseColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(TimeFormatting.minutesSeconds(engine.remaining))
                    .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .frame(width: 88, height: 88)
            .accessibilityLabel("\(engine.phase.displayName), \(TimeFormatting.minutesSeconds(engine.remaining)) remaining")

            controls(engine: engine)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var phaseColor: Color {
        engine.phase == .focus ? .orange : .mint
    }

    @ViewBuilder
    private func controls(engine: PomodoroEngine) -> some View {
        HStack(spacing: 10) {
            switch engine.runState {
            case .idle:
                Button("Start") { engine.start() }
                    .buttonStyle(NotchCapsuleButtonStyle(prominent: true))
                if engine.phase != .focus {
                    Button("Skip Break") { engine.skipBreak() }
                        .buttonStyle(NotchCapsuleButtonStyle(prominent: false))
                }
            case .running:
                Button("Pause") { engine.pause() }
                    .buttonStyle(NotchCapsuleButtonStyle(prominent: true))
                resetButton(engine: engine)
            case .paused:
                Button("Resume") { engine.resume() }
                    .buttonStyle(NotchCapsuleButtonStyle(prominent: true))
                resetButton(engine: engine)
            }
        }
    }

    private func resetButton(engine: PomodoroEngine) -> some View {
        NotchIconButton(systemName: "arrow.counterclockwise", size: 11) {
            engine.reset()
        }
        .accessibilityLabel("Reset timer")
    }
}
