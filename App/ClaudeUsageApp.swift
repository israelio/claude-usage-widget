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
                    HistoryWindowController.shared.configure(service: service)
                    service.start(); Updater.shared.start(); syncPanel()
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
                    openHistory: { HistoryWindowController.shared.show() },
                    openSettings: { NSApp.activate(ignoringOtherApps: true); openSettings() })
    }
}

/// Always-alive menu bar label (also hosts the status item tooltip).
private struct LabelHost: View {
    @ObservedObject var service: UsageService
    @ObservedObject var settings: AppSettings

    var body: some View {
        let tip = MenuBarLabel.tooltip(for: service.limits, mode: settings.prefs.menuBarMode)
        MenuBarLabel(service: service, settings: settings)
            .help(tip)
            .onChange(of: tip) { _, t in StatusItemTooltip.apply(t) }
            .onChange(of: settings.prefs.menuBarMode) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { StatusItemTooltip.apply(tip) }
            }
            .task {
                // Developer convenience (used for README screenshots): `open Claude\ Usage.app --args --show-history`.
                if CommandLine.arguments.contains("--show-history") {
                    HistoryWindowController.shared.configure(service: service)
                    HistoryWindowController.shared.show()
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
                StatusItemTooltip.apply(MenuBarLabel.tooltip(for: service.limits, mode: settings.prefs.menuBarMode))
            }
    }
}
