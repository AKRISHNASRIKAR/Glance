import GlanceKit
import SwiftUI

/// Compact — the smallest footprint: a small ring, one line of text, and
/// icon-only controls (no button labels). Built to still read cleanly at
/// half the notch width, for users who pair Pomodoro with another Screen
/// via Settings → Notch Screens → Width.
struct CompactPomodoroRenderer: View {
    let state: PomodoroDisplayState
    let actions: PomodoroActions
    var reduceMotion: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                PomodoroRingView(progress: state.progress, color: state.phaseColor, lineWidth: 3.5, reduceMotion: reduceMotion)
                Text(state.timeText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)
            .accessibilityLabel("\(state.phase.displayName), \(state.timeText) remaining")

            VStack(alignment: .leading, spacing: 4) {
                Text(state.phase.displayName.uppercased())
                    .font(.system(size: 8.5, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.55))
                PomodoroSessionTrack(
                    total: state.sessionsBeforeLongBreak,
                    filled: state.filledSessions,
                    color: state.phaseColor,
                    barSize: CGSize(width: 6, height: 3),
                    spacing: 2
                )
            }

            Spacer(minLength: 4)

            controls
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: state.phase)
    }

    private var controls: some View {
        let primary = PomodoroPrimaryActionSpec(runState: state.runState, actions: actions)
        return HStack(spacing: 2) {
            NotchIconButton(systemName: primary.systemImage, size: 12, action: primary.handler)
                .accessibilityLabel(primary.title)
            if state.runState != .idle {
                NotchIconButton(systemName: "arrow.counterclockwise", size: 10, action: actions.reset)
                    .accessibilityLabel("Reset timer")
            }
        }
    }
}
