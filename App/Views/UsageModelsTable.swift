import SwiftUI
import UsageCore

/// The "Group by Model" table: one expandable row per model across all projects, each opening to the projects that
/// used it and the model's daily trend.
struct UsageModelsTable: View {
    let breakdown: ModelBreakdown
    /// The same models over the 7 days ending on the selected day (Day mode only), for the trend charts.
    let context: ModelBreakdown?
    let showCost: Bool
    let day: Date?
    let span: UsageSpan
    @State private var expanded = Set<String>()

    var body: some View {
        VStack(spacing: 0) {
            UsageColumnHeader(title: "Model", showCost: showCost)
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 8)
            Divider().padding(.vertical, 4)
            ScrollView {
                VStack(spacing: 0) { ForEach(breakdown.rows) { row($0) } }
            }
            Divider().padding(.vertical, 4)
            UsageTotalRow(total: breakdown.total)
        }
        .onChange(of: span) { _, _ in expanded = [] }
        .onAppear(perform: applyDevExpand)
    }

    /// Developer convenience: CLAUDEUSAGE_PROJECTS_EXPAND=N expands the first N model rows.
    private func applyDevExpand() {
        guard let n = ProcessInfo.processInfo.environment["CLAUDEUSAGE_PROJECTS_EXPAND"].flatMap(Int.init), n > 0 else { return }
        expanded = Set(breakdown.rows.prefix(n).map(\.id))
    }

    /// Placeholder names follow each project's rank by cost across the whole table (see `CLAUDEUSAGE_ANONYMIZE_PROJECTS`).
    private func shownName(_ p: ProjectUsage) -> String {
        guard UsageAnonymizer.enabled, !p.isEarlier else { return p.name }
        var cost: [String: Double] = [:]
        for r in breakdown.rows { for u in r.projects where !u.isEarlier { cost[u.id, default: 0] += u.cost } }
        let ranked = cost.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
        return ranked.firstIndex(of: p.id).map(UsageAnonymizer.name(rank:)) ?? p.name
    }

    private func share(_ r: ModelRow) -> Double {
        usageShare(costShare: r.share, tokens: r.tokens.total, totalTokens: breakdown.total.tokens.total, showCost: showCost)
    }

    private func trend(_ r: ModelRow) -> [DailyPoint] {
        guard let ctx = context else { return r.daily }
        return ctx.rows.first { $0.id == r.id }?.daily ?? []
    }

    private func row(_ r: ModelRow) -> some View {
        let open = expanded.contains(r.id)
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                UsageRowTitle(title: PriceTable.displayName(r.model), open: open).help(r.model)
                UsageValueCells(cost: r.cost, tokens: r.tokens.total, share: share(r), showCost: showCost)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 8).padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) {
                    if open { expanded.remove(r.id) } else { expanded.insert(r.id) }
                }
            }
            if open { detail(r).padding(.leading, 8).padding(.trailing, 8).padding(.bottom, 8) }
        }
    }

    /// The projects that used one model; columns line up with the model rows, ordered by the active metric.
    private func projectTable(_ r: ModelRow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("By project").fontWeight(.semibold).foregroundStyle(.secondary)
            UsageColumnHeader(title: "Project", showCost: showCost, inset: 15).foregroundStyle(.secondary)
            ForEach(r.projects) { p in
                HStack(spacing: 12) {
                    Text(shownName(p)).lineLimit(1).truncationMode(.middle).foregroundStyle(p.isEarlier ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 15)
                        .help(p.isEarlier ? "Usage from days before per-project tracking, or logs Claude Code no longer keeps."
                                          : (UsageAnonymizer.enabled ? shownName(p) : (p.root ?? p.name)))
                    UsageValueCells(cost: p.cost, tokens: p.tokens.total,
                                    share: usageShare(costShare: p.share, tokens: p.tokens.total, totalTokens: r.tokens.total, showCost: showCost),
                                    showCost: showCost, dimmed: p.isEarlier)
                }
                .font(.system(size: 12))
                .opacity(p.isEarlier ? 0.7 : 1)
            }
        }
        .padding(.bottom, 2)
    }

    private func detail(_ r: ModelRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            projectTable(r)
            HStack {
                Text("In \(Format.tokens(r.tokens.input)) · Out \(Format.tokens(r.tokens.output)) · Cache \(Format.tokens(r.tokens.cache))")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            let pts = trend(r)
            if !pts.isEmpty {
                Text((showCost ? "Daily cost (USD)" : "Daily tokens") + (context != nil ? " — last 7 days" : ""))
                    .foregroundStyle(.secondary).padding(.top, 4)
                UsageTrendChart(points: pts, showCost: showCost, highlight: day)
            }
        }
        .font(.system(size: 11))
    }
}
