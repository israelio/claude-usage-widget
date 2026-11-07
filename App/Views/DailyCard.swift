import SwiftUI
import Charts
import UsageCore

struct DailyCard: View {
    @ObservedObject var service: UsageService
    @State private var range = 7
    @State private var selected: Date?

    var body: some View {
        let data = service.daily(days: range)
        GlassCard(title: "Daily Usage", icon: "chart.bar.fill",
                  trailing: AnyView(Picker("", selection: $range) {
                      Text("7d").tag(7); Text("30d").tag(30); Text("90d").tag(90)
                  }.pickerStyle(.segmented).labelsHidden().frame(width: 130))) {
            let hit = selected.flatMap { sel in data.first { Calendar.current.isDate($0.day, inSameDayAs: sel) } }
            Chart {
                ForEach(data) { p in
                    BarMark(x: .value("Day", p.day, unit: .day), y: .value("Cost", p.cost))
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
                                    Text("\(Format.cost(h.cost)) · \(Format.tokens(h.tokens.total)) tokens")
                                }
                            }
                        }
                }
            }
            .chartXSelection(value: $selected)
            .chartYAxis { AxisMarks { v in AxisValueLabel { Text(Format.cost(v.as(Double.self) ?? 0)).font(.system(size: 9)) } } }
            .frame(height: 90)
        }
    }
}
