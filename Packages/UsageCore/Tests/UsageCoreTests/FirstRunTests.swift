import XCTest
@testable import UsageCore

final class FirstRunTests: XCTestCase {
    func testFreshOnlyWhenNothingStored() {
        XCTAssertTrue(FirstRun.isFreshInstall(hasPrefs: false, shownFlag: false))
        XCTAssertFalse(FirstRun.isFreshInstall(hasPrefs: true, shownFlag: false))
        XCTAssertFalse(FirstRun.isFreshInstall(hasPrefs: false, shownFlag: true))
        XCTAssertFalse(FirstRun.isFreshInstall(hasPrefs: true, shownFlag: true))
    }
}
