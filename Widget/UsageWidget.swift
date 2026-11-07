import WidgetKit
import SwiftUI
import Charts
import UsageCore

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedSnapshot?
}

struct Provider: TimelineProvider {
    private func load() -> SharedSnapshot? {
        let id = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? ""
        guard let url = SharedSnapshot.groupURL(groupID: id) else { return nil }
        return SharedSnapshot.load(from: url)
    }
    func placeholder(in context: Context) -> UsageEntry { UsageEntry(date: Date(), snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(date: Date(), snapshot: load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = UsageEntry(date: Date(), snapshot: load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

private struct FreshnessCaption: View {
    let snapshot: SharedSnapshot
    var body: some View {
        if snapshot.limits?.isEstimated == true {
            Text("estimated").font(.system(size: 10)).foregroundStyle(.orange)
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
    let value: Double
    var body: some View {
        let t = Tone(mode: mode)
        ZStack {
            Circle().stroke(t.track, lineWidth: 9)
            Circle().trim(from: 0, to: max(0.02, min(1, value / 100)))
                .stroke(t.fill(value), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            Text("\(Int(value.rounded()))%").font(.system(size: 22, weight: .bold, design: .rounded))
        }
    }
}

/// Progress bar: dim track, solid fill, and a tick where an even burn rate would be right now.
struct WBar: View {
    @Environment(\.widgetRenderingMode) private var mode
    let fraction: Double
    let pace: Double?
    var body: some View {
        let t = Tone(mode: mode)
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(t.track)
                Capsule().fill(t.fill(fraction * 100)).frame(width: max(6, w * min(1, max(0, fraction))))
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
    var body: some View {
        let u = window?.utilization ?? 0
        let pace = window.flatMap { Pace.compute(window: $0, length: length, now: now) }
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.caption.bold())
                Spacer()
                Text(window.map { "\(Int($0.utilization.rounded()))%" } ?? "–").font(.caption.bold())
                    .foregroundStyle(Tone(mode: mode).full ? color(u) : Color.primary)
            }
            WBar(fraction: u / 100, pace: pace.map { $0.expected / 100 })
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
                    VStack(spacing: 6) {
                        Text("5h session").font(.caption2).foregroundStyle(.secondary)
                        Ring(value: l.fiveHour?.utilization ?? 0).frame(width: 78, height: 78)
                        Text("Week \(Int((l.sevenDay?.utilization ?? 0).rounded()))%").font(.caption2.bold())
                        FreshnessCaption(snapshot: s)
                    }
                case .systemMedium:
                    VStack(alignment: .leading, spacing: 10) {
                        Bar(title: "5-Hour Session", window: l.fiveHour, length: Pace.fiveHours, now: entry.date)
                        Bar(title: "Weekly Limit", window: l.sevenDay, length: Pace.week, now: entry.date)
                        Text("Today \(Format.cost(s.today.cost)) · \(Format.tokens(s.today.tokens.total)) tokens")
                            .font(.caption2).foregroundStyle(.secondary)
                        FreshnessCaption(snapshot: s)
                    }
                default:
                    VStack(alignment: .leading, spacing: 10) {
                        Bar(title: "5-Hour Session", window: l.fiveHour, length: Pace.fiveHours, now: entry.date)
                        Bar(title: "Weekly Limit", window: l.sevenDay, length: Pace.week, now: entry.date)
                        if let m = l.weeklyModel { Bar(title: "Weekly \(m.name.capitalized)", window: m.window, length: Pace.week, now: entry.date) }
                        Chart(s.daily) { p in
                            BarMark(x: .value("d", p.day, unit: .day), y: .value("c", p.cost))
                                .foregroundStyle(mode == .fullColor ? AnyShapeStyle(.orange.gradient) : AnyShapeStyle(Color.primary))
                        }
                        .chartYAxis { AxisMarks { v in AxisValueLabel { Text(Format.cost(v.as(Double.self) ?? 0)).font(.system(size: 9)) } } }
                        .frame(height: 70)
                        HStack {
                            Text("Today \(Format.cost(s.today.cost))"); Spacer(); Text("7d \(Format.cost(s.last7.cost))")
                        }.font(.caption.bold())
                        FreshnessCaption(snapshot: s)
                    }
                }
            } else {
                VStack { Image(systemName: "gauge.with.dots.needle.50percent"); Text("Open Claude Usage to sync").font(.caption2) }
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

@main
struct UsageWidgetBundle: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudeUsage", provider: Provider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Usage")
        .description("5-hour and weekly limits, plus today's cost.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
