import SwiftUI
import UsageCore

struct PlanCard: View {
    let plan: PlanInfo
    let extraUsage: ExtraUsage?

    var body: some View {
        GlassCard(title: "Plan", icon: "creditcard") {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(plan.planName).fontWeight(.semibold)
                    Spacer()
                    Text(plan.status).foregroundStyle(plan.status == "Active" ? Color.green : Color.orange)
                }
                if let r = plan.nextRenewal {
                    HStack {
                        Text("Renews ≈ \(Self.day.string(from: r)) · \(Self.relative(r))").foregroundStyle(.secondary)
                        Spacer()
                    }
                    .help(helpText)
                }
                HStack {
                    Text("Extra usage").foregroundStyle(.secondary)
                    Spacer()
                    Text(extraText)
                }
            }
            .font(.system(size: 12))
        }
    }

    private var extraText: String {
        guard let e = extraUsage, e.enabled else { return "off" }
        var s = Self.money(e.usedAmount, e.currency)
        if let l = e.limitAmount { s += " of " + Self.money(l, e.currency) }
        return s
    }

    private var helpText: String {
        let start = plan.subscriptionStart.map { Self.full.string(from: $0) } ?? "unknown"
        return "Estimated as the next monthly anniversary of your subscription start (\(start)). Annual plans renew on a different schedule."
    }

    private static func relative(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                                   to: Calendar.current.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<1: return "today"
        case 1: return "tomorrow"
        default: return "in \(days) days"
        }
    }

    private static func money(_ v: Double, _ currency: String) -> String {
        v.formatted(.currency(code: currency))
    }

    private static let day: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("d MMM"); return f
    }()
    private static let full: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()
}
