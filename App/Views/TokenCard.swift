import SwiftUI
import UsageCore

struct TokenCard: View {
    let summary: UsageSummary
    @Environment(\.compact) private var compact
    @AppStorage("tokenCardCollapsed") private var collapsed = false

    var body: some View {
        GlassCard(title: "Token Usage", icon: "number", trailing: AnyView(toggle)) {
            if !collapsed {
                Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: compact ? 3 : 5) {
                    GridRow {
                        Text("").gridColumnAlignment(.leading); Text("Input"); Text("Output"); Text("Cache"); Text("Cost")
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                    row("Today", summary.today); row("Last 7 Days", summary.last7)
                    row("This Month", summary.month); row("Last 30 Days", summary.last30)
                }
                Divider()
                ForEach(summary.modelShare.prefix(compact ? 3 : 5), id: \.model) { m in
                    HStack {
                        Text(PriceTable.displayName(m.model)).fontWeight(.semibold)
                        Spacer()
                        Text("\(Int((m.fraction * 100).rounded()))%").foregroundStyle(.secondary)
                    }.font(.system(size: 12))
                }
            }
        }
    }

    /// Collapse/expand control. When collapsed, a one-line summary stays visible in the header.
    private var toggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { collapsed.toggle() }
        } label: {
            HStack(spacing: 6) {
                if collapsed {
                    Text("Today \(Format.cost(summary.today.cost)) · 7d \(Format.cost(summary.last7.cost))")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    .frame(width: 22, height: 20)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(collapsed ? "Show token usage" : "Hide token usage")
    }

    private func row(_ name: String, _ t: Totals) -> some View {
        GridRow {
            Text(name).foregroundStyle(.secondary).gridColumnAlignment(.leading)
            Text(Format.tokens(t.tokens.input)); Text(Format.tokens(t.tokens.output))
            Text(Format.tokens(t.tokens.cache)); Text(Format.cost(t.cost)).fontWeight(.bold)
        }.font(.system(size: 12, design: .rounded))
    }
}
