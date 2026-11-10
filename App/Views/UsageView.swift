import SwiftUI
import AppKit
import UsageCore

/// The Usage window: the 90-day daily chart on top (click a bar to pick that day), and below it a table of the chosen
/// range grouped by project or by model. In Sessions granularity the top chart shows one bar per 5-hour session
/// instead (click a bar to pick that session) and the tables cover the selected session or the sessions of the range.
struct UsageView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var model: UsageViewModel
    @AppStorage("projectsMetric") private var metric = "cost"
    @AppStorage("usageGroupBy") private var groupBy = "project"
    @AppStorage("usageGranularity") private var granularity = "days"
    @Environment(\.colorScheme) private var scheme

    private var showCost: Bool { metric == "cost" }
    private var byModel: Bool { groupBy == "model" }
    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var sessionsMode: Bool { model.span.isSessions }
    /// 0 = Day, otherwise the number of days.
    private var rangeChoice: Binding<Int> {
        Binding {
            if case .days(let n) = model.span { return n }
            return 0
        } set: { n in
            model.select(n == 0 ? .day(model.lastDay ?? today) : .days(n))
        }
    }
    /// Sessions mode: 0 = one session, otherwise the number of days of sessions.
    private var sessionRangeChoice: Binding<Int> {
        Binding {
            if case .sessions(let n) = model.span { return n }
            return 0
        } set: { n in
            if n > 0 { model.select(.sessions(n)) }
            else if let id = model.lastSession ?? service.sessions.last?.id { model.select(.session(id)) }
        }
    }
    private var granularityChoice: Binding<String> {
        Binding {
            sessionsMode ? "sessions" : "days"
        } set: { g in
            granularity = g
            model.select(g == "sessions" ? .sessions(7) : .days(30))
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
        case .session, .sessions: return false
        }
    }

    var body: some View {
        let data = sessionsMode ? [] : service.daily(days: HistoryData.keepDays)
        VStack(alignment: .leading, spacing: 12) {
            topBar
            if sessionsMode {
                sessionsChart
            } else {
                UsageDailyChart(points: data, showCost: showCost,
                                isSelected: { inRange($0, in: data) },
                                onSelect: { model.select(.day($0)) })
            }
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
        .onChange(of: model.span) { _, s in granularity = s.isSessions ? "sessions" : "days" }
        .onAppear {
            // Developer/screenshot aid: CLAUDEUSAGE_USAGE_GROUPBY=model (or project) overrides the saved choice.
            if let g = ProcessInfo.processInfo.environment["CLAUDEUSAGE_USAGE_GROUPBY"], g == "model" || g == "project" { groupBy = g }
        }
    }

    @ViewBuilder private var tableSection: some View {
        // The 7 days ending on the selected day give the trend charts some context in Day mode.
        let sortedByTokens = !showCost
        let window: ProjectRange? = model.day.map { .window(end: $0, days: 7) }
        let range = currentRange
        let title = sessionsTitle
        if byModel {
            let b = service.byModel(range: range).sorted(byTokens: sortedByTokens)
            section(label: ProjectRangeLabel.make(range: range, count: b.rows.count, noun: "model", sessionsTitle: title, now: Date()),
                    empty: b.rows.isEmpty, emptyText: sessionsMode ? "No session detail in this range" : "No usage in this range") {
                UsageModelsTable(breakdown: b, context: window.map { service.byModel(range: $0) }, showCost: showCost,
                                 day: model.day, span: model.span, unit: model.trendUnit)
            }
        } else {
            let b = service.byProject(range: range).sorted(byTokens: sortedByTokens)
            section(label: ProjectRangeLabel.make(range: range, count: b.rows.count, sessionsTitle: title, now: Date()),
                    empty: b.rows.isEmpty && b.earlier == nil,
                    emptyText: sessionsMode ? "No session detail in this range"
                                            : "No per-project data yet — it fills in as you use Claude Code") {
                UsageProjectsTable(breakdown: b, context: window.map { service.byProject(range: $0) }, showCost: showCost,
                                   day: model.day, span: model.span, unit: model.trendUnit)
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
            Picker("", selection: granularityChoice) { Text("Days").tag("days"); Text("Sessions").tag("sessions") }
                .pickerStyle(.segmented).labelsHidden().frame(width: 150)
                .help("Days, or Claude's rolling 5-hour work sessions")
            if sessionsMode {
                Picker("", selection: sessionRangeChoice) {
                    Text("Session").tag(0); Text("3 days").tag(3); Text("7 days").tag(7); Text("14 days").tag(14); Text("30 days").tag(30)
                }.pickerStyle(.menu).labelsHidden().fixedSize()
            } else {
                Picker("", selection: rangeChoice) {
                    Text("Day").tag(0); Text("7 days").tag(7); Text("30 days").tag(30); Text("90 days").tag(90)
                }.pickerStyle(.menu).labelsHidden().fixedSize()
            }
            Picker("", selection: $metric) { Text("Cost").tag("cost"); Text("Tokens").tag("tokens") }
                .pickerStyle(.segmented).labelsHidden().frame(width: 140)
            if model.day != nil { dayNavigator }
            if model.sessionId != nil { sessionNavigator }
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
            if sessionsMode {
                Button("Sessions") {
                    save("sessions") {
                        var list: [UsageSession] = []
                        switch currentRange {
                        case .session(let s): list = [s]
                        case .sessions(let l): list = l
                        default: break
                        }
                        return SessionCSV.make(list, prices: service.settings.prefs.prices)
                    }
                }
            } else {
                Button("Daily totals") { exportDaily() }
            }
            Divider()
            Button("Projects") { save("projects") { ProjectCSV.make(service.byProject(range: currentRange)) } }
            Button("Projects by model") { save("projects-by-model") { ProjectCSV.makeWithModels(service.byProject(range: currentRange)) } }
            Button("Models by project") { save("models-by-project") { ModelCSV.makeByProject(service.byModel(range: currentRange)) } }
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

    // MARK: Sessions granularity

    private var sessionsTitle: String? {
        if case .sessions(let n) = model.span { return "Last \(n) days" }
        return nil
    }

    private var currentRange: ProjectRange { model.range(sessions: service.sessions) }

    /// Days of sessions the top chart covers: the range, or 7 (more when the selected session is older).
    private var chartDays: Int {
        switch model.span {
        case .sessions(let n): return n
        case .session(let id):
            let start = Date(timeIntervalSince1970: Double(id) * 3600)
            let back = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: start), to: today).day ?? 0
            return min(HistoryData.keepDays, max(7, back + 1))
        default: return 7
        }
    }

    private var sessionsChart: some View {
        let cal = Calendar.current
        let from = cal.date(byAdding: .day, value: -(chartDays - 1), to: today)!
        let to = cal.date(byAdding: .day, value: 1, to: today)!
        let shown = SessionBuilder.recent(service.sessions, days: chartDays, now: Date())
        return VStack(alignment: .leading, spacing: 4) {
            UsageSessionChart(sessions: shown, domain: from...to, showCost: showCost, prices: service.settings.prefs.prices, now: Date(),
                              isSelected: { s in model.sessionId.map { $0 == s.id } ?? true },
                              onSelect: { model.select(.session($0.id)) })
            if let e = service.earliestHour {
                if from < e {
                    Text("Session detail available since \(e.formatted(.dateTime.day().month(.abbreviated).year()))")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            } else {
                Text("No session detail yet. It builds up as you use Claude Code.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private func stepSession(_ delta: Int) {
        let all = service.sessions
        guard let id = model.sessionId, let i = all.firstIndex(where: { $0.id == id }), all.indices.contains(i + delta) else { return }
        model.select(.session(all[i + delta].id))
    }

    /// Previous / next session around a compact date picker (jumps to the session containing or just after that date).
    private var sessionNavigator: some View {
        let all = service.sessions
        let idx = model.sessionId.flatMap { id in all.firstIndex { $0.id == id } }
        let current = idx.map { all[$0].start } ?? Date()
        let lower = min(Calendar.current.startOfDay(for: service.earliestHour ?? today), current)
        let binding = Binding<Date> {
            current
        } set: { d in
            let dayStart = Calendar.current.startOfDay(for: d)
            if let s = all.first(where: { $0.end > dayStart }) ?? all.last { model.select(.session(s.id)) }
        }
        return HStack(spacing: 4) {
            Button { stepSession(-1) } label: { Image(systemName: "chevron.left") }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled((idx ?? 0) <= 0)
                .help("Previous session")
            DatePicker("", selection: binding, in: lower...max(Date(), current), displayedComponents: .date)
                .datePickerStyle(.compact).labelsHidden()
            Button { stepSession(1) } label: { Image(systemName: "chevron.right") }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled((idx ?? all.count - 1) >= all.count - 1)
                .help("Next session")
        }
    }
}
