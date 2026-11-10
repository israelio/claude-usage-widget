import SwiftUI
import UsageCore

/// What the Usage window is showing: one day, or the last N days ending today; in Sessions granularity one 5-hour
/// session (by its start epoch hour), or the sessions of the last N days.
enum UsageSpan: Equatable {
    case day(Date)
    case days(Int)
    case session(Int)
    case sessions(Int)

    var isSessions: Bool {
        switch self {
        case .session, .sessions: return true
        case .day, .days: return false
        }
    }
}

/// What the Usage window is showing; lives in the window controller so showing the window again (for another bar)
/// can switch the day without recreating the view.
@MainActor
final class UsageViewModel: ObservableObject {
    /// Single source of truth for the window's range.
    @Published var span: UsageSpan = .days(30)
    /// The last day that was selected, so switching back to "Day" returns to it.
    private(set) var lastDay: Date?
    /// The last session that was selected (start epoch hour), so switching back to "Session" returns to it.
    private(set) var lastSession: Int?

    /// The selected day in Day mode, nil in a range mode.
    var day: Date? { if case .day(let d) = span { return d }; return nil }
    /// The selected session's start epoch hour in Sessions "Session" mode, nil otherwise.
    var sessionId: Int? { if case .session(let i) = span { return i }; return nil }

    /// - sessions: open in Sessions granularity (7 days) instead of the last `days` days. Ignored when `day` is given.
    func open(day: Date?, days: Int = 30, sessions: Bool = false) {
        if let day { select(.day(day)) } else { select(sessions ? .sessions(7) : .days(days)) }
    }

    func select(_ s: UsageSpan) {
        if case .day(let d) = s { lastDay = Calendar.current.startOfDay(for: d) }
        if case .session(let i) = s { lastSession = i }
        span = s
    }

    /// The breakdown range; `sessions` is every known session (oldest first) and is only used in Sessions granularity.
    func range(sessions: [UsageSession], now: Date = Date()) -> ProjectRange {
        switch span {
        case .day(let d): return .day(d)
        case .days(let n): return .lastDays(n)
        case .session(let i): return sessions.first { $0.id == i }.map { .session($0) } ?? .sessions([])
        case .sessions(let n): return .sessions(SessionBuilder.recent(sessions, days: n, now: now))
        }
    }

    /// Unit of the expanded rows' trend charts.
    var trendUnit: TrendUnit {
        switch span {
        case .day, .days: return .day
        case .session: return .hour
        case .sessions: return .session
        }
    }

    /// Part of the CSV file names: the day, or "30d".
    var fileLabel: String {
        switch span {
        case .day(let d): return DayKey.string(d)
        case .days(let n): return "\(n)d"
        case .session(let i):
            let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmm"
            return "session-" + f.string(from: Date(timeIntervalSince1970: Double(i) * 3600))
        case .sessions(let n): return "sessions-\(n)d"
        }
    }
}
