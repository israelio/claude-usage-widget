import SwiftUI
import AppKit

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
            PopoverView(service: service)
                .onAppear { service.start(); service.refreshNow() }
        } label: {
            MenuBarLabel(service: service, settings: settings)
                .onAppear { service.start(); syncPanel() }
        }
        .menuBarExtraStyle(.window)
        .onChange(of: settings.prefs.floatingPanel) { _, _ in syncPanel() }

        Window("Usage History", id: "history") { HistoryView(service: service) }
        Settings { SettingsView(settings: settings) }
    }

    private func syncPanel() {
        if settings.prefs.floatingPanel {
            if panel == nil { panel = FloatingPanel(content: PopoverView(service: service)) }
            panel?.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }
}
