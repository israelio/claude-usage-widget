import XCTest
@testable import UsageCore
final class SmokeTests: XCTestCase {
    func testVersion() { XCTAssertEqual(UsageCoreVersion.value, 1) }
}
