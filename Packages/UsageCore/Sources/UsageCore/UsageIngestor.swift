import Foundation

public actor UsageIngestor {
    private var history = HistoryData()
    private var scanner: LogScanner?
    private let logsRoot: URL
    private let storeURL: URL
    private let resolver: ProjectResolver
    private var lastNewCount = 0

    public init(logsRoot: URL, storeURL: URL, resolver: ProjectResolver = DefaultProjectResolver()) {
        self.logsRoot = logsRoot
        self.storeURL = storeURL
        self.resolver = resolver
    }

    /// Loads history from disk on first use (inside the actor, off the main thread).
    private func ensureLoaded() -> LogScanner {
        if let s = scanner { return s }
        let h = Self.load(storeURL)
        history = h
        let s = LogScanner(root: logsRoot, state: h.scan)
        scanner = s
        return s
    }

    /// Scans new log lines, rolls them up, prunes, persists only if something changed, returns a copy.
    public func refreshLogs(now: Date = Date()) -> HistoryData {
        let scanner = ensureLoaded()
        var changed = backfillIfNeeded(now: now)
        var new = scanner.scan(now: now)
        for i in new.indices { new[i].project = resolver.resolve(cwd: new[i].cwd).root }
        lastNewCount = new.count
        if !new.isEmpty { changed = true }
        history.add(new)
        if history.scan != scanner.state { history.scan = scanner.state; changed = true }
        if history.prune(now: now) { changed = true }
        // Keep the scanner's view in sync with pruned `seen`.
        if changed { scanner.state = history.scan; save() }
        return history
    }

    /// One-off: rebuilds `projectDays` and/or `hourly` (whichever schema version is behind) from all log files still
    /// on disk, in a single pass with a throwaway scanner (own `seen` set). Only records already counted in `days`
    /// (present in the real scanner's `seen`) are used, so anything newer is left for the regular incremental scan and
    /// nothing is counted twice. Touches nothing but the structures being backfilled.
    private func backfillIfNeeded(now: Date) -> Bool {
        let projects = history.projectSchemaVersion < 1, hourly = history.hourlySchemaVersion < 1
        guard projects || hourly else { return false }
        var records = LogScanner(root: logsRoot, state: ScanState()).scan(now: now)
            .filter { history.scan.seen[$0.id] != nil }
        for i in records.indices { records[i].project = resolver.resolve(cwd: records[i].cwd).root }
        if projects {
            history.projectDays = [:]
            history.addProjects(records)
            history.projectSchemaVersion = 1
        }
        if hourly {
            history.hourly = [:]
            history.addHourly(records)
            history.hourlySchemaVersion = 1
        }
        return true
    }

    /// How many new log records the latest `refreshLogs` found.
    public func lastScanNewCount() -> Int { lastNewCount }

    public func record(_ snapshot: LimitsSnapshot) {
        _ = ensureLoaded()
        guard !snapshot.isEstimated else { return }
        history.add(sample: LimitSample(t: snapshot.fetchedAt, fiveHour: snapshot.fiveHour?.utilization,
                                        fiveHourReset: snapshot.fiveHour?.resetsAt,
                                        sevenDay: snapshot.sevenDay?.utilization, sevenDayReset: snapshot.sevenDay?.resetsAt))
        save()
    }

    public func current() -> HistoryData { _ = ensureLoaded(); return history }

    private func save() {
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(history) { try? d.write(to: storeURL, options: .atomic) }
    }

    private static func load(_ url: URL) -> HistoryData {
        guard let d = try? Data(contentsOf: url) else { return HistoryData() }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let h = try? dec.decode(HistoryData.self, from: d) { return h }
        // Unreadable: keep the bytes around rather than overwriting them with an empty history.
        let bak = url.appendingPathExtension("bak")
        try? FileManager.default.removeItem(at: bak)
        try? FileManager.default.moveItem(at: url, to: bak)
        return HistoryData()
    }
}
