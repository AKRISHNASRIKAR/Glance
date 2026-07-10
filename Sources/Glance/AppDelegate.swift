import AppKit
import GlanceKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator!
    private var notchWindow: NotchWindowController!
    private var settingsWindow: SettingsWindowController!
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        GlanceLog.application.info("Glance starting")
        coordinator = AppCoordinator()
        notchWindow = NotchWindowController(coordinator: coordinator)
        settingsWindow = SettingsWindowController(coordinator: coordinator)
        notchWindow.start()
        installStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        notchWindow.stop()
        coordinator.shutdown()
    }

    // MARK: Status item (the discoverable entry point for an accessory app)

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.menuBarIcon()

        let menu = NSMenu()
        menu.addItem(withTitle: "Open Notch", action: #selector(toggleNotch), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Glance", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleNotch() {
        notchWindow.toggleExpanded()
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    /// Glance's mark: the notch itself, with the "device active" dot real
    /// hardware shows beside it. Template image so AppKit tints it to match
    /// the menu bar's light/dark/selected appearance automatically.
    private static func menuBarIcon() -> NSImage? {
        guard let url = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "pdf"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: "Glance")
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = "Glance"
        return image
    }
}
