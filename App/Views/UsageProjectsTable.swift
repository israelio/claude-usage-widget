import SwiftUI
import UsageCore

/// The "Group by Project" table: one expandable row per project (small ones grouped under "Other"), each opening to
/// its per-model table and daily trend.
struct UsageProjectsTable: View {
    let breakdown: ProjectBreakdown
    /// The same projects over the 7 days ending on the selected day (Day mode only), for the trend charts.
    let context: ProjectBreakdown?
    let showCost: Bool
    let day: Date?
    let span: UsageSpan
    @State private var expanded = Set<String>()
    @State private var otherOpen = false

    var body: some View {
        let b = breakdown
        VStack(spacing: 0) {
            UsageColumnHeader(title: "Project", showCost: showCost)
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 8)
            Divider().padding(.vertical, 4)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(b.top) { row($0) }
                    if let o = b.other { otherRows(o) }
                    if let e = b.earlier { row(e) }
                }
            }
            Divider().padding(.vertical, 4)
            UsageTotalRow(total: b.total)
        }
        .onChange(of: span) { _, _ in expanded = []; otherOpen = false }
        .onAppear(perform: applyDevExpand)
    }

    /// Developer convenience: CLAUDEUSAGE_PROJECTS_EXPAND=N expands the first N project rows (99 also the "Other" group).
    private func applyDevExpand() {
        guard let n = ProcessInfo.processInfo.environment["CLAUDEUSAGE_PROJECTS_EXPAND"].flatMap(Int.init), n > 0 else { return }
        let b = breakdown
        var ids = b.top.prefix(n).map(\.id)
        if let e = b.earlier, n >= b.top.count { ids.append(e.id) }
        if n >= 99 { ids += b.tail.map(\.id); otherOpen = true }
        expanded = Set(ids)
    }

    private func shownName(_ r: ProjectRow) -> String {
        guard UsageAnonymizer.enabled, !r.isEarlier else { return r.name }
        let b = breakdown
        if let i = b.top.firstIndex(where: { $0.id == r.id }) { return UsageAnonymizer.name(rank: i) }
        if let j = b.tail.firstIndex(where: { $0.id == r.id }) { return UsageAnonymizer.name(rank: b.top.count + j) }
        return r.name
    }

    private func share(_ r: ProjectRow) -> Double {
        usageShare(costShare: r.share, tokens: r.tokens.total, totalTokens: breakdown.total.tokens.total, showCost: showCost)
    }

    /// Daily points for the row's trend chart: over the range, or the 7 days ending on the selected day.
    private func trend(_ r: ProjectRow) -> [DailyPoint] {
        guard let ctx = context else { return r.daily }
        func find(_ id: String) -> [DailyPoint]? { (ctx.rows + (ctx.earlier.map { [$0] } ?? [])).first { $0.id == id }?.daily }
        if r.id == "other" {
            var acc: [DailyPoint]?
            for t in breakdown.tail {
                guard let d = find(t.id) else { continue }
                if acc == nil { acc = d.map { DailyPoint(day: $0.day, tokens: .zero, cost: 0) } }
                for i in d.indices { acc![i].tokens += d[i].tokens; acc![i].cost += d[i].cost }
            }
            return acc ?? []
        }
        return find(r.id) ?? []
    }

    private func row(_ r: ProjectRow, indent: Bool = false) -> some View {
        let open = expanded.contains(r.id)
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                UsageRowTitle(title: shownName(r), open: open, dimmed: r.isEarlier, indent: indent ? 18 : 0)
                    .help(r.isEarlier ? "Usage from days before per-project tracking, or logs Claude Code no longer keeps."
                                      : (UsageAnonymizer.enabled ? shownName(r) : (r.root ?? r.name)))
                UsageValueCells(cost: r.cost, tokens: r.tokens.total, share: share(r), showCost: showCost, dimmed: r.isEarlier)
            }
            .font(.system(size: 12))
            .opacity(r.isEarlier ? 0.7 : 1)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { toggle(r.id) } }
            if open { detail(r).padding(.leading, indent ? 26 : 8).padding(.trailing, 8).padding(.bottom, 8) }
        }
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    @ViewBuilder private func otherRows(_ o: ProjectRow) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                UsageRowTitle(title: o.name, open: otherOpen)
                UsageValueCells(cost: o.cost, tokens: o.tokens.total, share: breakdown.tail.reduce(0) { $0 + share($1) }, showCost: showCost)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 8).padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { otherOpen.toggle() } }
            .help("The smaller projects, grouped. Click to list them.")
            if otherOpen { ForEach(breakdown.tail) { row($0, indent: true) } }
        }
    }

    /// Per-model breakdown of one project; columns line up with the project rows, ordered by the active metric.
    private func modelTable(_ r: ProjectRow) -> some View {
        let usage = ModelUsage.ordered(r.modelUsage, byTokens: !showCost)
        return VStack(alignment: .leading, spacing: 3) {
            Text("By model").fontWeight(.semibold).foregroundStyle(.secondary)
            UsageColumnHeader(title: "Model", showCost: showCost, inset: 15).foregroundStyle(.secondary)
            ForEach(usage) { u in
                HStack(spacing: 12) {
                    Text(PriceTable.displayName(u.model)).lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 15)
                    UsageValueCells(cost: u.cost, tokens: u.tokens.total,
                                    share: usageShare(costShare: u.share, tokens: u.tokens.total, totalTokens: r.tokens.total, showCost: showCost),
                                    showCost: showCost)
                }
                .font(.system(size: 12))
                .help("\(PriceTable.displayName(u.model)): \(Format.cost(u.cost)) over \(Format.tokens(u.tokens.total)) tokens in this project")
            }
        }
        .padding(.bottom, 2)
    }

    private func detail(_ r: ProjectRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !r.modelUsage.isEmpty { modelTable(r) }
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
