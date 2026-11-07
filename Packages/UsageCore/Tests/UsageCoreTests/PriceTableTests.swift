import XCTest
@testable import UsageCore

final class PriceTableTests: XCTestCase {
    func testCostSonnet() {
        var t = PriceTable.defaults
        t.byFamily["sonnet"] = ModelPrice(input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.30)
        let c = t.cost(model: "claude-sonnet-5-5",
                       tokens: TokenCounts(input: 1_000_000, output: 1_000_000, cacheWrite: 1_000_000, cacheRead: 1_000_000))
        XCTAssertEqual(c, 3 + 15 + 3.75 + 0.30, accuracy: 1e-9)
    }
    func testUnknownModelIsFree() {
        XCTAssertEqual(PriceTable.defaults.cost(model: "mystery-1", tokens: TokenCounts(input: 5)), 0)
    }
    func testFamilyMatchCaseInsensitive() {
        XCTAssertNotNil(PriceTable.defaults.price(for: "claude-OPUS-4-8"))
        XCTAssertNotNil(PriceTable.defaults.price(for: "claude-haiku-4-5-20251001"))
        XCTAssertNotNil(PriceTable.defaults.price(for: "fable-5"))
    }
    func testDisplayName() {
        XCTAssertEqual(PriceTable.displayName("claude-opus-4-8"), "opus-4-8")
    }
}
