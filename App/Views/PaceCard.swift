import SwiftUI
import Charts
import UsageCore

struct PaceCard: View {
    let samples: [LimitSample]
    let window: LimitWindow?

    private var points: [(Date, Double)] {
        guard let reset = window?.resetsAt else { return [] }
        let start = reset.addingTimeInterval(-Pace.fiveHours)
        return samples.compactMap { s in
            guard s.t >= start, let u = s.fiveHour, let r = s.fiveHourReset,
                  let p = Pace.compute(window: LimitWindow(utilization: u, resetsAt: r), length: Pace.fiveHours, now: s.t)
            else { return nil }
            return (s.t, max(-30, min(30, p.delta)))
        }
    }

    var body: some View {
        GlassCard(title: "Pace", icon: "chart.line.uptrend.xyaxis",
                  trailing: AnyView(Text(window?.resetsAt.map { Format.resetsIn($0) } ?? "").font(.caption).foregroundStyle(.secondary))) {
            if points.count < 2 {
                Text("Collecting samples…").font(.caption).foregroundStyle(.secondary).frame(height: 70)
            } else {
                Chart {
                    RuleMark(y: .value("Pace", 0)).foregroundStyle(.secondary.opacity(0.5))
                    ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                        LineMark(x: .value("t", p.0), y: .value("Δ", p.1))
                            .foregroundStyle(p.1 > 0 ? Color.red : Color.green).interpolationMethod(.catmullRom)
                    }
                }
                .chartYScale(domain: -30...30)
                .chartYAxis { AxisMarks(values: [-30, 0, 30]) { v in
                    AxisValueLabel { Text("\(v.as(Int.self).map { $0 > 0 ? "+\($0)" : "\($0)" } ?? "")%").font(.system(size: 9)) } } }
                .chartXAxis(.hidden)
                .frame(height: 70)
            }
        }
    }
}
