import AppKit
import SwiftUI

final class FloatingPanel: NSPanel {
    deinit { if let o = closeObserver { NotificationCenter.default.removeObserver(o) } }
    private var closeObserver: NSObjectProtocol?

    init<Content: View>(content: Content, onClose: @escaping () -> Void) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 360, height: PopoverView.preferredHeight),
                   styleMask: [.titled, .fullSizeContentView, .closable, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        setFrameAutosaveName("FloatingUsagePanel")
        contentView = NSHostingView(rootView: content)
        // The red close button closes the window without going through our prefs; report it.
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: self, queue: .main) { _ in
            onClose()
        }
    }
}
