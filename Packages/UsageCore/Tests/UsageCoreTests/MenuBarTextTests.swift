import XCTest
@testable import UsageCore

final class MenuBarTextTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000)
    // 2h14m left of 5h => 55.3% elapsed; 42% used => pace delta about -13
    func snap(five: Double = 42, week: Double? = 71, model: Double? = 78, reset: Date? = nil) -> LimitsSnapshot {
        LimitsSnapshot(fetchedAt: now,
                       fiveHour: LimitWindow(utilization: five, resetsAt: reset ?? now.addingTimeInterval(2 * 3600 + 14 * 60)),
                       sevenDay: week.map { LimitWindow(utilization: $0, resetsAt: nil) },
                       extra: model.map { ["fable": LimitWindow(utilization: $0, resetsAt: nil)] } ?? [:])
    }
    func make(_ l: LimitsSnapshot?, _ i: MenuBarItems, left: Bool = false, cost: Double? = 8.69) -> String {
        MenuBarText.make(limits: l, todayCost: cost, items: i, showRemaining: left, now: now)
    }
    let all = MenuBarItems(weeklyModel: true, todayCost: true, resetCountdown: true)
    let none = MenuBarItems(statusDot: false, session: false, pace: false, weekly: false)

    func testNilLimits() {
        XCTAssertEqual(make(nil, all), "…")
        XCTAssertEqual(MenuBarText.tooltip(limits: nil, todayCost: nil, items: all, showRemaining: false, now: now), "Claude Usage — loading…")
    }
    func testNothingEnabled() {
        XCTAssertEqual(make(snap(), none), "")
        XCTAssertEqual(MenuBarText.tooltip(limits: snap(), todayCost: 1, items: none, showRemaining: false, now: now), "Claude Usage")
    }
    func testDefaultsLookLikeToday() {
        XCTAssertEqual(make(snap(), MenuBarItems()), "🟢 42% ▼13% · 71%")
        XCTAssertEqual(make(snap(), MenuBarItems(), left: true), "🟢 58% left ▼13% · 29%")
    }
    func testAllItems() {
        XCTAssertEqual(make(snap(), all), "🟢 42% ▼13% · 71% · Fable 78% · $8.69 · ⏱ 2h 14m")
        XCTAssertEqual(make(snap(), all, left: true), "🟢 58% left ▼13% · 29% · Fable 22% · $8.69 · ⏱ 2h 14m")
    }
    func testSessionOnly() {
        XCTAssertEqual(make(snap(), MenuBarItems(pace: false, weekly: false)), "🟢 42%")
    }
    func testLeftWordOnceOnFirstPercentage() {
        let i = MenuBarItems(statusDot: false, session: false, pace: false, weekly: true, weeklyModel: true)
        XCTAssertEqual(make(snap(), i, left: true), "29% left · Fable 22%")
        XCTAssertEqual(make(snap(), MenuBarItems(statusDot: false, pace: false, weekly: false), left: true), "58% left")
    }
    func testPaceNeedsSession() {
        XCTAssertEqual(make(snap(), MenuBarItems(session: false, pace: true, weekly: false)), "🟢")
    }
    func testPaceAboveEven() {
        XCTAssertEqual(make(snap(five: 80), MenuBarItems(statusDot: false, weekly: false)), "80% ▲25%")
    }
    func testMissingWeeklyModelAndWeekly() {
        XCTAssertEqual(make(snap(model: nil), all), "🟢 42% ▼13% · 71% · $8.69 · ⏱ 2h 14m")
        XCTAssertEqual(make(snap(week: nil, model: nil), all), "🟢 42% ▼13% · $8.69 · ⏱ 2h 14m")
    }
    func testNilCostSkipped() {
        XCTAssertEqual(make(snap(), MenuBarItems(pace: false, weekly: false, todayCost: true), cost: nil), "🟢 42%")
    }
    func testNoResetDate() {
        var l = snap(); l.fiveHour = LimitWindow(utilization: 42, resetsAt: nil)
        XCTAssertEqual(make(l, MenuBarItems(weekly: false, resetCountdown: true)), "🟢 42%")
    }
    func testDotThresholds() {
        let i = MenuBarItems(session: false, pace: false, weekly: false)
        XCTAssertEqual(make(snap(five: 59.9), i), "🟢")
        XCTAssertEqual(make(snap(five: 60), i), "🟠")
        XCTAssertEqual(make(snap(five: 84.9), i), "🟠")
        XCTAssertEqual(make(snap(five: 85), i), "🔴")
        XCTAssertEqual(make(snap(five: 10), i, left: true), "🟢") // colour follows used, not remaining
        XCTAssertEqual(make(snap(five: 90), i, left: true), "🔴")
    }
    func testDecodingDefaults() throws {
        let i = try JSONDecoder().decode(MenuBarItems.self, from: Data("{}".utf8))
        XCTAssertEqual(i, MenuBarItems())
        XCTAssertTrue(i.statusDot && i.session && i.pace && i.weekly)
        XCTAssertFalse(i.weeklyModel || i.todayCost || i.resetCountdown)
        let j = try JSONDecoder().decode(MenuBarItems.self, from: Data(#"{"todayCost":true,"weekly":false}"#.utf8))
        XCTAssertTrue(j.todayCost); XCTAssertFalse(j.weekly); XCTAssertTrue(j.session)
    }
    func testTooltipAll() {
        let t = MenuBarText.tooltip(limits: snap(), todayCost: 8.69, items: all, showRemaining: true, now: now).split(separator: "\n").map(String.init)
        XCTAssertEqual(t, ["🟢 — session colour (orange from 60% used, red from 85%)",
                           "58% — 5-hour session left",
                           "▼13% — below an even pace (slower than average use)",
                           "29% — weekly limit left",
                           "Fable: 22% left",
                           "Today: $8.69 (API-equivalent)",
                           "2h 14m — until the 5-hour session resets"])
    }
    func testTooltipOnlyShown() {
        let t = MenuBarText.tooltip(limits: snap(), todayCost: 8.69, items: MenuBarItems(statusDot: false, pace: false, weekly: false), showRemaining: false, now: now)
        XCTAssertEqual(t, "42% — 5-hour session used")
        let e = MenuBarText.tooltip(limits: snap(model: nil), todayCost: nil, items: MenuBarItems(session: false, pace: false, weekly: false, weeklyModel: true, todayCost: true), showRemaining: false, now: now)
        XCTAssertEqual(e, "🟢 — session colour (orange from 60% used, red from 85%)")
    }
    func testTooltipEstimated() {
        var l = snap(); l.isEstimated = true
        XCTAssertTrue(MenuBarText.tooltip(limits: l, todayCost: nil, items: MenuBarItems(statusDot: false), showRemaining: false, now: now).contains("(estimated)"))
    }
}
