import SwiftUI
import UsageCore

struct PopoverView: View {
    /// Tall enough to show every card without scrolling; capped to the screen so it never overflows.
    static var preferredHeight: CGFloat {
        min(960, (NSScreen.main?.visibleFrame.height ?? 900) - 40)
    }

    @ObservedObject var service: UsageService
    var openHistory: () -> Void
    var openSettings: () -> Void
    @State private var showAbout = false
    @Environment(\.colorScheme) private var scheme

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
        .frame(width: 360, height: PopoverView.preferredHeight)
        .background(
            ZStack {
                Rectangle().fill(.regularMaterial)
                if scheme == .dark { Color.black.opacity(0.42) }   // deepen the panel in dark mode
            }
        )
    }

    private var footer: some View {
        GlassCard {
            HStack(spacing: 6) {
                RaisedIconButton(systemImage: "arrow.up.right.square", title: "Claude", help: "Open your usage page on claude.ai") {
                    NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
                }
                Spacer()
                RaisedIconButton(systemImage: "arrow.clockwise", help: "Refresh now") { service.refreshNow() }
                RaisedIconButton(systemImage: "chart.bar.doc.horizontal", help: "90-day usage history") { openHistory() }
                RaisedIconButton(systemImage: "gearshape", help: "Settings") { openSettings() }
                RaisedIconButton(systemImage: "star.circle", help: "About — Staraware: pay with a GitHub star") { showAbout.toggle() }
                    .popover(isPresented: $showAbout, arrowEdge: .top) { AboutView() }
                RaisedIconButton(systemImage: "power", help: "Quit Claude Usage", hoverTint: Color.red) { NSApp.terminate(nil) }
            }
        }
    }
}
