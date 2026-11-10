import XCTest
@testable import UsageCore

final class SessionTests: XCTestCase {
    let fm = FileManager.default
    var tmp: URL!
    let m = "claude-sonnet-5-5"
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    override func setUpWithError() throws {
        tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDown() { try? fm.removeItem(at: tmp) }

    func rec(_ id: String, _ ts: String, project: String? = "/p/a", out: Int = 10) -> UsageRecord {
        UsageRecord(id: id, timestamp: ISODate.parse(ts)!, model: m, tokens: TokenCounts(output: out), project: project)
    }
    /// hourly fixture: hours given as offsets from a base epoch hour.
    let base = 500_000
    func hourly(_ offsets: [Int], project: String = "/p/a", out: Int = 10) -> [Int: [String: [String: TokenCounts]]] {
        Dictionary(uniqueKeysWithValues: offsets.map { ($0 + base, [project: [m: TokenCounts(output: out)]]) })
    }

    // MARK: history

    func testHourlyAccumulationPruneAndCoding() {
        var h = HistoryData()
        h.add([rec("1", "2026-11-05T10:05:00Z"), rec("2", "2026-11-05T10:55:00Z", project: nil), rec("3", "2026-11-05T11:00:00Z")], calendar: utc)
        let e = HistoryData.epochHour(ISODate.parse("2026-11-05T10:00:00Z")!)
        XCTAssertEqual(h.hourly[e]?["/p/a"]?[m]?.output, 10)
        XCTAssertEqual(h.hourly[e]?["Unknown"]?[m]?.output, 10)
        XCTAssertEqual(h.hourly[e + 1]?["/p/a"]?[m]?.output, 10)
        XCTAssertEqual(h.hourly.count, 2)

        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        h.hourlySchemaVersion = 1
        let back = try! dec.decode(HistoryData.self, from: enc.encode(h))
        XCTAssertEqual(back.hourly, h.hourly)
        XCTAssertEqual(back.hourlySchemaVersion, 1)
        XCTAssertEqual(try! dec.decode(HistoryData.self, from: Data(#"{"days":{}}"#.utf8)).hourlySchemaVersion, 0)

        h.prune(now: ISODate.parse("2026-11-06T00:00:00Z")!, calendar: utc)
        XCTAssertEqual(h.hourly.count, 2)
        XCTAssertTrue(h.prune(now: ISODate.parse("2027-03-01T00:00:00Z")!, calendar: utc))
        XCTAssertTrue(h.hourly.isEmpty)
    }

    // MARK: backfill

    func line(_ id: String, ts: String, out: Int = 10) -> String {
        #"{"type":"assistant","cwd":"/gone/z","requestId":"r","timestamp":"\#(ts)","message":{"id":"\#(id)","model":"claude-sonnet-5-5","usage":{"output_tokens":\#(out)}}}"#
    }

    func testHourlyBackfillThenIncrementalAndNoRepeat() async throws {
        let logs = tmp.appendingPathComponent("logs/p"); try fm.createDirectory(at: logs, withIntermediateDirectories: true)
        let store = tmp.appendingPathComponent("store/history.json")
        let now = Date(); let at = now.addingTimeInterval(-60)
        let ts = ISO8601DateFormatter().string(from: at)
        let f = logs.appendingPathComponent("a.jsonl")
        try (line("m1", ts: ts) + "\n" + line("m2", ts: ts) + "\n").write(to: f, atomically: true, encoding: .utf8)

        // History from before hourly tracking, but with the project backfill already done.
        var seeded = HistoryData()
        let scanner = LogScanner(root: tmp.appendingPathComponent("logs"), state: ScanState())
        var recs = scanner.scan(now: now)
        for i in recs.indices { recs[i].project = "/gone/z" }
        seeded.add(recs); seeded.scan = scanner.state
        seeded.hourly = [:]; seeded.hourlySchemaVersion = 0; seeded.projectSchemaVersion = 1
        let projectDaysBefore = seeded.projectDays, daysBefore = seeded.days
        try fm.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try enc.encode(seeded).write(to: store)

        let ing = UsageIngestor(logsRoot: tmp.appendingPathComponent("logs"), storeURL: store, resolver: DefaultProjectResolver(home: "/h"))
        var h = await ing.refreshLogs(now: now)
        let hour = HistoryData.epochHour(at), key = DayKey.string(at)
        XCTAssertEqual(h.hourlySchemaVersion, 1)
        XCTAssertEqual(h.hourly[hour]?["/gone/z"]?[m]?.output, 20)
        XCTAssertEqual(h.days, daysBefore)
        XCTAssertEqual(h.projectDays, projectDaysBefore)

        let w = try FileHandle(forWritingTo: f); try w.seekToEnd()
        w.write(Data((line("m3", ts: ts, out: 5) + "\n").utf8)); try w.close()
        h = await ing.refreshLogs(now: now)
        XCTAssertEqual(h.hourly[hour]?["/gone/z"]?[m]?.output, 25)
        XCTAssertEqual(h.days[key]?[m]?.output, 25)
        XCTAssertEqual(h.projectDays[key]?["/gone/z"]?[m]?.output, 25)

        let ing2 = UsageIngestor(logsRoot: tmp.appendingPathComponent("logs"), storeURL: store, resolver: DefaultProjectResolver(home: "/h"))
        h = await ing2.refreshLogs(now: now)
        XCTAssertEqual(h.hourly[hour]?["/gone/z"]?[m]?.output, 25)
        XCTAssertEqual(h.days[key]?[m]?.output, 25)
    }

    // MARK: sessions

    func testEmpty() { XCTAssertTrue(SessionBuilder.sessions(hourly: [:], now: Date()).isEmpty) }

    func testSingleBurst() {
        let s = SessionBuilder.sessions(hourly: hourly([0, 1, 3]), now: Date())
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].id, base)
        XCTAssertEqual(s[0].end.timeIntervalSince(s[0].start), 5 * 3600)
        XCTAssertEqual(s[0].activeHourCount, 3)
        XCTAssertEqual(s[0].tokens.output, 30)
        XCTAssertEqual(s[0].projectCount, 1)
    }

    func testTwoBurstsSixHoursApart() {
        let s = SessionBuilder.sessions(hourly: hourly([0, 1, 7, 8]), now: Date())
        XCTAssertEqual(s.map(\.id), [base, base + 7])
        XCTAssertEqual(s.map(\.activeHourCount), [2, 2])
    }

    func testWindowEdgeStartsNewSession() {
        // 0..4 are inside [0,5); the activity at hour 5 starts a new one, whose window runs to 10 (hour 9 included).
        let s = SessionBuilder.sessions(hourly: hourly([0, 4, 5, 9, 10]), now: Date())
        XCTAssertEqual(s.map(\.id), [base, base + 5, base + 10])
        XCTAssertEqual(s[1].hours.keys.sorted(), [base + 5, base + 9])
    }

    func testOrderingIsOldestFirstAndTimezoneIndependent() {
        let s = SessionBuilder.sessions(hourly: hourly([20, 0, 10]), now: Date())
        XCTAssertEqual(s.map(\.id), [base, base + 10, base + 20])
        // Built from records: the same absolute timestamps give the same sessions whatever the calendar's zone.
        var a = HistoryData(), b = HistoryData()
        var tokyo = Calendar(identifier: .gregorian); tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let r = [rec("1", "2026-11-05T10:05:00Z"), rec("2", "2026-11-05T16:00:00Z")]
        a.add(r, calendar: utc); b.add(r, calendar: tokyo)
        XCTAssertEqual(a.hourly, b.hourly)
        XCTAssertEqual(SessionBuilder.sessions(hourly: a.hourly).map(\.id), SessionBuilder.sessions(hourly: b.hourly).map(\.id))
    }

    func testActiveDetectionAndCost() {
        let s = SessionBuilder.sessions(hourly: hourly([0], out: 1_000_000), now: Date())[0]
        let t0 = s.start
        XCTAssertTrue(s.isActive(now: t0))
        XCTAssertTrue(s.isActive(now: t0.addingTimeInterval(5 * 3600 - 1)))
        XCTAssertFalse(s.isActive(now: t0.addingTimeInterval(5 * 3600)))
        XCTAssertFalse(s.isActive(now: t0.addingTimeInterval(-1)))
        XCTAssertEqual(s.cost(prices: .defaults), 15, accuracy: 1e-9)
    }

    func testRecentFilterAndCSV() {
        let now = ISODate.parse("2026-11-10T12:00:00Z")!
        let e = HistoryData.epochHour(now)
        let all = SessionBuilder.sessions(hourly: [e - 24 * 10: ["/p/a": [m: TokenCounts(output: 1)]], e - 2: ["/p/a": [m: TokenCounts(output: 1_000_000)], "/p/b": [m: TokenCounts(output: 1)]]])
        XCTAssertEqual(all.count, 2)
        let r = SessionBuilder.recent(all, days: 7, now: now, calendar: utc)
        XCTAssertEqual(r.count, 1)
        let csv = SessionCSV.make(r, prices: .defaults).split(separator: "\n")
        XCTAssertEqual(csv[0], "start,end,input,output,cache_write,cache_read,total_tokens,cost_usd,projects")
        XCTAssertTrue(csv[1].hasSuffix(",0,1000001,0,0,1000001,15.0000,2"))
    }

    // MARK: breakdowns over sessions

    func testByProjectAndModelOverSessions() {
        let o = "claude-opus-5-5"
        let hrs: [Int: [String: [String: TokenCounts]]] = [
            base: ["/p/a": [m: TokenCounts(output: 1_000_000)]],
            base + 2: ["/p/a": [o: TokenCounts(output: 100_000)], "/p/b": [m: TokenCounts(output: 1_000_000)]],
            base + 10: ["/p/a": [m: TokenCounts(output: 1_000_000)]],
        ]
        let sessions = SessionBuilder.sessions(hourly: hrs)
        XCTAssertEqual(sessions.count, 2)
        var h = HistoryData(); h.days["2026-11-10"] = [m: TokenCounts(output: 99_999_999)]   // must not leak in as "Earlier"
        let now = Date()

        let one = Aggregator.byProject(h, prices: .defaults, range: .session(sessions[0]), now: now, calendar: utc, home: "/h")
        XCTAssertNil(one.earlier)
        XCTAssertEqual(one.rows.map(\.name), ["a", "b"])
        XCTAssertEqual(one.rows[0].daily.count, 5)
        XCTAssertEqual(one.rows[0].daily[0].tokens.output, 1_000_000)
        XCTAssertEqual(one.rows[0].daily[2].tokens.output, 100_000)
        XCTAssertEqual(one.rows[0].daily[1].tokens.total, 0)
        XCTAssertEqual(one.rows[0].daily[3].day.timeIntervalSince(one.rows[0].daily[2].day), 3600)
        XCTAssertEqual(one.total.cost, 15 + 7.5 + 15, accuracy: 1e-9)

        let both = Aggregator.byProject(h, prices: .defaults, range: .sessions(sessions), now: now, calendar: utc, home: "/h")
        XCTAssertNil(both.earlier)
        XCTAssertEqual(both.rows[0].name, "a")
        XCTAssertEqual(both.rows[0].daily.count, 2)
        XCTAssertEqual(both.rows[0].daily.map(\.day), sessions.map(\.start))
        XCTAssertEqual(both.rows[0].tokens.output, 2_100_000)

        let byModel = Aggregator.byModel(h, prices: .defaults, range: .sessions(sessions), now: now, calendar: utc, home: "/h")
        XCTAssertEqual(byModel.rows.count, 2)
        XCTAssertTrue(byModel.rows.allSatisfy { r in r.projects.allSatisfy { !$0.isEarlier } })
        XCTAssertEqual(byModel.total.cost, both.total.cost, accuracy: 1e-9)
        let single = Aggregator.byModel(h, prices: .defaults, range: .session(sessions[0]), now: now, calendar: utc)
        XCTAssertEqual(single.rows.first { $0.model == m }?.daily.count, 5)

        XCTAssertTrue(Aggregator.byProject(h, prices: .defaults, range: .sessions([]), now: now, calendar: utc).rows.isEmpty)
    }

    func testSessionHeading() {
        let now = ISODate.parse("2026-11-09T15:00:00Z")!
        let s = SessionBuilder.sessions(hourly: [HistoryData.epochHour(ISODate.parse("2026-11-09T14:00:00Z")!): ["/p/a": [m: TokenCounts(output: 1)]]])[0]
        let en = Locale(identifier: "en_GB")
        let one = ProjectRangeLabel.make(range: .session(s), count: 4, now: now, calendar: utc, locale: en)
        XCTAssertTrue(one.hasSuffix("14:00–19:00 · 4 projects · active"), one)
        XCTAssertFalse(ProjectRangeLabel.make(range: .session(s), count: 4, now: now.addingTimeInterval(86400), calendar: utc, locale: en).contains("active"))
        XCTAssertEqual(ProjectRangeLabel.make(range: .sessions([s, s]), count: 63, sessionsTitle: "Last 7 days", now: now, calendar: utc, locale: en),
                       "Last 7 days · 2 sessions · 63 projects")
    }
}
