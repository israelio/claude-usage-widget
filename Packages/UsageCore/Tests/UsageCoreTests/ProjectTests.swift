import XCTest
@testable import UsageCore

final class ProjectTests: XCTestCase {
    let fm = FileManager.default
    var tmp: URL!

    override func setUpWithError() throws {
        tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDown() { try? fm.removeItem(at: tmp) }

    @discardableResult
    func mkdir(_ rel: String) throws -> String {
        let u = tmp.appendingPathComponent(rel)
        try fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u.path
    }

    // MARK: resolver

    func testGitDirectoryRootFromSubfolder() throws {
        let repo = try mkdir("repo"); try mkdir("repo/.git"); let sub = try mkdir("repo/Sources/App")
        let r = DefaultProjectResolver(home: "/nonexistent-home")
        XCTAssertEqual(r.resolve(cwd: sub), ResolvedProject(root: repo, name: "repo"))
        XCTAssertEqual(r.resolve(cwd: repo).root, repo)
    }

    func testWorktreeFilePointsToMainRepo() throws {
        let repo = try mkdir("main"); try mkdir("main/.git/worktrees/feat")
        let wt = try mkdir("elsewhere/feat")
        try "gitdir: \(repo)/.git/worktrees/feat\n".write(toFile: wt + "/.git", atomically: true, encoding: .utf8)
        let r = DefaultProjectResolver(home: "/nonexistent-home")
        XCTAssertEqual(r.resolve(cwd: wt).root, repo)
        XCTAssertEqual(r.resolve(cwd: wt).name, "main")
    }

    func testMissingPathHeuristics() {
        let r = DefaultProjectResolver(home: "/nonexistent-home")
        XCTAssertEqual(r.resolve(cwd: "/gone/app/.claude/worktrees/x1").root, "/gone/app")
        XCTAssertEqual(r.resolve(cwd: "/gone/app/.worktrees/x1/sub").root, "/gone/app")
        XCTAssertEqual(r.resolve(cwd: "/gone/app/worktrees/x1").root, "/gone/app")
        XCTAssertEqual(r.resolve(cwd: "/gone/plain/").root, "/gone/plain")
    }

    func testNilAndEmptyAreUnknown() {
        let r = DefaultProjectResolver()
        XCTAssertEqual(r.resolve(cwd: nil), ResolvedProject(root: "Unknown", name: "Unknown"))
        XCTAssertEqual(r.resolve(cwd: "").root, "Unknown")
    }

    func testHomeAndRootNamedHome() {
        XCTAssertEqual(ProjectNaming.baseName("/Users/me", home: "/Users/me"), "Home")
        XCTAssertEqual(ProjectNaming.baseName("/", home: "/Users/me"), "Home")
        XCTAssertEqual(ProjectNaming.baseName("/Users/me/code/x", home: "/Users/me"), "x")
    }

    func testNameCollisionsAreDisambiguated() {
        let n = ProjectNaming.displayNames(for: ["/a/work/app", "/a/play/app", "/a/solo", "Unknown"], home: "/h")
        XCTAssertEqual(n["/a/work/app"], "app (work)")
        XCTAssertEqual(n["/a/play/app"], "app (play)")
        XCTAssertEqual(n["/a/solo"], "solo")
        XCTAssertEqual(n["Unknown"], "Unknown")
        let m = ProjectNaming.displayNames(for: ["/a/x/work/app", "/b/x/work/app"], home: "/h")
        XCTAssertEqual(m["/a/x/work/app"], "app (/a/x/work)")
    }

    // MARK: history

    func rec(_ id: String, _ ts: String, project: String?, model: String = "claude-sonnet-5-5", out: Int = 10) -> UsageRecord {
        UsageRecord(id: id, timestamp: ISODate.parse(ts)!, model: model, tokens: TokenCounts(output: out), project: project)
    }

    func testHistoryAddAndPrune() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        var h = HistoryData()
        h.add([rec("1", "2026-11-05T10:00:00Z", project: "/p/a")], calendar: cal)
        h.add([rec("2", "2026-11-05T11:00:00Z", project: nil)], calendar: cal)     // pre-backfill: not tracked
        XCTAssertEqual(h.projectDays["2026-11-05"]?["/p/a"]?["claude-sonnet-5-5"]?.output, 10)
        XCTAssertNil(h.projectDays["2026-11-05"]?["Unknown"])
        h.projectSchemaVersion = 1
        h.add([rec("3", "2026-11-05T12:00:00Z", project: nil)], calendar: cal)
        XCTAssertEqual(h.projectDays["2026-11-05"]?["Unknown"]?["claude-sonnet-5-5"]?.output, 10)

        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let back = try! dec.decode(HistoryData.self, from: enc.encode(h))
        XCTAssertEqual(back.projectDays, h.projectDays)
        XCTAssertEqual(back.projectSchemaVersion, 1)
        XCTAssertEqual(back.recent.first?.project, "/p/a")
        XCTAssertNil(back.recent.first?.cwd)
        let old = try! dec.decode(HistoryData.self, from: Data(#"{"days":{}}"#.utf8))
        XCTAssertEqual(old.projectSchemaVersion, 0)

        XCTAssertTrue(h.prune(now: ISODate.parse("2027-03-01T00:00:00Z")!, calendar: cal))
        XCTAssertTrue(h.projectDays.isEmpty)
    }

    func testParserReadsCwd() throws {
        let l = #"{"type":"assistant","cwd":"/x/y","timestamp":"2026-11-05T23:24:42.316Z","message":{"id":"m","model":"claude-sonnet-5-5","usage":{"output_tokens":1}}}"#
        XCTAssertEqual(LogParser.parse(Data(l.utf8))?.cwd, "/x/y")
    }

    // MARK: ingestor backfill

    func line(_ id: String, cwd: String, ts: String, out: Int = 10) -> String {
        #"{"type":"assistant","cwd":"\#(cwd)","requestId":"r","timestamp":"\#(ts)","message":{"id":"\#(id)","model":"claude-sonnet-5-5","usage":{"output_tokens":\#(out)}}}"#
    }

    func testBackfillThenIncrementalAndNoRepeat() async throws {
        let logs = try mkdir("logs/p"); let store = tmp.appendingPathComponent("store/history.json")
        let repo = try mkdir("repo"); try mkdir("repo/.git")
        let now = Date()
        let ts = ISO8601DateFormatter().string(from: now.addingTimeInterval(-60))
        let f = URL(fileURLWithPath: logs + "/a.jsonl")
        try (line("m1", cwd: repo, ts: ts) + "\n" + line("m1", cwd: repo, ts: ts) + "\n" + line("m2", cwd: "/gone/z", ts: ts) + "\n")
            .write(to: f, atomically: true, encoding: .utf8)

        // Simulate pre-feature history: logs already counted in days/seen, no project data.
        var seeded = HistoryData()
        let scanner = LogScanner(root: tmp.appendingPathComponent("logs"), state: ScanState())
        let recs = scanner.scan(now: now)
        seeded.add(recs); seeded.scan = scanner.state
        seeded.projectDays = [:]; seeded.projectSchemaVersion = 0
        try fm.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try enc.encode(seeded).write(to: store)

        let ing = UsageIngestor(logsRoot: tmp.appendingPathComponent("logs"), storeURL: store, resolver: DefaultProjectResolver(home: "/h"))
        var h = await ing.refreshLogs(now: now)
        XCTAssertEqual(h.projectSchemaVersion, 1)
        let key = DayKey.string(now.addingTimeInterval(-60))
        XCTAssertEqual(h.projectDays[key]?[repo]?["claude-sonnet-5-5"]?.output, 10)
        XCTAssertEqual(h.projectDays[key]?["/gone/z"]?["claude-sonnet-5-5"]?.output, 10)
        XCTAssertEqual(h.days[key]?["claude-sonnet-5-5"]?.output, 20)     // untouched

        // New line: counted in both.
        let w = try FileHandle(forWritingTo: f); try w.seekToEnd()
        w.write(Data((line("m3", cwd: repo, ts: ts, out: 5) + "\n").utf8)); try w.close()
        h = await ing.refreshLogs(now: now)
        XCTAssertEqual(h.days[key]?["claude-sonnet-5-5"]?.output, 25)
        XCTAssertEqual(h.projectDays[key]?[repo]?["claude-sonnet-5-5"]?.output, 15)

        // A second ingestor on the same store must not backfill again.
        let ing2 = UsageIngestor(logsRoot: tmp.appendingPathComponent("logs"), storeURL: store, resolver: DefaultProjectResolver(home: "/h"))
        h = await ing2.refreshLogs(now: now)
        XCTAssertEqual(h.projectDays[key]?[repo]?["claude-sonnet-5-5"]?.output, 15)
        XCTAssertEqual(h.days[key]?["claude-sonnet-5-5"]?.output, 25)
    }

    func testFreshInstallCountsOnceInBoth() async throws {
        let logs = try mkdir("logs/p"); let store = tmp.appendingPathComponent("s/history.json")
        let now = Date(); let ts = ISO8601DateFormatter().string(from: now.addingTimeInterval(-60))
        try (line("m1", cwd: "/gone/q", ts: ts) + "\n").write(toFile: logs + "/a.jsonl", atomically: true, encoding: .utf8)
        let ing = UsageIngestor(logsRoot: tmp.appendingPathComponent("logs"), storeURL: store)
        let h = await ing.refreshLogs(now: now)
        let key = DayKey.string(now.addingTimeInterval(-60))
        XCTAssertEqual(h.days[key]?["claude-sonnet-5-5"]?.output, 10)
        XCTAssertEqual(h.projectDays[key]?["/gone/q"]?["claude-sonnet-5-5"]?.output, 10)
    }

    // MARK: aggregator + csv

    func testByProject() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = ISODate.parse("2026-11-10T12:00:00Z")!
        var h = HistoryData()
        let m = "claude-sonnet-5-5"
        // day 1: two projects + 1M of unattributed output; day 2: only attributed
        h.days["2026-11-10"] = [m: TokenCounts(output: 3_000_000)]
        h.projectDays["2026-11-10"] = ["/w/app": [m: TokenCounts(output: 1_000_000)], "/v/app": [m: TokenCounts(output: 1_000_000)]]
        h.days["2026-11-09"] = [m: TokenCounts(output: 1_000_000)]
        h.projectDays["2026-11-09"] = ["/w/app": [m: TokenCounts(output: 1_000_000)]]
        let b = Aggregator.byProject(h, prices: .defaults, range: .lastDays(7), now: now, calendar: cal, home: "/h")
        XCTAssertEqual(b.rows.map(\.name), ["app (w)", "app (v)"])
        XCTAssertEqual(b.rows[0].cost, 30, accuracy: 1e-9)       // 2M * $15/M
        XCTAssertEqual(b.rows[0].daily.count, 7)
        XCTAssertEqual(b.rows[0].daily.last?.cost ?? 0, 15, accuracy: 1e-9)
        XCTAssertEqual(b.earlier?.name, "Earlier (unknown)")
        XCTAssertEqual(b.earlier?.tokens.output, 1_000_000)
        XCTAssertEqual(b.total.cost, 60, accuracy: 1e-9)
        XCTAssertEqual(b.rows[0].share, 0.5, accuracy: 1e-9)
        XCTAssertEqual(b.rows[0].models.first?.model, m)

        let day = Aggregator.byProject(h, prices: .defaults, range: .day(ISODate.parse("2026-11-09T01:00:00Z")!), now: now, calendar: cal)
        XCTAssertEqual(day.rows.count, 1); XCTAssertNil(day.earlier); XCTAssertEqual(day.rows[0].daily.count, 1)

        let csv = ProjectCSV.make(b).split(separator: "\n")
        XCTAssertEqual(csv[0], "project,input,output,cache_write,cache_read,total_tokens,cost_usd,share_percent")
        XCTAssertEqual(csv[1], "app (w),0,2000000,0,0,2000000,30.0000,50.0")
        XCTAssertEqual(csv.count, 4)
    }

    func testOtherGroupingAndCSVEscape() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = ISODate.parse("2026-11-10T12:00:00Z")!
        var h = HistoryData(); let m = "claude-sonnet-5-5"
        var day: [String: [String: TokenCounts]] = [:]
        for i in 1...10 { day["/p/proj\(i)"] = [m: TokenCounts(output: i * 1000)] }
        day["/p/a,b"] = [m: TokenCounts(output: 1)]
        h.projectDays["2026-11-10"] = day
        h.days["2026-11-10"] = [m: day.values.reduce(.zero) { $0 + $1[m]! }]
        let b = Aggregator.byProject(h, prices: .defaults, range: .lastDays(1), now: now, calendar: cal)
        XCTAssertEqual(b.rows.count, 11)
        XCTAssertEqual(b.top.count, 8)
        XCTAssertEqual(b.tail.count, 3)
        XCTAssertEqual(b.other?.name, "Other (3)")
        XCTAssertEqual(b.other?.tokens.total, b.tail.reduce(0) { $0 + $1.tokens.total })
        XCTAssertTrue(ProjectCSV.make(b).contains("\"a,b\","))
        XCTAssertNil(b.earlier)
        XCTAssertEqual(b.sorted(byTokens: true).rows.first?.name, "proj10")
    }

    // MARK: per-project model breakdown

    private func modelFixture() -> (HistoryData, Calendar, Date) {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = ISODate.parse("2026-11-10T12:00:00Z")!
        var h = HistoryData()
        let s = "claude-sonnet-5-5", o = "claude-opus-5-5"
        h.projectDays["2026-11-10"] = ["/p/a": [s: TokenCounts(output: 1_000_000), o: TokenCounts(output: 500_000)],
                                       "/p/b": [s: TokenCounts(output: 200_000)]]
        h.projectDays["2026-11-09"] = ["/p/a": [s: TokenCounts(output: 1_000_000)], "/p/b": [o: TokenCounts(output: 100_000)]]
        h.days["2026-11-10"] = [s: TokenCounts(output: 1_200_000), o: TokenCounts(output: 500_000)]
        h.days["2026-11-09"] = [s: TokenCounts(output: 1_000_000), o: TokenCounts(output: 100_000)]
        return (h, cal, now)
    }

    func testModelUsagePerProject() {
        let (h, cal, now) = modelFixture()
        let b = Aggregator.byProject(h, prices: .defaults, range: .lastDays(7), now: now, calendar: cal, home: "/h")
        let a = b.rows.first { $0.name == "a" }!
        XCTAssertEqual(a.modelUsage.count, 2)
        let s = a.modelUsage.first { $0.model == "claude-sonnet-5-5" }!
        let o = a.modelUsage.first { $0.model == "claude-opus-5-5" }!
        XCTAssertEqual(s.tokens.output, 2_000_000)
        XCTAssertEqual(o.tokens.output, 500_000)
        XCTAssertEqual(s.cost, PriceTable.defaults.cost(model: s.model, tokens: s.tokens), accuracy: 1e-9)
        XCTAssertEqual(o.cost, PriceTable.defaults.cost(model: o.model, tokens: o.tokens), accuracy: 1e-9)
        XCTAssertEqual(a.modelUsage.reduce(0) { $0 + $1.cost }, a.cost, accuracy: 1e-9)
        XCTAssertEqual(a.modelUsage.reduce(0) { $0 + $1.share }, 1, accuracy: 1e-9)
        XCTAssertEqual(a.modelUsage.map(\.cost), a.modelUsage.map(\.cost).sorted(by: >))
        XCTAssertEqual(a.modelUsage.map(\.model), a.models.map(\.model))
        let bb = b.rows.first { $0.name == "b" }!
        XCTAssertEqual(Set(bb.modelUsage.map(\.model)), ["claude-sonnet-5-5", "claude-opus-5-5"])
        XCTAssertEqual(bb.modelUsage.reduce(0) { $0 + $1.share }, 1, accuracy: 1e-9)
    }

    func testModelUsageZeroCostSharesByTokensAndEmptyRange() {
        let (h, cal, now) = modelFixture()
        var free = h
        free.projectDays["2026-11-10"] = ["/p/z": ["x-unpriced": TokenCounts(output: 300), "y-unpriced": TokenCounts(output: 100)]]
        let b = Aggregator.byProject(free, prices: PriceTable(byFamily: [:]), range: .lastDays(1), now: now, calendar: cal)
        let z = b.rows.first { $0.name == "z" }!
        XCTAssertEqual(z.cost, 0)
        XCTAssertEqual(z.modelUsage.map(\.model), ["x-unpriced", "y-unpriced"])
        XCTAssertEqual(z.modelUsage[0].share, 0.75, accuracy: 1e-9)

        let e = Aggregator.byProject(HistoryData(), prices: .defaults, range: .lastDays(7), now: now, calendar: cal)
        XCTAssertTrue(e.rows.isEmpty); XCTAssertNil(e.earlier); XCTAssertNil(e.other)
    }

    func testModelUsageEarlierAndOtherAndTokenSort() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = ISODate.parse("2026-11-10T12:00:00Z")!
        let s = "claude-sonnet-5-5", o = "claude-opus-5-5"
        var h = HistoryData()
        var day: [String: [String: TokenCounts]] = [:]
        for i in 1...10 { day["/p/proj\(i)"] = [s: TokenCounts(output: i * 1000), o: TokenCounts(output: 10)] }
        h.projectDays["2026-11-10"] = day
        h.days["2026-11-10"] = [s: TokenCounts(output: 55_000 + 400), o: TokenCounts(output: 100)]
        let b = Aggregator.byProject(h, prices: .defaults, range: .lastDays(1), now: now, calendar: cal)
        // earlier: unattributed remainder from the model dimension
        XCTAssertEqual(b.earlier?.modelUsage.map(\.model), [s])
        XCTAssertEqual(b.earlier?.modelUsage.first?.tokens.output, 400)
        // other merges models across the 2 tail projects
        let other = b.other!
        XCTAssertEqual(other.modelUsage.count, 2)
        XCTAssertEqual(other.modelUsage.first { $0.model == o }?.tokens.output, 20)
        XCTAssertEqual(other.modelUsage.first { $0.model == s }?.tokens.output, b.tail.reduce(0) { $0 + $1.tokens.output } - 20)
        XCTAssertEqual(other.modelUsage.reduce(0) { $0 + $1.share }, 1, accuracy: 1e-9)
        XCTAssertEqual(other.modelUsage.reduce(0) { $0 + $1.cost }, other.cost, accuracy: 1e-9)
        // token sort keeps modelUsage ordered by tokens
        let t = b.sorted(byTokens: true)
        for r in t.rows { XCTAssertEqual(r.modelUsage.map(\.tokens.total), r.modelUsage.map(\.tokens.total).sorted(by: >)) }
        XCTAssertEqual(t.other?.modelUsage.map(\.tokens.total), t.other?.modelUsage.map(\.tokens.total).sorted(by: >))
        XCTAssertEqual(t.rows.map(\.modelUsage.count), b.sorted(byTokens: false).rows.sorted { $0.tokens.total > $1.tokens.total }.map(\.modelUsage.count))
    }

    func testCSVWithModels() {
        let (h, cal, now) = modelFixture()
        let b = Aggregator.byProject(h, prices: .defaults, range: .lastDays(7), now: now, calendar: cal, home: "/h")
        let lines = ProjectCSV.makeWithModels(b).split(separator: "\n")
        XCTAssertEqual(lines[0], "project,model,input,output,cache_write,cache_read,total_tokens,cost_usd")
        XCTAssertEqual(lines.count, 1 + 4)
        XCTAssertTrue(lines.contains("a,claude-sonnet-5-5,0,2000000,0,0,2000000,30.0000"))
        XCTAssertEqual(ProjectCSV.makeWithModels(ProjectBreakdown(rows: [], earlier: nil, total: .zero)),
                       "project,model,input,output,cache_write,cache_read,total_tokens,cost_usd\n")
    }
}

final class ModelBreakdownTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    let now = ISODate.parse("2026-11-10T12:00:00Z")!
    let s = "claude-sonnet-5-5", o = "claude-opus-5-5"

    /// Project a: 2M sonnet + 0.5M opus out; project b: 0.2M sonnet + 0.1M opus out (opus is pricier, sonnet has more tokens).
    private func fixture(extra: Bool = false) -> HistoryData {
        var h = HistoryData()
        h.projectDays["2026-11-10"] = ["/p/a": [s: TokenCounts(output: 1_000_000), o: TokenCounts(output: 500_000)],
                                       "/p/b": [s: TokenCounts(output: 200_000)]]
        h.projectDays["2026-11-09"] = ["/p/a": [s: TokenCounts(output: 1_000_000)], "/p/b": [o: TokenCounts(output: 100_000)]]
        h.days["2026-11-10"] = [s: TokenCounts(output: 1_200_000 + (extra ? 300_000 : 0)), o: TokenCounts(output: 500_000)]
        h.days["2026-11-09"] = [s: TokenCounts(output: 1_000_000), o: TokenCounts(output: 100_000)]
        return h
    }
    private func run(_ h: HistoryData, _ r: ProjectRange = .lastDays(7)) -> ModelBreakdown {
        Aggregator.byModel(h, prices: .defaults, range: r, now: now, calendar: cal, home: "/h")
    }

    func testTotalsProjectsAndShares() {
        let b = run(fixture())
        XCTAssertEqual(Set(b.rows.map(\.model)), [s, o])
        let sr = b.rows.first { $0.model == s }!, or = b.rows.first { $0.model == o }!
        XCTAssertEqual(sr.tokens.output, 2_200_000)
        XCTAssertEqual(or.tokens.output, 600_000)
        XCTAssertEqual(sr.cost, PriceTable.defaults.cost(model: s, tokens: sr.tokens), accuracy: 1e-9)
        XCTAssertEqual(Set(sr.projects.map(\.name)), ["a", "b"])
        XCTAssertEqual(sr.projects.first { $0.name == "a" }?.tokens.output, 2_000_000)
        XCTAssertEqual(sr.projects.first { $0.name == "a" }?.root, "/p/a")
        XCTAssertEqual(or.projects.first { $0.name == "b" }?.tokens.output, 100_000)
        for r in b.rows {
            XCTAssertEqual(r.projects.reduce(0) { $0 + $1.share }, 1, accuracy: 1e-9)
            XCTAssertEqual(r.projects.reduce(0) { $0 + $1.cost }, r.cost, accuracy: 1e-9)
            XCTAssertEqual(r.daily.count, 7)
            XCTAssertEqual(r.daily.reduce(0) { $0 + $1.cost }, r.cost, accuracy: 1e-9)
            XCTAssertTrue(r.projects.allSatisfy { $0.daily.count == 7 })
        }
        XCTAssertEqual(b.rows.reduce(0) { $0 + $1.share }, 1, accuracy: 1e-9)
        XCTAssertEqual(b.total.cost, b.rows.reduce(0) { $0 + $1.cost }, accuracy: 1e-9)
        // same totals as the project view
        XCTAssertEqual(b.total.cost, Aggregator.byProject(fixture(), prices: .defaults, range: .lastDays(7), now: now, calendar: cal, home: "/h").total.cost, accuracy: 1e-9)
        XCTAssertEqual(sr.daily.last?.tokens.output, 1_200_000)
    }

    func testOrderingByCostAndByTokens() {
        let b = run(fixture())
        // opus: 600k * $75/M = 45 ; sonnet: 2.2M * $15/M = 33
        XCTAssertEqual(b.rows.map(\.model), [o, s])
        XCTAssertEqual(b.rows[1].projects.map(\.name), ["a", "b"])
        let t = b.sorted(byTokens: true)
        XCTAssertTrue(t.byTokens)
        XCTAssertEqual(t.rows.map(\.model), [s, o])
        XCTAssertEqual(t.rows[0].projects.map(\.name), ["a", "b"])
        XCTAssertEqual(t.rows[1].projects.map(\.tokens.total), [500_000, 100_000])
        XCTAssertEqual(b.sorted(byTokens: false), b)
    }

    func testRanges() {
        let h = fixture()
        let day = run(h, .day(ISODate.parse("2026-11-09T01:00:00Z")!))
        XCTAssertEqual(day.rows.count, 2)
        XCTAssertEqual(day.rows.first { $0.model == o }?.projects.map(\.name), ["b"])
        XCTAssertEqual(day.rows[0].daily.count, 1)
        let w = run(h, .window(end: ISODate.parse("2026-11-09T01:00:00Z")!, days: 3))
        XCTAssertEqual(w.rows.first { $0.model == s }?.tokens.output, 1_000_000)
        XCTAssertEqual(w.rows[0].daily.count, 3)
    }

    func testEmptyRange() {
        let b = run(HistoryData())
        XCTAssertTrue(b.rows.isEmpty)
        XCTAssertEqual(b.total, .zero)
        XCTAssertTrue(run(fixture(), .day(ISODate.parse("2026-10-01T00:00:00Z")!)).rows.isEmpty)
        XCTAssertEqual(ModelCSV.makeByProject(b), "model,project,input,output,cache_write,cache_read,total_tokens,cost_usd\n")
    }

    func testEarlierRemainderUnderModel() {
        let b = run(fixture(extra: true))
        let sr = b.rows.first { $0.model == s }!
        let e = sr.projects.first { $0.isEarlier }!
        XCTAssertEqual(e.name, "Earlier (unknown)")
        XCTAssertNil(e.root)
        XCTAssertEqual(e.tokens.output, 300_000)
        XCTAssertEqual(sr.tokens.output, 2_500_000)
        XCTAssertEqual(b.rows.first { $0.model == o }?.projects.contains { $0.isEarlier }, false)
        XCTAssertEqual(b.total.cost, Aggregator.byProject(fixture(extra: true), prices: .defaults, range: .lastDays(7), now: now, calendar: cal, home: "/h").total.cost, accuracy: 1e-9)
    }

    func testCSVByProject() {
        let lines = ModelCSV.makeByProject(run(fixture(extra: true))).split(separator: "\n")
        XCTAssertEqual(lines[0], "model,project,input,output,cache_write,cache_read,total_tokens,cost_usd")
        XCTAssertEqual(lines.count, 1 + 5)   // opus: a, b; sonnet: a, b, earlier
        XCTAssertTrue(lines.contains("claude-sonnet-5-5,a,0,2000000,0,0,2000000,30.0000"))
        XCTAssertTrue(lines.contains("claude-sonnet-5-5,Earlier (unknown),0,300000,0,0,300000,4.5000"))
        XCTAssertEqual(lines[1].prefix(15), "claude-opus-5-5")
    }

    func testDailyCSV() {
        let d = cal.startOfDay(for: now)
        let csv = DailyCSV.make([DailyPoint(day: d, tokens: TokenCounts(input: 1, output: 2, cacheWrite: 3, cacheRead: 4), cost: 1.5)], calendar: cal)
        XCTAssertEqual(csv, "date,input,output,cache_write,cache_read,cost_usd\n2026-11-10,1,2,3,4,1.5000\n")
    }
}
