import Foundation
import Network

/// One throughput measurement.
public struct NetworkThroughput: Equatable, Sendable {
    public var downloadBytesPerSecond: Double
    public var uploadBytesPerSecond: Double

    public init(downloadBytesPerSecond: Double, uploadBytesPerSecond: Double) {
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
    }

    public static let zero = NetworkThroughput(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0)
}

/// Decides when sustained throughput should surface as live activity.
/// Pure and testable: feed it samples, it answers "show or hide".
public struct ThroughputGate: Sendable {
    public var thresholdBytesPerSecond: Double
    public var sustainSeconds: TimeInterval
    /// Hide only after activity stays below threshold this long (hysteresis
    /// so the surface doesn't flicker).
    public var releaseSeconds: TimeInterval

    private var aboveSince: Date?
    private var belowSince: Date?
    public private(set) var isActive = false

    public init(thresholdBytesPerSecond: Double, sustainSeconds: TimeInterval, releaseSeconds: TimeInterval = 5) {
        self.thresholdBytesPerSecond = thresholdBytesPerSecond
        self.sustainSeconds = sustainSeconds
        self.releaseSeconds = releaseSeconds
    }

    public mutating func update(sample: NetworkThroughput, at now: Date, downloadOnly: Bool = false) -> Bool {
        let rate = downloadOnly
            ? sample.downloadBytesPerSecond
            : max(sample.downloadBytesPerSecond, sample.uploadBytesPerSecond)
        if rate >= thresholdBytesPerSecond {
            belowSince = nil
            if aboveSince == nil { aboveSince = now }
            if !isActive, let since = aboveSince, now.timeIntervalSince(since) >= sustainSeconds {
                isActive = true
            }
        } else {
            aboveSince = nil
            if belowSince == nil { belowSince = now }
            if isActive, let since = belowSince, now.timeIntervalSince(since) >= releaseSeconds {
                isActive = false
            }
        }
        return isActive
    }
}

/// Formats throughput for the notch. Compact: "↓ 42.8", detailed: "↓ 42.8 MB/s".
public enum ThroughputFormatter {
    public static func format(bytesPerSecond: Double, detailed: Bool) -> String {
        let mbps = bytesPerSecond / 1_000_000
        let value: String
        if mbps >= 100 { value = String(format: "%.0f", mbps) }
        else if mbps >= 1 { value = String(format: "%.1f", mbps) }
        else { value = String(format: "%.1f", max(bytesPerSecond / 1_000, 0) ) + (detailed ? "" : "") }
        if mbps < 1 {
            return detailed ? "\(value) KB/s" : value
        }
        return detailed ? "\(value) MB/s" : value
    }
}

/// Optional network provider.
///
/// - Connectivity (lost/restored): event-driven via `NWPathMonitor` — no
///   polling, no measurable cost.
/// - Throughput: interface byte counters sampled every 2 s **only while the
///   provider is enabled**. Reading counters via `getifaddrs` is a single
///   cheap syscall; there is no packet capture and no per-app attribution.
@MainActor
public final class NetworkProvider: ActivityProvider, ObservableObject {
    public let id = "network"
    public private(set) var status: ProviderStatus = .disabled

    public var emitInterruption: (@MainActor (NotchInterruption) -> Void)?
    public var resolveInterruption: (@MainActor (String?) -> Void)?

    @Published public private(set) var throughput: NetworkThroughput = .zero
    /// True while sustained high activity should be surfaced (per settings).
    @Published public private(set) var isHighActivity = false
    @Published public private(set) var isConnected = true

    private var gate: ThroughputGate
    private var pathMonitor: NWPathMonitor?
    private var pollHandle: GlanceCancellable?
    private var lastCounters: (rx: UInt64, tx: UInt64, at: Date)?
    private var hasObservedPath = false
    private let settings: SettingsStore
    private let scheduler: GlanceScheduler
    private let timeSource: TimeSource
    private static let pollInterval: TimeInterval = 2

    public init(settings: SettingsStore, scheduler: GlanceScheduler = TimerScheduler(), timeSource: TimeSource = SystemTimeSource()) {
        self.settings = settings
        self.scheduler = scheduler
        self.timeSource = timeSource
        let net = settings.settings.network
        gate = ThroughputGate(
            thresholdBytesPerSecond: net.activityThresholdBytesPerSecond,
            sustainSeconds: net.sustainSeconds
        )
    }

    public func start() {
        let net = settings.settings.network
        gate = ThroughputGate(
            thresholdBytesPerSecond: net.activityThresholdBytesPerSecond,
            sustainSeconds: net.sustainSeconds
        )
        startPathMonitor()
        scheduleNextSample()
        status = .running
    }

    public func stop() {
        pathMonitor?.cancel()
        pathMonitor = nil
        pollHandle?.cancel()
        pollHandle = nil
        lastCounters = nil
        hasObservedPath = false
        throughput = .zero
        isHighActivity = false
        status = .disabled
    }

    // MARK: Connectivity (event-driven)

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.connectivityChanged(connected: connected)
            }
        }
        monitor.start(queue: DispatchQueue(label: "app.glance.network-path"))
        pathMonitor = monitor
    }

    private func connectivityChanged(connected: Bool) {
        defer { hasObservedPath = true }
        let wasConnected = isConnected
        isConnected = connected
        // Only announce transitions after the initial reading.
        guard hasObservedPath, wasConnected != connected else { return }
        guard settings.settings.network.notifyConnectivityChanges else { return }
        if connected {
            resolveInterruption?("connection-lost")
            emitInterruption?(NotchInterruption(
                provider: id, kind: "connection-restored",
                title: "Connection restored", subtitle: nil,
                symbolName: "wifi", priority: .normal, displayDuration: 3
            ))
        } else {
            emitInterruption?(NotchInterruption(
                provider: id, kind: "connection-lost",
                title: "Connection lost", subtitle: nil,
                symbolName: "wifi.slash", priority: .normal, displayDuration: 4
            ))
        }
    }

    // MARK: Throughput (2 s sampling, enabled providers only)

    private func scheduleNextSample() {
        pollHandle = scheduler.schedule(after: Self.pollInterval) { [weak self] in
            guard let self, self.status.isRunning else { return }
            self.sample()
            self.scheduleNextSample()
        }
    }

    private func sample() {
        guard let counters = Self.readInterfaceCounters() else { return }
        let now = timeSource.now
        defer { lastCounters = (counters.rx, counters.tx, now) }
        guard let last = lastCounters else { return }
        let dt = now.timeIntervalSince(last.at)
        guard dt > 0.1 else { return }
        // Counters can reset (interface bounce); treat regressions as zero.
        let rxDelta = counters.rx >= last.rx ? counters.rx - last.rx : 0
        let txDelta = counters.tx >= last.tx ? counters.tx - last.tx : 0
        let sample = NetworkThroughput(
            downloadBytesPerSecond: Double(rxDelta) / dt,
            uploadBytesPerSecond: Double(txDelta) / dt
        )
        throughput = sample

        let config = settings.settings.network
        switch config.visibilityMode {
        case .always:
            isHighActivity = true
        case .highActivity:
            isHighActivity = gate.update(sample: sample, at: now)
        case .downloadingOnly:
            isHighActivity = gate.update(sample: sample, at: now, downloadOnly: true)
        }
    }

    /// Sum rx/tx bytes across physical interfaces (en*), skipping loopback
    /// and virtual interfaces so local traffic doesn't count.
    static func readInterfaceCounters() -> (rx: UInt64, tx: UInt64)? {
        var addrsPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrsPointer) == 0, let first = addrsPointer else { return nil }
        defer { freeifaddrs(addrsPointer) }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor {
            defer { cursor = ifa.pointee.ifa_next }
            guard let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: ifa.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }
            guard let dataPointer = ifa.pointee.ifa_data else { continue }
            let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
            rx &+= UInt64(data.ifi_ibytes)
            tx &+= UInt64(data.ifi_obytes)
        }
        return (rx, tx)
    }
}
