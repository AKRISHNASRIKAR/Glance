import GlanceKit
import SwiftUI

/// Content of the expanded notch: the interruption detail while one is
/// active, otherwise the horizontal Screen pager. When the interruption
/// ends, the previously selected Screen is simply revealed again — selection
/// is never mutated by interruptions.
struct ExpandedContentView: View {
    @EnvironmentObject var viewModel: NotchViewModel

    var body: some View {
        if let interruption = viewModel.currentInterruption {
            InterruptionDetailView(interruption: interruption)
        } else {
            ScreenPagerView()
        }
    }
}

// MARK: - Screen pager

struct ScreenPagerView: View {
    @EnvironmentObject var screens: ScreenStore
    @EnvironmentObject var viewModel: NotchViewModel

    var body: some View {
        let enabled = screens.enabledScreens
        let index = screens.selectedIndex

        VStack(spacing: 0) {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    ForEach(enabled) { screen in
                        screenView(for: screen.type)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
                .offset(x: -CGFloat(index) * proxy.size.width)
                .animation(
                    viewModel.reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85),
                    value: index
                )
            }
            .clipped()

            if enabled.count > 1 {
                pageIndicator(count: enabled.count, index: index)
                    .padding(.bottom, 7)
            }
        }
        .padding(.top, viewModel.geometry.hasPhysicalNotch ? viewModel.geometry.idleSize.height * 0.55 : 6)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func screenView(for type: ScreenType) -> some View {
        switch type {
        case .nowPlaying: NowPlayingScreenView()
        case .pomodoro: PomodoroScreenView()
        case .claudeCode: ClaudeCodeScreenView()
        case .codingContext: CodingContextScreenView()
        }
    }

    /// Dots + chevrons: the clickable navigation affordance (also the
    /// accessible one). Swipe and ⌘←/⌘→ do the same thing.
    private func pageIndicator(count: Int, index: Int) -> some View {
        HStack(spacing: 10) {
            Button { viewModel.navigate(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(NotchGlyphButtonStyle())
            .disabled(index == 0)
            .accessibilityLabel("Previous screen")

            HStack(spacing: 5) {
                ForEach(0..<count, id: \.self) { i in
                    Circle()
                        .fill(i == index ? Color.white.opacity(0.9) : Color.white.opacity(0.28))
                        .frame(width: 4.5, height: 4.5)
                }
            }

            Button { viewModel.navigate(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(NotchGlyphButtonStyle())
            .disabled(index == count - 1)
            .accessibilityLabel("Next screen")
        }
    }
}

// MARK: - Interruption detail

struct InterruptionDetailView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    let interruption: NotchInterruption

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Image(systemName: interruption.symbolName ?? "bell.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(iconColor)
            Text(interruption.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            if let subtitle = interruption.subtitle {
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                ForEach(interruption.actions) { action in
                    Button(action.title) {
                        coordinator.interruptions.performAction(action)
                    }
                    .buttonStyle(NotchCapsuleButtonStyle(prominent: true))
                }
                Button("Dismiss") {
                    coordinator.interruptions.dismissCurrent()
                }
                .buttonStyle(NotchCapsuleButtonStyle(prominent: false))
            }
            .padding(.top, 2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var iconColor: Color {
        switch interruption.priority {
        case .urgent: return .red
        case .important: return .orange
        case .normal, .passive: return .white
        }
    }
}

// MARK: - Button styles

struct NotchCapsuleButtonStyle: ButtonStyle {
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(prominent ? .black : .white.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(prominent ? Color.white.opacity(0.92) : Color.white.opacity(0.14))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct NotchGlyphButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(isEnabled ? 0.75 : 0.25))
            .frame(width: 20, height: 16)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

/// Circular icon button with hover + pressed states, used for transport
/// controls and small actions.
struct NotchIconButton: View {
    let systemName: String
    var size: CGFloat = 14
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
        }
        .buttonStyle(IconStyle(hovering: hovering))
        .onHover { hovering = $0 }
    }

    private struct IconStyle: ButtonStyle {
        let hovering: Bool
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundStyle(.white.opacity(configuration.isPressed ? 0.5 : 0.92))
                .padding(7)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.14 : 0)))
                .contentShape(Circle())
        }
    }
}
