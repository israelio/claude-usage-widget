import Foundation

public enum ProjectRange: Equatable, Sendable {
    case day(Date)
    case lastDays(Int)
    /// `days` days ending on (and including) `end`, which need not be today.
    case window(end: Date, days: Int)
}

/// One model's usage inside a project (or the synthetic Other / Earlier rows).
public struct ModelUsage: Equatable, Sendable, Identifiable {
    public var model: String
    public var tokens: TokenCounts
    public var cost: Double
    /// Fraction 0...1 of the row's cost (of its tokens when the row's cost is 0).
    public var share: Double
    public var id: String { model }

    public init(model: String, tokens: TokenCounts, cost: Double, share: Double) {
        self.model = model; self.tokens = tokens; self.cost = cost; self.share = share
    }

    /// Builds the list from per-model tokens and costs: shares computed, sorted by cost (or tokens), ties by the other, then name.
    static func list(_ items: [(model: String, tokens: TokenCounts, cost: Double)], byTokens: Bool = false) -> [ModelUsage] {
        let totalCost = items.reduce(0) { $0 + $1.cost }
        let totalTokens = items.reduce(0) { $0 + $1.tokens.total }
        return sorted(items.map { i in
            let s = totalCost > 0 ? i.cost / totalCost : (totalTokens > 0 ? Double(i.tokens.total) / Double(totalTokens) : 0)
            return ModelUsage(model: i.model, tokens: i.tokens, cost: i.cost, share: s)
        }, byTokens: byTokens)
    }

    /// `usage` ordered by cost, or by tokens (for the UI's Cost / Tokens toggle).
    public static func ordered(_ u: [ModelUsage], byTokens: Bool) -> [ModelUsage] { sorted(u, byTokens: byTokens) }

    static func sorted(_ u: [ModelUsage], byTokens: Bool) -> [ModelUsage] {
        u.sorted { a, b in
            let (ka, kb) = byTokens ? (Double(a.tokens.total), Double(b.tokens.total)) : (a.cost, b.cost)
            if ka != kb { return ka > kb }
            let (la, lb) = byTokens ? (a.cost, b.cost) : (Double(a.tokens.total), Double(b.tokens.total))
            if la != lb { return la > lb }
            return a.model < b.model
        }
    }
}

public struct ProjectRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Root path for tooltips; nil for synthetic rows (Unknown, Other, Earlier).
    public var root: String?
    public var tokens: TokenCounts
    public var cost: Double
    /// Fraction 0...1 of the range total (by cost; by tokens when the total cost is 0).
    public var share: Double
    /// Cost share per model, descending.
    public var models: [ModelShare]
    /// Tokens, cost and share per model, ordered by cost (by tokens after `ProjectBreakdown.sorted(byTokens: true)`).
    public var modelUsage: [ModelUsage] = []
    /// One point per day of the range, oldest first, empty days included.
    public var daily: [DailyPoint]
    public var isEarlier = false
}

public struct ProjectBreakdown: Equatable, Sendable {
    public static let maxVisible = 8
    public static let earlierName = "Earlier (unknown)"

    /// Every real project, sorted by cost descending.
    public var rows: [ProjectRow]
    /// Usage in the range that has no project info (history older than per-project tracking or the logs kept).
    public var earlier: ProjectRow?
    public var total: Totals
    /// Whether per-row `modelUsage` is ordered by tokens (see `sorted(byTokens:)`).
    public var byTokens = false

    /// The same breakdown with `rows` ordered by tokens instead of cost (so `top` / `tail` follow that order).
    public func sorted(byTokens: Bool) -> ProjectBreakdown {
        guard byTokens else { return self }
        var b = self
        b.byTokens = true
        for i in b.rows.indices { b.rows[i].modelUsage = ModelUsage.sorted(b.rows[i].modelUsage, byTokens: true) }
        if b.earlier != nil { b.earlier!.modelUsage = ModelUsage.sorted(b.earlier!.modelUsage, byTokens: true) }
        b.rows.sort { $0.tokens.total != $1.tokens.total ? $0.tokens.total > $1.tokens.total : $0.name < $1.name }
        return b
    }

    /// The rows to show before the long tail: all of them when there are `maxVisible` or fewer.
    public var top: [ProjectRow] { rows.count > Self.maxVisible ? Array(rows.prefix(Self.maxVisible)) : rows }
    /// The grouped long tail (so the UI can expand "Other (N)").
    public var tail: [ProjectRow] { rows.count > Self.maxVisible ? Array(rows.dropFirst(Self.maxVisible)) : [] }
    /// The "Other (N)" row merging `tail`, or nil when nothing is grouped.
    public var other: ProjectRow? {
        let t = tail
        guard !t.isEmpty else { return nil }
        var tokens = TokenCounts.zero, cost = 0.0, share = 0.0
        var modelCost: [String: Double] = [:]
        var usage: [String: (TokenCounts, Double)] = [:]
        var daily = t[0].daily.map { DailyPoint(day: $0.day, tokens: .zero, cost: 0) }
        for r in t {
            tokens += r.tokens; cost += r.cost; share += r.share
            for m in r.models { modelCost[m.model, default: 0] += m.fraction * r.cost }
            for i in daily.indices { daily[i].tokens += r.daily[i].tokens; daily[i].cost += r.daily[i].cost }
            for u in r.modelUsage { let o = usage[u.model] ?? (.zero, 0); usage[u.model] = (o.0 + u.tokens, o.1 + u.cost) }
        }
        let sum = modelCost.values.reduce(0, +)
        let models = modelCost.sorted { $0.value > $1.value }.map { ModelShare(model: $0.key, fraction: sum > 0 ? $0.value / sum : 0) }
        return ProjectRow(id: "other", name: "Other (\(t.count))", root: nil, tokens: tokens, cost: cost, share: share,
                          models: models,
                          modelUsage: ModelUsage.list(usage.map { ($0.key, $0.value.0, $0.value.1) }, byTokens: byTokens), daily: daily)
    }
}

extension Aggregator {
    /// Per-project cost and tokens over `range`. Project keys are root paths; names are disambiguated here.
    public static func byProject(_ h: HistoryData, prices: PriceTable, range: ProjectRange, now: Date,
                                 calendar: Calendar = .current, home: String = NSHomeDirectory()) -> ProjectBreakdown {
        let dates: [Date]
        switch range {
        case .day(let d): dates = [calendar.startOfDay(for: d)]
        case .window(let end, let n):
            dates = (0..<max(1, n)).reversed().map { calendar.startOfDay(for: calendar.date(byAdding: .day, value: -$0, to: end)!) }
        case .lastDays(let n):
            dates = (0..<max(1, n)).reversed().map { calendar.startOfDay(for: calendar.date(byAdding: .day, value: -$0, to: now)!) }
        }
        let keys = dates.map { DayKey.string($0, calendar: calendar) }

        struct Acc {
            var models: [String: TokenCounts] = [:]
            var daily: [TokenCounts]
        }
        var acc: [String: Acc] = [:]
        var remainder = Acc(daily: Array(repeating: .zero, count: keys.count))   // days minus projects
        var remainderCostByDay = [Double](repeating: 0, count: keys.count)
        for (i, k) in keys.enumerated() {
            var projectSum: [String: TokenCounts] = [:]
            for (project, models) in h.projectDays[k] ?? [:] {
                for (model, tok) in models {
                    acc[project, default: Acc(daily: Array(repeating: .zero, count: keys.count))].models[model, default: .zero] += tok
                    acc[project]!.daily[i] += tok
                    projectSum[model, default: .zero] += tok
                }
            }
            for (model, tok) in h.days[k] ?? [:] {
                let p = projectSum[model] ?? .zero
                let rem = TokenCounts(input: max(0, tok.input - p.input), output: max(0, tok.output - p.output),
                                      cacheWrite: max(0, tok.cacheWrite - p.cacheWrite), cacheRead: max(0, tok.cacheRead - p.cacheRead))
                guard rem.total > 0 else { continue }
                remainder.models[model, default: .zero] += rem
                remainder.daily[i] += rem
                remainderCostByDay[i] += prices.cost(model: model, tokens: rem)
            }
        }

        func row(id: String, name: String, root: String?, _ a: Acc) -> ProjectRow {
            var tokens = TokenCounts.zero, cost = 0.0
            var byModel: [String: Double] = [:]
            var items: [(model: String, tokens: TokenCounts, cost: Double)] = []
            for (m, t) in a.models { let c = prices.cost(model: m, tokens: t); tokens += t; cost += c; byModel[m] = c; items.append((m, t, c)) }
            let sum = byModel.values.reduce(0, +)
            let models = byModel.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
                .map { ModelShare(model: $0.key, fraction: sum > 0 ? $0.value / sum : 0) }
            return ProjectRow(id: id, name: name, root: root, tokens: tokens, cost: cost, share: 0, models: models,
                              modelUsage: ModelUsage.list(items), daily: [])
        }
        /// Daily points need per-day cost, which depends on the per-model split of that day.
        func dailyPoints(_ project: String) -> [DailyPoint] {
            keys.enumerated().map { i, k in
                var t = TokenCounts.zero, c = 0.0
                for (m, tok) in h.projectDays[k]?[project] ?? [:] { t += tok; c += prices.cost(model: m, tokens: tok) }
                return DailyPoint(day: dates[i], tokens: t, cost: c)
            }
        }

        let names = ProjectNaming.displayNames(for: Array(acc.keys), home: home)
        var rows = acc.map { project, a -> ProjectRow in
            var r = row(id: project, name: names[project] ?? project, root: project == ProjectNaming.unknown ? nil : project, a)
            r.daily = dailyPoints(project)
            return r
        }
        var earlier: ProjectRow?
        if remainder.daily.contains(where: { $0.total > 0 }) {
            var r = row(id: "earlier", name: ProjectBreakdown.earlierName, root: nil, remainder)
            r.daily = keys.indices.map { DailyPoint(day: dates[$0], tokens: remainder.daily[$0], cost: remainderCostByDay[$0]) }
            r.isEarlier = true
            earlier = r
        }
        let all = rows + (earlier.map { [$0] } ?? [])
        var total = Totals.zero
        for r in all { total.tokens += r.tokens; total.cost += r.cost }
        for i in rows.indices { rows[i].share = share(rows[i], total) }
        if earlier != nil { earlier!.share = share(earlier!, total) }
        rows.sort { a, b in
            if a.cost != b.cost { return a.cost > b.cost }
            if a.tokens.total != b.tokens.total { return a.tokens.total > b.tokens.total }
            return a.name < b.name
        }
        return ProjectBreakdown(rows: rows, earlier: earlier, total: total)
    }

    private static func share(_ r: ProjectRow, _ total: Totals) -> Double {
        if total.cost > 0 { return r.cost / total.cost }
        return total.tokens.total > 0 ? Double(r.tokens.total) / Double(total.tokens.total) : 0
    }
}

public enum ProjectCSV {
    public static func make(_ b: ProjectBreakdown) -> String {
        var csv = "project,input,output,cache_write,cache_read,total_tokens,cost_usd,share_percent\n"
        for r in b.rows + (b.earlier.map { [$0] } ?? []) {
            csv += "\(escape(r.name)),\(r.tokens.input),\(r.tokens.output),\(r.tokens.cacheWrite),\(r.tokens.cacheRead),"
            csv += "\(r.tokens.total),\(String(format: "%.4f", r.cost)),\(String(format: "%.1f", r.share * 100))\n"
        }
        return csv
    }

    /// One row per project and model (including the "Earlier" row when present).
    public static func makeWithModels(_ b: ProjectBreakdown) -> String {
        var csv = "project,model,input,output,cache_write,cache_read,total_tokens,cost_usd\n"
        for r in b.rows + (b.earlier.map { [$0] } ?? []) {
            for u in r.modelUsage {
                csv += "\(escape(r.name)),\(escape(u.model)),\(u.tokens.input),\(u.tokens.output),\(u.tokens.cacheWrite),\(u.tokens.cacheRead),"
                csv += "\(u.tokens.total),\(String(format: "%.4f", u.cost))\n"
            }
        }
        return csv
    }

    private static func escape(_ s: String) -> String {
        s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }
}
