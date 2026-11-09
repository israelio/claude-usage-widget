import XCTest
@testable import UsageCore

final class DisplayPercentTests: XCTestCase {
    func testDisplayPercent() {
        XCTAssertEqual(Format.displayPercent(used: 2.4, showRemaining: false), 2)
        XCTAssertEqual(Format.displayPercent(used: 2.4, showRemaining: true), 98)
        XCTAssertEqual(Format.displayPercent(used: 120, showRemaining: true), 0)
        XCTAssertEqual(Format.displayPercent(used: -5, showRemaining: true), 100)
        XCTAssertEqual(Format.displayPercent(used: 120, showRemaining: false), 100)
    }

    func testSnapshotDecodesWithoutShowRemaining() throws {
        var s = SharedSnapshot(limits: nil, today: .zero, last7: .zero, daily: [], updatedAt: Date(timeIntervalSince1970: 0), showRemaining: true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("snap-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try s.save(to: url)
        XCTAssertEqual(SharedSnapshot.load(from: url)?.showRemaining, true)
        s.showRemaining = nil
        try s.save(to: url)
        XCTAssertNil(SharedSnapshot.load(from: url)?.showRemaining)
    }
}
