import AppKit

/// Shared placement for the History and Usage by Project windows: glued to the floating panel as a child window
/// (to its right, or left when there is no room, top-aligned, with a gap), or free-standing otherwise.
@MainActor
enum WindowPlacement {
    static let gap: CGFloat = 12

    /// Attaches `w` to `panel` and positions it beside `panel`, or beside `neighbor` (another window already attached to
    /// the panel) so that the two sit side by side instead of overlapping.
    static func attach(_ w: NSWindow, to panel: NSWindow, beside neighbor: NSWindow? = nil) {
        if w.parent !== panel {
            w.parent?.removeChildWindow(w)
            panel.addChildWindow(w, ordered: .above)
        }
        w.level = panel.level
        let area = (panel.screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let anchor = neighbor ?? panel
        let leftSide = neighbor.map { $0.frame.minX < panel.frame.minX } ?? false
        var origin = NSPoint(x: anchor.frame.maxX + gap, y: panel.frame.maxY - w.frame.height)
        if leftSide || origin.x + w.frame.width > area.maxX { origin.x = anchor.frame.minX - gap - w.frame.width }
        origin.x = max(area.minX, origin.x)
        origin.y = max(area.minY, origin.y)
        w.setFrameOrigin(origin)
    }

    static func detach(_ w: NSWindow) {
        w.parent?.removeChildWindow(w)
        w.level = .normal
    }
}
