import Foundation

/// One project's usage of a single model (a child of a `ModelRow`).
public struct ProjectUsage: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Root path for tooltips; nil for the synthetic Unknown / Earlier entries.
    public var root: String?
    public var tokens: TokenCounts
    public var cost: Double
    /// Fraction 0...1 of the model's cost (of its tokens when the model's cost is 0).
    public var share: Double
    /// One point per day of the range, oldest first, empty days included.
    public var daily: [DailyPoint]
    public var isEarlier = false

    public init(id: String, name: String, root: String?, tokens: TokenCounts, cost: Double, share: Double,
                daily: [DailyPoint], isEarlier: Bool = false) {
        self.id = id; self.name = name; self.root = root; self.tokens = tokens; self.cost = cost
        self.share = share; self.daily = daily; self.isEarlier = isEarlier
    }
}

public struct ModelRow: Equatable, Sendable, Identifiable {
    public var model: String
    public var tokens: TokenCounts
    public var cost: Double
    /// Fraction 0...1 of the range total (by cost; by tokens when the total cost is 0).
    public var share: Double
    /// The projects that used this model, by cost (by tokens after `ModelBreakdown.sorted(byTokens: true)`). Usage
    /// that has no project info is one "Earlier (unknown)" entry.
    public var projects: [ProjectUsage]
    /// One point per day of the range, oldest first, empty days included.
    public var daily: [DailyPoint]
    public var id: String { model }
}

public struct ModelBreakdown: Equatable, Sendable {
    /// Every model used in the range, sorted by cost descending.
    public var rows: [ModelRow]
    public var total: Totals
    /// Whether rows (and their projects) are ordered by tokens (see `sorted(byTokens:)`).
    public var byTokens = false

    /// The same breakdown ordered by tokens instead of cost.
    public func sorted(byTokens: Bool) -> ModelBreakdown {
        guard byTokens else { return self }
        var b = self
        b.byTokens = true
        for i in b.rows.indices { b.rows[i].projects = Self.order(b.rows[i].projects, byTokens: true) }
        b.rows.sort { $0.tokens.total != $1.tokens.total ? $0.tokens.total > $1.tokens.total : $0.model < $1.model }
        return b
    }

    static func order(_ p: [ProjectUsage], byTokens: Bool) -> [ProjectUsage] {
        p.sorted { a, b in
            let (ka, kb) = byTokens ? (Double(a.tokens.total), Double(b.tokens.total)) : (a.cost, b.cost)
            if ka != kb { return ka > kb }
            let (la, lb) = byTokens ? (a.cost, b.cost) : (Double(a.tokens.total), Double(b.tokens.total))
            if la != lb { return la > lb }
            return a.name < b.name
        }
    }
}

extension Aggregator {
    /// Per-model cost and tokens over `range`, each model split by project. Project names and roots are the same as
    /// in `byProject`. Usage in `days` that `projectDays` does not cover is listed under each model as "Earlier (unknown)" (day ranges only;
    /// session ranges have none, and their trend points are hours or sessions, see `ProjectRange`).
    public static func byModel(_ h: HistoryData, prices: PriceTable, range: ProjectRange, now: Date,
                               calendar: Calendar = .current, home: String = NSHomeDirectory()) -> ModelBreakdown {
        let buckets = Self.buckets(range, h: h, now: now, calendar: calendar)
        let dates = buckets.map(\.date)
        let keys = dates
        let earlierId = "earlier"

        // model -> project (or earlierId) -> tokens per day
        var acc: [String: [String: [TokenCounts]]] = [:]
        func add(_ model: String, _ project: String, _ i: Int, _ t: TokenCounts) {
            acc[model, default: [:]][project, default: Array(repeating: .zero, count: keys.count)][i] += t
        }
        for (i, bucket) in buckets.enumerated() {
            var attributed: [String: TokenCounts] = [:]
            for (project, models) in bucket.projects {
                for (model, tok) in models { add(model, project, i, tok); attributed[model, default: .zero] += tok }
            }
            for (model, tok) in bucket.totals ?? [:] {
                let p = attributed[model] ?? .zero
                let rem = TokenCounts(input: max(0, tok.input - p.input), output: max(0, tok.output - p.output),
                                      cacheWrite: max(0, tok.cacheWrite - p.cacheWrite), cacheRead: max(0, tok.cacheRead - p.cacheRead))
                if rem.total > 0 { add(model, earlierId, i, rem) }
            }
        }

        let names = ProjectNaming.displayNames(for: Array(Set(acc.values.flatMap { $0.keys })).filter { $0 != earlierId }, home: home)
        func points(_ model: String, _ perDay: [TokenCounts]) -> [DailyPoint] {
            perDay.enumerated().map { DailyPoint(day: dates[$0.offset], tokens: $0.element, cost: prices.cost(model: model, tokens: $0.element)) }
        }
        func sum(_ pts: [DailyPoint]) -> (TokenCounts, Double) {
            pts.reduce((TokenCounts.zero, 0.0)) { ($0.0 + $1.tokens, $0.1 + $1.cost) }
        }

        var rows: [ModelRow] = acc.map { model, byProject in
            var usages: [ProjectUsage] = byProject.map { project, perDay in
                let daily = points(model, perDay)
                let (t, c) = sum(daily)
                let earlier = project == earlierId
                return ProjectUsage(id: project, name: earlier ? ProjectBreakdown.earlierName : (names[project] ?? project),
                                    root: earlier || project == ProjectNaming.unknown ? nil : project,
                                    tokens: t, cost: c, share: 0, daily: daily, isEarlier: earlier)
            }
            let cost = usages.reduce(0) { $0 + $1.cost }, tokens = usages.reduce(TokenCounts.zero) { $0 + $1.tokens }
            for i in usages.indices {
                usages[i].share = cost > 0 ? usages[i].cost / cost : (tokens.total > 0 ? Double(usages[i].tokens.total) / Double(tokens.total) : 0)
            }
            let daily = keys.indices.map { i in
                DailyPoint(day: dates[i], tokens: usages.reduce(.zero) { $0 + $1.daily[i].tokens }, cost: usages.reduce(0) { $0 + $1.daily[i].cost })
            }
            return ModelRow(model: model, tokens: tokens, cost: cost, share: 0,
                            projects: ModelBreakdown.order(usages, byTokens: false), daily: daily)
        }
        var total = Totals.zero
        for r in rows { total.tokens += r.tokens; total.cost += r.cost }
        for i in rows.indices {
            rows[i].share = total.cost > 0 ? rows[i].cost / total.cost
                : (total.tokens.total > 0 ? Double(rows[i].tokens.total) / Double(total.tokens.total) : 0)
        }
        rows.sort { a, b in
            if a.cost != b.cost { return a.cost > b.cost }
            if a.tokens.total != b.tokens.total { return a.tokens.total > b.tokens.total }
            return a.model < b.model
        }
        return ModelBreakdown(rows: rows, total: total)
    }
}

public enum ModelCSV {
    /// One row per model and project (the "Earlier (unknown)" entries included).
    public static func makeByProject(_ b: ModelBreakdown) -> String {
        var csv = "model,project,input,output,cache_write,cache_read,total_tokens,cost_usd\n"
        for r in b.rows {
            for p in r.projects {
                csv += "\(ProjectCSV.escape(r.model)),\(ProjectCSV.escape(p.name)),\(p.tokens.input),\(p.tokens.output),\(p.tokens.cacheWrite),\(p.tokens.cacheRead),"
                csv += "\(p.tokens.total),\(String(format: "%.4f", p.cost))\n"
            }
        }
        return csv
    }
}
