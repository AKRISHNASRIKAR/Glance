import AppKit
import Combine
import GlanceKit
import SwiftUI

/// Derives the notch's visual state from user intent, interruptions, and
/// live activity — and owns the interactive geometry the window uses for
/// hit-testing.
///
/// State precedence: expanded (user intent) > peek (interruption) >
/// live (persistent activity) > idle.
@MainActor
final class NotchViewModel: ObservableObject {
    enum LiveActivity: Equatable {
        case pomodoro
        case claudeWorking
        case media
        case network
    }

    @Published private(set) var userExpanded = false
    @Published private(set) var isHovering = false
    @Published var geometry: NotchGeometry
    @Published private(set) var currentInterruption: NotchInterruption?
    @Published private(set) var liveActivity: LiveActivity?

    let coordinator: AppCoordinator
    var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var cancellables: Set<AnyCancellable> = []

    init(coordinator: AppCoordinator, geometry: NotchGeometry) {
        self.coordinator = coordinator
        self.geometry = geometry

        coordinator.interruptions.$current
            .sink { [weak self] interruption in
                self?.currentInterruption = interruption
            }
            .store(in: &cancellables)

        // Live indicator selection: pomodoro (deliberate focus) wins over
        // Claude working, which wins over passive media, then network.
        let pomodoroLive = coordinator.pomodoro.engine.$runState.map { $0 == .running }
        let claudeLive = coordinator.claudeCode.$machine.map { $0.state == .working }
        let mediaLive = coordinator.nowPlaying.$state.map { $0?.playbackState == .playing }
        let networkLive = coordinator.network.$isHighActivity

        Publishers.CombineLatest4(pomodoroLive, claudeLive, mediaLive, networkLive)
            .map { pomodoro, claude, media, network -> LiveActivity? in
                if pomodoro { return .pomodoro }
                if claude { return .claudeWorking }
                if media { return .media }
                if network { return .network }
                return nil
            }
            .removeDuplicates()
            .sink { [weak self] value in self?.liveActivity = value }
            .store(in: &cancellables)
    }

    // MARK: Visual state

    var visualState: NotchVisualState {
        if userExpanded { return .expanded }
        if currentInterruption != nil { return .peek }
        if liveActivity != nil { return .live }
        return .idle
    }

    /// The current visible shape size (top-center anchored).
    var shapeSize: CGSize {
        switch visualState {
        case .idle:
            var size = geometry.idleSize
            if isHovering {
                size.width += 12
                size.height += 3
            }
            return size
        case .live: return geometry.liveSize()
        case .peek: return geometry.peekSize()
        case .expanded: return NotchGeometry.expandedSize
        }
    }

    /// Shape rect in window coordinates (window is top-anchored).
    func shapeRect(inWindowOfSize windowSize: CGSize) -> CGRect {
        let size = shapeSize
        return CGRect(
            x: (windowSize.width - size.width) / 2,
            y: windowSize.height - size.height,
            width: size.width,
            height: size.height
        )
    }

    // MARK: Intent

    func setHovering(_ hovering: Bool) {
        guard isHovering != hovering else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.8)) {
            isHovering = hovering
        }
    }

    func expand() {
        guard !userExpanded else { return }
        coordinator.screens.notchWillOpen()
        withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82)) {
            userExpanded = true
        }
        coordinator.nowPlaying.setDetailVisible(selectedScreenType == .nowPlaying)
    }

    func collapse() {
        guard userExpanded else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85)) {
            userExpanded = false
        }
        coordinator.screens.notchDidClose()
        coordinator.nowPlaying.setDetailVisible(false)
    }

    func toggleExpanded() {
        userExpanded ? collapse() : expand()
    }

    /// Tapping the peek surface opens the expanded view (which shows the
    /// interruption detail while one is active).
    func handleClick() {
        if userExpanded {
            // Clicks inside expanded content are handled by controls.
            return
        }
        expand()
    }

    // MARK: Screen navigation

    var selectedScreenType: ScreenType? {
        coordinator.screens.selectedScreen?.type
    }

    func navigate(by delta: Int) {
        coordinator.screens.navigate(by: delta)
        coordinator.nowPlaying.setDetailVisible(selectedScreenType == .nowPlaying)
    }

    // MARK: Scroll-driven paging

    private var scrollAccumulator: CGFloat = 0
    private var lastScrollNavigation = Date.distantPast

    /// Two-finger horizontal swipe / horizontal mouse scroll while expanded.
    /// Accumulates deltas and fires one navigation per gesture burst.
    func handleScroll(deltaX: CGFloat) {
        guard userExpanded else { return }
        let now = Date()
        if now.timeIntervalSince(lastScrollNavigation) < 0.35 {
            return // settle time between page turns
        }
        scrollAccumulator += deltaX
        let threshold: CGFloat = 30
        if scrollAccumulator <= -threshold {
            navigate(by: 1)
            scrollAccumulator = 0
            lastScrollNavigation = now
        } else if scrollAccumulator >= threshold {
            navigate(by: -1)
            scrollAccumulator = 0
            lastScrollNavigation = now
        }
    }

    func scrollGestureEnded() {
        scrollAccumulator = 0
    }

    // MARK: Keyboard (panel-local, only while the panel is key & expanded)

    /// Returns true when the event was consumed.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard userExpanded else { return false }
        switch event.keyCode {
        case 53: // Escape
            collapse()
            return true
        case 123 where event.modifierFlags.contains(.command): // ⌘←
            navigate(by: -1)
            return true
        case 124 where event.modifierFlags.contains(.command): // ⌘→
            navigate(by: 1)
            return true
        default:
            return false
        }
    }
}
