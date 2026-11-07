import Foundation

public actor UsageIngestor {
    private var history: HistoryData
    private let scanner: LogScanner
    private let storeURL: URL

    public init(logsRoot: URL, storeURL: URL) {
        self.storeURL = storeURL
        let loaded = Self.load(storeURL)
        self.history = loaded
        self.scanner = LogScanner(root: logsRoot, state: loaded.scan)
    }

    /// Scans new log lines, rolls them up, prunes, persists, returns a copy.
    public func refreshLogs(now: Date = Date()) -> HistoryData {
        let new = scanner.scan(now: now)
        history.add(new)
        history.scan = scanner.state
        history.prune(now: now)
        save()
        return history
    }

    public func record(_ snapshot: LimitsSnapshot) {
        guard !snapshot.isEstimated else { return }
        history.add(sample: LimitSample(t: snapshot.fetchedAt, fiveHour: snapshot.fiveHour?.utilization,
                                        fiveHourReset: snapshot.fiveHour?.resetsAt,
                                        sevenDay: snapshot.sevenDay?.utilization, sevenDayReset: snapshot.sevenDay?.resetsAt))
        save()
    }

    public func current() -> HistoryData { history }

    private func save() {
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(history) { try? d.write(to: storeURL, options: .atomic) }
    }

    private static func load(_ url: URL) -> HistoryData {
        guard let d = try? Data(contentsOf: url) else { return HistoryData() }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(HistoryData.self, from: d)) ?? HistoryData()
    }
}
