import XCTest
@testable import UsageCore

final class FetchPolicyTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func should(ago: TimeInterval?, activity: Bool = false, reset: Bool = false, manual: Bool = false,
                        blocked: TimeInterval? = nil, minGap: TimeInterval = 300, idleGap: TimeInterval = 900) -> Bool {
        FetchPolicy.shouldFetch(now: now, lastFetch: ago.map { now.addingTimeInterval(-$0) }, newLogActivitySinceLastFetch: activity,
                                windowResetPassed: reset, manual: manual, blockedUntil: blocked.map { now.addingTimeInterval($0) },
                                minGap: minGap, idleGap: idleGap)
    }

    func testBlockedWinsEvenForManual() {
        XCTAssertFalse(should(ago: 5000, activity: true, manual: true, blocked: 10))
        XCTAssertFalse(should(ago: nil, blocked: 10))
        XCTAssertTrue(should(ago: nil, blocked: -10))
    }
    func testNoLastFetch() { XCTAssertTrue(should(ago: nil)) }
    func testActivityNeedsMinGap() {
        XCTAssertFalse(should(ago: 299, activity: true))
        XCTAssertTrue(should(ago: 300, activity: true))
    }
    func testIdleNeedsIdleGap() {
        XCTAssertFalse(should(ago: 899))
        XCTAssertTrue(should(ago: 900))
    }
    func testManualAndResetNeed60s() {
        XCTAssertFalse(should(ago: 59, manual: true))
        XCTAssertTrue(should(ago: 60, manual: true))
        XCTAssertFalse(should(ago: 59, reset: true))
        XCTAssertTrue(should(ago: 60, reset: true))
    }
    func testCustomGaps() {
        XCTAssertFalse(should(ago: 500, activity: true, minGap: 600))
        XCTAssertTrue(should(ago: 1800, idleGap: 1800))
    }
    func testMultiplier() {
        XCTAssertEqual(FetchPolicy.gapMultiplier(sinceLastBlock: nil), 1)
        XCTAssertEqual(FetchPolicy.gapMultiplier(sinceLastBlock: 0), 2)
        XCTAssertEqual(FetchPolicy.gapMultiplier(sinceLastBlock: 3599), 2)
        XCTAssertEqual(FetchPolicy.gapMultiplier(sinceLastBlock: 3600), 1)
    }
    func testWindowResetPassed() {
        let reset = now.addingTimeInterval(-100)
        let l = LimitsSnapshot(fetchedAt: now.addingTimeInterval(-500), fiveHour: LimitWindow(utilization: 50, resetsAt: reset))
        XCTAssertTrue(FetchPolicy.windowResetPassed(limits: l, lastFetch: now.addingTimeInterval(-500), now: now))
        XCTAssertFalse(FetchPolicy.windowResetPassed(limits: l, lastFetch: now.addingTimeInterval(-50), now: now))
        XCTAssertFalse(FetchPolicy.windowResetPassed(limits: nil, lastFetch: now, now: now))
    }
    func testLastFetchPersistence() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lf-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let l = LimitsSnapshot(fetchedAt: now, fiveHour: LimitWindow(utilization: 10, resetsAt: now.addingTimeInterval(3600)))
        LastFetch(lastFetchSuccess: now, limits: l).save(to: url)
        XCTAssertEqual(LastFetch.load(from: url, now: now.addingTimeInterval(60))?.limits.fiveHour?.utilization, 10)
        XCTAssertNil(LastFetch.load(from: url, now: now.addingTimeInterval(6 * 3600 + 1)))
        try Data("junk".utf8).write(to: url)
        XCTAssertNil(LastFetch.load(from: url, now: now))
    }
}
