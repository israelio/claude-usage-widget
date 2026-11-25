import XCTest
@testable import UsageCore

/// A relaunch more than `LastFetch.maxAge` after the last fetch, with the API unreachable, must not replace a weekly
/// window that is still in force with the local token estimate (which can be far off the real figure).
final class StaleLimitsTests: XCTestCase {
    let fetched = Date(timeIntervalSince1970: 1_800_000_000)
    var later: Date { fetched.addingTimeInterval(7 * 3600) }   // past maxAge, before the weekly reset

    private func real() -> LimitsSnapshot {
        LimitsSnapshot(fetchedAt: fetched,
                       fiveHour: LimitWindow(utilization: 17, resetsAt: fetched.addingTimeInterval(3 * 3600)),
                       sevenDay: LimitWindow(utilization: 38, resetsAt: fetched.addingTimeInterval(4 * 86400)),
                       extra: ["fable": LimitWindow(utilization: 5, resetsAt: fetched.addingTimeInterval(3600)),
                               "opus": LimitWindow(utilization: 9, resetsAt: fetched.addingTimeInterval(4 * 86400))])
    }

    private func estimate(at now: Date) -> LimitsSnapshot {
        LimitsSnapshot(fetchedAt: now,
                       fiveHour: LimitWindow(utilization: 4, resetsAt: now.addingTimeInterval(3600)),
                       sevenDay: LimitWindow(utilization: 79, resetsAt: nil), isEstimated: true)
    }

    func testLoadKeepsSnapshotPastMaxAgeWhileAWindowIsInForce() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lf-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        LastFetch(lastFetchSuccess: fetched, limits: real()).save(to: url)
        XCTAssertEqual(LastFetch.load(from: url, now: later)?.limits.sevenDay?.utilization, 38)
        // Once every window has reset, the old numbers say nothing about now.
        XCTAssertNil(LastFetch.load(from: url, now: fetched.addingTimeInterval(5 * 86400)))
    }

    func testExpiredWindowsAreReplacedOrDroppedAndLiveOnesKept() {
        let s = real().replacingExpired(with: estimate(at: later), now: later)
        XCTAssertFalse(s.isEstimated)
        XCTAssertEqual(s.sevenDay?.utilization, 38)          // still in force: real value kept
        XCTAssertEqual(s.fiveHour?.utilization, 4)           // reset passed: old 17% is meaningless, use estimate
        XCTAssertNil(s.extra["fable"])                       // reset passed, no estimate for it
        XCTAssertEqual(s.extra["opus"]?.utilization, 9)
    }

    func testNothingExpiredIsUnchanged() {
        let now = fetched.addingTimeInterval(60)
        XCTAssertEqual(real().replacingExpired(with: estimate(at: now), now: now), real())
    }

    func testEstimateIsLeftAlone() {
        let e = estimate(at: later)
        XCTAssertEqual(e.replacingExpired(with: estimate(at: later.addingTimeInterval(9 * 3600)), now: later.addingTimeInterval(9 * 3600)), e)
    }
}
