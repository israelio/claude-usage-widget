import Foundation

public struct TokenCounts: Codable, Equatable, Sendable {
    public var input: Int
    public var output: Int
    public var cacheWrite: Int
    public var cacheRead: Int
    public init(input: Int = 0, output: Int = 0, cacheWrite: Int = 0, cacheRead: Int = 0) {
        self.input = input; self.output = output; self.cacheWrite = cacheWrite; self.cacheRead = cacheRead
    }
    public static let zero = TokenCounts()
    public var cache: Int { cacheWrite + cacheRead }
    public var total: Int { input + output + cacheWrite + cacheRead }
    public static func + (l: TokenCounts, r: TokenCounts) -> TokenCounts {
        TokenCounts(input: l.input + r.input, output: l.output + r.output,
                    cacheWrite: l.cacheWrite + r.cacheWrite, cacheRead: l.cacheRead + r.cacheRead)
    }
    public static func += (l: inout TokenCounts, r: TokenCounts) { l = l + r }
}

public struct UsageRecord: Codable, Equatable, Sendable {
    public var id: String
    public var timestamp: Date
    public var model: String
    public var tokens: TokenCounts
    /// Working directory the log line was written from. Transient: only used to resolve `project`, never persisted.
    public var cwd: String?
    /// Resolved project root path (or "Unknown"); nil for records persisted before per-project tracking.
    public var project: String?
    public init(id: String, timestamp: Date, model: String, tokens: TokenCounts, cwd: String? = nil, project: String? = nil) {
        self.id = id; self.timestamp = timestamp; self.model = model; self.tokens = tokens
        self.cwd = cwd; self.project = project
    }

    private enum CodingKeys: String, CodingKey { case id, timestamp, model, tokens, project }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        model = try c.decode(String.self, forKey: .model)
        tokens = try c.decode(TokenCounts.self, forKey: .tokens)
        project = try c.decodeIfPresent(String.self, forKey: .project)
        cwd = nil
    }
}

public struct LimitWindow: Codable, Equatable, Sendable {
    /// Percent 0...100 (may exceed 100).
    public var utilization: Double
    public var resetsAt: Date?
    public init(utilization: Double, resetsAt: Date?) { self.utilization = utilization; self.resetsAt = resetsAt }
}

public struct LimitsSnapshot: Codable, Equatable, Sendable {
    public var fetchedAt: Date
    public var fiveHour: LimitWindow?
    public var sevenDay: LimitWindow?
    /// Per-model weekly windows keyed by suffix of `seven_day_<name>` (e.g. "opus", "fable").
    public var extra: [String: LimitWindow]
    public var isEstimated: Bool
    public var extraUsage: ExtraUsage?
    public init(fetchedAt: Date, fiveHour: LimitWindow? = nil, sevenDay: LimitWindow? = nil,
                extra: [String: LimitWindow] = [:], isEstimated: Bool = false, extraUsage: ExtraUsage? = nil) {
        self.extraUsage = extraUsage
        self.fetchedAt = fetchedAt; self.fiveHour = fiveHour; self.sevenDay = sevenDay
        self.extra = extra; self.isEstimated = isEstimated
    }
    /// First per-model weekly window (prefers "fable"), for the third card.
    public var weeklyModel: (name: String, window: LimitWindow)? {
        if let w = extra["fable"] { return ("fable", w) }
        guard let k = extra.keys.sorted().first, let w = extra[k] else { return nil }
        return (k, w)
    }
}
