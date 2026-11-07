import Foundation

public enum Format {
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
