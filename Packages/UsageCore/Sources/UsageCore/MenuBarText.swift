import Foundation

/// Which pieces appear in the menu bar label.
public struct MenuBarItems: Codable, Equatable, Sendable {
    public var statusDot = true
    public var session = true
    public var pace = true
    public var weekly = true
    public var weeklyModel = false
    public var todayCost = false
    public var resetCountdown = false

    public init(statusDot: Bool = true, session: Bool = true, pace: Bool = true, weekly: Bool = true,
                weeklyModel: Bool = false, todayCost: Bool = false, resetCountdown: Bool = false) {
        self.statusDot = statusDot; self.session = session; self.pace = pace; self.weekly = weekly
        self.weeklyModel = weeklyModel; self.todayCost = todayCost; self.resetCountdown = resetCountdown
    }

    private enum CodingKeys: String, CodingKey { case statusDot, session, pace, weekly, weeklyModel, todayCost, resetCountdown }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        statusDot = try c.decodeIfPresent(Bool.self, forKey: .statusDot) ?? true
        session = try c.decodeIfPresent(Bool.self, forKey: .session) ?? true
        pace = try c.decodeIfPresent(Bool.self, forKey: .pace) ?? true
        weekly = try c.decodeIfPresent(Bool.self, forKey: .weekly) ?? true
        weeklyModel = try c.decodeIfPresent(Bool.self, forKey: .weeklyModel) ?? false
        todayCost = try c.decodeIfPresent(Bool.self, forKey: .todayCost) ?? false
        resetCountdown = try c.decodeIfPresent(Bool.self, forKey: .resetCountdown) ?? false
    }
}

public enum MenuBarText {
    static func dot(_ used: Double) -> String { used >= 85 ? "🔴" : used >= 60 ? "🟠" : "🟢" }

    /// The menu bar label. "…" while there is no data, "" when nothing is enabled.
    public static func make(limits: LimitsSnapshot?, todayCost: Double?, items: MenuBarItems,
                            showRemaining: Bool, now: Date) -> String {
        guard let l = limits, let five = l.fiveHour else { return "…" }
        var head: [String] = []
        var extras: [String] = []
        var leftWordPending = showRemaining
        func pct(_ used: Double) -> String {
            var s = "\(Format.displayPercent(used: used, showRemaining: showRemaining))%"
            if leftWordPending { s += " left"; leftWordPending = false }
            return s
        }
        if items.statusDot { head.append(dot(five.utilization)) }
        if items.session {
            head.append(pct(five.utilization))
            if items.pace, let p = Pace.compute(window: five, length: Pace.fiveHours, now: now) {
                let d = Int(p.delta.rounded()); head.append("\(d >= 0 ? "▲" : "▼")\(abs(d))%")
            }
        }
        if items.weekly, let w = l.sevenDay { extras.append(pct(w.utilization)) }
        if items.weeklyModel, let m = l.weeklyModel { extras.append("\(m.name.capitalized) \(pct(m.window.utilization))") }
        if items.todayCost, let c = todayCost { extras.append(Format.cost(c)) }
        if items.resetCountdown, let r = five.resetsAt { extras.append("⏱ " + Format.resetsIn(r, now: now)) }
        return ([head.joined(separator: " ")].filter { !$0.isEmpty } + extras).joined(separator: " · ")
    }

    /// Short hover text explaining only the items that are shown.
    public static func tooltip(limits: LimitsSnapshot?, todayCost: Double?, items: MenuBarItems,
                               showRemaining: Bool, now: Date) -> String {
        guard let l = limits, let five = l.fiveHour else { return "Claude Usage — loading…" }
        let word = showRemaining ? "left" : "used"
        func pct(_ used: Double) -> Int { Format.displayPercent(used: used, showRemaining: showRemaining) }
        var lines: [String] = []
        if items.statusDot { lines.append("\(dot(five.utilization)) — session colour (orange from 60% used, red from 85%)") }
        if items.session {
            lines.append("\(pct(five.utilization))% — 5-hour session \(word)\(l.isEstimated ? " (estimated)" : "")")
            if items.pace, let p = Pace.compute(window: five, length: Pace.fiveHours, now: now) {
                let d = Int(p.delta.rounded())
                lines.append("\(d >= 0 ? "▲" : "▼")\(abs(d))% — \(d >= 0 ? "above" : "below") an even pace (\(d >= 0 ? "faster" : "slower") than average use)")
            }
        }
        if items.weekly, let w = l.sevenDay { lines.append("\(pct(w.utilization))% — weekly limit \(word)") }
        if items.weeklyModel, let m = l.weeklyModel { lines.append("\(m.name.capitalized): \(pct(m.window.utilization))% \(word)") }
        if items.todayCost, let c = todayCost { lines.append("Today: \(Format.cost(c)) (API-equivalent)") }
        if items.resetCountdown, let r = five.resetsAt { lines.append("\(Format.resetsIn(r, now: now)) — until the 5-hour session resets") }
        return lines.isEmpty ? "Claude Usage" : lines.joined(separator: "\n")
    }
}
