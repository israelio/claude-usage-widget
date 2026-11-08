import AppKit
import SwiftUI

enum ScreenMetrics {
    /// Usable height of a screen. `CLAUDEUSAGE_SCREEN_HEIGHT` (points) overrides it so small laptop screens can be
    /// simulated on a large display.
    static func visibleHeight(_ frame: NSRect) -> CGFloat {
        if let v = ProcessInfo.processInfo.environment["CLAUDEUSAGE_SCREEN_HEIGHT"], let d = Double(v) { return CGFloat(d) }
        return frame.height
    }
}

private struct CompactLayoutKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// True on screens too short for the roomy layout: tighter spacing, shorter charts, fewer rows.
    var compact: Bool {
        get { self[CompactLayoutKey.self] }
        set { self[CompactLayoutKey.self] = newValue }
    }
}
