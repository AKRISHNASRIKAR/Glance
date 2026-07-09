import GlanceKit
import SwiftUI

/// The notch surface: a black top-anchored shape that morphs between idle,
/// peek, live, and expanded — all motion originates from the notch itself.
struct NotchRootView: View {
    @EnvironmentObject var viewModel: NotchViewModel
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        GeometryReader { proxy in
            let size = viewModel.shapeSize
            NotchShape(bottomRadius: bottomRadius)
                .fill(Color.black)
                .overlay(content)
                .clipShape(NotchShape(bottomRadius: bottomRadius))
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .onTapGesture { viewModel.handleClick() }
                .onHover { viewModel.setHovering($0) }
                .position(x: proxy.size.width / 2, y: size.height / 2)
                .animation(
                    viewModel.reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82),
                    value: viewModel.visualState
                )
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Glance notch")
    }

    private var bottomRadius: CGFloat {
        switch viewModel.visualState {
        case .idle: return viewModel.geometry.hasPhysicalNotch ? 10 : 12
        case .live, .peek: return 12
        case .expanded: return 22
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.visualState {
        case .idle:
            EmptyView()
        case .live:
            NotchWingsView(notchWidth: viewModel.geometry.idleSize.width) {
                LiveIndicatorLeading()
            } trailing: {
                LiveIndicatorTrailing()
            }
        case .peek:
            if let interruption = viewModel.currentInterruption {
                NotchWingsView(notchWidth: viewModel.geometry.idleSize.width) {
                    PeekLeading(interruption: interruption)
                } trailing: {
                    PeekTrailing(interruption: interruption)
                }
            }
        case .expanded:
            ExpandedContentView()
                .transition(viewModel.reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        }
    }
}

/// Notch outline: square top corners (flush with the bezel), rounded bottom.
struct NotchShape: Shape {
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(bottomRadius, min(rect.width, rect.height) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

/// Content beside the physical notch: a leading and trailing wing with the
/// notch (dead pixels) left empty in the middle.
struct NotchWingsView<Leading: View, Trailing: View>: View {
    let notchWidth: CGFloat
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            leading()
                .frame(maxWidth: .infinity, alignment: .center)
            Color.clear
                .frame(width: notchWidth * 0.72) // keep clear of the sensor housing
            trailing()
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 10)
    }
}

// MARK: - Live indicators

private struct LiveIndicatorLeading: View {
    @EnvironmentObject var viewModel: NotchViewModel
    @EnvironmentObject var engine: PomodoroEngine

    var body: some View {
        switch viewModel.liveActivity {
        case .pomodoro:
            Image(systemName: engine.phase == .focus ? "timer" : "cup.and.saucer.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
        case .claudeWorking:
            Image(systemName: "sparkle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.purple)
        case .media:
            MiniArtworkView(size: 18)
        case .network:
            Image(systemName: "arrow.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.cyan)
        case nil:
            EmptyView()
        }
    }
}

private struct LiveIndicatorTrailing: View {
    @EnvironmentObject var viewModel: NotchViewModel
    @EnvironmentObject var network: NetworkProvider

    var body: some View {
        switch viewModel.liveActivity {
        case .pomodoro:
            PomodoroRemainingLabel()
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.orange)
        case .claudeWorking:
            AudioBarsView(color: .purple, isAnimating: !viewModel.reduceMotion)
        case .media:
            AudioBarsView(color: .white.opacity(0.9), isAnimating: !viewModel.reduceMotion)
        case .network:
            Text(ThroughputFormatter.format(
                bytesPerSecond: network.throughput.downloadBytesPerSecond,
                detailed: false
            ))
            .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.cyan)
        case nil:
            EmptyView()
        }
    }
}

/// Ticks once a second to render the countdown without re-rendering the tree.
struct PomodoroRemainingLabel: View {
    @EnvironmentObject var engine: PomodoroEngine

    var body: some View {
        Text(TimeFormatting.minutesSeconds(engine.remaining))
    }
}

// MARK: - Peek content

private struct PeekLeading: View {
    let interruption: NotchInterruption

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: interruption.symbolName ?? "bell.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(interruption.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch interruption.priority {
        case .urgent: return .red
        case .important: return .orange
        case .normal, .passive: return .white.opacity(0.9)
        }
    }
}

private struct PeekTrailing: View {
    let interruption: NotchInterruption

    var body: some View {
        if let subtitle = interruption.subtitle {
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
        }
    }
}

// MARK: - Shared bits

/// Small three-bar equalizer used as the "something is live" glyph.
struct AudioBarsView: View {
    let color: Color
    let isAnimating: Bool
    @State private var phase = false

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: 2.5, height: phase ? heights[index].0 : heights[index].1)
            }
        }
        .frame(height: 14, alignment: .center)
        .onAppear {
            guard isAnimating else { return }
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                phase = true
            }
        }
        .accessibilityLabel("Playing")
    }

    private let heights: [(CGFloat, CGFloat)] = [(6, 12), (13, 5), (8, 11)]
}

struct MiniArtworkView: View {
    @EnvironmentObject var nowPlaying: NowPlayingProvider
    let size: CGFloat

    var body: some View {
        Group {
            if let cgImage = nowPlaying.artwork {
                Image(decorative: cgImage, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

enum TimeFormatting {
    static func minutesSeconds(_ interval: TimeInterval) -> String {
        let total = max(Int(interval.rounded()), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func hoursMinutes(_ interval: TimeInterval) -> String {
        let minutes = max(Int(interval) / 60, 0)
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
