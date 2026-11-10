import Foundation

public struct Totals: Codable, Equatable, Sendable {
    public var tokens: TokenCounts
    public var cost: Double
    public static let zero = Totals(tokens: .zero, cost: 0)
    public init(tokens: TokenCounts, cost: Double) { self.tokens = tokens; self.cost = cost }
}

public struct ModelShare: Codable, Equatable, Sendable {
    public var model: String
    public var fraction: Double
}

public struct DailyPoint: Codable, Equatable, Sendable, Identifiable {
    public var day: Date
    public var tokens: TokenCounts
    public var cost: Double
    public var id: Date { day }
    public init(day: Date, tokens: TokenCounts, cost: Double) { self.day = day; self.tokens = tokens; self.cost = cost }
}

public struct UsageSummary: Codable, Equatable, Sendable {
    public var today: Totals
    public var last7: Totals
    public var month: Totals
    public var last30: Totals
    /// last-30-day cost share per model, descending
    public var modelShare: [ModelShare]
    public static let empty = UsageSummary(today: .zero, last7: .zero, month: .zero, last30: .zero, modelShare: [])
}

public enum Aggregator {
    private static func totals(_ h: HistoryData, prices: PriceTable, from: String, through: String) -> (Totals, [String: Double]) {
        var t = Totals.zero
        var byModel: [String: Double] = [:]
        for (day, models) in h.days where day >= from && day <= through {
            for (model, tok) in models {
                let c = prices.cost(model: model, tokens: tok)
                t.tokens += tok; t.cost += c; byModel[model, default: 0] += c
            }
        }
        return (t, byModel)
    }

    public static func summarize(_ h: HistoryData, prices: PriceTable, now: Date, calendar: Calendar = .current) -> UsageSummary {
        func key(_ daysBack: Int) -> String { DayKey.string(calendar.date(byAdding: .day, value: -daysBack, to: now)!, calendar: calendar) }
        let today = key(0)
        let monthStart = String(today.prefix(8)) + "01"
        let (t0, _) = totals(h, prices: prices, from: today, through: today)
        let (t7, _) = totals(h, prices: prices, from: key(6), through: today)
        let (tm, _) = totals(h, prices: prices, from: monthStart, through: today)
        let (t30, models) = totals(h, prices: prices, from: key(29), through: today)
        let sum = models.values.reduce(0, +)
        let shares = models.sorted { $0.value > $1.value }
            .map { ModelShare(model: $0.key, fraction: sum > 0 ? $0.value / sum : 0) }
        return UsageSummary(today: t0, last7: t7, month: tm, last30: t30, modelShare: shares)
    }

    /// Oldest-first series of `days` points ending today; empty days included.
    public static func daily(_ h: HistoryData, prices: PriceTable, days: Int, now: Date, calendar: Calendar = .current) -> [DailyPoint] {
        (0..<days).reversed().map { back in
            let date = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -back, to: now)!)
            let k = DayKey.string(date, calendar: calendar)
            let (t, _) = totals(h, prices: prices, from: k, through: k)
            return DailyPoint(day: date, tokens: t.tokens, cost: t.cost)
        }
    }
}

public enum DailyCSV {
    /// One row per day: date (local), token counts and API-equivalent cost.
    public static func make(_ points: [DailyPoint], calendar: Calendar = .current) -> String {
        var csv = "date,input,output,cache_write,cache_read,cost_usd\n"
        for p in points {
            csv += "\(DayKey.string(p.day, calendar: calendar)),\(p.tokens.input),\(p.tokens.output),\(p.tokens.cacheWrite),\(p.tokens.cacheRead),\(String(format: "%.4f", p.cost))\n"
        }
        return csv
    }
}
