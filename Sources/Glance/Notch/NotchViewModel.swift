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
    private let scheduler: GlanceScheduler
    private var hoverOpenHandle: GlanceCancellable?
    private var autoCloseHandle: GlanceCancellable?

    /// Boring.notch-style timings: open shortly after hover settles, close
    /// about a second after the cursor leaves.
    private let hoverOpenDelay: TimeInterval = 0.18
    private let autoCloseDelay: TimeInterval = 1.0

    init(coordinator: AppCoordinator, geometry: NotchGeometry, scheduler: GlanceScheduler = TimerScheduler()) {
        self.coordinator = coordinator
        self.geometry = geometry
        self.scheduler = scheduler

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
        case .expanded: return geometry.expandedSize
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

    /// Haptic tick on real interactions (trackpads only; no-op elsewhere).
    private func haptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
    }

    /// Hover drives everything: hovering the notch opens it after a short
    /// settle; leaving closes it a second later. Re-entering cancels the
    /// pending close.
    func setHovering(_ hovering: Bool) {
        guard isHovering != hovering else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.8)) {
            isHovering = hovering
        }
        if hovering {
            haptic(.levelChange)
            autoCloseHandle?.cancel()
            autoCloseHandle = nil
            if !userExpanded {
                hoverOpenHandle?.cancel()
                hoverOpenHandle = scheduler.schedule(after: hoverOpenDelay) { [weak self] in
                    guard let self, self.isHovering, !self.userExpanded else { return }
                    self.expand()
                }
            }
        } else {
            hoverOpenHandle?.cancel()
            hoverOpenHandle = nil
            if userExpanded {
                autoCloseHandle?.cancel()
                autoCloseHandle = scheduler.schedule(after: autoCloseDelay) { [weak self] in
                    guard let self, !self.isHovering else { return }
                    self.collapse()
                }
            }
        }
    }

    func expand() {
        guard !userExpanded else { return }
        coordinator.screens.notchWillOpen()
        haptic(.generic)
        withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82)) {
            userExpanded = true
        }
        coordinator.nowPlaying.setDetailVisible(coordinator.screens.selectedPageContains(.nowPlaying))
    }

    func collapse() {
        guard userExpanded else { return }
        autoCloseHandle?.cancel()
        autoCloseHandle = nil
        haptic(.generic)
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85)) {
            userExpanded = false
        }
        coordinator.screens.notchDidClose()
        coordinator.nowPlaying.setDetailVisible(false)
    }

    func toggleExpanded() {
        userExpanded ? collapse() : expand()
    }

    /// Clicking the idle/peek notch opens it immediately (hover already
    /// opens it; the click is a fast path and the accessible affordance).
    func handleClick() {
        if !userExpanded { expand() }
    }

    // MARK: Screen navigation

    var selectedScreenType: ScreenType? {
        coordinator.screens.selectedScreen?.type
    }

    func navigate(by delta: Int) {
        let before = coordinator.screens.selectedPageIndex
        coordinator.screens.navigate(by: delta)
        if coordinator.screens.selectedPageIndex != before {
            haptic(.alignment)
        }
        coordinator.nowPlaying.setDetailVisible(coordinator.screens.selectedPageContains(.nowPlaying))
    }

    // MARK: Scroll-driven paging

    private var scrollAccumulator: CGFloat = 0
    private var gestureConsumed = false
    private var lastLegacyScrollAt = Date.distantPast

    /// One page turn per gesture: accumulate finger-down deltas, navigate
    /// once past the threshold, then ignore the rest of the gesture —
    /// including all momentum — until the fingers go down again.
    func handleScroll(event: NSEvent) {
        guard userExpanded else { return }

        // Momentum (inertia) events never navigate; they were the cause of
        // page skipping.
        guard event.momentumPhase == [] else { return }

        let threshold: CGFloat = 30

        if event.phase == .began {
            scrollAccumulator = 0
            gestureConsumed = false
        }

        if event.phase == .changed || event.phase == .began {
            guard !gestureConsumed else { return }
            scrollAccumulator += event.scrollingDeltaX
            if abs(scrollAccumulator) >= threshold {
                navigate(by: scrollAccumulator < 0 ? 1 : -1)
                gestureConsumed = true
                scrollAccumulator = 0
            }
            return
        }

        if event.phase == .ended || event.phase == .cancelled {
            scrollAccumulator = 0
            return
        }

        // Legacy scroll wheels / horizontal mouse scroll (no phases): treat
        // bursts within 400 ms as one gesture.
        if event.phase == [] {
            let now = Date()
            if now.timeIntervalSince(lastLegacyScrollAt) > 0.4 {
                scrollAccumulator = 0
                gestureConsumed = false
            }
            lastLegacyScrollAt = now
            guard !gestureConsumed else { return }
            scrollAccumulator += event.scrollingDeltaX
            if abs(scrollAccumulator) >= threshold {
                navigate(by: scrollAccumulator < 0 ? 1 : -1)
                gestureConsumed = true
                scrollAccumulator = 0
            }
        }
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
