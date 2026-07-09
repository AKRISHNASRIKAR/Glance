import Foundation
import IOKit.ps

/// Snapshot of battery state, decoupled from IOKit so event logic is testable.
public struct BatterySnapshot: Equatable, Sendable {
    public var percentage: Int
    public var isCharging: Bool
    public var isPluggedIn: Bool
    public var isFullyCharged: Bool

    public init(percentage: Int, isCharging: Bool, isPluggedIn: Bool, isFullyCharged: Bool) {
        self.percentage = percentage
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.isFullyCharged = isFullyCharged
    }
}

/// Battery events derived from consecutive snapshots. Pure and testable.
public enum BatteryEvent: Equatable, Sendable {
    case chargerConnected(percentage: Int)
    case chargerDisconnected(percentage: Int)
    case reachedEightyPercent
    case fullyCharged
    case lowBattery(percentage: Int)
    case criticalBattery(percentage: Int)
}

/// Pure edge detection between two battery snapshots.
public struct BatteryEventDetector: Sendable {
    public var lowThreshold: Int
    public var criticalThreshold: Int

    public init(lowThreshold: Int = 20, criticalThreshold: Int = 10) {
        self.lowThreshold = lowThreshold
        self.criticalThreshold = criticalThreshold
    }

    public func events(from old: BatterySnapshot?, to new: BatterySnapshot) -> [BatteryEvent] {
        var events: [BatteryEvent] = []
        guard let old else { return events } // No events on first observation.

        if !old.isPluggedIn && new.isPluggedIn {
            events.append(.chargerConnected(percentage: new.percentage))
        }
        if old.isPluggedIn && !new.isPluggedIn {
            events.append(.chargerDisconnected(percentage: new.percentage))
        }
        if new.isPluggedIn, old.percentage < 80, new.percentage >= 80, !new.isFullyCharged {
            events.append(.reachedEightyPercent)
        }
        if !old.isFullyCharged && new.isFullyCharged && new.isPluggedIn {
            events.append(.fullyCharged)
        }
        if !new.isPluggedIn {
            if old.percentage > criticalThreshold, new.percentage <= criticalThreshold {
                events.append(.criticalBattery(percentage: new.percentage))
            } else if old.percentage > lowThreshold, new.percentage <= lowThreshold {
                events.append(.lowBattery(percentage: new.percentage))
            }
        }
        return events
    }
}

/// Optional battery & charging provider. Entirely event-driven: IOKit's
/// power-source notification fires on real changes; there is no polling.
@MainActor
public final class BatteryProvider: ActivityProvider, ObservableObject {
    public let id = "battery"
    public private(set) var status: ProviderStatus = .disabled

    public var emitInterruption: (@MainActor (NotchInterruption) -> Void)?
    public var resolveInterruption: (@MainActor (String?) -> Void)?

    @Published public private(set) var snapshot: BatterySnapshot?

    private var detector = BatteryEventDetector()
    private var runLoopSource: CFRunLoopSource?
    private let settings: SettingsStore

    public init(settings: SettingsStore) {
        self.settings = settings
    }

    public func start() {
        let config = settings.settings.battery
        detector = BatteryEventDetector(
            lowThreshold: config.lowBatteryThreshold,
            criticalThreshold: config.criticalBatteryThreshold
        )
        guard Self.readSnapshot() != nil else {
            status = .unavailable("No battery detected on this Mac")
            return
        }

        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let provider = Unmanaged<BatteryProvider>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { provider.powerSourcesChanged() }
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else {
            status = .error("Failed to register for power source notifications")
            return
        }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        status = .running
        snapshot = Self.readSnapshot()
    }

    public func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        runLoopSource = nil
        snapshot = nil
        status = .disabled
    }

    private func powerSourcesChanged() {
        guard let new = Self.readSnapshot() else { return }
        let old = snapshot
        snapshot = new
        for event in detector.events(from: old, to: new) {
            if let interruption = interruption(for: event) {
                emitInterruption?(interruption)
            }
        }
    }

    /// Map battery events to interruptions per the user's settings.
    /// Testable via `interruption(for:)`.
    public func interruption(for event: BatteryEvent) -> NotchInterruption? {
        let config = settings.settings.battery
        switch event {
        case .chargerConnected(let pct):
            guard config.notifyChargerConnected else { return nil }
            return NotchInterruption(
                provider: id, kind: "charger-connected",
                title: "Charging", subtitle: "\(pct)%",
                symbolName: "bolt.fill", priority: .normal, displayDuration: 3
            )
        case .chargerDisconnected(let pct):
            guard config.notifyChargerDisconnected else { return nil }
            return NotchInterruption(
                provider: id, kind: "charger-disconnected",
                title: "On battery", subtitle: "\(pct)%",
                symbolName: "battery.75percent", priority: .normal, displayDuration: 3
            )
        case .reachedEightyPercent:
            guard config.notifyEightyPercent else { return nil }
            return NotchInterruption(
                provider: id, kind: "eighty-percent",
                title: "80% charged", subtitle: nil,
                symbolName: "battery.75percent", priority: .normal, displayDuration: 3
            )
        case .fullyCharged:
            guard config.notifyFullyCharged else { return nil }
            return NotchInterruption(
                provider: id, kind: "fully-charged",
                title: "Fully charged", subtitle: nil,
                symbolName: "battery.100percent.bolt", priority: .normal, displayDuration: 3
            )
        case .lowBattery(let pct):
            guard config.notifyLowBattery else { return nil }
            return NotchInterruption(
                provider: id, kind: "low-battery",
                title: "Low battery", subtitle: "\(pct)%",
                symbolName: "battery.25percent", priority: .important, displayDuration: 5
            )
        case .criticalBattery(let pct):
            guard config.notifyCriticalBattery else { return nil }
            return NotchInterruption(
                provider: id, kind: "critical-battery",
                title: "Battery critical", subtitle: "\(pct)% — connect power",
                symbolName: "battery.0percent", priority: .urgent, displayDuration: 8
            )
        }
    }

    // MARK: IOKit reading

    static func readSnapshot() -> BatterySnapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let percentage = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : 0
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let powerSource = desc[kIOPSPowerSourceStateKey] as? String
            let pluggedIn = powerSource == kIOPSACPowerValue
            let charged = desc[kIOPSIsChargedKey] as? Bool ?? (pluggedIn && percentage >= 100)
            return BatterySnapshot(
                percentage: percentage,
                isCharging: charging,
                isPluggedIn: pluggedIn,
                isFullyCharged: charged
            )
        }
        return nil
    }
}
