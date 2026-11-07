import XCTest
@testable import UsageCore

final class LocalEstimatorTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 10_000_000)
    func rec(_ ago: TimeInterval, out: Int) -> UsageRecord {
        UsageRecord(id: "\(ago)", timestamp: now.addingTimeInterval(-ago), model: "m", tokens: TokenCounts(output: out, cacheRead: 999_999))
    }
    func testEstimate() {
        let limits = PlanLimits(fiveHourTokens: 1000, weeklyTokens: 10_000)
        let s = LocalEstimator.estimate(records: [rec(3600, out: 200), rec(600, out: 300), rec(2*86400, out: 1000)], limits: limits, now: now)
        XCTAssertTrue(s.isEstimated)
        XCTAssertEqual(s.fiveHour!.utilization, 50, accuracy: 1e-9)          // cacheRead excluded
        XCTAssertEqual(s.fiveHour!.resetsAt, now.addingTimeInterval(-3600 + 5*3600))
        XCTAssertEqual(s.sevenDay!.utilization, 15, accuracy: 1e-9)
        XCTAssertNil(s.sevenDay!.resetsAt)
    }
    func testIdle() {
        let s = LocalEstimator.estimate(records: [], limits: PlanLimits(), now: now)
        XCTAssertEqual(s.fiveHour!.utilization, 0)
        XCTAssertNil(s.fiveHour!.resetsAt)
    }
}
