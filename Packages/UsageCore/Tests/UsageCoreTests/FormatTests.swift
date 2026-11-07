import XCTest
@testable import UsageCore

final class FormatTests: XCTestCase {
    func testTokens() {
        XCTAssertEqual(Format.tokens(999), "999")
        XCTAssertEqual(Format.tokens(184_300), "184.3k")
        XCTAssertEqual(Format.tokens(2_100_000), "2.1M")
        XCTAssertEqual(Format.tokens(1_800_000_000), "1.8B")
    }
    func testCost() {
        XCTAssertEqual(Format.cost(118.4), "$118.40")
        XCTAssertEqual(Format.cost(2012), "$2.0k")
    }
    func testResetsIn() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(Format.resetsIn(now.addingTimeInterval(2*3600+48*60), now: now), "2h 48m")
        XCTAssertEqual(Format.resetsIn(now.addingTimeInterval(3*86400+8*3600+12*60), now: now), "3 days 8h 12m")
        XCTAssertEqual(Format.resetsIn(now.addingTimeInterval(-5), now: now), "0m")
    }
    func testISODate() {
        XCTAssertNotNil(ISODate.parse("2026-11-05T23:24:42.316Z"))
        XCTAssertNotNil(ISODate.parse("2026-11-05T23:24:42Z"))
        XCTAssertNil(ISODate.parse("nope"))
    }
    func testTokenCountsMath() {
        let a = TokenCounts(input: 1, output: 2, cacheWrite: 3, cacheRead: 4)
        XCTAssertEqual((a + a).total, 20)
        XCTAssertEqual(a.cache, 7)
    }
}
