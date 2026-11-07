import SwiftUI
import AppKit

extension Notification.Name {
    static let openHistoryRequested = Notification.Name("ClaudeUsageWidget.openHistory")
}

@main
struct ClaudeUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var settings: AppSettings
    @StateObject private var service: UsageService
    @State private var panel: FloatingPanel?

    init() {
        let s = AppSettings()
        _settings = StateObject(wrappedValue: s)
        _service = StateObject(wrappedValue: UsageService(settings: s))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(service: service)
        } label: {
            LabelHost(service: service, settings: settings)
                .onAppear { service.start(); syncPanel() }   // start() also performs the first refresh
        }
        .menuBarExtraStyle(.window)
        .onChange(of: settings.prefs.floatingPanel) { _, _ in syncPanel() }

        Window("Usage History", id: "history") { HistoryView(service: service) }
        Settings { SettingsView(settings: settings) }
    }

    private func syncPanel() {
        if settings.prefs.floatingPanel {
            if panel == nil {
                panel = FloatingPanel(content: PopoverView(
                    service: service,
                    openHistory: { NotificationCenter.default.post(name: .openHistoryRequested, object: nil) },
                    openSettings: {
                        NSApp.activate(ignoringOtherApps: true)
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }),
                    onClose: { [settings] in Task { @MainActor in settings.prefs.floatingPanel = false } })
            }
            panel?.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }
}

/// Popover inside the MenuBarExtra, where SwiftUI environment actions work.
private struct MenuBarPopover: View {
    @ObservedObject var service: UsageService
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        PopoverView(service: service,
                    openHistory: { openWindow(id: "history"); NSApp.activate(ignoringOtherApps: true) },
                    openSettings: { NSApp.activate(ignoringOtherApps: true); openSettings() })
    }
}

/// Always-alive menu bar label; also services history requests coming from the floating panel.
private struct LabelHost: View {
    @ObservedObject var service: UsageService
    @ObservedObject var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarLabel(service: service, settings: settings)
            .onReceive(NotificationCenter.default.publisher(for: .openHistoryRequested)) { _ in
                openWindow(id: "history"); NSApp.activate(ignoringOtherApps: true)
            }
    }
}
