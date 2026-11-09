import Foundation

public struct SharedSnapshot: Codable, Equatable, Sendable {
    public var limits: LimitsSnapshot?
    public var today: Totals
    public var last7: Totals
    public var daily: [DailyPoint]
    public var updatedAt: Date
    /// App preference: show remaining instead of used. Optional so older snapshot files still decode.
    public var showRemaining: Bool?
    public init(limits: LimitsSnapshot?, today: Totals, last7: Totals, daily: [DailyPoint], updatedAt: Date, showRemaining: Bool? = nil) {
        self.showRemaining = showRemaining; self.limits = limits; self.today = today; self.last7 = last7; self.daily = daily; self.updatedAt = updatedAt
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try enc.encode(self).write(to: url, options: .atomic)
    }

    public static func load(from url: URL) -> SharedSnapshot? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(SharedSnapshot.self, from: d)
    }

    /// App Group location if the group is provisioned, else nil.
    public static func groupURL(groupID: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("snapshot.json")
    }

    /// Whether two snapshots would render the same widget: ignores timestamps (`updatedAt`, `fetchedAt`) and
    /// anything below what's displayed (whole percents, cents).
    public func displayEquals(_ o: SharedSnapshot) -> Bool { displayKey == o.displayKey }

    private var displayKey: [String] {
        func win(_ w: LimitWindow?) -> String {
            guard let w else { return "-" }
            return "\(Int(w.utilization.rounded()))@\(w.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "-")"
        }
        func tot(_ t: Totals) -> String { "\(Int((t.cost * 100).rounded()))" }
        var k = [win(limits?.fiveHour), win(limits?.sevenDay), limits == nil ? "nolimits" : "limits",
                 limits?.isEstimated == true ? "est" : "real", tot(today), tot(last7), showRemaining == true ? "left" : "used"]
        k += (limits?.extra ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key)=\(win($0.value))" }
        k += daily.map { "\(Int($0.day.timeIntervalSince1970)):\(Int(($0.cost * 100).rounded()))" }
        return k
    }
}
