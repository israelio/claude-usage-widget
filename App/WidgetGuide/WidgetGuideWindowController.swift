import AppKit
import SwiftUI

/// The "Desktop widgets" guide window. Created on request only (not a SwiftUI `Window` scene, which would auto-open).
@MainActor
final class WidgetGuideWindowController {
    static let shared = WidgetGuideWindowController()
    private var window: NSWindow?

    func show(firstRun: Bool) {
        let w = window ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
                                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Claude Usage — Desktop widgets"
        w.isReleasedWhenClosed = false
        // Rebuilt on every show so the mode (and the status polling) is fresh.
        w.contentView = NSHostingView(rootView: WidgetGuideView(mode: firstRun ? .firstRun : .settings) { [weak w] in w?.close() })
        if window == nil { w.center() }
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}
