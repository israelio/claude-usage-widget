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
                if let pace {
                    Text(Theme.label(for: pace.status)).foregroundStyle(Theme.color(for: pace.status)).fontWeight(.semibold)
                        .help(statusHelp(pace))
                }
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func header(_ pace: Pace?) -> some View {
        HStack(spacing: 6) {
            Text("\(Int(window.utilization.rounded()))%").fontWeight(.bold)
                .foregroundStyle(Theme.color(forUtilization: window.utilization))
                .help(usedHelp)
            if let pace {
                let d = Int(pace.delta.rounded())
                Text("\(d >= 0 ? "▲" : "▼")\(abs(d))%").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(d > 0 ? .red : .green)
                    .help(deltaHelp(pace, d))
            }
        }
    }

    // MARK: tooltips

    private var usedPct: Int { Int(window.utilization.rounded()) }

    private var usedHelp: String {
        var t = "\(usedPct)% of your \(title.lowercased()) allowance is used."
        if let r = window.resetsAt { t += " It resets in \(Format.resetsIn(r))." }
        return t
    }

    private func deltaHelp(_ pace: Pace, _ d: Int) -> String {
        let expected = Int(pace.expected.rounded())
        let base = "Compared with an even pace: about \(expected)% of this window has passed, so using it evenly would put you at \(expected)%. You are at \(usedPct)%."
        if d < 0 { return "\(abs(d)) points BELOW an even pace (good, you have room). " + base }
        if d > 0 { return "\(abs(d)) points ABOVE an even pace (you're using it faster than the window refills). " + base }
        return "Exactly on an even pace. " + base
    }

    private func statusHelp(_ pace: Pace) -> String {
        let proj = Int(pace.projected.rounded())
        switch pace.status {
        case .onTrack: return "At your current rate you would reach about \(proj)% by the reset, within the limit."
        case .ahead: return "At your current rate you would reach about \(proj)% by the reset, right at the limit."
        case .over: return "At your current rate you would hit the limit before it resets (projected about \(proj)%)."
        }
    }
}
