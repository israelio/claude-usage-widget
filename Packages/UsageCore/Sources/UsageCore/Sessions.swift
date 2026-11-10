import Foundation

/// One of Claude's rolling 5-hour work windows: it starts at the first active hour and covers 5 hours.
public struct UsageSession: Equatable, Sendable, Identifiable {
    public static let length = 5

    /// Epoch hour of the start (absolute, timezone independent).
    public var id: Int
    /// The active hours inside the window: epoch hour -> project root -> model -> tokens.
    public var hours: [Int: [String: [String: TokenCounts]]]
    public var tokens: TokenCounts

    public init(id: Int, hours: [Int: [String: [String: TokenCounts]]]) {
        self.id = id; self.hours = hours
        var t = TokenCounts.zero
        for p in hours.values { for m in p.values { for tok in m.values { t += tok } } }
        tokens = t
    }

    public var start: Date { Date(timeIntervalSince1970: Double(id) * 3600) }
    public var end: Date { Date(timeIntervalSince1970: Double(id + Self.length) * 3600) }
    /// In progress: `now` is inside the window.
    public func isActive(now: Date) -> Bool { now >= start && now < end }
    public var activeHourCount: Int { hours.count }
    /// Distinct projects (including "Unknown") used in the session.
    public var projectCount: Int { Set(hours.values.flatMap { $0.keys }).count }

    public func cost(prices: PriceTable) -> Double {
        var c = 0.0
        for p in hours.values { for (model, tok) in p.values.flatMap({ $0 }) { c += prices.cost(model: model, tokens: tok) } }
        return c
    }
}

public enum SessionBuilder {
    /// Sessions from hourly buckets, oldest first. Rolling-window rule: a session starts at an active hour H and
    /// covers [H, H+5h); every active hour inside belongs to it; the next active hour at or after H+5h starts a new one.
    /// `now` is unused for the grouping (kept so callers pass the same clock as `isActive`).
    public static func sessions(hourly: [Int: [String: [String: TokenCounts]]], now: Date = Date()) -> [UsageSession] {
        var out: [UsageSession] = []
        var start: Int?
        var slice: [Int: [String: [String: TokenCounts]]] = [:]
        for h in hourly.keys.sorted() {
            if let s = start, h < s + UsageSession.length {
                slice[h] = hourly[h]
            } else {
                if let s = start { out.append(UsageSession(id: s, hours: slice)) }
                start = h; slice = [h: hourly[h]!]
            }
        }
        if let s = start { out.append(UsageSession(id: s, hours: slice)) }
        return out
    }

    /// The sessions that overlap the last `days` calendar days (today included), same day semantics as the daily ranges.
    public static func recent(_ sessions: [UsageSession], days: Int, now: Date, calendar: Calendar = .current) -> [UsageSession] {
        let first = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: now)!)
        return sessions.filter { $0.end > first }
    }
}

public enum SessionCSV {
    /// One row per session: start/end (ISO 8601, UTC), tokens, API-equivalent cost and project count.
    public static func make(_ sessions: [UsageSession], prices: PriceTable) -> String {
        let f = ISO8601DateFormatter()
        var csv = "start,end,input,output,cache_write,cache_read,total_tokens,cost_usd,projects\n"
        for s in sessions {
            let t = s.tokens
            csv += "\(f.string(from: s.start)),\(f.string(from: s.end)),\(t.input),\(t.output),\(t.cacheWrite),\(t.cacheRead),"
            csv += "\(t.total),\(String(format: "%.4f", s.cost(prices: prices))),\(s.projectCount)\n"
        }
        return csv
    }
}
