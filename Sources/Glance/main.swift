import AppKit

// Entry point. Uses main.swift + explicit NSApplication setup because the
// app is assembled by SwiftPM (no storyboard, no @main attribute conflicts).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
