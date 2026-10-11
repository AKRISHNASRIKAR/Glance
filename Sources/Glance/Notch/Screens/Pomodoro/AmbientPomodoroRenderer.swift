import GlanceKit
import SwiftUI

/// Ambient — the calmest appearance. Just the time, a hairline arc behind
/// it at very low opacity, and no other chrome at rest; controls fade in
/// only on hover so the surface stays almost empty otherwise.
struct AmbientPomodoroRenderer: View {
    let state: PomodoroDisplayState
    let actions: PomodoroActions
    var reduceMotion: Bool = false

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                PomodoroRingView(
                    progress: state.progress,
                    color: state.phaseColor.opacity(0.7),
                    lineWidth: 2,
                    trackOpacity: 0.05,
                    reduceMotion: reduceMotion
                )
                Text(state.timeText)
                    .font(.system(size: 30, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.88))
            }
            .frame(width: 96, height: 96)
            .accessibilityLabel("\(state.phase.displayName), \(state.timeText) remaining")

            controls
                .opacity(hovering ? 0.85 : 0.22)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: hovering)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: state.phase)
    }

    @ViewBuilder
    private var controls: some View {
        let primary = PomodoroPrimaryActionSpec(runState: state.runState, actions: actions)
        HStack(spacing: 10) {
            NotchIconButton(systemName: primary.systemImage, size: 11, action: primary.handler)
                .accessibilityLabel(primary.title)
            switch state.runState {
            case .idle:
                if state.canSkipBreak {
                    NotchIconButton(systemName: "forward.fill", size: 10, action: actions.skipBreak)
                        .accessibilityLabel("Skip break")
                }
            case .running, .paused:
                NotchIconButton(systemName: "arrow.counterclockwise", size: 10, action: actions.reset)
                    .accessibilityLabel("Reset timer")
            }
        }
    }
}
