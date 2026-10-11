import Foundation
import Testing
@testable import GlanceKit

struct PomodoroAppearanceMigrationTests {
    @Test func retiredAppearancesMigrateWithoutResettingTimerSettings() throws {
        for appearance in ["ambient", "compact"] {
            let json = Data("{\"appearance\":\"\(appearance)\",\"focusDuration\":3000}".utf8)
            let settings = try JSONDecoder().decode(PomodoroSettings.self, from: json)
            #expect(settings.appearance == .classic)
            #expect(settings.focusDuration == 3000)
        }
        #expect(PomodoroAppearance.allCases == [.classic, .minimal, .artwork])
    }
}
