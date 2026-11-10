import AppKit
import SwiftUI

/// The "Usage by Project" window, opened by clicking a bar on the Daily Usage chart. Created on request (like the
/// History window) and reused: showing it again just switches the day it is filtered to.
///
/// Opened from the floating panel it is attached to that panel as a child (beside the History window if that is open
/// too); opened from the menu bar popover it is a normal free-standing window.
@MainActor
final class ProjectsWindowController {
    static let shared = ProjectsWindowController()
    private var window: NSWindow?
    private var service: UsageService?
    private var closeObserver: NSObjectProtocol?
    private let model = ProjectsViewModel()

    func configure(service: UsageService) { self.service = service }

    /// - day: the bar that was clicked (the window opens filtered to that day), or nil for the default 30 days.
    /// - attachTo: the floating panel to glue the window to, or nil for a free-standing window.
    func show(day: Date?, attachTo panel: NSWindow? = nil) {
        guard let service else { return }
        model.open(day: day)
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "Usage by Project"
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 640, height: 420)
            w.contentView = NSHostingView(rootView: ProjectsView(service: service, model: model))
            closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.detach() }
            }
            window = w
        }
        guard let window else { return }
        if let panel, panel.isVisible {
            let history = HistoryWindowController.shared.visibleWindow
            WindowPlacement.attach(window, to: panel, beside: history?.parent === panel ? history : nil)
        } else {
            detach()
            if !window.isVisible { window.center() }
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func detach() { if let window { WindowPlacement.detach(window) } }
}
