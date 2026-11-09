import XCTest
@testable import UsageCore

final class WidgetHealthTests: XCTestCase {
    func testParseEtime() {
        XCTAssertEqual(WidgetHealth.parseEtime("05:12"), 312)
        XCTAssertEqual(WidgetHealth.parseEtime("1:02:03"), 3723)
        XCTAssertEqual(WidgetHealth.parseEtime("2-03:04:05"), 183845)
        XCTAssertNil(WidgetHealth.parseEtime(""))
        XCTAssertNil(WidgetHealth.parseEtime("abc"))
        XCTAssertNil(WidgetHealth.parseEtime("12"))
        XCTAssertNil(WidgetHealth.parseEtime("x-01:02"))
    }

    func testStaleBoundary() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let mtime = now.addingTimeInterval(-1000)
        // Started 1006s ago = 6s before mtime: stale. 1004s ago: within tolerance.
        XCTAssertTrue(WidgetHealth.isStale(elapsed: 1006, binaryModified: mtime, now: now))
        XCTAssertFalse(WidgetHealth.isStale(elapsed: 1004, binaryModified: mtime, now: now))
        XCTAssertFalse(WidgetHealth.isStale(elapsed: 10, binaryModified: mtime, now: now))
    }

    func testMatchingProcesses() {
        let exe = "/Applications/Claude Usage.app/Contents/PlugIns/UsageWidgetExtension.appex/Contents/MacOS/UsageWidgetExtension"
        let ps = """
          123 05:12 \(exe)
          456 1:02:03 /other/path/UsageWidgetExtension
          garbage
          789 2-03:04:05 \(exe) -arg
        """
        let m = WidgetHealth.matchingProcesses(psOutput: ps, executable: exe)
        XCTAssertEqual(m.map { $0.pid }, [123, 789])
        XCTAssertEqual(m.first?.elapsed, 312)
    }
}

final class KeychainGuardTests: XCTestCase {
    private let creds = TokenCredentials(token: "t", expiresAt: nil)

    func testLockedWithoutInteractionThrowsAndDoesNotRead() {
        var read = false
        XCTAssertThrowsError(try KeychainTokenProvider.credentials(isLocked: { true }, allowInteraction: false) { read = true; return creds }) {
            XCTAssertEqual($0 as? LimitsError, .keychainLocked)
        }
        XCTAssertFalse(read)
    }

    func testLockedWithInteractionReads() throws {
        let c = try KeychainTokenProvider.credentials(isLocked: { true }, allowInteraction: true) { creds }
        XCTAssertEqual(c, creds)
    }

    func testUnlockedReads() throws {
        XCTAssertEqual(try KeychainTokenProvider.credentials(isLocked: { false }, allowInteraction: false) { creds }, creds)
    }

    func testAllowUserInteractionDefaultsFalseAndToggles() {
        XCTAssertFalse(KeychainTokenProvider.allowUserInteraction)
        KeychainTokenProvider.allowUserInteraction = true
        XCTAssertTrue(KeychainTokenProvider.allowUserInteraction)
        KeychainTokenProvider.allowUserInteraction = false
    }
}
