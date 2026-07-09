import Combine
import Foundation

/// Central coordinator between providers, settings, and the interruption
/// engine.
///
///     Provider → ActivityEngine → Screen state / InterruptionEngine → UI
///
/// The engine owns provider lifecycle: providers are started when their
/// settings toggle turns on and stopped when it turns off. Each provider's
/// `start()` is wrapped so a crash-adjacent failure in one provider cannot
/// take down the others (providers report problems via `status`).
@MainActor
public final class ActivityEngine: ObservableObject {
    public let interruptions: InterruptionEngine

    /// Published so Settings can render provider health.
    @Published public private(set) var providerStatuses: [String: ProviderStatus] = [:]

    private var providers: [String: any ActivityProvider] = [:]
    private var enablement: [String: (GlanceSettings) -> Bool] = [:]
    private var displayNames: [String: String] = [:]
    private var running: Set<String> = []
    /// Set once app launch wiring is done, so enable-confirmations only fire
    /// for user-initiated toggles, never at startup.
    private var launchComplete = false
    private let settings: SettingsStore
    private var cancellable: AnyCancellable?
    private var statusPoll: GlanceCancellable?
    private let scheduler: GlanceScheduler

    public init(settings: SettingsStore, interruptions: InterruptionEngine, scheduler: GlanceScheduler = TimerScheduler()) {
        self.settings = settings
        self.interruptions = interruptions
        self.scheduler = scheduler
        cancellable = settings.$settings
            .removeDuplicates()
            .sink { [weak self] value in self?.reconcile(with: value) }
    }

    /// Register a provider with the predicate that decides whether it should
    /// run for a given settings value. Providers with a `displayName` get a
    /// brief confirmation peek when the user enables them, so toggling an
    /// activity always has visible feedback.
    public func register(_ provider: any ActivityProvider, displayName: String? = nil, enabledWhen: @escaping (GlanceSettings) -> Bool) {
        providers[provider.id] = provider
        enablement[provider.id] = enabledWhen
        displayNames[provider.id] = displayName
        let providerID = provider.id
        provider.emitInterruption = { [weak self] interruption in
            self?.interruptions.present(interruption)
        }
        provider.resolveInterruption = { [weak self] kind in
            self?.interruptions.resolve(provider: providerID, kind: kind)
        }
        reconcile(with: settings.settings)
    }

    public func provider(id: String) -> (any ActivityProvider)? { providers[id] }

    /// Call once the app finishes launch wiring; from then on, enabling a
    /// provider shows a confirmation peek.
    public func markLaunchComplete() {
        launchComplete = true
    }

    public func stopAll() {
        for id in running { stopProvider(id) }
    }

    // MARK: Lifecycle reconciliation

    private func reconcile(with value: GlanceSettings) {
        for (id, provider) in providers {
            let shouldRun = enablement[id]?(value) ?? false
            let isRunning = running.contains(id)
            if shouldRun && !isRunning {
                startProvider(provider)
            } else if !shouldRun && isRunning {
                stopProvider(id)
            }
        }
        refreshStatuses()
    }

    private func startProvider(_ provider: any ActivityProvider) {
        GlanceLog.activityEngine.info("Starting provider \(provider.id, privacy: .public)")
        running.insert(provider.id)
        provider.start()
        refreshStatuses()
        if launchComplete, let name = displayNames[provider.id], provider.status.isRunning {
            interruptions.present(NotchInterruption(
                provider: provider.id,
                kind: "provider-enabled",
                title: "\(name) enabled",
                subtitle: "Events will appear when they matter",
                symbolName: "checkmark.circle",
                priority: .normal,
                displayDuration: 2.5
            ))
        }
    }

    private func stopProvider(_ id: String) {
        guard let provider = providers[id] else { return }
        GlanceLog.activityEngine.info("Stopping provider \(id, privacy: .public)")
        provider.stop()
        running.remove(id)
        interruptions.removeAll(fromProvider: id)
        refreshStatuses()
    }

    /// Providers update `status` internally; call after lifecycle changes and
    /// whenever a provider reports a change.
    public func refreshStatuses() {
        var statuses: [String: ProviderStatus] = [:]
        for (id, provider) in providers {
            statuses[id] = running.contains(id) ? provider.status : .disabled
        }
        if statuses != providerStatuses { providerStatuses = statuses }
    }
}
