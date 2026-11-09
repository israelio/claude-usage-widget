import XCTest
@testable import UsageCore

final class WidgetWatchdogTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
    private let hour: TimeInterval = 3600

    private func decide(now: TimeInterval, hb: TimeInterval?, started: TimeInterval = -10 * 3600, widgets: Bool = true,
                        kick: TimeInterval? = nil, restart: TimeInterval? = nil) -> WidgetWatchdog.Action {
        WidgetWatchdog.decide(now: at(now), heartbeat: hb.map(at), appStartedAt: at(started), hasWidgets: widgets,
                              lastKick: kick.map(at), lastRestart: restart.map(at))
    }

    func testNoWidgetsOrFreshHeartbeat() {
        XCTAssertEqual(decide(now: 0, hb: -3 * hour, widgets: false), .none)
        XCTAssertEqual(decide(now: 0, hb: -20 * 60), .none)
    }

    func testStaleKicksOnce() {
        XCTAssertEqual(decide(now: 0, hb: -21 * 60), .reload)
        XCTAssertEqual(decide(now: 0, hb: -21 * 60, kick: -10 * 60 - 3 * hour), .reload)   // old kick, before last sign
    }

    func testMissingHeartbeatOnlyStaleAfterAppUptime() {
        XCTAssertEqual(decide(now: 0, hb: nil, started: -5 * 60), .none)
        XCTAssertEqual(decide(now: 0, hb: nil, started: -25 * 60), .reload)
        XCTAssertEqual(decide(now: 0, hb: -2 * hour, started: -60), .none)   // heartbeat predates launch
    }

    func testEscalatesWhenKickDidNotHelp() {
        XCTAssertEqual(decide(now: 0, hb: -hour, kick: -60), .none)             // inside kick cooldown
        XCTAssertEqual(decide(now: 0, hb: -hour, kick: -6 * 60), .none)         // waiting to see if it helps
        XCTAssertEqual(decide(now: 0, hb: -hour, kick: -11 * 60), .restart)
        XCTAssertEqual(decide(now: 0, hb: -hour, kick: -11 * 60, restart: -hour), .none)
        XCTAssertEqual(decide(now: 0, hb: -hour, kick: -11 * 60, restart: -3 * hour), .restart)
    }

    func testKickThatHelpedIsNotEscalated() {
        // Heartbeat came back after the kick, then went stale again: soft kick again, not a restart.
        XCTAssertEqual(decide(now: 0, hb: -30 * 60, kick: -50 * 60), .reload)
    }

    func testCustomThresholds() {
        let a = WidgetWatchdog.decide(now: at(0), heartbeat: at(-61), appStartedAt: at(-1000), hasWidgets: true, lastKick: nil,
                                      lastRestart: nil, staleAfter: 60, kickCooldown: 30, restartCooldown: 240)
        XCTAssertEqual(a, .reload)
    }
}

final class WidgetHeartbeatTests: XCTestCase {
    private func tmp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("hb-\(UUID().uuidString).txt") }

    func testRoundTrip() {
        let u = tmp(); defer { try? FileManager.default.removeItem(at: u) }
        let d = Date(timeIntervalSince1970: 1_700_000_123)
        WidgetHeartbeat.write(to: u, date: d)
        XCTAssertEqual(WidgetHeartbeat.read(from: u), d)
    }

    func testMissingAndGarbage() {
        let u = tmp(); defer { try? FileManager.default.removeItem(at: u) }
        XCTAssertNil(WidgetHeartbeat.read(from: u))
        try? "not a date".write(to: u, atomically: true, encoding: .utf8)
        XCTAssertNil(WidgetHeartbeat.read(from: u))
    }
}

final class SnapshotDisplayEqualsTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 1_700_000_000)
    private func snap(util: Double = 40.2, reset: Date? = nil, cost: Double = 1.234, remaining: Bool? = false, est: Bool = false,
                      updated: Date? = nil, fetched: Date? = nil) -> SharedSnapshot {
        let l = LimitsSnapshot(fetchedAt: fetched ?? t, fiveHour: LimitWindow(utilization: util, resetsAt: reset ?? t),
                               sevenDay: LimitWindow(utilization: 10, resetsAt: t), isEstimated: est)
        return SharedSnapshot(limits: l, today: Totals(tokens: .zero, cost: cost), last7: .zero,
                              daily: [DailyPoint(day: t, tokens: .zero, cost: cost)], updatedAt: updated ?? t, showRemaining: remaining)
    }

    func testIgnoresTimestampsAndSubDisplayNoise() {
        let a = snap()
        XCTAssertTrue(a.displayEquals(snap(util: 40.4, cost: 1.2341, updated: t.addingTimeInterval(300), fetched: t.addingTimeInterval(300))))
    }

    func testDetectsDisplayedChanges() {
        let a = snap()
        XCTAssertFalse(a.displayEquals(snap(util: 41)))
        XCTAssertFalse(a.displayEquals(snap(reset: t.addingTimeInterval(60))))
        XCTAssertFalse(a.displayEquals(snap(cost: 1.25)))
        XCTAssertFalse(a.displayEquals(snap(remaining: true)))
        XCTAssertFalse(a.displayEquals(snap(est: true)))
    }
}
