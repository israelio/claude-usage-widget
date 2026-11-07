import SwiftUI
import UsageCore

struct TokenCard: View {
    let summary: UsageSummary

    var body: some View {
        GlassCard(title: "Token Usage", icon: "number") {
            Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 5) {
                GridRow {
                    Text("").gridColumnAlignment(.leading); Text("Input"); Text("Output"); Text("Cache"); Text("Cost")
                }.font(.system(size: 10)).foregroundStyle(.secondary)
                row("Today", summary.today); row("Last 7 Days", summary.last7)
                row("This Month", summary.month); row("Last 30 Days", summary.last30)
            }
            Divider()
            ForEach(summary.modelShare.prefix(5), id: \.model) { m in
                HStack {
                    Text(PriceTable.displayName(m.model)).fontWeight(.semibold)
                    Spacer()
                    Text("\(Int((m.fraction * 100).rounded()))%").foregroundStyle(.secondary)
                }.font(.system(size: 12))
            }
        }
    }

    private func row(_ name: String, _ t: Totals) -> some View {
        GridRow {
            Text(name).foregroundStyle(.secondary).gridColumnAlignment(.leading)
            Text(Format.tokens(t.tokens.input)); Text(Format.tokens(t.tokens.output))
            Text(Format.tokens(t.tokens.cache)); Text(Format.cost(t.cost)).fontWeight(.bold)
        }.font(.system(size: 12, design: .rounded))
    }
}
