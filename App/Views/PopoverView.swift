import SwiftUI
import UsageCore

struct PopoverView: View {
    /// Height the roomy layout needs to show every card without scrolling.
    static let fullLayoutHeight: CGFloat = 1120
    static func availableHeight(for screen: NSScreen?) -> CGFloat {
        ScreenMetrics.visibleHeight(screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)) - 40
    }
    /// Screens shorter than the roomy layout get the compact layout instead of scrolling.
    static func isCompact(for screen: NSScreen?) -> Bool { availableHeight(for: screen) < fullLayoutHeight }
    /// Tall enough to show every card without scrolling; capped to the screen so it never overflows.
    static var preferredHeight: CGFloat { preferredHeight(for: NSScreen.main) }
    static func preferredHeight(for screen: NSScreen?) -> CGFloat { min(fullLayoutHeight, availableHeight(for: screen)) }

    @ObservedObject var service: UsageService
    var openHistory: () -> Void
    var openSettings: () -> Void
    /// Opens the per-project breakdown, for the clicked day on the Daily Usage chart.
    var openProjects: (Date?) -> Void = { _ in }
    /// Fixed height for the menu bar popover; nil lets the content fill its container (the resizable floating panel).
    var panelHeight: CGFloat? = PopoverView.preferredHeight
    /// Reports the height the content wants (used by the floating panel to size itself to its content).
    var onContentHeight: ((CGFloat) -> Void)? = nil
    @State private var showAbout = false
    @State private var contentH: CGFloat = 0
    @State private var footerH: CGFloat = 0
    @Environment(\.colorScheme) private var scheme

    /// The menu bar popover is as tall as its content (up to `panelHeight`, the screen limit), so there is no empty gap
    /// above the pinned footer; the floating panel (panelHeight == nil) is sized by its window instead.
    private var effectiveHeight: CGFloat? {
        guard let cap = panelHeight else { return nil }
        let total = contentH + footerH
        return total > 0 ? min(total, cap) : cap
    }

    var body: some View {
        let compact = Self.isCompact(for: NSScreen.main)
        VStack(spacing: 0) {
        ScrollView {
            VStack(spacing: compact ? 6 : 10) {
                titleRow
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
                DailyCard(service: service, openProjects: openProjects)
                TokenCard(summary: service.summary)
                if let p = service.plan { PlanCard(plan: p, extraUsage: service.limits?.extraUsage) }
                if !compact { GlassCard {
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
                } }
                if !service.groupAvailable {
                    Text("Widgets need signing + app group").font(.caption2).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(compact ? 8 : 10)
            .background(GeometryReader { g in Color.clear.preference(key: PopoverContentHeightKey.self, value: g.size.height) })
        }
        footer(compact: compact)
            .padding(.horizontal, compact ? 8 : 10).padding(.bottom, compact ? 8 : 10).padding(.top, 2)
            .background(GeometryReader { g in Color.clear.preference(key: PopoverFooterHeightKey.self, value: g.size.height) })
        }
        .onPreferenceChange(PopoverContentHeightKey.self) { h in contentH = h; onContentHeight?(h + footerH) }
        .onPreferenceChange(PopoverFooterHeightKey.self) { h in footerH = h; onContentHeight?(contentH + h) }
        .environment(\.compact, compact)
        .frame(width: 360, height: effectiveHeight)
        .background(
            ZStack {
                Rectangle().fill(.regularMaterial)
                if scheme == .dark { Color.black.opacity(0.42) }   // deepen the panel in dark mode
            }
        )
    }

    private var titleRow: some View {
        HStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 18, height: 18)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Claude Usage").font(.system(size: 12, weight: .semibold))
                Text("v\(AppInfo.version)").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
            Spacer()
            StarPill()
        }
        .padding(.horizontal, 4)
    }

    private func footer(compact: Bool) -> some View {
        GlassCard {
            HStack(spacing: 6) {
                RaisedIconButton(systemImage: "arrow.up.right.square", title: "Claude", help: "Open your usage page on claude.ai") {
                    NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
                }
                if compact {
                    HStack(spacing: 3) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text(service.nextRefresh, style: .timer).monospacedDigit()
                    }
                    .font(.system(size: 10)).foregroundStyle(.secondary).help("Time until the next refresh")
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

struct PopoverContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct PopoverFooterHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
