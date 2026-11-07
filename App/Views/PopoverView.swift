import SwiftUI
import UsageCore

struct PopoverView: View {
    @ObservedObject var service: UsageService
    var openHistory: () -> Void
    var openSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let e = service.error {
                    Label(e + (service.limits?.isEstimated == false ? " — showing last known values" : " — showing local estimate"), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
                }
                if let l = service.limits {
                    if let w = l.fiveHour { LimitCard(title: "5-Hour Session", icon: "clock", window: w, length: Pace.fiveHours, estimated: l.isEstimated) }
                    if let w = l.sevenDay { LimitCard(title: "Weekly Limit", icon: "calendar", window: w, length: Pace.week, estimated: l.isEstimated) }
                    if let m = l.weeklyModel {
                        LimitCard(title: "Weekly \(m.name.capitalized)", icon: "book", window: m.window, length: Pace.week, estimated: false)
                    }
                    PaceCard(samples: service.history.samples, window: l.fiveHour)
                } else {
                    ProgressView().padding()
                }
                DailyCard(service: service)
                TokenCard(summary: service.summary)
                GlassCard {
                    HStack {
                        Text("Next refresh in ").foregroundStyle(.secondary)
                        Text(service.nextRefresh, style: .timer).monospacedDigit()
                        Spacer()
                        if let l = service.limits {
                            if l.isEstimated { Text("estimated").font(.caption).foregroundStyle(.orange) }
                            else if service.error != nil {
                                Text("updated \(Text(l.fetchedAt, style: .relative)) ago").font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }.font(.system(size: 11))
                }
                if !service.groupAvailable {
                    Text("Widgets need signing + app group").font(.caption2).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                footer
            }
            .padding(10)
        }
        .frame(width: 360, height: 640)
        .background(.regularMaterial)
    }

    private var footer: some View {
        GlassCard {
            HStack(spacing: 14) {
                Button { NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!) } label: { Label("Claude", systemImage: "arrow.up.right.square") }
                Spacer()
                Button { service.refreshNow() } label: { Image(systemName: "arrow.clockwise") }
                Button { openHistory() } label: { Image(systemName: "chart.bar.doc.horizontal") }
                Button { openSettings() } label: { Image(systemName: "gearshape") }
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
            }.buttonStyle(.plain).font(.system(size: 13))
        }
    }
}
