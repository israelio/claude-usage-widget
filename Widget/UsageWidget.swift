import WidgetKit
import AppIntents
import SwiftUI
import Charts
import UsageCore

enum DisplayChoice: String, AppEnum {
    case followApp, used, left
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Show")
    static var caseDisplayRepresentations: [DisplayChoice: DisplayRepresentation] = [
        .followApp: "Same as app setting", .used: "Used", .left: "Left",
    ]
}

enum SmallMetric: String, AppEnum {
    case session, weekly
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Small widget shows")
    static var caseDisplayRepresentations: [SmallMetric: DisplayRepresentation] = [
        .session: "5-hour session", .weekly: "Weekly limit",
    ]
}

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Claude Usage"
    static var description = IntentDescription("Choose used or remaining, and the small widget's metric.")

    @Parameter(title: "Show", default: .followApp) var display: DisplayChoice
    @Parameter(title: "Small widget shows", default: .session) var smallMetric: SmallMetric
}

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedSnapshot?
    var configuration = ConfigurationAppIntent()

    /// Show remaining (100 - used) instead of used, per the widget's setting or the app's.
    var showLeft: Bool {
        configuration.display == .left || (configuration.display == .followApp && snapshot?.showRemaining == true)
    }
}

struct Provider: AppIntentTimelineProvider {
    private func load() -> SharedSnapshot? {
        let id = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? ""
        guard let url = SharedSnapshot.groupURL(groupID: id) else { return nil }
        return SharedSnapshot.load(from: url)
    }
    /// Stamped on every system request so the app can tell the widgets are still being served.
    private func beat() {
        let id = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? ""
        if let url = WidgetHeartbeat.url(groupID: id) { WidgetHeartbeat.write(to: url) }
    }
    func placeholder(in context: Context) -> UsageEntry { UsageEntry(date: Date(), snapshot: load()) }
    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> UsageEntry {
        beat()
        return UsageEntry(date: Date(), snapshot: load(), configuration: configuration)
    }
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<UsageEntry> {
        beat()
        let entry = UsageEntry(date: Date(), snapshot: load(), configuration: configuration)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
    }
}

private struct FreshnessCaption: View {
    let snapshot: SharedSnapshot
    let now: Date
    private static let staleAfter: TimeInterval = 30 * 60
    var body: some View {
        let time = snapshot.updatedAt.formatted(date: .omitted, time: .shortened)
        if snapshot.limits?.isEstimated == true {
            Text("estimated").font(.system(size: 10)).foregroundStyle(.orange)
        } else if now.timeIntervalSince(snapshot.updatedAt) > Self.staleAfter {
            Text("Stale · updated \(time)").font(.system(size: 10)).foregroundStyle(.orange)
        } else {
            Text("Updated \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

private func color(_ u: Double) -> Color { u >= 85 ? .red : u >= 60 ? .orange : .green }

/// macOS desktop widgets are often shown in a monochrome "accented" style where every colour becomes the same
/// tint, so track and fill must differ by opacity, not just hue. Full-colour mode keeps green/orange/red.
private struct Tone {
    let mode: WidgetRenderingMode
    var full: Bool { mode == .fullColor }
    func fill(_ u: Double) -> Color { full ? color(u) : Color.primary }
    var track: Color { Color.primary.opacity(0.22) }
    var tick: Color { full ? Color.white : Color.primary }
}

struct Ring: View {
    @Environment(\.widgetRenderingMode) private var mode
    let value: Double          // percent used
    var showLeft = false
    var body: some View {
        let t = Tone(mode: mode)
        let shown = showLeft ? 100 - value : value
        ZStack {
            Circle().stroke(t.track, lineWidth: 9)
            Circle().trim(from: 0, to: max(0.02, min(1, shown / 100)))
                .stroke(t.fill(value), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            VStack(spacing: 0) {
                Text("\(Format.displayPercent(used: value, showRemaining: showLeft))%")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                if showLeft { Text("left").font(.system(size: 9)).foregroundStyle(.secondary) }
            }
        }
    }
}

/// Progress bar: dim track, solid fill, and a tick where an even burn rate would be right now.
struct WBar: View {
    @Environment(\.widgetRenderingMode) private var mode
    let fraction: Double       // fill
    let pace: Double?
    var colorValue: Double? = nil   // percent used, which drives the colour (defaults to the fill)
    var body: some View {
        let t = Tone(mode: mode)
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(t.track)
                Capsule().fill(t.fill(colorValue ?? fraction * 100)).frame(width: max(6, w * min(1, max(0, fraction))))
                    .widgetAccentable()
                if let p = pace {
                    RoundedRectangle(cornerRadius: 1).fill(t.tick).frame(width: 2, height: 11)
                        .shadow(color: .black.opacity(0.4), radius: 1)
                        .offset(x: min(w - 2, max(0, w * min(1, max(0, p)) - 1)))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 11)
    }
}

struct Bar: View {
    @Environment(\.widgetRenderingMode) private var mode
    let title: String; let window: LimitWindow?; let length: TimeInterval; let now: Date
    var showLeft = false
    var body: some View {
        let u = window?.utilization ?? 0
        let pace = window.flatMap { Pace.compute(window: $0, length: length, now: now) }
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.caption.bold())
                Spacer()
                Text(window.map { "\(Format.displayPercent(used: $0.utilization, showRemaining: showLeft))%\(showLeft ? " left" : "")" } ?? "–").font(.caption.bold())
                    .foregroundStyle(Tone(mode: mode).full ? color(u) : Color.primary)
            }
            WBar(fraction: (showLeft ? 100 - u : u) / 100, pace: pace.map { showLeft ? 1 - $0.expected / 100 : $0.expected / 100 }, colorValue: u)
            if let r = window?.resetsAt { Text("Resets in \(Format.resetsIn(r, now: now))").font(.system(size: 10)).foregroundStyle(.secondary) }
        }
    }
}

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var mode
    let entry: UsageEntry

    var body: some View {
        Group {
            if let s = entry.snapshot, let l = s.limits {
                switch family {
                case .systemSmall:
                    let weekly = entry.configuration.smallMetric == .weekly
                    let main = weekly ? l.sevenDay : l.fiveHour
                    let other = weekly ? l.fiveHour : l.sevenDay
                    VStack(spacing: 6) {
                        Text(weekly ? "Weekly" : "5h session").font(.caption2).foregroundStyle(.secondary)
                        Ring(value: main?.utilization ?? 0, showLeft: entry.showLeft).frame(width: 78, height: 78)
                        Text("\(weekly ? "5h" : "Week") \(Format.displayPercent(used: other?.utilization ?? 0, showRemaining: entry.showLeft))%")
                            .font(.caption2.bold())
                        FreshnessCaption(snapshot: s, now: entry.date)
                    }
                case .systemMedium:
                    VStack(alignment: .leading, spacing: 10) {
                        Bar(title: "5-Hour Session", window: l.fiveHour, length: Pace.fiveHours, now: entry.date, showLeft: entry.showLeft)
                        Bar(title: "Weekly Limit", window: l.sevenDay, length: Pace.week, now: entry.date, showLeft: entry.showLeft)
                        Text("Today \(Format.cost(s.today.cost)) · \(Format.tokens(s.today.tokens.total)) tokens")
                            .font(.caption2).foregroundStyle(.secondary)
                        FreshnessCaption(snapshot: s, now: entry.date)
                    }
                default:
                    VStack(alignment: .leading, spacing: 10) {
                        Bar(title: "5-Hour Session", window: l.fiveHour, length: Pace.fiveHours, now: entry.date, showLeft: entry.showLeft)
                        Bar(title: "Weekly Limit", window: l.sevenDay, length: Pace.week, now: entry.date, showLeft: entry.showLeft)
                        if let m = l.weeklyModel { Bar(title: "Weekly \(m.name.capitalized)", window: m.window, length: Pace.week, now: entry.date, showLeft: entry.showLeft) }
                        Chart(s.daily) { p in
                            BarMark(x: .value("d", p.day, unit: .day), y: .value("c", p.cost))
                                .foregroundStyle(mode == .fullColor ? AnyShapeStyle(.orange.gradient) : AnyShapeStyle(Color.primary))
                        }
                        .chartYAxis { AxisMarks { v in AxisValueLabel { Text(Format.cost(v.as(Double.self) ?? 0)).font(.system(size: 9)) } } }
                        .frame(height: 70)
                        HStack {
                            Text("Today \(Format.cost(s.today.cost))"); Spacer(); Text("7d \(Format.cost(s.last7.cost))")
                        }.font(.caption.bold())
                        FreshnessCaption(snapshot: s, now: entry.date)
                    }
                }
            } else {
                VStack { Image(systemName: "gauge.with.dots.needle.50percent"); Text("Open Claude Usage to sync").font(.caption2) }
                    .foregroundStyle(.secondary)
            }
        }
        .unredacted()   // if the system falls back to the placeholder, still show the last known numbers
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "claudeusage://open"))   // tap opens the app's panel
    }
}

@main
struct UsageWidgetBundle: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ClaudeUsage", intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Usage")
        .description("5-hour and weekly limits, plus today's cost. Choose used or remaining, and the small widget's metric by editing the widget.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
