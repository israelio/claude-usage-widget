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
    /// A widget tap can arrive before the app's service is ready (cold launch); show as soon as it is.
    private var pendingShow = false
    private var pendingCentered = false

    func configure(service: UsageService, settings: AppSettings) {
        self.service = service; self.settings = settings
        if pendingShow { pendingShow = false; show(activate: true, centered: pendingCentered) }
    }

    /// - centered: place the panel in the middle of the screen the mouse is on (used when opened from a widget click).
    func show(activate: Bool = false, centered: Bool = false) {
        guard let service, let settings else { pendingShow = true; pendingCentered = centered; return }
        if panel == nil {
            panel = FloatingPanel(content: PopoverView(
                service: service,
                openHistory: { HistoryWindowController.shared.show() },
                openSettings: {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                },
                panelHeight: nil),
                onClose: { Task { @MainActor in settings.prefs.floatingPanel = false } })
        }
        if let panel {
            if centered, !panel.isVisible { center(panel) } else { fit(panel) }
        }
        panel?.orderFrontRegardless()
        if activate { NSApp.activate(ignoringOtherApps: true) }
    }

    func hide() { panel?.orderOut(nil) }

    private func center(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame
        var frame = panel.frame
        frame.size.height = min(frame.size.height, area.height - 40)
        frame.origin = NSPoint(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2)
        panel.setFrame(frame, display: true)
    }

    /// Keep the panel fully on a screen it overlaps (screen size or arrangement may have changed since it was saved).
    private func fit(_ panel: NSPanel) {
        let screen = NSScreen.screens.first { $0.frame.intersects(panel.frame) } ?? NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame
        var f = panel.frame
        f.size.height = min(f.height, area.height - 20)
        f.size.width = min(f.width, area.width - 20)
        f.origin.x = min(max(f.origin.x, area.minX), area.maxX - f.width)
        f.origin.y = min(max(f.origin.y, area.minY), area.maxY - f.height)
        if f != panel.frame { panel.setFrame(f, display: true) }
    }
}
