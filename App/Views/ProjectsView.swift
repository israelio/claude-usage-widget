import SwiftUI
import Charts
import AppKit
import UsageCore

/// What the Usage by Project window is showing: one day, or the last N days ending today.
enum ProjectsSpan: Equatable {
    case day(Date)
    case days(Int)
}

/// What the Usage by Project window is showing; lives in the window controller so showing the window again (for
/// another bar) can switch the day without recreating the view.
@MainActor
final class ProjectsViewModel: ObservableObject {
    /// Single source of truth for the window's range.
    @Published var span: ProjectsSpan = .days(30)
    /// The last day that was selected, so switching back to "Day" returns to it.
    private(set) var lastDay: Date?

    /// The selected day in Day mode, nil in a range mode.
    var day: Date? { if case .day(let d) = span { return d }; return nil }

    func open(day: Date?) { select(day.map { .day($0) } ?? .days(30)) }

    func select(_ s: ProjectsSpan) {
        if case .day(let d) = s { lastDay = Calendar.current.startOfDay(for: d) }
        span = s
    }
}

struct ProjectsView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var model: ProjectsViewModel
    @AppStorage("projectsMetric") private var metric = "cost"
    @State private var expanded = Set<String>()
    @State private var otherOpen = false
    @Environment(\.colorScheme) private var scheme

    private var showCost: Bool { metric == "cost" }
    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var range: ProjectRange {
        switch model.span {
        case .day(let d): return .day(d)
        case .days(let n): return .lastDays(n)
        }
    }
    /// 0 = Day, otherwise the number of days.
    private var rangeChoice: Binding<Int> {
        Binding {
            if case .days(let n) = model.span { return n }
            return 0
        } set: { n in
            model.select(n == 0 ? .day(model.lastDay ?? today) : .days(n))
        }
    }
    private var dayBinding: Binding<Date> {
        Binding { model.day ?? today } set: { model.select(.day(min($0, today))) }
    }
    private var earliest: Date { min(service.earliestDay ?? today, model.day ?? today) }
    private func step(_ delta: Int) {
        guard let d = model.day, let n = Calendar.current.date(byAdding: .day, value: delta, to: d) else { return }
        if n > today || n < earliest { return }
        model.select(.day(n))
    }

    /// Developer convenience: CLAUDEUSAGE_PROJECTS_EXPAND=N expands the first N project rows (99 also the "Other" group).
    private func applyDevExpand(_ b: ProjectBreakdown) {
        guard let n = ProcessInfo.processInfo.environment["CLAUDEUSAGE_PROJECTS_EXPAND"].flatMap(Int.init), n > 0 else { return }
        var ids = b.top.prefix(n).map(\.id)
        if let e = b.earlier, n >= b.top.count { ids.append(e.id) }
        if n >= 99 { ids += b.tail.map(\.id); otherOpen = true }
        expanded = Set(ids)
    }

    /// Daily points for the row's trend chart, over the window shown (the range, or the 7 days ending on the
    /// selected day) and the matching highlighted day.
    private func trend(_ r: ProjectRow, _ b: ProjectBreakdown, _ ctx: ProjectBreakdown?) -> [DailyPoint] {
        guard let ctx else { return r.daily }
        func find(_ id: String) -> [DailyPoint]? { (ctx.rows + (ctx.earlier.map { [$0] } ?? [])).first { $0.id == id }?.daily }
        if r.id == "other" {
            var acc: [DailyPoint]?
            for t in b.tail {
                guard let d = find(t.id) else { continue }
                if acc == nil { acc = d.map { DailyPoint(day: $0.day, tokens: .zero, cost: 0) } }
                for i in d.indices { acc![i].tokens += d[i].tokens; acc![i].cost += d[i].cost }
            }
            return acc ?? []
        }
        return find(r.id) ?? []
    }

    var body: some View {
        let b = service.byProject(range: range).sorted(byTokens: !showCost)
        let ctx = model.day.map { service.byProject(range: .window(end: $0, days: 7)) }
        VStack(alignment: .leading, spacing: 12) {
            topBar(b)
            Text(ProjectRangeLabel.make(range: range, projects: b.rows.count, now: Date()))
                .font(.system(size: 13, weight: .semibold))
            if b.rows.isEmpty && b.earlier == nil {
                Spacer()
                Text("No per-project data yet — it fills in as you use Claude Code")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                GlassCard {
                    VStack(spacing: 0) {
                        header
                        Divider().padding(.vertical, 4)
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(b.top) { row($0, b, ctx) }
                                if let o = b.other { otherRows(o, b, ctx) }
                                if let e = b.earlier { row(e, b, ctx) }
                            }
                        }
                        Divider().padding(.vertical, 4)
                        totalRow(b)
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 420)
        .background(
            ZStack {
                Rectangle().fill(.regularMaterial)
                if scheme == .dark { Color.black.opacity(0.42) }
            }
        )
        .onChange(of: model.span) { _, _ in expanded = []; otherOpen = false }
        .onAppear { applyDevExpand(b) }
    }

    private func topBar(_ b: ProjectBreakdown) -> some View {
        HStack(spacing: 12) {
            Picker("", selection: rangeChoice) {
                Text("Day").tag(0); Text("7 days").tag(7); Text("30 days").tag(30); Text("90 days").tag(90)
            }.pickerStyle(.menu).labelsHidden().fixedSize()
            Picker("", selection: $metric) { Text("Cost").tag("cost"); Text("Tokens").tag("tokens") }
                .pickerStyle(.segmented).labelsHidden().frame(width: 140)
            if model.day != nil { dayNavigator }
            Spacer()
            Menu("Export CSV") {
                Button("Projects") { export(b, byModel: false) }
                Button("Projects by model") { export(b, byModel: true) }
            }.fixedSize()
        }
    }

    /// Previous / next day around a compact date picker. The arrow keys step the day (the window must be key).
    private var dayNavigator: some View {
        HStack(spacing: 4) {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled((model.day ?? today) <= Calendar.current.startOfDay(for: earliest))
                .help("Previous day")
            DatePicker("", selection: dayBinding, in: earliest...today, displayedComponents: .date)
                .datePickerStyle(.compact).labelsHidden()
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled((model.day ?? today) >= today)
                .help("Next day")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Project").frame(maxWidth: .infinity, alignment: .leading)
            Text("Cost").frame(width: 80, alignment: .trailing).fontWeight(showCost ? .bold : .regular)
            Text("Tokens").frame(width: 70, alignment: .trailing).fontWeight(showCost ? .regular : .bold)
            Text("Share").frame(width: 170, alignment: .leading)
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .padding(.horizontal, 8)
    }

    /// Share of the total in the selected metric (the bar and percent follow the Cost / Tokens toggle).
    private func share(_ r: ProjectRow, _ b: ProjectBreakdown) -> Double {
        if showCost { return r.share }
        let t = b.total.tokens.total
        return t > 0 ? Double(r.tokens.total) / Double(t) : 0
    }

    private func row(_ r: ProjectRow, _ b: ProjectBreakdown, _ ctx: ProjectBreakdown?, indent: Bool = false) -> some View {
        let open = expanded.contains(r.id)
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary).frame(width: 10)
                    Text(shownName(r, b)).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(r.isEarlier ? .secondary : .primary)
                }
                .padding(.leading, indent ? 18 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(r.isEarlier ? "Usage from days before per-project tracking, or logs Claude Code no longer keeps." : (Self.anonymize ? shownName(r, b) : (r.root ?? r.name)))
                Text(Format.cost(r.cost)).monospacedDigit().frame(width: 80, alignment: .trailing)
                    .fontWeight(showCost ? .semibold : .regular)
                Text(Format.tokens(r.tokens.total)).monospacedDigit().frame(width: 70, alignment: .trailing)
                    .fontWeight(showCost ? .regular : .semibold)
                shareBar(share(r, b), dimmed: r.isEarlier).frame(width: 170)
            }
            .font(.system(size: 12))
            .opacity(r.isEarlier ? 0.7 : 1)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { toggle(r.id) } }
            if open { detail(r, b, ctx).padding(.leading, indent ? 26 : 8).padding(.trailing, 8).padding(.bottom, 8) }
        }
    }

    /// Developer/screenshot aid: `CLAUDEUSAGE_ANONYMIZE_PROJECTS=1` shows generic project names (for README images).
    private static let anonymize = ProcessInfo.processInfo.environment["CLAUDEUSAGE_ANONYMIZE_PROJECTS"] != nil
    private static let demoNames = ["web-app", "api-service", "mobile-client", "docs-site", "data-pipeline", "infra-tools", "design-system", "cli-tool"]
    private func shownName(_ r: ProjectRow, _ b: ProjectBreakdown) -> String {
        guard Self.anonymize, !r.isEarlier else { return r.name }
        if let i = b.top.firstIndex(where: { $0.id == r.id }), i < Self.demoNames.count { return Self.demoNames[i] }
        if let j = b.tail.firstIndex(where: { $0.id == r.id }) { return "project-\(j + 1)" }
        return r.name
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    @ViewBuilder private func otherRows(_ o: ProjectRow, _ b: ProjectBreakdown, _ ctx: ProjectBreakdown?) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Image(systemName: otherOpen ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary).frame(width: 10)
                    Text(o.name)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(Format.cost(o.cost)).monospacedDigit().frame(width: 80, alignment: .trailing)
                    .fontWeight(showCost ? .semibold : .regular)
                Text(Format.tokens(o.tokens.total)).monospacedDigit().frame(width: 70, alignment: .trailing)
                    .fontWeight(showCost ? .regular : .semibold)
                shareBar(b.tail.reduce(0) { $0 + share($1, b) }, dimmed: false).frame(width: 170)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 8).padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { otherOpen.toggle() } }
            .help("The smaller projects, grouped. Click to list them.")
            if otherOpen { ForEach(b.tail) { row($0, b, ctx, indent: true) } }
        }
    }

    private func totalRow(_ b: ProjectBreakdown) -> some View {
        HStack(spacing: 12) {
            Text("Total").frame(maxWidth: .infinity, alignment: .leading)
            Text(Format.cost(b.total.cost)).monospacedDigit().frame(width: 80, alignment: .trailing)
            Text(Format.tokens(b.total.tokens.total)).monospacedDigit().frame(width: 70, alignment: .trailing)
            Spacer().frame(width: 170)
        }
        .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 8)
    }

    private func shareBar(_ f: Double, dimmed: Bool) -> some View {
        HStack(spacing: 8) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.10))
                    Capsule().fill(LinearGradient(colors: [.orange, .green], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(f > 0 ? 3 : 0, g.size.width * min(1, f)))
                        .opacity(dimmed ? 0.45 : 1)
                }
            }.frame(height: 8)
            Text("\(Int((f * 100).rounded()))%").font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
        }
    }

    /// Per-model breakdown of one project; columns line up with the project rows, ordered by the active metric.
    private func modelTable(_ r: ProjectRow) -> some View {
        let usage = ModelUsage.ordered(r.modelUsage, byTokens: !showCost)
        let totalTokens = r.tokens.total
        return VStack(alignment: .leading, spacing: 3) {
            Text("By model").fontWeight(.semibold).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Text("Model").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 15)
                Text("Cost").frame(width: 80, alignment: .trailing).fontWeight(showCost ? .bold : .regular)
                Text("Tokens").frame(width: 70, alignment: .trailing).fontWeight(showCost ? .regular : .bold)
                Text("Share").frame(width: 170, alignment: .leading)
            }
            .foregroundStyle(.secondary)
            ForEach(usage) { u in
                let f = showCost ? u.share : (totalTokens > 0 ? Double(u.tokens.total) / Double(totalTokens) : 0)
                HStack(spacing: 12) {
                    Text(PriceTable.displayName(u.model)).lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 15)
                    Text(Format.cost(u.cost)).monospacedDigit().frame(width: 80, alignment: .trailing)
                        .fontWeight(showCost ? .semibold : .regular)
                    Text(Format.tokens(u.tokens.total)).monospacedDigit().frame(width: 70, alignment: .trailing)
                        .fontWeight(showCost ? .regular : .semibold)
                    shareBar(f, dimmed: false).frame(width: 170)
                }
                .font(.system(size: 12))
                .help("\(PriceTable.displayName(u.model)): \(Format.cost(u.cost)) over \(Format.tokens(u.tokens.total)) tokens in this project")
            }
        }
        .padding(.bottom, 2)
    }

    private func detail(_ r: ProjectRow, _ b: ProjectBreakdown, _ ctx: ProjectBreakdown?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !r.modelUsage.isEmpty { modelTable(r) }
            HStack {
                Text("In \(Format.tokens(r.tokens.input)) · Out \(Format.tokens(r.tokens.output)) · Cache \(Format.tokens(r.tokens.cache))")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            let pts = trend(r, b, ctx)
            if !pts.isEmpty {
                Text((showCost ? "Daily cost (USD)" : "Daily tokens") + (ctx != nil ? " — last 7 days" : ""))
                    .foregroundStyle(.secondary).padding(.top, 4)
                ProjectTrendChart(points: pts, showCost: showCost, highlight: model.day)
            }
        }
        .font(.system(size: 11))
    }

    private func export(_ b: ProjectBreakdown, byModel: Bool) {
        let panel = NSSavePanel()
        let label: String
        switch model.span {
        case .day(let d): label = DayKey.string(d)
        case .days(let n): label = "\(n)d"
        }
        panel.nameFieldStringValue = "claude-usage-projects\(byModel ? "-by-model" : "")-\(label).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? (byModel ? ProjectCSV.makeWithModels(b) : ProjectCSV.make(b)).write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Full-width daily trend of one project: faint gridlines, a Y axis with 3 ticks, date labels on X, and a hover readout.
private struct ProjectTrendChart: View {
    let points: [DailyPoint]
    let showCost: Bool
    /// The day to emphasise (Day mode); others are dimmed.
    let highlight: Date?
    @State private var hovered: Date?

    private func value(_ p: DailyPoint) -> Double { showCost ? p.cost : Double(p.tokens.total) }
    private func same(_ a: Date, _ b: Date?) -> Bool { b.map { Calendar.current.isDate(a, inSameDayAs: $0) } ?? false }

    var body: some View {
        let hit = hovered.flatMap { h in points.first { same($0.day, h) } }
        let emphasised = hit?.day ?? highlight
        let ticks = ChartAxis.tickIndices(count: points.count).map { points[$0].day }
        Chart {
            ForEach(points) { p in
                BarMark(x: .value("Day", p.day, unit: .day), y: .value(showCost ? "Cost" : "Tokens", value(p)))
                    .foregroundStyle(.orange.gradient)
                    .opacity(emphasised == nil || same(p.day, emphasised) ? 1 : 0.4)
            }
            if let h = hit {
                RuleMark(x: .value("Day", h.day, unit: .day))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartTip {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(h.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                Text(showCost ? "\(Format.cost(h.cost)) · \(Format.tokens(h.tokens.total)) tokens"
                                              : "\(Format.tokens(h.tokens.total)) tokens · \(Format.cost(h.cost))")
                            }
                        }
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: ticks) { _ in
                AxisTick()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true).font(.system(size: 9))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel {
                    let x = v.as(Double.self) ?? 0
                    Text(showCost ? Format.cost(x) : Format.tokens(Int(x))).font(.system(size: 9))
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let loc):
                            guard let frame = proxy.plotFrame else { hovered = nil; return }
                            let x = loc.x - geo[frame].origin.x
                            if x >= 0, x <= geo[frame].width, let d: Date = proxy.value(atX: x) {
                                hovered = points.first { same($0.day, d) }?.day
                            } else { hovered = nil }
                        case .ended: hovered = nil
                        }
                    }
            }
        }
        .frame(height: 96)
    }
}
