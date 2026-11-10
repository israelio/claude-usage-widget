import SwiftUI
import UsageCore

/// What the Usage window is showing: one day, or the last N days ending today.
enum UsageSpan: Equatable {
    case day(Date)
    case days(Int)
}

/// What the Usage window is showing; lives in the window controller so showing the window again (for another bar)
/// can switch the day without recreating the view.
@MainActor
final class UsageViewModel: ObservableObject {
    /// Single source of truth for the window's range.
    @Published var span: UsageSpan = .days(30)
    /// The last day that was selected, so switching back to "Day" returns to it.
    private(set) var lastDay: Date?

    /// The selected day in Day mode, nil in a range mode.
    var day: Date? { if case .day(let d) = span { return d }; return nil }

    func open(day: Date?, days: Int = 30) { select(day.map { .day($0) } ?? .days(days)) }

    func select(_ s: UsageSpan) {
        if case .day(let d) = s { lastDay = Calendar.current.startOfDay(for: d) }
        span = s
    }

    var range: ProjectRange {
        switch span {
        case .day(let d): return .day(d)
        case .days(let n): return .lastDays(n)
        }
    }

    /// Part of the CSV file names: the day, or "30d".
    var fileLabel: String {
        switch span {
        case .day(let d): return DayKey.string(d)
        case .days(let n): return "\(n)d"
        }
    }
}
