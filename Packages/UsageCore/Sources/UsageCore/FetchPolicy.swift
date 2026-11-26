import Foundation

/// Decides when the usage API may be called. The endpoint has a tiny request budget, so calls are driven by
/// local activity (new Claude Code log records) and kept far apart otherwise.
public enum FetchPolicy {
    /// Never faster than this for manual refreshes or a window reset.
    public static let manualGap: TimeInterval = 60

    public static func shouldFetch(now: Date, lastFetch: Date?, newLogActivitySinceLastFetch: Bool, windowResetPassed: Bool,
                                   manual: Bool, blockedUntil: Date?, minGap: TimeInterval = 300,
                                   idleGap: TimeInterval = 900) -> Bool {
        if let b = blockedUntil, b > now { return false }
        guard let last = lastFetch else { return true }
        let age = now.timeIntervalSince(last)
        if windowResetPassed || manual { return age >= manualGap }
        if newLogActivitySinceLastFetch { return age >= minGap }
        return age >= idleGap
    }

    /// True when a known window has reset since `lastFetch`, so the stored percentages are out of date.
    public static func windowResetPassed(limits: LimitsSnapshot?, lastFetch: Date?, now: Date) -> Bool {
        guard let l = limits, !l.isEstimated, let last = lastFetch else { return false }
        let windows = [l.fiveHour, l.sevenDay] + Array(l.extra.values).map { Optional($0) }
        return windows.contains { w in
            guard let r = w?.resetsAt else { return false }
            return r <= now && last < r
        }
    }

    /// Gaps are doubled for an hour after a rate-limit block ends, to stay clear of the limit.
    public static func gapMultiplier(sinceLastBlock: TimeInterval?) -> Double {
        guard let s = sinceLastBlock, s >= 0, s < 3600 else { return 1.0 }
        return 2.0
    }
}

/// The last successful usage fetch, kept on disk so a relaunch doesn't spend a request.
public struct LastFetch: Codable, Equatable, Sendable {
    public var lastFetchSuccess: Date
    public var limits: LimitsSnapshot
    public init(lastFetchSuccess: Date, limits: LimitsSnapshot) { self.lastFetchSuccess = lastFetchSuccess; self.limits = limits }
    public static let maxAge: TimeInterval = 6 * 3600

    public func save(to url: URL) { Persisted.save(self, to: url) }
    /// Nil when missing, undecodable, estimated, or older than `maxAge` with no window still in force. A snapshot
    /// whose weekly window hasn't reset yet is kept past `maxAge` (e.g. a relaunch after a reboot while the API is
    /// unreachable), so the app shows the last real weekly figure instead of the local token estimate.
    public static func load(from url: URL, now: Date = Date()) -> LastFetch? {
        guard let v: LastFetch = Persisted.load(from: url), !v.limits.isEstimated else { return nil }
        guard now.timeIntervalSince(v.lastFetchSuccess) < maxAge || v.limits.hasWindowInForce(now: now) else { return nil }
        return v
    }
}

public extension LimitsSnapshot {
    private static func expired(_ w: LimitWindow?, now: Date) -> Bool { w?.resetsAt.map { $0 <= now } ?? false }

    /// True when some window has a known reset time that is still ahead.
    func hasWindowInForce(now: Date) -> Bool {
        ([fiveHour, sevenDay] + extra.values.map { Optional($0) }).contains { w in
            w?.resetsAt.map { $0 > now } ?? false
        }
    }

    /// A real snapshot kept after a failed refresh: windows whose reset time has passed show pre-reset usage, so
    /// they are replaced by the estimate's (5-hour, weekly) or dropped (per-model); windows still in force are kept.
    /// An estimated snapshot is returned unchanged.
    func replacingExpired(with estimate: LimitsSnapshot, now: Date) -> LimitsSnapshot {
        guard !isEstimated else { return self }
        var s = self
        if Self.expired(fiveHour, now: now) { s.fiveHour = estimate.fiveHour }
        if Self.expired(sevenDay, now: now) { s.sevenDay = estimate.sevenDay }
        s.extra = extra.filter { !Self.expired($0.value, now: now) }
        return s
    }
}

/// The plan/profile response and when it was fetched.
public struct CachedPlan: Codable, Equatable, Sendable {
    public var plan: PlanInfo
    public var fetchedAt: Date
    public init(plan: PlanInfo, fetchedAt: Date) { self.plan = plan; self.fetchedAt = fetchedAt }
    public func save(to url: URL) { Persisted.save(self, to: url) }
    public static func load(from url: URL) -> CachedPlan? { Persisted.load(from: url) }
}

enum Persisted {
    static func save<T: Encodable>(_ v: T, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(v) { try? d.write(to: url, options: .atomic) }
    }
    static func load<T: Decodable>(from url: URL) -> T? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(T.self, from: d)
    }
}
