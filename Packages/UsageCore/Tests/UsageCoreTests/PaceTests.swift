import XCTest
@testable import UsageCore

final class PaceTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000)
    func window(_ u: Double, remaining: TimeInterval) -> LimitWindow { LimitWindow(utilization: u, resetsAt: now.addingTimeInterval(remaining)) }

    func testOnTrack() {
        // 3h of 5h elapsed, 42% used -> expected 60, delta -18, projected 70
        let p = Pace.compute(window: window(42, remaining: 2*3600), length: Pace.fiveHours, now: now)!
        XCTAssertEqual(p.expected, 60, accuracy: 1e-6)
        XCTAssertEqual(p.delta, -18, accuracy: 1e-6)
        XCTAssertEqual(p.projected, 70, accuracy: 1e-6)
        XCTAssertEqual(p.status, .onTrack)
    }
    func testAhead() {
        XCTAssertEqual(Pace.compute(window: window(55, remaining: 2.5*3600), length: Pace.fiveHours, now: now)!.status, .ahead)
    }
    func testOver() {
        XCTAssertEqual(Pace.compute(window: window(90, remaining: 2.5*3600), length: Pace.fiveHours, now: now)!.status, .over)
        XCTAssertEqual(Pace.compute(window: window(100, remaining: 1*3600), length: Pace.fiveHours, now: now)!.status, .over)
    }
    func testNoResetOrEarlyWindow() {
        XCTAssertNil(Pace.compute(window: LimitWindow(utilization: 10, resetsAt: nil), length: Pace.fiveHours, now: now))
        let early = Pace.compute(window: window(3, remaining: Pace.fiveHours - 60), length: Pace.fiveHours, now: now)!
        XCTAssertEqual(early.projected, 3, accuracy: 1e-6)   // <2% elapsed: no extrapolation
    }
}
