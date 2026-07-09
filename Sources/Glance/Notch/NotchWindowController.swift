import AppKit
import GlanceKit
import SwiftUI

/// A non-activating panel pinned over the notch. The panel has a fixed frame
/// large enough for the expanded state; the visible shape animates inside it.
/// Custom hit-testing makes everything outside the current shape click-through.
final class NotchPanel: NSPanel {
    weak var viewModel: NotchViewModel?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if viewModel?.handleKeyDown(event) != true {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        viewModel?.collapse()
    }
}

/// Hosting view that rejects clicks outside the notch shape so the rest of
/// the (invisible) window never swallows events meant for apps below.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    weak var viewModel: NotchViewModel?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let viewModel else { return nil }
        // `point` is in the superview's coordinate space; convert to ours.
        let local = convert(point, from: superview)
        var shape = viewModel.shapeRect(inWindowOfSize: bounds.size)
        // SwiftUI/AppKit coordinate flip: hosting view is flipped.
        shape.origin.y = bounds.height - shape.maxY
        // A small grace margin keeps hover/click forgiving near the edge.
        return shape.insetBy(dx: -4, dy: -4).contains(local) ? super.hitTest(point) : nil
    }
}

@MainActor
final class NotchWindowController {
    private var panel: NotchPanel?
    private var viewModel: NotchViewModel?
    private let coordinator: AppCoordinator
    private var scrollMonitor: Any?
    private var clickOutsideMonitor: Any?
    private var screenObserver: NSObjectProtocol?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        // Handle display connect/disconnect/rearrangement.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in self?.rebuildForCurrentScreens() }
        }
    }

    func start() {
        rebuildForCurrentScreens()
        installEventMonitors()
    }

    func stop() {
        removeEventMonitors()
        panel?.orderOut(nil)
        panel = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }

    func toggleExpanded() {
        viewModel?.toggleExpanded()
    }

    // MARK: Window lifecycle

    private func rebuildForCurrentScreens() {
        guard let screen = NotchGeometry.bestScreen() else {
            panel?.orderOut(nil)
            panel = nil
            return
        }
        let geometry = NotchGeometry.forScreen(screen)

        // Respect the setting for notch-less displays.
        if !geometry.hasPhysicalNotch, !coordinator.settings.settings.general.showOnNotchlessDisplays {
            panel?.orderOut(nil)
            panel = nil
            return
        }

        if let viewModel, let panel {
            // Same panel, new geometry (resolution change, display move).
            viewModel.geometry = geometry
            panel.setFrame(geometry.windowFrame, display: true)
            return
        }

        let viewModel = NotchViewModel(coordinator: coordinator, geometry: geometry)
        self.viewModel = viewModel

        let panel = NotchPanel(
            contentRect: geometry.windowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.viewModel = viewModel
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = true

        // Each provider/engine is injected directly: nested ObservableObjects
        // do not republish through the coordinator, so views must observe
        // the specific object whose @Published state they render.
        let root = NotchRootView()
            .environmentObject(viewModel)
            .environmentObject(coordinator)
            .environmentObject(coordinator.screens)
            .environmentObject(coordinator.settings)
            .environmentObject(coordinator.nowPlaying)
            .environmentObject(coordinator.pomodoro.engine)
            .environmentObject(coordinator.claudeCode)
            .environmentObject(coordinator.codingContext)
            .environmentObject(coordinator.network)
            .environmentObject(coordinator.context)
            .environmentObject(coordinator.context.history)
        let hosting = NotchHostingView(rootView: AnyView(root))
        hosting.viewModel = viewModel
        panel.contentView = hosting

        panel.setFrame(geometry.windowFrame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    // MARK: Event monitors

    private func installEventMonitors() {
        // Horizontal two-finger swipe / horizontal scroll → screen paging.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel else { return event }
            self.viewModel?.handleScroll(event: event)
            return event
        }
        // Click anywhere outside the panel collapses the expanded notch.
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.viewModel?.collapse()
            }
        }
    }

    private func removeEventMonitors() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        if let clickOutsideMonitor { NSEvent.removeMonitor(clickOutsideMonitor) }
        scrollMonitor = nil
        clickOutsideMonitor = nil
    }
}
