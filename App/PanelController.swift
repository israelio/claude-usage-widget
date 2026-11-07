import AppKit
import SwiftUI

/// Owns the always-on-top panel. Used both for the "floating panel" preference and for opening the app
/// from a desktop widget click (a menu bar app has no window of its own to show).
@MainActor
final class PanelController {
    static let shared = PanelController()
    private var panel: FloatingPanel?
    private var service: UsageService?
    private var settings: AppSettings?

    func configure(service: UsageService, settings: AppSettings) {
        self.service = service; self.settings = settings
    }

    func show(activate: Bool = false) {
        guard let service, let settings else { return }
        if panel == nil {
            panel = FloatingPanel(content: PopoverView(
                service: service,
                openHistory: { NotificationCenter.default.post(name: .openHistoryRequested, object: nil) },
                openSettings: {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }),
                onClose: { Task { @MainActor in settings.prefs.floatingPanel = false } })
        }
        panel?.orderFrontRegardless()
        if activate { NSApp.activate(ignoringOtherApps: true) }
    }

    func hide() { panel?.orderOut(nil) }
}
