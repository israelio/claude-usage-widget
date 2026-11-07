import AppKit
import SwiftUI

final class FloatingPanel: NSPanel {
    init<Content: View>(content: Content) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 360, height: 640),
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
    }
}
