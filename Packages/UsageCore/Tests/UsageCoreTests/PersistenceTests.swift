import XCTest
@testable import UsageCore

final class PersistenceTests: XCTestCase {
    func tmp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    func testSharedSnapshotRoundTrip() throws {
        let url = tmp().appendingPathComponent("snap.json")
        let snap = SharedSnapshot(limits: LimitsSnapshot(fetchedAt: Date(timeIntervalSince1970: 5), fiveHour: LimitWindow(utilization: 42, resetsAt: nil)),
                                  today: Totals(tokens: TokenCounts(output: 3), cost: 1.5), last7: .zero,
                                  daily: [], updatedAt: Date(timeIntervalSince1970: 9))
        try snap.save(to: url)
        XCTAssertEqual(SharedSnapshot.load(from: url), snap)
        XCTAssertNil(SharedSnapshot.load(from: tmp()))
    }

    func testIngestorPersistsAndIsIncremental() async throws {
        let root = tmp().appendingPathComponent("logs"); try FileManager.default.createDirectory(at: root.appendingPathComponent("p"), withIntermediateDirectories: true)
        let log = root.appendingPathComponent("p/a.jsonl")
        let line = #"{"type":"assistant","requestId":"r","timestamp":"2026-11-07T10:00:00Z","message":{"id":"m1","model":"claude-sonnet-5-5","usage":{"output_tokens":7}}}"# + "\n"
        try line.write(to: log, atomically: true, encoding: .utf8)
        let store = tmp().appendingPathComponent("history.json")
        let now = ISODate.parse("2026-11-07T12:00:00Z")!

        let ing = UsageIngestor(logsRoot: root, storeURL: store)
        let h1 = await ing.refreshLogs(now: now)
        XCTAssertEqual(h1.days.values.flatMap { $0.values }.map(\.output).reduce(0, +), 7)

        let ing2 = UsageIngestor(logsRoot: root, storeURL: store)   // reload from disk
        let h2 = await ing2.refreshLogs(now: now)
        XCTAssertEqual(h2.days.values.flatMap { $0.values }.map(\.output).reduce(0, +), 7)   // not double counted
    }
}
