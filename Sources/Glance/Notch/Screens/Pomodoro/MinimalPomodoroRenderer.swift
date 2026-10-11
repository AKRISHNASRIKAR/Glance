import GlanceKit
import SwiftUI

/// Minimal — almost entirely typography. No ring, no stepper, no session
/// track: just the mode, a large timer, a hairline progress rule, and one
/// primary action. Flow's defining trick is restraint; this is Glance's
/// version of that same idea.
struct MinimalPomodoroRenderer: View {
    let state: PomodoroDisplayState
    let actions: PomodoroActions
    var reduceMotion: Bool = false

    var body: some View {
        VStack(spacing: 10) {
            Text(state.phase.displayName.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.4)
                .foregroundStyle(.white.opacity(0.45))

            Text(state.timeText)
                .font(.system(size: 34, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)

            progressRule

            actionRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.vertical, 8)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: state.phase)
    }

    private var progressRule: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(state.phaseColor.opacity(0.85))
                    .frame(width: proxy.size.width * max(state.progress, 0.015))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: state.progress)
            }
        }
        .frame(width: 120, height: 2)
    }

    @ViewBuilder
    private var actionRow: some View {
        let primary = PomodoroPrimaryActionSpec(runState: state.runState, actions: actions)
        HStack(spacing: 12) {
            plainTextButton(primary.title, action: primary.handler, emphasized: true)
            switch state.runState {
            case .idle:
                if state.canSkipBreak {
                    dot
                    plainTextButton("Skip", action: actions.skipBreak)
                }
            case .running, .paused:
                dot
                plainTextButton("Reset", action: actions.reset)
            }
        }
    }

    private var dot: some View {
        Circle().fill(Color.white.opacity(0.25)).frame(width: 2.5, height: 2.5)
    }

    private func plainTextButton(_ title: String, action: @escaping () -> Void, emphasized: Bool = false) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: emphasized ? .semibold : .medium))
                .foregroundStyle(.white.opacity(emphasized ? 0.92 : 0.5))
        }
        .buttonStyle(.plain)
    }
}
