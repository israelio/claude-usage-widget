import Foundation

public struct AlertSettings: Codable, Equatable, Sendable {
    public var thresholds: [Int] = [50, 75, 90]
    public var burnRate = true
    public var resetNotice = true
    public var dailyDigest = true
    public var weeklyDigest = true
    public var digestHour = 18
    public var quietStartHour: Int? = nil
    public var quietEndHour: Int? = nil
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case thresholds, burnRate, resetNotice, dailyDigest, weeklyDigest, digestHour, quietStartHour, quietEndHour
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AlertSettings()
        thresholds = try c.decodeIfPresent([Int].self, forKey: .thresholds) ?? d.thresholds
        burnRate = try c.decodeIfPresent(Bool.self, forKey: .burnRate) ?? d.burnRate
        resetNotice = try c.decodeIfPresent(Bool.self, forKey: .resetNotice) ?? d.resetNotice
        dailyDigest = try c.decodeIfPresent(Bool.self, forKey: .dailyDigest) ?? d.dailyDigest
        weeklyDigest = try c.decodeIfPresent(Bool.self, forKey: .weeklyDigest) ?? d.weeklyDigest
        digestHour = try c.decodeIfPresent(Int.self, forKey: .digestHour) ?? d.digestHour
        quietStartHour = try c.decodeIfPresent(Int.self, forKey: .quietStartHour)
        quietEndHour = try c.decodeIfPresent(Int.self, forKey: .quietEndHour)
    }
}

public struct FiredState: Codable, Equatable, Sendable {
    public var keys: [String] = []
    /// Last adopted reset time per window tag; gives each window a stable identity despite jitter.
    public var lastReset: [String: Date] = [:]
    public init() {}

    private enum CodingKeys: String, CodingKey { case keys, lastReset }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keys = try c.decodeIfPresent([String].self, forKey: .keys) ?? []
        lastReset = try c.decodeIfPresent([String: Date].self, forKey: .lastReset) ?? [:]
    }

    /// Stable key for a window: reuses the stored reset time if the new one is within 600s, else adopts the new one.
    mutating func windowKey(tag: String, reset: Date?) -> String {
        guard let r = reset else { return "none" }
        if let stored = lastReset[tag], abs(r.timeIntervalSince(stored)) <= 600 {
            return String(Int(stored.timeIntervalSince1970))
        }
        lastReset[tag] = r
        return String(Int(r.timeIntervalSince1970))
    }

    /// Like `windowKey` but never changes state.
    func peekWindowKey(tag: String, reset: Date?) -> String {
        guard let r = reset else { return "none" }
        if let stored = lastReset[tag], abs(r.timeIntervalSince(stored)) <= 600 {
            return String(Int(stored.timeIntervalSince1970))
        }
        return String(Int(r.timeIntervalSince1970))
    }
    /// Returns true if `key` was not seen before (and records it).
    public mutating func fire(_ key: String) -> Bool {
        guard !keys.contains(key) else { return false }
        keys.append(key)
        if keys.count > 300 { keys.removeFirst(keys.count - 300) }
        return true
    }
}

public struct AlertMessage: Equatable, Sendable {
    public var id: String
    public var title: String
    public var body: String
}

public enum AlertEngine {
    public static func isQuiet(_ s: AlertSettings, now: Date, calendar: Calendar = .current) -> Bool {
        guard let a = s.quietStartHour, let b = s.quietEndHour, a != b else { return false }
        let h = calendar.component(.hour, from: now)
        return a < b ? (h >= a && h < b) : (h >= a || h < b)
    }

    public static func evaluate(current: LimitsSnapshot, previous: LimitsSnapshot?, settings: AlertSettings,
                                fired: inout FiredState, now: Date, calendar: Calendar = .current) -> [AlertMessage] {
        if isQuiet(settings, now: now, calendar: calendar) { return [] }
        var out: [AlertMessage] = []
        let windows: [(tag: String, name: String, cur: LimitWindow?, prev: LimitWindow?, len: TimeInterval)] = [
            ("5h", "5-hour session", current.fiveHour, previous?.fiveHour, Pace.fiveHours),
            ("7d", "weekly limit", current.sevenDay, previous?.sevenDay, Pace.week),
        ]
        for w in windows {
            guard let cur = w.cur else { continue }
            // Compute the ended window's key before adopting the current one.
            let prevKey = w.prev.map { fired.peekWindowKey(tag: w.tag, reset: $0.resetsAt) }
            let rkey = fired.windowKey(tag: w.tag, reset: cur.resetsAt)
            let pct = Int(cur.utilization.rounded())

            let sorted = settings.thresholds.sorted()
            if let top = sorted.last(where: { cur.utilization >= Double($0) }) {
                for lower in sorted where lower < top { _ = fired.fire("thr-\(w.tag)-\(rkey)-\(lower)") }
                if fired.fire("thr-\(w.tag)-\(rkey)-\(top)") {
                    out.append(AlertMessage(id: "thr-\(w.tag)-\(rkey)-\(top)", title: "\(top)% of \(w.name) used",
                                            body: "You're at \(pct)%." + resetSuffix(cur, now: now)))
                }
            }
            if settings.burnRate, cur.utilization >= 20, cur.utilization < 100,
               let p = Pace.compute(window: cur, length: w.len, now: now), p.status == .over,
               fired.fire("burn-\(w.tag)-\(rkey)") {
                out.append(AlertMessage(id: "burn-\(w.tag)-\(rkey)", title: "Burning through your \(w.name)",
                                        body: "At this pace you'll hit ~\(Int(p.projected.rounded()))% before it resets."))
            }
            if settings.resetNotice, let prev = w.prev, let pr = prev.resetsAt, let pk = prevKey {
                let expired = pr <= now && cur.utilization < prev.utilization
                let rolled = prev.utilization >= 75 && (cur.resetsAt.map { $0.timeIntervalSince(pr) > 600 } ?? true)
                if (expired || rolled), fired.fire("reset-\(w.tag)-\(pk)") {
                    out.append(AlertMessage(id: "reset-\(w.tag)-\(pk)", title: "\(w.name.capitalized) reset",
                                            body: "Usage is back to \(pct)%."))
                }
            }
        }
        return out
    }

    public static func digests(summary: UsageSummary, settings: AlertSettings, fired: inout FiredState,
                               now: Date, calendar: Calendar = .current) -> [AlertMessage] {
        guard calendar.component(.hour, from: now) >= settings.digestHour,
              !isQuiet(settings, now: now, calendar: calendar) else { return [] }
        let day = DayKey.string(now, calendar: calendar)
        var out: [AlertMessage] = []
        func line(_ t: Totals) -> String {
            "\(Format.tokens(t.tokens.total)) tokens · \(Format.cost(t.cost)) (API-equivalent)"
        }
        if settings.dailyDigest, fired.fire("digest-d-\(day)") {
            out.append(AlertMessage(id: "digest-d-\(day)", title: "Today's Claude usage", body: line(summary.today)))
        }
        if settings.weeklyDigest, calendar.component(.weekday, from: now) == 2, fired.fire("digest-w-\(day)") {
            out.append(AlertMessage(id: "digest-w-\(day)", title: "Last 7 days of Claude usage", body: line(summary.last7)))
        }
        return out
    }

    private static func resetSuffix(_ w: LimitWindow, now: Date) -> String {
        guard let r = w.resetsAt else { return "" }
        return " Resets in \(Format.resetsIn(r, now: now))."
    }
}
