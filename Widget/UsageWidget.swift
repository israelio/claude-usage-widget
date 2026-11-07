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

private func color(_ u: Double) -> Color { u >= 85 ? .red : u >= 60 ? .orange : .green }

struct Ring: View {
    let value: Double
    var body: some View {
        ZStack {
            Circle().stroke(.secondary.opacity(0.25), lineWidth: 9)
            Circle().trim(from: 0, to: min(1, value / 100)).stroke(color(value), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(value.rounded()))%").font(.system(size: 22, weight: .bold, design: .rounded))
        }
    }
}

struct Bar: View {
    let title: String; let window: LimitWindow?
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.caption.bold())
                Spacer()
                Text(window.map { "\(Int($0.utilization.rounded()))%" } ?? "–").font(.caption.bold())
            }
            ProgressView(value: min(1, (window?.utilization ?? 0) / 100)).tint(color(window?.utilization ?? 0))
            if let r = window?.resetsAt { Text("Resets in \(Format.resetsIn(r))").font(.system(size: 10)).foregroundStyle(.secondary) }
        }
    }
}

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
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
                    }
                case .systemMedium:
                    VStack(alignment: .leading, spacing: 10) {
                        Bar(title: "5-Hour Session", window: l.fiveHour)
                        Bar(title: "Weekly Limit", window: l.sevenDay)
                        Text("Today \(Format.cost(s.today.cost)) · \(Format.tokens(s.today.tokens.total)) tokens")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                default:
                    VStack(alignment: .leading, spacing: 10) {
                        Bar(title: "5-Hour Session", window: l.fiveHour)
                        Bar(title: "Weekly Limit", window: l.sevenDay)
                        if let m = l.weeklyModel { Bar(title: "Weekly \(m.name.capitalized)", window: m.window) }
                        Chart(s.daily) { p in
                            BarMark(x: .value("d", p.day, unit: .day), y: .value("c", p.cost)).foregroundStyle(.orange.gradient)
                        }.frame(height: 70)
                        HStack {
                            Text("Today \(Format.cost(s.today.cost))"); Spacer(); Text("7d \(Format.cost(s.last7.cost))")
                        }.font(.caption.bold())
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
