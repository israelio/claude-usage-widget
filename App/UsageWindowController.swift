import AppKit
import SwiftUI

/// The "Usage" window (daily chart plus the by-project / by-model tables). It is created and shown only on request
/// (footer button or a click on a Daily Usage bar) and reused: showing it again just switches the range it shows. It is
/// not a SwiftUI `Window` scene because SwiftUI shows such scenes by itself whenever the app is activated (for example
/// by a desktop widget click).
///
/// Opened from the floating panel, the window is attached to that panel as a child: it sits just to the right of the
/// panel (or to the left if there is no room), top-aligned, above it, and moves with it. Opened from the menu bar
/// popover it is a normal free-standing window, so it can stay open after the popover closes.
@MainActor
final class UsageWindowController {
    static let shared = UsageWindowController()
    private var window: NSWindow?
    private var service: UsageService?
    private var closeObserver: NSObjectProtocol?
    private let model = UsageViewModel()

    func configure(service: UsageService) { self.service = service }

    /// - day: the bar that was clicked (the window opens on that day), or nil for the last `days` days.
    /// - attachTo: the floating panel to glue the window to, or nil for a free-standing window.
    /// - sessions: open in Sessions granularity (7 days); nil follows the saved granularity; the developer env
    ///   `CLAUDEUSAGE_USAGE_GRANULARITY=sessions|days` overrides both. A clicked day always opens Days mode on that day.
    func show(day: Date?, days: Int = 30, sessions: Bool? = nil, attachTo panel: NSWindow? = nil) {
        guard let service else { return }
        let env = ProcessInfo.processInfo.environment["CLAUDEUSAGE_USAGE_GRANULARITY"]
        let wantSessions = env.map { $0 == "sessions" } ?? sessions ?? (UserDefaults.standard.string(forKey: "usageGranularity") == "sessions")
        model.open(day: day, days: days, sessions: wantSessions)
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "Usage"
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 760, height: 520)
            w.contentView = NSHostingView(rootView: UsageView(service: service, model: model))
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

    private func detach() { if let window { WindowPlacement.detach(window) } }
}
