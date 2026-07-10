import GlanceKit
import SwiftUI

/// The Claude Code Screen: a minimal status surface. Never a chat interface,
/// never prompts, never code.
struct ClaudeCodeScreenView: View {
    @EnvironmentObject var claudeCode: ClaudeCodeProvider

    var body: some View {
        let machine = claudeCode.machine
        VStack(spacing: 9) {
            Text("CLAUDE")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.2)
                .foregroundStyle(Color.claudeAccent.opacity(0.9))

            switch claudeCode.status {
            case .notConfigured:
                statusBlock(
                    symbol: "wrench.adjustable",
                    tint: .white.opacity(0.5),
                    title: "Not configured",
                    detail: "Set up hooks in Settings → Claude Code"
                )
            case .running:
                runningContent(machine: machine)
            case .disabled, .permissionRequired, .unavailable, .error:
                statusBlock(
                    symbol: "exclamationmark.circle",
                    tint: .white.opacity(0.5),
                    title: "Unavailable",
                    detail: "Check Settings → Claude Code"
                )
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func runningContent(machine: ClaudeCodeStateMachine) -> some View {
        switch machine.state {
        case .idle:
            statusBlock(symbol: "moon.zzz", tint: .white.opacity(0.5), title: "No active session", detail: nil)
        case .working:
            VStack(spacing: 7) {
                AudioBarsView(color: .claudeAccent, isAnimating: true)
                Text("Working")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                if let since = machine.workingSince {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        Text("Session active · \(ClaudeCodeProvider.formatDuration(timeline.date.timeIntervalSince(since)))")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
            }
        case .needsInput:
            actionBlock(symbol: "bubble.left.and.exclamationmark.bubble.right", tint: .orange, title: "Needs your input")
        case .permissionRequired:
            actionBlock(symbol: "lock.shield", tint: .orange, title: "Permission required")
        case .completed:
            statusBlock(
                symbol: "checkmark.circle.fill",
                tint: .green,
                title: "Completed",
                detail: machine.lastCompletedDuration.map(ClaudeCodeProvider.formatDuration)
            )
        case .failed:
            statusBlock(symbol: "exclamationmark.triangle.fill", tint: .red, title: "Failed", detail: "Task requires attention")
        }
    }

    private func statusBlock(symbol: String, tint: Color, title: String, detail: String?) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func actionBlock(symbol: String, tint: Color, title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Button("Open Claude") {
                ClaudeCodeProvider.activateTerminalApplication()
            }
            .buttonStyle(NotchCapsuleButtonStyle(prominent: true))
        }
    }
}
