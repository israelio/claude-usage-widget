import SwiftUI
import Charts
import UsageCore

struct PaceCard: View {
    @Environment(\.compact) private var compact
    @State private var selected: Date?
    let samples: [LimitSample]
    let window: LimitWindow?

    private var points: [(Date, Double, Double)] {
        guard let reset = window?.resetsAt else { return [] }
        let start = reset.addingTimeInterval(-Pace.fiveHours)
        return samples.compactMap { s in
            guard s.t >= start, let u = s.fiveHour, let r = s.fiveHourReset,
                  let p = Pace.compute(window: LimitWindow(utilization: u, resetsAt: r), length: Pace.fiveHours, now: s.t)
            else { return nil }
            return (s.t, max(-30, min(30, p.delta)), u)
        }
    }

    var body: some View {
        GlassCard(title: "Pace", icon: "chart.line.uptrend.xyaxis",
                  trailing: AnyView(Text(window?.resetsAt.map { Format.resetsIn($0) } ?? "").font(.caption).foregroundStyle(.secondary))) {
            if points.count < 2 {
                Text("Collecting samples…").font(.caption).foregroundStyle(.secondary).frame(height: compact ? 52 : 70)
            } else {
                let pts = points
                let hit = selected.flatMap { sel in pts.min { abs($0.0.timeIntervalSince(sel)) < abs($1.0.timeIntervalSince(sel)) } }
                Chart {
                    RuleMark(y: .value("Pace", 0)).foregroundStyle(.secondary.opacity(0.5))
                    ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
                        LineMark(x: .value("t", p.0), y: .value("Δ", p.1))
                            .foregroundStyle(p.1 > 0 ? Color.red : Color.green).interpolationMethod(.catmullRom)
                    }
                    if let h = hit {
                        RuleMark(x: .value("t", h.0)).foregroundStyle(.secondary.opacity(0.35))
                        PointMark(x: .value("t", h.0), y: .value("Δ", h.1))
                            .foregroundStyle(h.1 > 0 ? Color.red : Color.green)
                            .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                ChartTip {
                                    let d = Int(h.1.rounded())
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(h.0.formatted(date: .omitted, time: .shortened))
                                        Text("Used \(Int(h.2.rounded()))% · \(d == 0 ? "on" : "\(abs(d)) pts \(d < 0 ? "below" : "above")") even pace")
                                    }
                                }
                            }
                    }
                }
                .chartXSelection(value: $selected)
                .chartYScale(domain: -30...30)
                .chartYAxis { AxisMarks(values: [-30, 0, 30]) { v in
                    AxisValueLabel { Text("\(v.as(Int.self).map { $0 > 0 ? "+\($0)" : "\($0)" } ?? "")%").font(.system(size: 9)) } } }
                .chartXAxis(.hidden)
                .frame(height: compact ? 52 : 70)
            }
        }
    }
}
