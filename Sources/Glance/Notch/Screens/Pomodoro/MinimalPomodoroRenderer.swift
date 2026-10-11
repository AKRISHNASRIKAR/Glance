import GlanceKit
import SwiftUI

/// The time stays on the screen's true center; transport lives independently
/// at the right edge so Start/Pause/Resume never shifts the countdown.
struct MinimalPomodoroRenderer: View {
    let state: PomodoroDisplayState
    let actions: PomodoroActions
    var reduceMotion: Bool = false

    var body: some View {
        ZStack {
            HStack(spacing: 5) {
                arrow("chevron.left", direction: -1)
                Text(state.timeText)
                    .font(.system(size: 30, weight: .light, design: .rounded).monospacedDigit())
                    .tracking(-1)
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: state.timeText)
                    .lineLimit(1).minimumScaleFactor(0.65)
                    .frame(width: 102)
                    .accessibilityLabel("\(state.phase.displayName), \(state.timeText) remaining")
                arrow("chevron.right", direction: 1)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            HStack {
                Spacer()
                let primary = PomodoroPrimaryActionSpec(runState: state.runState, actions: actions)
                NotchIconButton(systemName: primary.systemImage, size: 13, action: primary.handler)
                    .accessibilityLabel(primary.title)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contextMenu {
            if state.runState == .idle {
                Button("Focus") { actions.selectPhase(.focus) }
                Button("Rest") { actions.selectPhase(.shortBreak) }
            } else {
                Button("Reset timer", action: actions.reset)
            }
            if state.canSkipBreak { Button("Skip rest", action: actions.skipBreak) }
        }
    }

    private func arrow(_ symbol: String, direction: Int) -> some View {
        Button { actions.adjustMinimalDuration(direction) } label: {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                .frame(width: 16, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(state.runState == .idle ? 0.55 : 0.15))
        .disabled(state.runState != .idle)
        .accessibilityLabel(direction > 0 ? "Increase duration" : "Decrease duration")
    }
}
