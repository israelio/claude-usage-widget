import XCTest
@testable import UsageCore

final class AlertsTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    let now = ISODate.parse("2026-11-09T19:00:00Z")!   // a Monday
    func snap(five: Double, remaining: TimeInterval = 2 * 3600, week: Double = 10) -> LimitsSnapshot {
        LimitsSnapshot(fetchedAt: now,
                       fiveHour: LimitWindow(utilization: five, resetsAt: now.addingTimeInterval(remaining)),
                       sevenDay: LimitWindow(utilization: week, resetsAt: now.addingTimeInterval(3 * 86400)))
    }
    func eval(_ cur: LimitsSnapshot, prev: LimitsSnapshot? = nil, s: AlertSettings = AlertSettings(), fired: inout FiredState) -> [AlertMessage] {
        AlertEngine.evaluate(current: cur, previous: prev, settings: s, fired: &fired, now: now, calendar: cal)
    }

    func testThresholdFiresOnceAtHighestCrossed() {
        var f = FiredState()
        let m1 = eval(snap(five: 80, remaining: 4.5 * 3600), fired: &f)
        XCTAssertEqual(m1.filter { $0.id.hasPrefix("thr-5h") }.count, 1)
        XCTAssertTrue(m1.first { $0.id.hasPrefix("thr-5h") }!.title.contains("75%"))
        XCTAssertTrue(eval(snap(five: 82, remaining: 4.5 * 3600), fired: &f).filter { $0.id.hasPrefix("thr-5h") }.isEmpty)
        let m3 = eval(snap(five: 91, remaining: 4.5 * 3600), fired: &f)
        XCTAssertTrue(m3.first { $0.id.hasPrefix("thr-5h") }!.title.contains("90%"))
    }
    func testBelowThresholdSilent() {
        var f = FiredState()
        XCTAssertTrue(eval(snap(five: 30, remaining: 2 * 3600), fired: &f).isEmpty)
    }
    func testBurnRate() {
        var f = FiredState()
        // 40% used with 4.5h left of 5h => frac 0.1, projected 400% -> over
        var s = AlertSettings(); s.thresholds = []
        let m = eval(snap(five: 40, remaining: 4.5 * 3600), s: s, fired: &f)
        XCTAssertEqual(m.filter { $0.id.hasPrefix("burn-5h") }.count, 1)
        XCTAssertTrue(eval(snap(five: 41, remaining: 4.5 * 3600), s: s, fired: &f).isEmpty)
    }
    func testResetNotice() {
        var f = FiredState(); var s = AlertSettings(); s.thresholds = []; s.burnRate = false
        let prev = snap(five: 80, remaining: 60)
        let cur = snap(five: 2, remaining: 5 * 3600)
        let m = eval(cur, prev: prev, s: s, fired: &f)
        XCTAssertEqual(m.filter { $0.id.hasPrefix("reset-5h") }.count, 1)
    }
    func testQuietHoursSuppressWithoutConsuming() {
        var f = FiredState(); var s = AlertSettings(); s.quietStartHour = 18; s.quietEndHour = 8
        XCTAssertTrue(eval(snap(five: 95, remaining: 4 * 3600), s: s, fired: &f).isEmpty)
        XCTAssertTrue(f.keys.isEmpty)
    }
    func testDigests() {
        var f = FiredState()
        let sum = UsageSummary(today: Totals(tokens: TokenCounts(input: 1000, output: 2000), cost: 12.5),
                               last7: Totals(tokens: TokenCounts(output: 5_000_000), cost: 80),
                               month: .zero, last30: .zero, modelShare: [])
        var s = AlertSettings(); s.digestHour = 18
        let m = AlertEngine.digests(summary: sum, settings: s, fired: &f, now: now, calendar: cal)
        XCTAssertEqual(Set(m.map(\.id)), ["digest-d-2026-11-09", "digest-w-2026-11-09"])
        XCTAssertTrue(AlertEngine.digests(summary: sum, settings: s, fired: &f, now: now, calendar: cal).isEmpty)
        var early = AlertSettings(); early.digestHour = 20
        var f2 = FiredState()
        XCTAssertTrue(AlertEngine.digests(summary: sum, settings: early, fired: &f2, now: now, calendar: cal).isEmpty)
    }
}

final class AlertsResetTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    let now = ISODate.parse("2026-11-09T12:00:00Z")!
    func snap(_ u: Double, reset: Date?, week: Double = 5) -> LimitsSnapshot {
        LimitsSnapshot(fetchedAt: now, fiveHour: LimitWindow(utilization: u, resetsAt: reset),
                       sevenDay: LimitWindow(utilization: week, resetsAt: now.addingTimeInterval(3 * 86400)))
    }
    func quiet() -> AlertSettings { var s = AlertSettings(); s.thresholds = []; s.burnRate = false; return s }
    func eval(_ cur: LimitsSnapshot, _ prev: LimitsSnapshot?, _ s: AlertSettings, _ f: inout FiredState, at t: Date? = nil) -> [AlertMessage] {
        AlertEngine.evaluate(current: cur, previous: prev, settings: s, fired: &f, now: t ?? now, calendar: cal)
    }

    func testIdleResetWithNilResetsAt() {
        var f = FiredState()
        let prev = snap(80, reset: now.addingTimeInterval(120))
        let cur = snap(0, reset: nil)
        let m = eval(cur, prev, quiet(), &f)
        XCTAssertEqual(m.filter { $0.id.hasPrefix("reset-5h") }.count, 1)
        // A later idle reset of a new window must fire again.
        let prev2 = snap(90, reset: now.addingTimeInterval(86400 + 120))
        let m2 = eval(snap(0, reset: nil), prev2, quiet(), &f)
        XCTAssertEqual(m2.filter { $0.id.hasPrefix("reset-5h") }.count, 1)
    }

    func testExpiredWindowWithLowerUtilizationIsReset() {
        var f = FiredState()
        let prev = snap(30, reset: now.addingTimeInterval(-60))
        let m = eval(snap(3, reset: now.addingTimeInterval(5 * 3600)), prev, quiet(), &f)
        XCTAssertEqual(m.filter { $0.id.hasPrefix("reset-5h") }.count, 1)
    }

    func testNoResetWhenSameWindow() {
        var f = FiredState()
        let r = now.addingTimeInterval(3600)
        XCTAssertTrue(eval(snap(81, reset: r), snap(80, reset: r.addingTimeInterval(5)), quiet(), &f).isEmpty)
    }

    func testResetsAtJitterAcrossOldBucketBoundaryDoesNotRefire() {
        var f = FiredState(); var s = AlertSettings(); s.resetNotice = false
        // Old buckets were multiples of 600s; straddle one.
        let boundary = Date(timeIntervalSince1970: ceil(now.addingTimeInterval(4 * 3600).timeIntervalSince1970 / 600) * 600 + 300)
        let a = eval(snap(95, reset: boundary.addingTimeInterval(-90)), nil, s, &f)
        XCTAssertFalse(a.isEmpty)
        let b = eval(snap(96, reset: boundary.addingTimeInterval(90)), nil, s, &f)
        XCTAssertTrue(b.isEmpty, "jitter must not refire thresholds/burn: \(b)")
        let c = eval(snap(96, reset: boundary.addingTimeInterval(-90)), nil, s, &f)
        XCTAssertTrue(c.isEmpty)
    }

    func testNewWindowAdoptsNewKey() {
        var f = FiredState(); var s = AlertSettings(); s.burnRate = false
        _ = eval(snap(80, reset: now.addingTimeInterval(3600)), nil, s, &f)
        let m = eval(snap(80, reset: now.addingTimeInterval(3600 + 5 * 3600)), nil, s, &f)
        XCTAssertFalse(m.isEmpty)
    }

    func testFiredStateDecodesLegacy() throws {
        let f = try JSONDecoder().decode(FiredState.self, from: Data(#"{"keys":["a"]}"#.utf8))
        XCTAssertEqual(f.keys, ["a"]); XCTAssertTrue(f.lastReset.isEmpty)
        let a = try JSONDecoder().decode(AlertSettings.self, from: Data(#"{"burnRate":false}"#.utf8))
        XCTAssertFalse(a.burnRate); XCTAssertEqual(a.thresholds, [50, 75, 90])
    }

    func testIsQuietPublic() {
        var s = AlertSettings(); s.quietStartHour = 11; s.quietEndHour = 13
        XCTAssertTrue(AlertEngine.isQuiet(s, now: now, calendar: cal))
    }
}
