import SwiftUI
import Charts
import AppKit
import UsageCore

/// What the Usage by Project window is showing; lives in the window controller so showing the window again (for
/// another bar) can switch the day without recreating the view.
@MainActor
final class ProjectsViewModel: ObservableObject {
    /// The clicked day, or nil when opened without one.
    @Published var day: Date?
    /// 0 = the specific day; otherwise the number of days ending today.
    @Published var span = 30

    func open(day: Date?) {
        self.day = day
        span = day == nil ? 30 : 0
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
    private var range: ProjectRange {
        if model.span == 0, let d = model.day { return .day(d) }
        return .lastDays(model.span == 0 ? 30 : model.span)
    }
    private func dayLabel(_ d: Date) -> String { d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) }

    var body: some View {
        let b = service.byProject(range: range).sorted(byTokens: !showCost)
        VStack(alignment: .leading, spacing: 12) {
            topBar(b)
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
                                ForEach(b.top) { row($0, b) }
                                if let o = b.other { otherRows(o, b) }
                                if let e = b.earlier { row(e, b) }
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
        .onChange(of: model.day) { _, _ in expanded = []; otherOpen = false }
    }

    private func topBar(_ b: ProjectBreakdown) -> some View {
        HStack(spacing: 12) {
            Picker("", selection: $model.span) {
                if let d = model.day { Text(dayLabel(d)).tag(0) }
                Text("7 days").tag(7); Text("30 days").tag(30); Text("90 days").tag(90)
            }.pickerStyle(.menu).labelsHidden().fixedSize()
            Picker("", selection: $metric) { Text("Cost").tag("cost"); Text("Tokens").tag("tokens") }
                .pickerStyle(.segmented).labelsHidden().frame(width: 140)
            Spacer()
            Button("Export CSV") { export(b) }
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

    private func row(_ r: ProjectRow, _ b: ProjectBreakdown, indent: Bool = false) -> some View {
        let open = expanded.contains(r.id)
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary).frame(width: 10)
                    Text(r.name).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(r.isEarlier ? .secondary : .primary)
                }
                .padding(.leading, indent ? 18 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(r.isEarlier ? "Usage from days before per-project tracking, or logs Claude Code no longer keeps." : (r.root ?? r.name))
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
            if open { detail(r).padding(.leading, indent ? 26 : 8).padding(.trailing, 8).padding(.bottom, 8) }
        }
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    @ViewBuilder private func otherRows(_ o: ProjectRow, _ b: ProjectBreakdown) -> some View {
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
            if otherOpen { ForEach(b.tail) { row($0, b, indent: true) } }
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

    private func detail(_ r: ProjectRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !r.models.isEmpty {
                HStack(spacing: 14) {
                    ForEach(r.models, id: \.model) { m in
                        Text("\(PriceTable.displayName(m.model)) \(Int((m.fraction * 100).rounded()))%")
                    }
                }
            }
            HStack {
                Text("In \(Format.tokens(r.tokens.input)) · Out \(Format.tokens(r.tokens.output)) · Cache \(Format.tokens(r.tokens.cache))")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if r.daily.count > 1 {
                Chart(r.daily) { p in
                    BarMark(x: .value("Day", p.day, unit: .day), y: .value("v", showCost ? p.cost : Double(p.tokens.total)))
                        .foregroundStyle(.orange.gradient)
                }
                .chartXAxis(.hidden).chartYAxis(.hidden)
                .frame(height: 36)
                .help(showCost ? "Daily cost" : "Daily tokens")
            }
        }
        .font(.system(size: 11))
    }

    private func export(_ b: ProjectBreakdown) {
        let panel = NSSavePanel()
        let label = model.span == 0 ? (model.day.map { DayKey.string($0) } ?? "30d") : "\(model.span)d"
        panel.nameFieldStringValue = "claude-usage-projects-\(label).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? ProjectCSV.make(b).write(to: url, atomically: true, encoding: .utf8)
    }
}
