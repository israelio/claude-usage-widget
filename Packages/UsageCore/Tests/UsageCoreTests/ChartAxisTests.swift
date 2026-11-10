import XCTest
@testable import UsageCore

final class ChartAxisTests: XCTestCase {
    func testStride() {
        XCTAssertEqual(ChartAxis.strideDays(forCount: 1), 1)
        XCTAssertEqual(ChartAxis.strideDays(forCount: 7), 1)
        XCTAssertEqual(ChartAxis.strideDays(forCount: 30), 5)
        XCTAssertEqual(ChartAxis.strideDays(forCount: 90), 15)
    }

    func testTicksIncludeFirstAndLast() {
        for n in [1, 2, 7, 30, 90] {
            let t = ChartAxis.tickIndices(count: n)
            XCTAssertEqual(t.first, 0); XCTAssertEqual(t.last, n - 1)
            XCTAssertEqual(t, t.sorted())
        }
        XCTAssertEqual(ChartAxis.tickIndices(count: 7), [0, 1, 2, 3, 4, 5, 6])
        XCTAssertEqual(ChartAxis.tickIndices(count: 30), [0, 5, 10, 15, 20, 25, 29])
        XCTAssertEqual(ChartAxis.tickIndices(count: 0), [])
    }

    func testRangeLabel() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let loc = Locale(identifier: "en_GB")
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!
        let day = cal.date(from: DateComponents(year: 2026, month: 11, day: 7))!
        XCTAssertEqual(ProjectRangeLabel.make(range: .day(day), projects: 6, now: now, calendar: cal, locale: loc),
                       "Saturday, 7 November 2026 · 6 projects")
        XCTAssertEqual(ProjectRangeLabel.make(range: .lastDays(30), projects: 1, now: now, calendar: cal, locale: loc),
                       "Last 30 days (11 Oct – 9 Nov) · 1 project")
    }
}
