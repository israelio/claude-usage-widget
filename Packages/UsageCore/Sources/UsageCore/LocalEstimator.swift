import Foundation

/// User-configured plan budgets in "billable" tokens (input + output + cache writes). Starting guesses; tune in Settings.
public struct PlanLimits: Codable, Equatable, Sendable {
    public var fiveHourTokens: Int
    public var weeklyTokens: Int
    public init(fiveHourTokens: Int = 3_000_000, weeklyTokens: Int = 40_000_000) {
        self.fiveHourTokens = fiveHourTokens; self.weeklyTokens = weeklyTokens
    }
}

public enum LocalEstimator {
    private static func billable(_ t: TokenCounts) -> Int { t.input + t.output + t.cacheWrite }

    public static func estimate(records: [UsageRecord], limits: PlanLimits, now: Date) -> LimitsSnapshot {
        let fiveAgo = now.addingTimeInterval(-Pace.fiveHours)
        let weekAgo = now.addingTimeInterval(-Pace.week)
        let five = records.filter { $0.timestamp >= fiveAgo && $0.timestamp <= now }
        let week = records.filter { $0.timestamp >= weekAgo && $0.timestamp <= now }
        let fiveUsed = five.reduce(0) { $0 + billable($1.tokens) }
        let weekUsed = week.reduce(0) { $0 + billable($1.tokens) }
        let start = five.map(\.timestamp).min()
        return LimitsSnapshot(
            fetchedAt: now,
            fiveHour: LimitWindow(utilization: Double(fiveUsed) / Double(max(1, limits.fiveHourTokens)) * 100,
                                  resetsAt: start.map { $0.addingTimeInterval(Pace.fiveHours) }),
            sevenDay: LimitWindow(utilization: Double(weekUsed) / Double(max(1, limits.weeklyTokens)) * 100, resetsAt: nil),
            isEstimated: true)
    }
}
