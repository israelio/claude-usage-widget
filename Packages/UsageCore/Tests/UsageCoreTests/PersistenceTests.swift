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

final class RobustnessTests: XCTestCase {
    func tmp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    let now = ISODate.parse("2026-11-07T12:00:00Z")!

    func testCorruptHistoryIsBackedUp() async throws {
        let dir = tmp(); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = dir.appendingPathComponent("history.json")
        try "{not json".write(to: store, atomically: true, encoding: .utf8)
        let ing = UsageIngestor(logsRoot: dir.appendingPathComponent("none"), storeURL: store)
        let h = await ing.refreshLogs(now: now)
        XCTAssertTrue(h.days.isEmpty)
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("history.json.bak")), "{not json")
    }

    func testDecodeMissingFieldsKeepsData() throws {
        let json = #"{"days":{"2026-11-05":{"m":{"input":1,"output":2,"cacheWrite":0,"cacheRead":0}}}}"#
        let h = try JSONDecoder().decode(HistoryData.self, from: Data(json.utf8))
        XCTAssertEqual(h.days["2026-11-05"]?["m"]?.output, 2)
        XCTAssertTrue(h.recent.isEmpty)
        XCTAssertEqual(h.scan, ScanState())
    }

    func testLegacySeenSetMigrates() throws {
        let json = #"{"offsets":{"/a":5},"seen":["x","y"]}"#
        let s = try JSONDecoder().decode(ScanState.self, from: Data(json.utf8))
        XCTAssertEqual(Set(s.seen.keys), ["x", "y"])
        XCTAssertEqual(s.offsets["/a"], 5)
    }

    func testPrunesOldSeen() {
        var h = HistoryData()
        h.scan.seen = ["old": "2026-01-01", "new": "2026-11-06"]
        XCTAssertTrue(h.prune(now: now))
        XCTAssertEqual(Set(h.scan.seen.keys), ["new"])
        XCTAssertFalse(h.prune(now: now))
    }

    func testOffsetsForDeletedFilesRemoved() throws {
        let root = tmp(); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let f = root.appendingPathComponent("a.jsonl")
        try "{}\n".write(to: f, atomically: true, encoding: .utf8)
        let sc = LogScanner(root: root, state: ScanState())
        _ = sc.scan(now: now)
        XCTAssertEqual(sc.state.offsets.count, 1)
        try FileManager.default.removeItem(at: f)
        _ = sc.scan(now: now)
        XCTAssertTrue(sc.state.offsets.isEmpty)
    }

    func testNoRewriteWhenNothingChanged() async throws {
        let dir = tmp(); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = dir.appendingPathComponent("history.json")
        let ing = UsageIngestor(logsRoot: dir.appendingPathComponent("none"), storeURL: store)
        _ = await ing.refreshLogs(now: now)
        // The first refresh persists the one-off project backfill marker; later idle refreshes must not write.
        try? FileManager.default.removeItem(at: store)
        _ = await ing.refreshLogs(now: now)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.path))
        await ing.record(LimitsSnapshot(fetchedAt: now, fiveHour: LimitWindow(utilization: 1, resetsAt: nil)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.path))
    }
}
