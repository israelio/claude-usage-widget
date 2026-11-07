import AppKit
import SwiftUI

/// The 90-day history window. It is created and shown only on request (footer button), instead of being a SwiftUI
/// `Window` scene, because SwiftUI shows such scenes by itself whenever the app is activated, for example by a
/// desktop widget click.
@MainActor
final class HistoryWindowController {
    static let shared = HistoryWindowController()
    private var window: NSWindow?
    private var service: UsageService?

    func configure(service: UsageService) { self.service = service }

    func show() {
        guard let service else { return }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "Usage History"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: HistoryView(service: service))
            w.setFrameAutosaveName("UsageHistoryWindow")
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
