import AppKit
import GlanceKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let coordinator: AppCoordinator

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func show() {
        if window == nil {
            let root = SettingsRootView()
                .environmentObject(coordinator)
                .environmentObject(coordinator.settings)
                .environmentObject(coordinator.screens)
                .environmentObject(coordinator.activity)
                .environmentObject(coordinator.claudeCode)
            let hosting = NSHostingController(rootView: AnyView(root))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Glance Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = false
            window.setContentSize(NSSize(width: 760, height: 520))
            window.center()
            window.isReleasedWhenClosed = false
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Root

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case screens = "Notch Screens"
    case nowPlaying = "Now Playing"
    case pomodoro = "Pomodoro"
    case activities = "Activities"
    case contextAwareness = "Context Awareness"
    case claudeCode = "Claude Code"
    case privacy = "Privacy"
    case about = "About"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .screens: return "rectangle.on.rectangle"
        case .nowPlaying: return "music.note"
        case .pomodoro: return "timer"
        case .activities: return "sparkles"
        case .contextAwareness: return "brain"
        case .claudeCode: return "terminal"
        case .privacy: return "hand.raised"
        case .about: return "info.circle"
        }
    }
}

struct SettingsRootView: View {
    @State private var selection: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.symbol).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 200)
        } detail: {
            ScrollView {
                detail
                    .padding(24)
                    .frame(maxWidth: 560, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .general: GeneralPane()
        case .screens: ScreensPane()
        case .nowPlaying: NowPlayingPane()
        case .pomodoro: PomodoroPane()
        case .activities: ActivitiesPane()
        case .contextAwareness: ContextPane()
        case .claudeCode: ClaudeCodePane()
        case .privacy: PrivacyPane()
        case .about: AboutPane()
        }
    }
}

// MARK: - General

struct GeneralPane: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var loginItemError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "General")
            Form {
                Toggle("Launch at login", isOn: binding(\.general.launchAtLogin, onChange: updateLoginItem))
                if let loginItemError {
                    Text(loginItemError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Show on displays without a notch", isOn: binding(\.general.showOnNotchlessDisplays))
                Text("On Macs without a physical notch, Glance shows a compact surface at the top-center of the screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
        }
    }

    private func updateLoginItem(_ enabled: Bool) {
        do {
            try LoginItemManager.setEnabled(enabled)
            loginItemError = nil
        } catch {
            loginItemError = "Launch at login needs the installed app bundle (\(error.localizedDescription))"
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<GlanceSettings, T>, onChange: ((T) -> Void)? = nil) -> Binding<T> {
        Binding(
            get: { settings.settings[keyPath: keyPath] },
            set: { newValue in
                settings.update { $0[keyPath: keyPath] = newValue }
                onChange?(newValue)
            }
        )
    }
}

/// Shared binding helper for panes.
extension View {
    @MainActor
    func settingsBinding<T>(_ store: SettingsStore, _ keyPath: WritableKeyPath<GlanceSettings, T>) -> Binding<T> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { newValue in store.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}

struct SettingsHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.weight(.semibold))
            if let subtitle {
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Notch Screens

struct ScreensPane: View {
    @EnvironmentObject var screens: ScreenStore
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(
                title: "Notch Screens",
                subtitle: "The screens you swipe between in the expanded notch. Drag to reorder. Two adjacent half-width screens share one page side by side."
            )
            List {
                ForEach(screens.screens) { screen in
                    HStack {
                        Image(systemName: symbol(for: screen.type)).frame(width: 20)
                        Text(screen.type.displayName)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { screen.width },
                            set: { screens.setScreenWidth(id: screen.id, width: $0) }
                        )) {
                            Text("Full").tag(ScreenWidth.full)
                            Text("Half").tag(ScreenWidth.half)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .frame(width: 110)
                        Toggle("", isOn: Binding(
                            get: { screen.isEnabled },
                            set: { screens.setScreen(id: screen.id, enabled: $0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        if !ScreenType.defaultTypes.contains(screen.type) {
                            Button {
                                screens.removeScreen(id: screen.id)
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(screen.type.displayName)")
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onMove { offsets, destination in
                    screens.moveScreen(fromOffsets: offsets, toOffset: destination)
                }
            }
            .frame(height: 200)
            Text("Example: set Pomodoro to Half and add another Half screen next to it — they'll share one page, Pomodoro on the right.")
                .font(.caption)
                .foregroundStyle(.secondary)

            let addable = screens.addableScreenTypes { type in
                switch type {
                case .claudeCode: return settings.settings.claudeCode.isEnabled
                case .codingContext: return settings.settings.codingContext.isEnabled
                default: return true
                }
            }
            if !addable.isEmpty {
                Menu {
                    ForEach(addable, id: \.self) { type in
                        Button(type.displayName) { screens.addScreen(type: type) }
                    }
                } label: {
                    Label("Add Screen", systemImage: "plus")
                }
                .fixedSize()
            } else {
                Text("More screens become available when you enable their activities under Activities.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func symbol(for type: ScreenType) -> String {
        switch type {
        case .nowPlaying: return "music.note"
        case .pomodoro: return "timer"
        case .claudeCode: return "terminal"
        case .codingContext: return "keyboard"
        }
    }
}

// MARK: - Now Playing

struct NowPlayingPane: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "Now Playing", subtitle: "Apple Music and Spotify are supported.")
            Form {
                Section("Player Appearance") {
                    Picker("Appearance", selection: settingsBinding(settings, \.nowPlaying.appearance)) {
                        Text("Minimal — black notch background").tag(PlayerAppearance.minimal)
                        Text("Artwork — translucent album artwork background").tag(PlayerAppearance.artwork)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
                if settings.settings.nowPlaying.appearance == .artwork {
                    Section("Artwork Appearance") {
                        LabeledContent("Artwork blur") {
                            Slider(value: settingsBinding(settings, \.nowPlaying.artworkBlur), in: 0...1)
                                .frame(width: 200)
                        }
                        LabeledContent("Background intensity") {
                            Slider(value: settingsBinding(settings, \.nowPlaying.backgroundIntensity), in: 0.3...1)
                                .frame(width: 200)
                        }
                        Toggle("Adaptive contrast", isOn: settingsBinding(settings, \.nowPlaying.adaptiveContrast))
                        Text("Bright artwork automatically gets a stronger dark overlay so text stays readable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Show") {
                    Toggle("Album artwork", isOn: settingsBinding(settings, \.nowPlaying.showAlbumArtwork))
                    Toggle("Playback progress", isOn: settingsBinding(settings, \.nowPlaying.showPlaybackProgress))
                    Toggle("Previous / Next controls", isOn: settingsBinding(settings, \.nowPlaying.showPreviousNextControls))
                }
                Section {
                    Text("Playback control uses Automation permission — macOS asks the first time Glance controls Music or Spotify.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: - Pomodoro

struct PomodoroPane: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "Pomodoro")
            Form {
                Section("Durations") {
                    durationStepper("Focus", \.pomodoro.focusDuration, range: 5...120)
                    durationStepper("Short break", \.pomodoro.shortBreakDuration, range: 1...45)
                    durationStepper("Long break", \.pomodoro.longBreakDuration, range: 5...90)
                    Stepper(
                        "Sessions before long break: \(settings.settings.pomodoro.sessionsBeforeLongBreak)",
                        value: settingsBinding(settings, \.pomodoro.sessionsBeforeLongBreak),
                        in: 2...8
                    )
                }
                Section("Flow") {
                    Toggle("Auto-start break", isOn: settingsBinding(settings, \.pomodoro.autoStartBreak))
                    Toggle("Auto-start focus", isOn: settingsBinding(settings, \.pomodoro.autoStartFocus))
                }
                Section("Completion") {
                    Toggle("Sound", isOn: settingsBinding(settings, \.pomodoro.soundEnabled))
                    Toggle("Notch interruption on completion", isOn: settingsBinding(settings, \.pomodoro.interruptionOnCompletion))
                }
            }
            .formStyle(.grouped)
        }
    }

    private func durationStepper(_ label: String, _ keyPath: WritableKeyPath<GlanceSettings, TimeInterval>, range: ClosedRange<Int>) -> some View {
        let minutes = Int(settings.settings[keyPath: keyPath] / 60)
        return Stepper("\(label): \(minutes) min", value: Binding(
            get: { minutes },
            set: { newValue in settings.update { $0[keyPath: keyPath] = TimeInterval(newValue * 60) } }
        ), in: range)
    }
}

// MARK: - Activities ("Add to your notch")

struct ActivitiesPane: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(
                title: "Add to Your Notch",
                subtitle: "Glance starts minimal. Enable only what you want to see. Providers run independently — one failing never affects another."
            )
            Form {
                Section("Context") {
                    activityRow(
                        title: "Context Awareness",
                        detail: "Track what you're working on, locally",
                        isOn: settingsBinding(settings, \.context.isEnabled),
                        status: coordinator.activity.providerStatuses["context"]
                    )
                    activityRow(
                        title: "Coding Activity",
                        detail: "See coding time and the app you're coding in",
                        isOn: settingsBinding(settings, \.codingContext.isEnabled),
                        status: coordinator.activity.providerStatuses["coding-context"]
                    )
                }
                Section("System") {
                    activityRow(
                        title: "Battery & Charging",
                        detail: "Charging, 80%, full, and low-battery events",
                        isOn: settingsBinding(settings, \.battery.isEnabled),
                        status: coordinator.activity.providerStatuses["battery"]
                    )
                    activityRow(
                        title: "Network Activity",
                        detail: "Meaningful throughput and connectivity changes",
                        isOn: settingsBinding(settings, \.network.isEnabled),
                        status: coordinator.activity.providerStatuses["network"]
                    )
                }
                Section("Developer") {
                    activityRow(
                        title: "Claude Code",
                        detail: "Know when Claude needs you",
                        isOn: settingsBinding(settings, \.claudeCode.isEnabled),
                        status: coordinator.activity.providerStatuses["claude-code"]
                    )
                    Text("Universal Activities (local scripts publishing to the notch) is planned — see the roadmap.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                networkDetails
                batteryDetails
            }
            .formStyle(.grouped)
        }
    }

    @ViewBuilder
    private var networkDetails: some View {
        if settings.settings.network.isEnabled {
            Section("Network Options") {
                Picker("Show when", selection: settingsBinding(settings, \.network.visibilityMode)) {
                    Text("High network activity").tag(NetworkVisibilityMode.highActivity)
                    Text("Downloading only").tag(NetworkVisibilityMode.downloadingOnly)
                    Text("Always").tag(NetworkVisibilityMode.always)
                }
                LabeledContent("Activity threshold") {
                    Picker("", selection: settingsBinding(settings, \.network.activityThresholdBytesPerSecond)) {
                        Text("1 MB/s").tag(1_000_000.0)
                        Text("5 MB/s").tag(5_000_000.0)
                        Text("10 MB/s").tag(10_000_000.0)
                        Text("25 MB/s").tag(25_000_000.0)
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                Toggle("Connection lost / restored events", isOn: settingsBinding(settings, \.network.notifyConnectivityChanges))
            }
        }
    }

    @ViewBuilder
    private var batteryDetails: some View {
        if settings.settings.battery.isEnabled {
            Section("Battery Options") {
                Toggle("Charger connected", isOn: settingsBinding(settings, \.battery.notifyChargerConnected))
                Toggle("Charger disconnected", isOn: settingsBinding(settings, \.battery.notifyChargerDisconnected))
                Toggle("80% reached", isOn: settingsBinding(settings, \.battery.notifyEightyPercent))
                Toggle("Fully charged", isOn: settingsBinding(settings, \.battery.notifyFullyCharged))
                Toggle("Low battery", isOn: settingsBinding(settings, \.battery.notifyLowBattery))
                Toggle("Critical battery", isOn: settingsBinding(settings, \.battery.notifyCriticalBattery))
            }
        }
    }

    private func activityRow(title: String, detail: String, isOn: Binding<Bool>, status: ProviderStatus?) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                    ProviderStatusBadge(status: status)
                }
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch)
        }
    }
}

struct ProviderStatusBadge: View {
    let status: ProviderStatus?

    var body: some View {
        if let status, status != .disabled {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(color.opacity(0.18)))
                .foregroundStyle(color)
        }
    }

    private var label: String {
        switch status {
        case .running: return "Running"
        case .notConfigured: return "Not Configured"
        case .permissionRequired: return "Permission Required"
        case .unavailable: return "Unavailable"
        case .error: return "Error"
        case .disabled, nil: return ""
        }
    }

    private var color: Color {
        switch status {
        case .running: return .green
        case .notConfigured, .permissionRequired: return .orange
        case .unavailable, .error: return .red
        case .disabled, nil: return .secondary
        }
    }
}

// MARK: - Context Awareness

struct ContextPane: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(
                title: "Context Awareness",
                subtitle: "Your Mac activity is analysed locally. Activity data does not leave this Mac."
            )
            Form {
                Section {
                    Toggle("Context Awareness", isOn: settingsBinding(settings, \.context.isEnabled))
                }
                if settings.settings.context.isEnabled {
                    Section("Signals") {
                        Toggle("Active applications", isOn: settingsBinding(settings, \.context.trackActiveApplications))
                        Toggle("Time spent in applications", isOn: settingsBinding(settings, \.context.trackApplicationTime))
                    }
                    Section("Opt-in signals (not yet used by the classifier)") {
                        Text("Window titles, browser domains, and terminal processes are planned signals. They stay off and unread until a future version implements them — enabling context awareness today only reads app names.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Section("History") {
                        Picker("Keep history", selection: settingsBinding(settings, \.context.retention)) {
                            Text("Today only").tag(HistoryRetention.todayOnly)
                            Text("7 days").tag(HistoryRetention.sevenDays)
                            Text("30 days").tag(HistoryRetention.thirtyDays)
                            Text("Forever").tag(HistoryRetention.forever)
                        }
                        Button("Clear Activity History", role: .destructive) {
                            coordinator.context.history.clear()
                        }
                    }
                }
                if settings.settings.codingContext.isEnabled {
                    Section("Coding Context") {
                        Toggle("Show current application", isOn: settingsBinding(settings, \.codingContext.showCurrentApplication))
                        LabeledContent("Show after") {
                            Picker("", selection: settingsBinding(settings, \.codingContext.displayAfterSeconds)) {
                                Text("Immediately").tag(0.0)
                                Text("1 minute").tag(60.0)
                                Text("5 minutes").tag(300.0)
                                Text("10 minutes").tag(600.0)
                            }
                            .labelsHidden()
                            .frame(width: 130)
                        }
                        Text("Project and git-branch detection require window-title access and are planned; today Glance only uses the frontmost application.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: - Claude Code

struct ClaudeCodePane: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var showInstallConfirmation = false
    @State private var installMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(
                title: "Claude Code",
                subtitle: "Glance integrates through Claude Code's official hooks. Prompts and code are never read or stored."
            )
            Form {
                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        ProviderStatusBadge(status: statusForDisplay)
                    }
                    Toggle("Claude Code integration", isOn: settingsBinding(settings, \.claudeCode.isEnabled))
                }
                if settings.settings.claudeCode.isEnabled {
                    Section("Hooks") {
                        if coordinator.claudeCode.installer.isInstalled {
                            LabeledContent("Hooks installed in ~/.claude/settings.json") {
                                Button("Remove") { uninstallHooks() }
                            }
                        } else {
                            LabeledContent("Hooks not installed") {
                                Button("Install Hooks…") { showInstallConfirmation = true }
                            }
                        }
                        if let installMessage {
                            Text(installMessage).font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Install adds Glance hook entries for SessionStart, UserPromptSubmit, PreToolUse, Notification, Stop, and SessionEnd. Your settings file is backed up first, existing hooks are preserved, and prompt/tool contents are discarded (`cat > /dev/null`) — only empty event markers reach disk.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Section("Show interruptions for") {
                        Toggle("Needs input", isOn: settingsBinding(settings, \.claudeCode.interruptOnNeedsInput))
                        Toggle("Permission required", isOn: settingsBinding(settings, \.claudeCode.interruptOnPermissionRequired))
                        Toggle("Completed", isOn: settingsBinding(settings, \.claudeCode.interruptOnCompleted))
                        Text("Failure events are not reported by Claude Code hooks today, so Glance does not offer a failure interruption.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Section("Screen") {
                        ClaudeScreenToggle()
                    }
                    Section("Privacy") {
                        Toggle("Store session durations in local history", isOn: settingsBinding(settings, \.claudeCode.storeSessionDurations))
                        Text("Prompts are never stored. This is enforced by the hook design, not just policy.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .confirmationDialog(
            "Install Claude Code hooks?",
            isPresented: $showInstallConfirmation
        ) {
            Button("Install") { installHooks() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(coordinator.claudeCode.installer.installPreview())
        }
    }

    private var statusForDisplay: ProviderStatus? {
        coordinator.activity.providerStatuses["claude-code"]
    }

    private func installHooks() {
        do {
            let backup = try coordinator.claudeCode.installer.install()
            installMessage = backup.map { "Installed. Backup saved to \($0.lastPathComponent)." } ?? "Installed."
            coordinator.claudeCode.refreshConfiguration()
            coordinator.activity.refreshStatuses()
        } catch {
            installMessage = "Install failed: \(error.localizedDescription)"
        }
    }

    private func uninstallHooks() {
        do {
            try coordinator.claudeCode.installer.uninstall()
            installMessage = "Hooks removed. A backup of the previous settings was saved."
            coordinator.claudeCode.refreshConfiguration()
            coordinator.activity.refreshStatuses()
        } catch {
            installMessage = "Removal failed: \(error.localizedDescription)"
        }
    }
}

struct ClaudeScreenToggle: View {
    @EnvironmentObject var screens: ScreenStore

    var body: some View {
        let hasScreen = screens.screens.contains { $0.type == .claudeCode }
        Toggle("Claude Code Screen", isOn: Binding(
            get: { hasScreen },
            set: { enabled in
                if enabled {
                    screens.addScreen(type: .claudeCode)
                } else {
                    screens.removeScreens(ofType: .claudeCode)
                }
            }
        ))
    }
}

// MARK: - Privacy

struct PrivacyPane: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var newBundleID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(
                title: "Privacy",
                subtitle: "Your Mac activity is analysed locally. Activity data does not leave this Mac unless an explicitly enabled integration requires external communication (Spotify artwork is fetched from Spotify's image servers)."
            )
            Form {
                Section("Never track these applications") {
                    ForEach(settings.settings.privacy.neverTrackBundleIdentifiers, id: \.self) { bundleID in
                        HStack {
                            Text(bundleID).font(.system(.body, design: .monospaced))
                            Spacer()
                            Button {
                                settings.update { $0.privacy.neverTrackBundleIdentifiers.removeAll { $0 == bundleID } }
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack {
                        TextField("Bundle identifier (e.g. com.1password.1password)", text: $newBundleID)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            let trimmed = newBundleID.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            settings.update {
                                if !$0.privacy.neverTrackBundleIdentifiers.contains(trimmed) {
                                    $0.privacy.neverTrackBundleIdentifiers.append(trimmed)
                                }
                            }
                            newBundleID = ""
                        }
                    }
                    Button("Add Frontmost Application") {
                        if let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier {
                            settings.update {
                                if !$0.privacy.neverTrackBundleIdentifiers.contains(id) {
                                    $0.privacy.neverTrackBundleIdentifiers.append(id)
                                }
                            }
                        }
                    }
                }
                Section("What Glance never logs") {
                    Text("Prompts · source code · clipboard contents · tokens or API keys · window titles · browser history. See docs/PRIVACY.md in the repository for the full policy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: - About

struct AboutPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "About")
            VStack(alignment: .leading, spacing: 8) {
                Text("Glance").font(.title3.weight(.semibold))
                Text("A configurable, context-aware Live Activity layer for macOS.")
                    .foregroundStyle(.secondary)
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("The notch is a scarce attention surface. Every activity must earn the right to appear.")
                    .font(.callout.italic())
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
        }
    }
}

// MARK: - Login item

import ServiceManagement

enum LoginItemManager {
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
