import SwiftUI
import UsageCore

struct LimitCard: View {
    let title: String
    let icon: String
    let window: LimitWindow
    let length: TimeInterval
    let estimated: Bool

    var body: some View {
        let pace = Pace.compute(window: window, length: length, now: Date())
        GlassCard(title: title, icon: icon, trailing: AnyView(header(pace))) {
            ProgressView(value: min(1, max(0, window.utilization / 100)))
                .tint(Theme.color(forUtilization: window.utilization))
            HStack {
                if let r = window.resetsAt {
                    Text("Resets in: \(Format.resetsIn(r)) at \(r.formatted(date: .omitted, time: .shortened))")
                } else { Text(estimated ? "Estimated from local logs" : "Rolling window") }
                Spacer()
                if let pace { Text(Theme.label(for: pace.status)).foregroundStyle(Theme.color(for: pace.status)).fontWeight(.semibold) }
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func header(_ pace: Pace?) -> some View {
        HStack(spacing: 6) {
            Text("\(Int(window.utilization.rounded()))%").fontWeight(.bold)
                .foregroundStyle(Theme.color(forUtilization: window.utilization))
            if let pace {
                let d = Int(pace.delta.rounded())
                Text("\(d >= 0 ? "▲" : "▼")\(abs(d))%").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(d > 0 ? .red : .green)
            }
        }
    }
}
