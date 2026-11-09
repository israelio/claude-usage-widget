import Foundation

public enum Format {
    /// The number to display for a utilization percent: used, or 100 - used (clamped 0...100) when showing what's left.
    public static func displayPercent(used: Double, showRemaining: Bool) -> Int {
        let v = showRemaining ? 100 - used : used
        return Int(min(100, max(0, v)).rounded())
    }
    public static func tokens(_ n: Int) -> String {
        let d = Double(n)
        switch n {
        case ..<1_000: return "\(n)"
        case ..<1_000_000: return String(format: "%.1fk", d / 1_000)
        case ..<1_000_000_000: return String(format: "%.1fM", d / 1_000_000)
        default: return String(format: "%.1fB", d / 1_000_000_000)
        }
    }
    public static func cost(_ v: Double) -> String {
        v >= 1000 ? String(format: "$%.1fk", v / 1000) : String(format: "$%.2f", v)
    }
    public static func resetsIn(_ date: Date, now: Date = Date()) -> String {
        let secs = max(0, Int(date.timeIntervalSince(now)))
        let d = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60
        if d > 0 { return "\(d) day\(d == 1 ? "" : "s") \(h)h \(m)m" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
