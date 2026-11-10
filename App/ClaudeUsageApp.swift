import SwiftUI
import AppKit

@main
struct ClaudeUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var settings: AppSettings
    @StateObject private var service: UsageService

    init() {
        // Show native tooltips quickly (default is ~1.5s).
        UserDefaults.standard.set(100, forKey: "NSInitialToolTipDelay")
        // Older versions used a SwiftUI "history" window scene; its saved-window entry makes that window reappear.
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame history")
        WidgetOnboarding.captureFreshInstall()   // must run before AppSettings() creates prefs
        let s = AppSettings()
        _settings = StateObject(wrappedValue: s)
        _service = StateObject(wrappedValue: UsageService(settings: s))
        Updater.shared.configure(settings: s)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(service: service)
        } label: {
            LabelHost(service: service, settings: settings)
                .onAppear {
                    // Hand the panel the app's real (installed) service; creating one in init() would be a separate copy.
                    PanelController.shared.configure(service: service, settings: settings)
                    UsageWindowController.shared.configure(service: service)
                    service.start(); Updater.shared.start(); syncPanel()
                    WidgetOnboarding.offerIfFresh()
                }   // start() also performs the first refresh
        }
        .menuBarExtraStyle(.window)
        .onChange(of: settings.prefs.floatingPanel) { _, _ in syncPanel() }

        Settings { SettingsView(settings: settings) }
    }

    private func syncPanel() {
        if settings.prefs.floatingPanel { PanelController.shared.show() } else { PanelController.shared.hide() }
    }
}

/// Popover inside the MenuBarExtra, where SwiftUI environment actions work.
private struct MenuBarPopover: View {
    @ObservedObject var service: UsageService
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        PopoverView(service: service,
                    openSettings: { NSApp.activate(ignoringOtherApps: true); openSettings() },
                    openUsage: { MenuBarPopoverActions.openUsage($0) })
    }
}

/// Always-alive menu bar label (also hosts the status item tooltip).
private struct LabelHost: View {
    @ObservedObject var service: UsageService
    @ObservedObject var settings: AppSettings
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let tip = MenuBarLabel.tooltip(service: service, prefs: settings.prefs)
        MenuBarLabel(service: service, settings: settings)
            .help(tip)
            .onChange(of: tip) { _, t in StatusItemTooltip.apply(t) }
            .onChange(of: settings.prefs.showRemaining) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { StatusItemTooltip.apply(tip) }
            }
            .onChange(of: settings.prefs.menuBarMode) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { StatusItemTooltip.apply(tip) }
            }
            .onChange(of: settings.prefs.menuBarItems) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { StatusItemTooltip.apply(tip) }
            }
            .task {
                // Developer conveniences (README screenshots / checks), all opening the Usage window:
                //   --show-history           for 90 days, as the panel's footer button does (glued to the panel if visible)
                //   --show-history-menubar   for 90 days, as the menu bar popover's button does (free-standing)
                //   --show-projects[=-N]     free-standing for 30 days (or for the day N days ago)
                //   --show-sessions          free-standing in Sessions granularity (7 days)
                //   --show-widget-guide      opens the desktop widget guide window (first-run mode)
                //   CLAUDEUSAGE_PROJECTS_EXPAND=N  (env var) expands the first N rows in that window on appear
                //                            (99 also expands the "Other" project group)
                //   CLAUDEUSAGE_ANONYMIZE_PROJECTS=1  (env var) shows placeholder project names
                //   CLAUDEUSAGE_USAGE_GROUPBY=model   (env var) groups by model instead of project
                //   CLAUDEUSAGE_USAGE_GRANULARITY=sessions|days  (env var) overrides the saved Days / Sessions choice
                let args = CommandLine.arguments
                if args.contains("--show-settings") {   // developer aid: open the Settings window
                    try? await Task.sleep(nanoseconds: 7_000_000_000)
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                if let a = args.first(where: { $0.hasPrefix("--show-projects") }) {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    UsageWindowController.shared.configure(service: service)
                    var day: Date? = nil
                    if let n = Int(a.dropFirst("--show-projects=".count)), a.contains("=") { day = Calendar.current.date(byAdding: .day, value: -abs(n), to: Date()) }
                    UsageWindowController.shared.show(day: day, sessions: false, attachTo: nil)
                }
                if args.contains("--show-widget-guide") {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    WidgetGuideWindowController.shared.show(firstRun: true)
                }
                if args.contains("--show-sessions") {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    UsageWindowController.shared.configure(service: service)
                    UsageWindowController.shared.show(day: nil, sessions: true, attachTo: nil)
                }
                if args.contains("--show-history") || args.contains("--show-history-menubar") {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)   // let the pinned panel appear first
                    UsageWindowController.shared.configure(service: service)
                    UsageWindowController.shared.show(day: nil, days: 90, sessions: false, attachTo: args.contains("--show-history") ? PanelController.shared.visiblePanel : nil)
                    if args.contains("--show-history-menubar") { UsageWindowController.shared.liftAbovePopover() }
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
                StatusItemTooltip.apply(MenuBarLabel.tooltip(service: service, prefs: settings.prefs))
            }
    }
}

/// Actions triggered from the menu bar popover.
@MainActor
enum MenuBarPopoverActions {
    /// Opens the Usage window as a free-standing window above the popover (see `liftAbovePopover`).
    static func openUsage(_ day: Date?) {
        UsageWindowController.shared.show(day: day, attachTo: nil)
        UsageWindowController.shared.liftAbovePopover()
    }
}
