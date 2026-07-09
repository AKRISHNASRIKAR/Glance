import Foundation
import Testing
@testable import GlanceKit

struct ContextEngineTests {
    @Test func classificationPriorityLadder() {
        let engine = ContextEngine()
        #expect(engine.classify(ContextSignals(idleSeconds: 10 * 60)) == .away)
        #expect(engine.classify(ContextSignals(
            frontmostBundleID: "com.apple.dt.Xcode", isPomodoroFocusRunning: true
        )) == .focus)
        #expect(engine.classify(ContextSignals(frontmostBundleID: "com.apple.dt.Xcode")) == .coding)
        #expect(engine.classify(ContextSignals(frontmostBundleID: "us.zoom.xos")) == .meeting)
        #expect(engine.classify(ContextSignals(frontmostBundleID: "com.figma.Desktop")) == .designing)
        #expect(engine.classify(ContextSignals(frontmostBundleID: "com.unknown.app")) == .general)
    }

    @Test func sessionRecordedOnTransitionAfterMinimumDuration() {
        var engine = ContextEngine()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(engine.update(signals: ContextSignals(frontmostBundleID: "com.apple.dt.Xcode", frontmostAppName: "Xcode"), at: start) == nil)
        let finished = engine.update(signals: ContextSignals(frontmostBundleID: "us.zoom.xos", frontmostAppName: "Zoom"), at: start.addingTimeInterval(3600))
        #expect(finished?.kind == .coding)
        #expect(finished?.label == "Xcode")
        #expect(finished?.duration == 3600)
    }

    @Test func shortBlipsAreDropped() {
        var engine = ContextEngine()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        _ = engine.update(signals: ContextSignals(frontmostBundleID: "com.apple.dt.Xcode"), at: start)
        // 20 seconds in Xcode, below the 60 s minimum.
        let finished = engine.update(signals: ContextSignals(frontmostBundleID: "us.zoom.xos"), at: start.addingTimeInterval(20))
        #expect(finished == nil)
    }

    @Test func generalAndAwayTimeIsNotRecorded() {
        var engine = ContextEngine()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        _ = engine.update(signals: ContextSignals(frontmostBundleID: "com.unknown.app"), at: start)
        let finished = engine.update(signals: ContextSignals(frontmostBundleID: "com.apple.dt.Xcode"), at: start.addingTimeInterval(3600))
        #expect(finished == nil)
    }
}

@MainActor
struct ContextHistoryTests {
    private func makeStore(retention: HistoryRetention, clock: TestClock) -> ContextHistoryStore {
        ContextHistoryStore(
            fileURL: makeTempDirectory().appendingPathComponent("history.json"),
            retention: retention,
            timeSource: clock
        )
    }

    private func session(kind: ContextKind = .coding, label: String? = "Xcode", endingAgo: TimeInterval, duration: TimeInterval, from clock: TestClock) -> ContextSession {
        let end = clock.now.addingTimeInterval(-endingAgo)
        return ContextSession(kind: kind, label: label, start: end.addingTimeInterval(-duration), end: end)
    }

    @Test func retentionPrunesOldSessions() {
        let clock = TestClock()
        let store = makeStore(retention: .sevenDays, clock: clock)
        store.append(session(endingAgo: 8 * 24 * 3600, duration: 3600, from: clock))
        store.append(session(endingAgo: 3600, duration: 3600, from: clock))
        #expect(store.sessions.count == 1)
    }

    @Test func foreverKeepsEverything() {
        let clock = TestClock()
        let store = makeStore(retention: .forever, clock: clock)
        store.append(session(endingAgo: 365 * 24 * 3600, duration: 3600, from: clock))
        #expect(store.sessions.count == 1)
    }

    @Test func historyPersistsAcrossStores() {
        let clock = TestClock()
        let url = makeTempDirectory().appendingPathComponent("history.json")
        let store = ContextHistoryStore(fileURL: url, retention: .forever, timeSource: clock)
        store.append(session(endingAgo: 3600, duration: 1800, from: clock))
        let reloaded = ContextHistoryStore(fileURL: url, retention: .forever, timeSource: clock)
        #expect(reloaded.sessions.count == 1)
        #expect(reloaded.sessions.first?.kind == .coding)
    }

    @Test func clearRemovesEverything() {
        let clock = TestClock()
        let url = makeTempDirectory().appendingPathComponent("history.json")
        let store = ContextHistoryStore(fileURL: url, retention: .forever, timeSource: clock)
        store.append(session(endingAgo: 3600, duration: 1800, from: clock))
        store.clear()
        #expect(store.sessions.isEmpty)
        let reloaded = ContextHistoryStore(fileURL: url, retention: .forever, timeSource: clock)
        #expect(reloaded.sessions.isEmpty)
    }

    @Test func todaySummaryAggregatesAndClipsToToday() {
        let clock = TestClock()
        let store = makeStore(retention: .forever, clock: clock)
        store.append(session(kind: .coding, label: "Xcode", endingAgo: 600, duration: 1800, from: clock))
        store.append(session(kind: .coding, label: "Xcode", endingAgo: 3600, duration: 1800, from: clock))
        store.append(session(kind: .focus, label: nil, endingAgo: 7200, duration: 1500, from: clock))
        let summary = store.todaySummary()
        let coding = summary.first { $0.kind == .coding }
        #expect(coding != nil)
        #expect(coding.map { abs($0.duration - 3600) < 1 } == true)
    }
}

struct BatteryDetectorTests {
    private func snapshot(_ pct: Int, plugged: Bool, charged: Bool = false) -> BatterySnapshot {
        BatterySnapshot(percentage: pct, isCharging: plugged && !charged, isPluggedIn: plugged, isFullyCharged: charged)
    }

    @Test func firstObservationEmitsNothing() {
        let detector = BatteryEventDetector()
        #expect(detector.events(from: nil, to: snapshot(50, plugged: true)).isEmpty)
    }

    @Test func chargerTransitions() {
        let detector = BatteryEventDetector()
        #expect(detector.events(from: snapshot(50, plugged: false), to: snapshot(50, plugged: true))
            == [.chargerConnected(percentage: 50)])
        #expect(detector.events(from: snapshot(50, plugged: true), to: snapshot(50, plugged: false))
            == [.chargerDisconnected(percentage: 50)])
    }

    @Test func thresholdCrossings() {
        let detector = BatteryEventDetector()
        #expect(detector.events(from: snapshot(79, plugged: true), to: snapshot(80, plugged: true))
            == [.reachedEightyPercent])
        #expect(detector.events(from: snapshot(21, plugged: false), to: snapshot(20, plugged: false))
            == [.lowBattery(percentage: 20)])
        #expect(detector.events(from: snapshot(11, plugged: false), to: snapshot(9, plugged: false))
            == [.criticalBattery(percentage: 9)])
        // No low/critical events while plugged in.
        #expect(detector.events(from: snapshot(21, plugged: true), to: snapshot(20, plugged: true)).isEmpty)
    }

    @Test func fullyChargedEdge() {
        let detector = BatteryEventDetector()
        #expect(detector.events(from: snapshot(99, plugged: true), to: snapshot(100, plugged: true, charged: true))
            == [.fullyCharged])
    }
}

struct ThroughputGateTests {
    @Test func sustainedHighActivityActivates() {
        var gate = ThroughputGate(thresholdBytesPerSecond: 5_000_000, sustainSeconds: 3)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let high = NetworkThroughput(downloadBytesPerSecond: 10_000_000, uploadBytesPerSecond: 0)
        #expect(gate.update(sample: high, at: start) == false)
        #expect(gate.update(sample: high, at: start.addingTimeInterval(2)) == false)
        #expect(gate.update(sample: high, at: start.addingTimeInterval(3.1)) == true)
    }

    @Test func briefSpikeDoesNotActivate() {
        var gate = ThroughputGate(thresholdBytesPerSecond: 5_000_000, sustainSeconds: 3)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let high = NetworkThroughput(downloadBytesPerSecond: 10_000_000, uploadBytesPerSecond: 0)
        let low = NetworkThroughput.zero
        #expect(gate.update(sample: high, at: start) == false)
        #expect(gate.update(sample: low, at: start.addingTimeInterval(1)) == false)
        #expect(gate.update(sample: high, at: start.addingTimeInterval(2)) == false)
        #expect(gate.update(sample: high, at: start.addingTimeInterval(4)) == false)
    }

    @Test func hysteresisHoldsThroughBriefDips() {
        var gate = ThroughputGate(thresholdBytesPerSecond: 5_000_000, sustainSeconds: 3, releaseSeconds: 5)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let high = NetworkThroughput(downloadBytesPerSecond: 10_000_000, uploadBytesPerSecond: 0)
        let low = NetworkThroughput.zero
        _ = gate.update(sample: high, at: start)
        _ = gate.update(sample: high, at: start.addingTimeInterval(3.1))
        #expect(gate.isActive)
        #expect(gate.update(sample: low, at: start.addingTimeInterval(5)) == true)   // dip, still active
        #expect(gate.update(sample: low, at: start.addingTimeInterval(10.2)) == false) // sustained low releases
    }

    @Test func downloadOnlyModeIgnoresUploads() {
        var gate = ThroughputGate(thresholdBytesPerSecond: 5_000_000, sustainSeconds: 0)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let uploadHeavy = NetworkThroughput(downloadBytesPerSecond: 0, uploadBytesPerSecond: 50_000_000)
        #expect(gate.update(sample: uploadHeavy, at: start, downloadOnly: true) == false)
    }
}
