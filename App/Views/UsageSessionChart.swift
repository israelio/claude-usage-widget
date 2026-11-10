import SwiftUI
import Charts
import AppKit
import UsageCore

/// Date/time text for sessions ("14:00–19:00", "Sun 9 Nov 14:00–19:00").
enum SessionFormat {
    static func range(_ a: Date, _ b: Date) -> String {
        a.formatted(.dateTime.hour().minute()) + "–" + b.formatted(.dateTime.hour().minute())
    }
    static func full(_ s: UsageSession) -> String {
        s.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + " " + range(s.start, s.end)
    }
}

/// The Usage window's top chart in Sessions mode: one bar per 5-hour session across the range (x = start, y = cost or
/// tokens). Bars of the selected session(s) are highlighted and the rest dimmed; clicking a bar selects that session.
struct UsageSessionChart: View {
    let sessions: [UsageSession]
    /// The visible time range (start of the first day ... end of today).
    let domain: ClosedRange<Date>
    let showCost: Bool
    let prices: PriceTable
    let now: Date
    /// Whether a session is inside the window's current selection.
    let isSelected: (UsageSession) -> Bool
    let onSelect: (UsageSession) -> Void
    @State private var hovered: Int?

    private func cost(_ s: UsageSession) -> Double { s.cost(prices: prices) }
    private func value(_ s: UsageSession) -> Double { showCost ? cost(s) : Double(s.tokens.total) }

    /// Tick dates: every 6 hours up to 3 days, otherwise at midnights every `strideDays`.
    private var ticks: [Date] {
        let cal = Calendar.current
        let days = max(1, Int((domain.upperBound.timeIntervalSince(domain.lowerBound) / 86400).rounded()))
        let step = days <= 3 ? 6 * 3600.0 : 0
        var out: [Date] = []
        if step > 0 {
            var t = domain.lowerBound
            while t <= domain.upperBound { out.append(t); t.addTimeInterval(step) }
        } else {
            let s = ChartAxis.strideDays(forCount: days)
            var d = cal.startOfDay(for: domain.lowerBound)
            while d <= domain.upperBound { out.append(d); d = cal.date(byAdding: .day, value: s, to: d)! }
        }
        return out
    }

    private func label(_ d: Date) -> String {
        let midnight = Calendar.current.startOfDay(for: d) == d
        let days = domain.upperBound.timeIntervalSince(domain.lowerBound) / 86400
        if days > 3 || midnight { return d.formatted(.dateTime.weekday(.abbreviated).day()) }
        return d.formatted(.dateTime.hour().minute())
    }

    var body: some View {
        let hit = hovered.flatMap { h in sessions.first { $0.id == h } }
        Chart {
            ForEach(sessions) { s in
                RectangleMark(xStart: .value("Start", s.start), xEnd: .value("End", s.end),
                        yStart: .value("Base", 0.0), yEnd: .value(showCost ? "Cost" : "Tokens", value(s)))
                    .foregroundStyle(.orange.gradient)
                    .opacity(isSelected(s) || s.id == hit?.id ? 1 : 0.3)
            }
            if let h = hit {
                RuleMark(x: .value("Start", h.start))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartTip {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(SessionFormat.full(h) + (h.isActive(now: now) ? " · active now" : ""))
                                let c = Format.cost(cost(h)), t = Format.tokens(h.tokens.total) + " tokens"
                                let p = "\(h.projectCount) project" + (h.projectCount == 1 ? "" : "s")
                                Text(showCost ? "\(c) · \(t) · \(p)" : "\(t) · \(c) · \(p)")
                                Text("Click to show this session").foregroundStyle(.secondary)
                            }
                        }
                    }
            }
        }
        .chartXScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: ticks) { v in
                AxisTick()
                AxisValueLabel(centered: false) { if let d = v.as(Date.self) { Text(label(d)) } }.font(.system(size: 9))
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
                            hovered = session(at: loc, proxy: proxy, geo: geo)?.id
                            if hovered != nil { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                        case .ended:
                            hovered = nil
                            NSCursor.arrow.set()
                        }
                    }
                    .onTapGesture { loc in
                        if let s = session(at: loc, proxy: proxy, geo: geo) { onSelect(s) }
                    }
            }
        }
        .frame(height: 150)
    }

    /// The session nearest to `location` (an overlay coordinate), within a small tolerance because bars are thin.
    private func session(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) -> UsageSession? {
        guard let frame = proxy.plotFrame else { return nil }
        let x = location.x - geo[frame].origin.x
        guard x >= 0, x <= geo[frame].width, let date: Date = proxy.value(atX: x) else { return nil }
        let tol = domain.upperBound.timeIntervalSince(domain.lowerBound) / 120
        func dist(_ s: UsageSession) -> TimeInterval {
            date < s.start ? s.start.timeIntervalSince(date) : (date > s.end ? date.timeIntervalSince(s.end) : 0)
        }
        return sessions.filter { dist($0) <= tol }.min { dist($0) < dist($1) }
    }
}
