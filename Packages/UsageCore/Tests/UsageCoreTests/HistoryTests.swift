import XCTest
@testable import UsageCore

final class HistoryTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    func date(_ s: String) -> Date { ISODate.parse(s)! }
    func rec(_ id: String, _ ts: String, model: String = "claude-sonnet-5-5", out: Int = 1_000_000) -> UsageRecord {
        UsageRecord(id: id, timestamp: date(ts), model: model, tokens: TokenCounts(output: out))
    }

    func testAddRollsUpByDayAndModel() {
        var h = HistoryData()
        h.add([rec("a", "2026-11-05T10:00:00Z"), rec("b", "2026-11-05T11:00:00Z"),
               rec("c", "2026-11-06T01:00:00Z", model: "claude-opus-4-8")], calendar: cal)
        XCTAssertEqual(h.days["2026-11-05"]?["claude-sonnet-5-5"]?.output, 2_000_000)
        XCTAssertEqual(h.days["2026-11-06"]?["claude-opus-4-8"]?.output, 1_000_000)
    }

    func testPruneDropsOldDaysRecordsAndSamples() {
        var h = HistoryData()
        h.add([rec("old", "2026-07-01T10:00:00Z"), rec("new", "2026-11-05T10:00:00Z")], calendar: cal)
        h.add(sample: LimitSample(t: date("2026-10-01T00:00:00Z"), fiveHour: 1, fiveHourReset: nil, sevenDay: 1, sevenDayReset: nil))
        h.prune(now: date("2026-11-07T00:00:00Z"), calendar: cal)
        XCTAssertNil(h.days["2026-07-01"])
        XCTAssertNotNil(h.days["2026-11-05"])
        XCTAssertEqual(h.recent.map(\.id), ["new"])
        XCTAssertTrue(h.samples.isEmpty)
    }

    func testSummaryTotalsAndShare() {
        var h = HistoryData()
        h.add([rec("a", "2026-11-07T10:00:00Z", out: 1_000_000),                 // today sonnet $15
               rec("b", "2026-11-01T10:00:00Z", model: "claude-opus-4-8", out: 1_000_000)], calendar: cal) // opus $75
        var prices = PriceTable.defaults
        prices.byFamily["sonnet"] = ModelPrice(input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.3)
        prices.byFamily["opus"] = ModelPrice(input: 15, output: 75, cacheWrite: 18.75, cacheRead: 1.5)
        let s = Aggregator.summarize(h, prices: prices, now: date("2026-11-07T12:00:00Z"), calendar: cal)
        XCTAssertEqual(s.today.cost, 15, accuracy: 1e-9)
        XCTAssertEqual(s.last7.cost, 90, accuracy: 1e-9)
        XCTAssertEqual(s.month.cost, 90, accuracy: 1e-9)
        XCTAssertEqual(s.modelShare.first?.model, "claude-opus-4-8")
        XCTAssertEqual(s.modelShare.first!.fraction, 75.0/90.0, accuracy: 1e-9)
    }

    func testDailySeriesFillsGaps() {
        var h = HistoryData()
        h.add([rec("a", "2026-11-05T10:00:00Z")], calendar: cal)
        let d = Aggregator.daily(h, prices: .defaults, days: 3, now: date("2026-11-07T12:00:00Z"), calendar: cal)
        XCTAssertEqual(d.count, 3)
        XCTAssertEqual(d.map { $0.tokens.output }, [1_000_000, 0, 0])
    }
}
