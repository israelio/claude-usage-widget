import Foundation

public enum DayKey {
    public static func string(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}

public struct LimitSample: Codable, Equatable, Sendable {
    public var t: Date
    public var fiveHour: Double?
    public var fiveHourReset: Date?
    public var sevenDay: Double?
    public var sevenDayReset: Date?
    public init(t: Date, fiveHour: Double?, fiveHourReset: Date?, sevenDay: Double?, sevenDayReset: Date?) {
        self.t = t; self.fiveHour = fiveHour; self.fiveHourReset = fiveHourReset
        self.sevenDay = sevenDay; self.sevenDayReset = sevenDayReset
    }
}

public struct HistoryData: Codable, Equatable, Sendable {
    public static let keepDays = 90
    /// day key -> model -> tokens
    public var days: [String: [String: TokenCounts]] = [:]
    /// raw records from the last 7 days (for local estimation)
    public var recent: [UsageRecord] = []
    public var samples: [LimitSample] = []
    public var scan = ScanState()
    public init() {}

    public mutating func add(_ records: [UsageRecord], calendar: Calendar = .current) {
        for r in records {
            let key = DayKey.string(r.timestamp, calendar: calendar)
            days[key, default: [:]][r.model, default: .zero] += r.tokens
            recent.append(r)
        }
    }

    public mutating func add(sample: LimitSample) { samples.append(sample) }

    public mutating func prune(now: Date, calendar: Calendar = .current) {
        let dayCutoff = DayKey.string(calendar.date(byAdding: .day, value: -Self.keepDays, to: now)!, calendar: calendar)
        days = days.filter { $0.key >= dayCutoff }
        let weekAgo = now.addingTimeInterval(-7 * 86400)
        recent.removeAll { $0.timestamp < weekAgo }
        let sampleCutoff = now.addingTimeInterval(-8 * 86400)
        samples.removeAll { $0.t < sampleCutoff }
    }
}
