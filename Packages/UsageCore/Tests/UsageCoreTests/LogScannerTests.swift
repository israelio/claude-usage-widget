import XCTest
@testable import UsageCore

final class LogScannerTests: XCTestCase {
    func line(id: String, req: String = "r1", model: String = "claude-sonnet-5-5",
              ts: String = "2026-11-05T23:24:42.316Z", out: Int = 10) -> String {
        """
        {"type":"assistant","requestId":"\(req)","timestamp":"\(ts)","message":{"id":"\(id)","model":"\(model)","usage":{"input_tokens":2,"cache_creation_input_tokens":100,"cache_read_input_tokens":50,"output_tokens":\(out)}}}
        """
    }

    func testParseLine() throws {
        let r = try XCTUnwrap(LogParser.parse(Data(line(id: "m1").utf8)))
        XCTAssertEqual(r.id, "m1:r1")
        XCTAssertEqual(r.model, "claude-sonnet-5-5")
        XCTAssertEqual(r.tokens, TokenCounts(input: 2, output: 10, cacheWrite: 100, cacheRead: 50))
    }
    func testParseSkipsNonAssistantAndSynthetic() {
        XCTAssertNil(LogParser.parse(Data(#"{"type":"user","message":{"role":"user"}}"#.utf8)))
        XCTAssertNil(LogParser.parse(Data(line(id: "m", model: "<synthetic>").utf8)))
        XCTAssertNil(LogParser.parse(Data("garbage".utf8)))
    }

    func makeDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: d.appendingPathComponent("proj"), withIntermediateDirectories: true)
        return d
    }

    func testIncrementalScanDedupAndPartialLine() throws {
        let root = try makeDir()
        let f = root.appendingPathComponent("proj/a.jsonl")
        try (line(id: "m1") + "\n" + line(id: "m1") + "\n").write(to: f, atomically: true, encoding: .utf8)
        let s = LogScanner(root: root, state: ScanState(), maxAge: .infinity)
        XCTAssertEqual(s.scan().count, 1)           // duplicate dropped
        XCTAssertEqual(s.scan().count, 0)           // nothing new

        // append one full line and one partial (no trailing newline)
        let h = try FileHandle(forWritingTo: f); try h.seekToEnd()
        h.write(Data((line(id: "m2") + "\n" + String(line(id: "m3").prefix(20))).utf8)); try h.close()
        let second = s.scan()
        XCTAssertEqual(second.map(\.id), ["m2:r1"])  // partial line not consumed

        // complete the partial line
        let h2 = try FileHandle(forWritingTo: f); try h2.seekToEnd()
        h2.write(Data((String(line(id: "m3").dropFirst(20)) + "\n").utf8)); try h2.close()
        XCTAssertEqual(s.scan().map(\.id), ["m3:r1"])
    }

    func testDedupAcrossFilesAndStateRoundTrip() throws {
        let root = try makeDir()
        try (line(id: "m1") + "\n").write(to: root.appendingPathComponent("proj/a.jsonl"), atomically: true, encoding: .utf8)
        let s1 = LogScanner(root: root, state: ScanState(), maxAge: .infinity)
        XCTAssertEqual(s1.scan().count, 1)
        try (line(id: "m1") + "\n").write(to: root.appendingPathComponent("proj/b.jsonl"), atomically: true, encoding: .utf8)
        let s2 = LogScanner(root: root, state: s1.state, maxAge: .infinity)
        XCTAssertEqual(s2.scan().count, 0)
    }
}
