import Foundation

/// Pure helpers for the project trend chart's axes and the Usage window's heading.
public enum ChartAxis {
    /// Days between X axis labels for a chart of `count` daily points.
    public static func strideDays(forCount count: Int) -> Int {
        switch count {
        case ...7: return 1
        case ...14: return 2
        case ...31: return 5
        case ...60: return 10
        default: return 15
        }
    }

    /// Indices of the points to label: every `strideDays`, always including the first and the last. A stride tick
    /// that would crowd the last label (closer than half a stride) is dropped.
    public static func tickIndices(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let s = strideDays(forCount: count)
        let last = count - 1
        var out = Array(stride(from: 0, to: count, by: s))
        if out.last != last {
            if let l = out.last, last - l < (s + 1) / 2, out.count > 1 { out.removeLast() }
            out.append(last)
        }
        return out
    }
}

/// The heading line of the Usage window ("Saturday, 7 November 2026 · 6 projects"; for sessions "Sun 9 Nov · 14:00–19:00 · 4 projects",
/// or "Last 7 days · 18 sessions · 63 projects" with `sessionsTitle`).
public enum ProjectRangeLabel {
    public static func make(range: ProjectRange, count: Int, noun: String = "project", sessionsTitle: String? = nil, now: Date,
                            calendar: Calendar = .current, locale: Locale = .current) -> String {
        func fmt(_ d: Date, _ pattern: String) -> String {
            let f = DateFormatter()
            f.calendar = calendar; f.timeZone = calendar.timeZone; f.locale = locale
            f.setLocalizedDateFormatFromTemplate(pattern)
            return f.string(from: d)
        }
        let label = "\(count) \(noun)" + (count == 1 ? "" : "s")
        let head: String
        switch range {
        case .session(let s):
            let day = fmt(s.start, "EEEdMMM"), from = fmt(s.start, "Hmm"), to = fmt(s.end, "Hmm")
            head = "\(day) · \(from)–\(to)"
            return "\(head) · \(label)" + (s.isActive(now: now) ? " · active" : "")
        case .sessions(let list):
            return "\(sessionsTitle ?? "Sessions") · \(list.count) session" + (list.count == 1 ? "" : "s") + " · \(label)"
        case .day(let d):
            head = fmt(d, "EEEEdMMMMyyyy")
        case .lastDays(let n), .window(_, let n):
            var end = now
            if case .window(let e, _) = range { end = e }
            let start = calendar.date(byAdding: .day, value: -(max(1, n) - 1), to: end)!
            head = "Last \(n) days (\(fmt(start, "dMMM")) – \(fmt(end, "dMMM")))"
        }
        return "\(head) · \(label)"
    }
}
