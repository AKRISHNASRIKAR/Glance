import Foundation
import GlanceKit

// Test-only headless host: never copied into Glance.app or distributed as a helper.
// Its storage/socket location MUST be explicitly isolated by the test runner.
guard let root=ProcessInfo.processInfo.environment["GLANCE_BROWSER_DIR"],root.hasPrefix("/tmp/") || root.hasPrefix("/private/tmp/") else {fatalError("Harness requires isolated temporary storage.")}
let settings=SettingsStore(fileURL:URL(fileURLWithPath:root).appendingPathComponent("test-settings.json"))
let engine=PomodoroEngine(configuration:settings.settings.pomodoro)
let companion=BrowserCompanion(engine:engine,settings:settings)
companion.approvePairing={_ in true}
print("HARNESS_READY",companion.enabled)
RunLoop.main.run()
