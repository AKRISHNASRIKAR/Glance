import Foundation
import Testing
@testable import GlanceKit

@MainActor
struct ScreenStoreTests {
    @Test func firstLaunchHasExactlyNowPlayingAndPomodoro() {
        let (settings, _) = makeTestSettingsStore()
        let store = ScreenStore(settings: settings)
        #expect(store.screens.map(\.type) == [.nowPlaying, .pomodoro])
        #expect(store.selectedScreen?.type == .nowPlaying)
    }

    @Test func navigationClampsAtEnds() {
        let (settings, _) = makeTestSettingsStore()
        let store = ScreenStore(settings: settings)
        store.navigate(by: -1)
        #expect(store.selectedIndex == 0)
        store.navigate(by: 1)
        #expect(store.selectedScreen?.type == .pomodoro)
        store.navigate(by: 1)
        #expect(store.selectedScreen?.type == .pomodoro)
    }

    @Test func orderingPersistsAcrossStores() {
        let clock = TestClock()
        let (settings, url) = makeTestSettingsStore(clock: clock)
        let store = ScreenStore(settings: settings)
        store.moveScreen(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        #expect(store.screens.map(\.type) == [.pomodoro, .nowPlaying])
        settings.saveNow()

        let reloaded = SettingsStore(fileURL: url, scheduler: clock)
        let store2 = ScreenStore(settings: reloaded)
        #expect(store2.screens.map(\.type) == [.pomodoro, .nowPlaying])
    }

    @Test func selectionPersists() {
        let clock = TestClock()
        let (settings, url) = makeTestSettingsStore(clock: clock)
        let store = ScreenStore(settings: settings)
        store.navigate(by: 1)
        settings.saveNow()

        let reloaded = SettingsStore(fileURL: url, scheduler: clock)
        let store2 = ScreenStore(settings: reloaded)
        #expect(store2.selectedScreen?.type == .pomodoro)
    }

    @Test func reopenAfterLongIdleReturnsToFirstScreen() {
        let clock = TestClock()
        let (settings, _) = makeTestSettingsStore(clock: clock)
        let store = ScreenStore(settings: settings, timeSource: clock)
        store.navigate(by: 1)
        store.notchDidClose()
        clock.advance(by: 31 * 60)
        store.notchWillOpen()
        #expect(store.selectedScreen?.type == .nowPlaying)
    }

    @Test func reopenSoonKeepsSelectedScreen() {
        let clock = TestClock()
        let (settings, _) = makeTestSettingsStore(clock: clock)
        let store = ScreenStore(settings: settings, timeSource: clock)
        store.navigate(by: 1)
        store.notchDidClose()
        clock.advance(by: 5 * 60)
        store.notchWillOpen()
        #expect(store.selectedScreen?.type == .pomodoro)
    }

    @Test func addableTypesRespectProviderGating() {
        let (settings, _) = makeTestSettingsStore()
        let store = ScreenStore(settings: settings)
        let withoutProviders = store.addableScreenTypes { _ in false }
        #expect(withoutProviders.isEmpty)
        let withClaudeCode = store.addableScreenTypes { $0 == .claudeCode }
        #expect(withClaudeCode == [.claudeCode])
    }

    @Test func removingSelectedScreenFallsBackToFirst() {
        let (settings, _) = makeTestSettingsStore()
        let store = ScreenStore(settings: settings)
        store.navigate(by: 1)
        let pomodoroID = store.selectedScreen!.id
        store.removeScreen(id: pomodoroID)
        #expect(store.screens.map(\.type) == [.nowPlaying])
        #expect(store.selectedScreen?.type == .nowPlaying)
    }

    @Test func removingLastScreenRestoresDefaults() {
        let (settings, _) = makeTestSettingsStore()
        let store = ScreenStore(settings: settings)
        for screen in store.screens {
            store.removeScreen(id: screen.id)
        }
        #expect(store.screens.map(\.type) == [.nowPlaying, .pomodoro])
    }

    @Test func disablingSelectedScreenMovesSelection() {
        let (settings, _) = makeTestSettingsStore()
        let store = ScreenStore(settings: settings)
        let first = store.screens[0]
        store.setScreen(id: first.id, enabled: false)
        #expect(store.enabledScreens.map(\.type) == [.pomodoro])
        #expect(store.selectedScreen?.type == .pomodoro)
    }

    @Test func disablingProviderRemovesItsScreens() {
        let (settings, _) = makeTestSettingsStore()
        let store = ScreenStore(settings: settings)
        store.addScreen(type: .claudeCode)
        #expect(store.screens.count == 3)
        store.removeScreens(ofType: .claudeCode)
        #expect(store.screens.map(\.type) == [.nowPlaying, .pomodoro])
    }
}

@MainActor
struct SettingsStoreTests {
    /// Screen IDs are random per instance, so compare structure rather
    /// than full equality.
    private func expectDefaults(_ value: GlanceSettings) {
        let defaults = GlanceSettings()
        #expect(value.screens.map(\.type) == defaults.screens.map(\.type))
        #expect(value.selectedScreenID == value.screens.first?.id)
        #expect(value.nowPlaying == defaults.nowPlaying)
        #expect(value.pomodoro == defaults.pomodoro)
        #expect(value.battery == defaults.battery)
        #expect(value.context == defaults.context)
        #expect(value.claudeCode == defaults.claudeCode)
        #expect(value.privacy == defaults.privacy)
    }

    @Test func missingFileYieldsDefaults() {
        let (settings, _) = makeTestSettingsStore()
        expectDefaults(settings.settings)
    }

    @Test func roundTripPersistence() {
        let clock = TestClock()
        let (settings, url) = makeTestSettingsStore(clock: clock)
        settings.update { s in
            s.nowPlaying.appearance = .artwork
            s.pomodoro.focusDuration = 30 * 60
            s.battery.isEnabled = true
            s.privacy.neverTrackBundleIdentifiers = ["com.example.secret"]
        }
        settings.saveNow()

        let reloaded = SettingsStore(fileURL: url, scheduler: clock)
        #expect(reloaded.settings.nowPlaying.appearance == .artwork)
        #expect(reloaded.settings.pomodoro.focusDuration == 30 * 60)
        #expect(reloaded.settings.battery.isEnabled)
        #expect(reloaded.settings.privacy.neverTrackBundleIdentifiers == ["com.example.secret"])
    }

    @Test func sanitizeRepairsEmptyScreensAndBadSelection() {
        var broken = GlanceSettings()
        broken.screens = []
        broken.selectedScreenID = UUID()
        let repaired = SettingsStore.sanitize(broken)
        #expect(repaired.screens.map(\.type) == [.nowPlaying, .pomodoro])
        #expect(repaired.selectedScreenID == repaired.screens.first?.id)
    }

    @Test func migrationStampsCurrentVersion() {
        var old = GlanceSettings()
        old.schemaVersion = 0
        let migrated = SettingsStore.migrate(old)
        #expect(migrated.schemaVersion == GlanceSettings.currentSchemaVersion)
    }

    @Test func corruptFileFallsBackToDefaults() throws {
        let url = makeTempDirectory().appendingPathComponent("settings.json")
        try Data("not json{{{".utf8).write(to: url)
        let settings = SettingsStore(fileURL: url, scheduler: TestClock())
        expectDefaults(settings.settings)
    }

    @Test func decodeToleratesMissingKeys() throws {
        let url = makeTempDirectory().appendingPathComponent("settings.json")
        try Data(#"{"schemaVersion": 1}"#.utf8).write(to: url)
        let settings = SettingsStore(fileURL: url, scheduler: TestClock())
        #expect(settings.settings.screens.map(\.type) == [.nowPlaying, .pomodoro])
        #expect(settings.settings.pomodoro.focusDuration == 25 * 60)
    }
}
