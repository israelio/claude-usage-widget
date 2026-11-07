import SwiftUI
import Charts
import UsageCore

struct DailyCard: View {
    @ObservedObject var service: UsageService
    @State private var range = 7

    var body: some View {
        let data = service.daily(days: range)
        GlassCard(title: "Daily Usage", icon: "chart.bar.fill",
                  trailing: AnyView(Picker("", selection: $range) {
                      Text("7d").tag(7); Text("30d").tag(30); Text("90d").tag(90)
                  }.pickerStyle(.segmented).labelsHidden().frame(width: 130))) {
            Chart(data) { p in
                BarMark(x: .value("Day", p.day, unit: .day), y: .value("Cost", p.cost))
                    .foregroundStyle(LinearGradient(colors: [.green, .orange], startPoint: .bottom, endPoint: .top))
            }
            .chartYAxis { AxisMarks { v in AxisValueLabel { Text(Format.cost(v.as(Double.self) ?? 0)).font(.system(size: 9)) } } }
            .frame(height: 90)
        }
    }
}
