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

/// Full-width daily trend of one project or model: faint gridlines, a Y axis with 3 ticks, date labels on X, and a hover readout.
struct UsageTrendChart: View {
    let points: [DailyPoint]
    let showCost: Bool
    /// The day to emphasise (Day mode); others are dimmed.
    let highlight: Date?
    @State private var hovered: Date?

    private func value(_ p: DailyPoint) -> Double { showCost ? p.cost : Double(p.tokens.total) }
    private func same(_ a: Date, _ b: Date?) -> Bool { b.map { Calendar.current.isDate(a, inSameDayAs: $0) } ?? false }

    var body: some View {
        let hit = hovered.flatMap { h in points.first { same($0.day, h) } }
        let emphasised = hit?.day ?? highlight
        let ticks = ChartAxis.tickIndices(count: points.count).map { points[$0].day }
        Chart {
            ForEach(points) { p in
                BarMark(x: .value("Day", p.day, unit: .day), y: .value(showCost ? "Cost" : "Tokens", value(p)))
                    .foregroundStyle(.orange.gradient)
                    .opacity(emphasised == nil || same(p.day, emphasised) ? 1 : 0.4)
            }
            if let h = hit {
                RuleMark(x: .value("Day", h.day, unit: .day))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartTip {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(h.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                Text(showCost ? "\(Format.cost(h.cost)) · \(Format.tokens(h.tokens.total)) tokens"
                                              : "\(Format.tokens(h.tokens.total)) tokens · \(Format.cost(h.cost))")
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
                                hovered = points.first { same($0.day, d) }?.day
                            } else { hovered = nil }
                        case .ended: hovered = nil
                        }
                    }
            }
        }
        .frame(height: 96)
    }
}
