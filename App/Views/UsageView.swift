import SwiftUI
import AppKit
import UsageCore

/// The Usage window: the 90-day daily chart on top (click a bar to pick that day), and below it a table of the chosen
/// range grouped by project or by model.
struct UsageView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var model: UsageViewModel
    @AppStorage("projectsMetric") private var metric = "cost"
    @AppStorage("usageGroupBy") private var groupBy = "project"
    @Environment(\.colorScheme) private var scheme

    private var showCost: Bool { metric == "cost" }
    private var byModel: Bool { groupBy == "model" }
    private var today: Date { Calendar.current.startOfDay(for: Date()) }
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

    /// Whether `day` (a bar of the 90-day chart) is inside the current range.
    private func inRange(_ day: Date, in data: [DailyPoint]) -> Bool {
        switch model.span {
        case .day(let d): return Calendar.current.isDate(day, inSameDayAs: d)
        case .days(let n): return data.suffix(n).contains { $0.day == day }
        }
    }

    var body: some View {
        let data = service.daily(days: HistoryData.keepDays)
        VStack(alignment: .leading, spacing: 12) {
            topBar
            UsageDailyChart(points: data, showCost: showCost,
                            isSelected: { inRange($0, in: data) },
                            onSelect: { model.select(.day($0)) })
            tableSection
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 520)
        .background(
            ZStack {
                Rectangle().fill(.regularMaterial)
                if scheme == .dark { Color.black.opacity(0.42) }
            }
        )
        .onAppear {
            // Developer/screenshot aid: CLAUDEUSAGE_USAGE_GROUPBY=model (or project) overrides the saved choice.
            if let g = ProcessInfo.processInfo.environment["CLAUDEUSAGE_USAGE_GROUPBY"], g == "model" || g == "project" { groupBy = g }
        }
    }

    @ViewBuilder private var tableSection: some View {
        // The 7 days ending on the selected day give the trend charts some context in Day mode.
        let sortedByTokens = !showCost
        let window: ProjectRange? = model.day.map { .window(end: $0, days: 7) }
        if byModel {
            let b = service.byModel(range: model.range).sorted(byTokens: sortedByTokens)
            section(label: ProjectRangeLabel.make(range: model.range, count: b.rows.count, noun: "model", now: Date()),
                    empty: b.rows.isEmpty, emptyText: "No usage in this range") {
                UsageModelsTable(breakdown: b, context: window.map { service.byModel(range: $0) }, showCost: showCost,
                                 day: model.day, span: model.span)
            }
        } else {
            let b = service.byProject(range: model.range).sorted(byTokens: sortedByTokens)
            section(label: ProjectRangeLabel.make(range: model.range, count: b.rows.count, now: Date()),
                    empty: b.rows.isEmpty && b.earlier == nil,
                    emptyText: "No per-project data yet — it fills in as you use Claude Code") {
                UsageProjectsTable(breakdown: b, context: window.map { service.byProject(range: $0) }, showCost: showCost,
                                   day: model.day, span: model.span)
            }
        }
    }

    private func section<Table: View>(label: String, empty: Bool, emptyText: String,
                                      @ViewBuilder table: () -> Table) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(label).font(.system(size: 13, weight: .semibold))
                Spacer()
                exportMenu
            }
            if empty {
                Spacer()
                Text(emptyText).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                GlassCard { table() }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Picker("", selection: rangeChoice) {
                Text("Day").tag(0); Text("7 days").tag(7); Text("30 days").tag(30); Text("90 days").tag(90)
            }.pickerStyle(.menu).labelsHidden().fixedSize()
            Picker("", selection: $metric) { Text("Cost").tag("cost"); Text("Tokens").tag("tokens") }
                .pickerStyle(.segmented).labelsHidden().frame(width: 140)
            if model.day != nil { dayNavigator }
            Spacer()
            Text("Group by").foregroundStyle(.secondary)
            Picker("", selection: $groupBy) { Text("Project").tag("project"); Text("Model").tag("model") }
                .pickerStyle(.segmented).labelsHidden().frame(width: 150)
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

    private var exportMenu: some View {
        Menu("Export") {
            Button("Daily totals") { exportDaily() }
            Divider()
            Button("Projects") { save("projects") { ProjectCSV.make(service.byProject(range: model.range)) } }
            Button("Projects by model") { save("projects-by-model") { ProjectCSV.makeWithModels(service.byProject(range: model.range)) } }
            Button("Models by project") { save("models-by-project") { ModelCSV.makeByProject(service.byModel(range: model.range)) } }
        }.fixedSize()
    }

    /// One row per day of the current range (the whole 90 days for "90 days").
    private func exportDaily() {
        save("daily") {
            let data = service.daily(days: HistoryData.keepDays)
            return DailyCSV.make(data.filter { inRange($0.day, in: data) })
        }
    }

    private func save(_ kind: String, csv: () -> String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "claude-usage-\(kind)-\(model.fileLabel).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? csv().write(to: url, atomically: true, encoding: .utf8)
    }
}
