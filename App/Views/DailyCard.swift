import SwiftUI
import Charts
import UsageCore

struct DailyCard: View {
    @Environment(\.compact) private var compact
    @ObservedObject var service: UsageService
    /// Called with the day of a clicked bar (opens the Usage window on that day).
    var openUsage: (Date?) -> Void = { _ in }
    @State private var range = 7
    @State private var selected: Date?
    @AppStorage("dailyChartMetric") private var metric = "cost"

    private var showCost: Bool { metric == "cost" }
    private func value(_ p: DailyPoint) -> Double { showCost ? p.cost : Double(p.tokens.total) }
    private func axisLabel(_ v: Double) -> String { showCost ? Format.cost(v) : Format.tokens(Int(v)) }

    var body: some View {
        let data = service.daily(days: range)
        GlassCard(title: "Daily Usage", icon: "chart.bar.fill",
                  trailing: AnyView(HStack(spacing: 16) {
                      Picker("", selection: $metric) {
                          Image(systemName: "dollarsign").tag("cost")
                          Image(systemName: "number").tag("tokens")
                      }.pickerStyle(.segmented).labelsHidden().frame(width: 56)
                          .help("Chart metric: cost ($) or tokens (#)")
                      Picker("", selection: $range) {
                          Text("7d").tag(7); Text("30d").tag(30); Text("90d").tag(90)
                      }.pickerStyle(.segmented).labelsHidden().frame(width: 116)
                  })) {
            let hit = selected.flatMap { sel in data.first { Calendar.current.isDate($0.day, inSameDayAs: sel) } }
            Chart {
                ForEach(data) { p in
                    BarMark(x: .value("Day", p.day, unit: .day), y: .value(showCost ? "Cost" : "Tokens", value(p)))
                        .foregroundStyle(LinearGradient(colors: [.green, .orange], startPoint: .bottom, endPoint: .top))
                        .opacity(hit == nil || hit?.id == p.id ? 1 : 0.45)
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
                                    Text("Click for usage details").foregroundStyle(.secondary)
                                }
                            }
                        }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let loc):
                                selected = day(at: loc, proxy: proxy, geo: geo, in: data)
                                if selected != nil { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                            case .ended:
                                selected = nil
                                NSCursor.arrow.set()
                            }
                        }
                        .onTapGesture { loc in
                            if let d = day(at: loc, proxy: proxy, geo: geo, in: data) { openUsage(d) }
                        }
                }
            }
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: compact ? 2 : 4)) { v in AxisValueLabel { Text(axisLabel(v.as(Double.self) ?? 0)).font(.system(size: 9)) } } }
            .frame(height: compact ? 84 : 90)
            .padding(.top, 4)
        }
    }

    /// The chart's day under `location` (an overlay coordinate), or nil when it is outside the plot or off any day.
    private func day(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy, in data: [DailyPoint]) -> Date? {
        guard let frame = proxy.plotFrame else { return nil }
        let x = location.x - geo[frame].origin.x
        guard x >= 0, x <= geo[frame].width, let date: Date = proxy.value(atX: x) else { return nil }
        return data.first { Calendar.current.isDate($0.day, inSameDayAs: date) }?.day
    }
}
