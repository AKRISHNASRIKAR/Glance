import AppKit
import GlanceKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var coordinator: AppCoordinator!
    private var notchWindow: NotchWindowController!
    private var settingsWindow: SettingsWindowController!
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        GlanceLog.application.info("Glance starting")
        installMainMenu()
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

    /// Status-item menus do not provide application-wide keyboard equivalents.
    /// Keep a standard main menu even though this accessory app has no Dock icon.
    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Glance")
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Glance", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").target = NSApp
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(closeWindow), keyEquivalent: "w").target = self
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func closeWindow() {
        guard let window = NSApp.keyWindow else { return }
        if window is NotchPanel {
            window.cancelOperation(nil)
        } else {
            window.performClose(nil)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(closeWindow) {
            guard let window = NSApp.keyWindow else { return false }
            return window is NotchPanel || window.styleMask.contains(.closable)
        }
        return true
    }

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
