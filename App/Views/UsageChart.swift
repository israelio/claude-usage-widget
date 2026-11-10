import SwiftUI
import Charts
import AppKit
import UsageCore

/// The Usage window's 90-day daily chart: cost or tokens per day with labelled axes and a hover readout. Bars inside
/// the selected range are highlighted and the rest dimmed; clicking a bar selects that day.
struct UsageDailyChart: View {
    let points: [DailyPoint]
    let showCost: Bool
    /// Whether a day is inside the window's current range.
    let isSelected: (Date) -> Bool
    let onSelect: (Date) -> Void
    @State private var hovered: Date?

    private func value(_ p: DailyPoint) -> Double { showCost ? p.cost : Double(p.tokens.total) }
    private func same(_ a: Date, _ b: Date?) -> Bool { b.map { Calendar.current.isDate(a, inSameDayAs: $0) } ?? false }

    var body: some View {
        let hit = hovered.flatMap { h in points.first { same($0.day, h) } }
        let ticks = ChartAxis.tickIndices(count: points.count).map { points[$0].day }
        Chart {
            ForEach(points) { p in
                BarMark(x: .value("Day", p.day, unit: .day), y: .value(showCost ? "Cost" : "Tokens", value(p)))
                    .foregroundStyle(.orange.gradient)
                    .opacity(isSelected(p.day) || same(p.day, hit?.day) ? 1 : 0.3)
            }
            if let h = hit {
                RuleMark(x: .value("Day", h.day, unit: .day))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartTip {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(h.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                if showCost {
                                    Text("\(Format.cost(h.cost)) · \(Format.tokens(h.tokens.total)) tokens")
                                } else {
                                    Text("\(Format.tokens(h.tokens.total)) tokens · \(Format.cost(h.cost))")
                                    Text("In \(Format.tokens(h.tokens.input)) · Out \(Format.tokens(h.tokens.output)) · Cache \(Format.tokens(h.tokens.cache))")
                                        .foregroundStyle(.secondary)
                                }
                                Text("Click to show this day").foregroundStyle(.secondary)
                            }
                        }
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: ticks) { _ in
                AxisTick()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true).font(.system(size: 9))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { v in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel {
                    let x = v.as(Double.self) ?? 0
                    Text(showCost ? Format.cost(x) : Format.tokens(Int(x))).font(.system(size: 9))
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let loc):
                            hovered = day(at: loc, proxy: proxy, geo: geo)
                            if hovered != nil { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                        case .ended:
                            hovered = nil
                            NSCursor.arrow.set()
                        }
                    }
                    .onTapGesture { loc in
                        if let d = day(at: loc, proxy: proxy, geo: geo) { onSelect(d) }
                    }
            }
        }
        .frame(height: 150)
    }

    /// The chart's day under `location` (an overlay coordinate), or nil when it is outside the plot or off any day.
    private func day(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) -> Date? {
        guard let frame = proxy.plotFrame else { return nil }
        let x = location.x - geo[frame].origin.x
        guard x >= 0, x <= geo[frame].width, let date: Date = proxy.value(atX: x) else { return nil }
        return points.first { same($0.day, date) }?.day
    }
}

/// What one point of a trend chart stands for.
enum TrendUnit {
    case day, hour
    /// A 5-hour session, dated at its start.
    case session

    /// Chart caption, e.g. "Daily cost (USD)".
    func caption(showCost: Bool) -> String {
        switch self {
        case .day: return showCost ? "Daily cost (USD)" : "Daily tokens"
        case .hour: return showCost ? "Hourly cost (USD)" : "Hourly tokens"
        case .session: return showCost ? "Cost per session (USD)" : "Tokens per session"
        }
    }

    /// The point of `points` under `date`.
    func point(_ points: [DailyPoint], at date: Date) -> DailyPoint? {
        switch self {
        case .day: return points.first { Calendar.current.isDate($0.day, inSameDayAs: date) }
        case .hour: return points.first { date >= $0.day && date < $0.day.addingTimeInterval(3600) }
        case .session: return points.min { abs($0.day.timeIntervalSince(date) + 9000) < abs($1.day.timeIntervalSince(date) + 9000) }
        }
    }

    func tipTitle(_ d: Date) -> String {
        switch self {
        case .day: return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        case .hour:
            return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + " " + SessionFormat.range(d, d.addingTimeInterval(3600))
        case .session:
            return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + " " + SessionFormat.range(d, d.addingTimeInterval(5 * 3600))
        }
    }

    func axisLabel(_ d: Date) -> String {
        switch self {
        case .day: return d.formatted(.dateTime.day().month(.abbreviated))
        case .hour: return d.formatted(.dateTime.hour().minute())
        case .session: return d.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        }
    }
}

/// Full-width trend of one project or model (per day, per hour of a session, or per session): faint gridlines, a Y axis
/// with 3 ticks, labels on X, and a hover readout.
struct UsageTrendChart: View {
    let points: [DailyPoint]
    let showCost: Bool
    /// The day to emphasise (Day mode); others are dimmed.
    let highlight: Date?
    var unit: TrendUnit = .day
    @State private var hovered: Date?

    private func value(_ p: DailyPoint) -> Double { showCost ? p.cost : Double(p.tokens.total) }
    private func same(_ a: Date, _ b: Date?) -> Bool {
        guard let b else { return false }
        return unit == .day ? Calendar.current.isDate(a, inSameDayAs: b) : a == b
    }

    var body: some View {
        let hit = hovered.flatMap { unit.point(points, at: $0) }
        let emphasised = hit?.day ?? highlight
        let ticks = ChartAxis.tickIndices(count: points.count).map { points[$0].day }
        Chart {
            ForEach(points) { p in
                bar(p).foregroundStyle(.orange.gradient)
                    .opacity(emphasised == nil || same(p.day, emphasised) ? 1 : 0.4)
            }
            if let h = hit {
                RuleMark(x: .value("Time", h.day, unit: unit == .day ? .day : .hour))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartTip {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(unit.tipTitle(h.day))
                                Text(showCost ? "\(Format.cost(h.cost)) · \(Format.tokens(h.tokens.total)) tokens"
                                              : "\(Format.tokens(h.tokens.total)) tokens · \(Format.cost(h.cost))")
                            }
                        }
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: ticks) { v in
                AxisTick()
                AxisValueLabel(centered: unit != .session) { if let d = v.as(Date.self) { Text(unit.axisLabel(d)) } }.font(.system(size: 9))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel {
                    let x = v.as(Double.self) ?? 0
                    Text(showCost ? Format.cost(x) : Format.tokens(Int(x))).font(.system(size: 9))
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let loc):
                            guard let frame = proxy.plotFrame else { hovered = nil; return }
                            let x = loc.x - geo[frame].origin.x
                            if x >= 0, x <= geo[frame].width, let d: Date = proxy.value(atX: x) {
                                hovered = unit.point(points, at: d)?.day
                            } else { hovered = nil }
                        case .ended: hovered = nil
                        }
                    }
            }
        }
        .frame(height: 96)
    }

    @ChartContentBuilder private func bar(_ p: DailyPoint) -> some ChartContent {
        let y = PlottableValue.value(showCost ? "Cost" : "Tokens", value(p))
        switch unit {
        case .day: BarMark(x: .value("Day", p.day, unit: .day), y: y)
        case .hour: BarMark(x: .value("Hour", p.day, unit: .hour), y: y)
        case .session: BarMark(xStart: .value("Start", p.day), xEnd: .value("End", p.day.addingTimeInterval(5 * 3600)), y: y)
        }
    }
}
