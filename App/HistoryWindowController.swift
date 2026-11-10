import AppKit
import SwiftUI

/// The 90-day history window. It is created and shown only on request (footer button), instead of being a SwiftUI
/// `Window` scene, because SwiftUI shows such scenes by itself whenever the app is activated (for example by a
/// desktop widget click).
///
/// Opened from the floating panel's History button, the window is attached to that panel as a child: it sits just to
/// the right of the panel (or to the left if there is no room), top-aligned, above it, and moves with it.
/// Opened from the menu bar popover it is a normal free-standing window, so it can stay open after the popover closes.
@MainActor
final class HistoryWindowController {
    static let shared = HistoryWindowController()
    private var window: NSWindow?
    private var service: UsageService?
    private var closeObserver: NSObjectProtocol?

    func configure(service: UsageService) { self.service = service }

    /// - attachTo: the floating panel to glue the window to, or nil for a free-standing window.
    func show(attachTo panel: NSWindow? = nil) {
        guard let service else { return }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "Usage History"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: HistoryView(service: service))
            closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.detach() }
            }
            window = w
        }
        guard let window else { return }
        if let panel, panel.isVisible {
            WindowPlacement.attach(window, to: panel)
        } else {
            detach()
            if !window.isVisible { window.center() }
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// The window while it is open (so a sibling window can be placed next to it).
    var visibleWindow: NSWindow? { window?.isVisible == true ? window : nil }

    private func detach() { if let window { WindowPlacement.detach(window) } }
}
