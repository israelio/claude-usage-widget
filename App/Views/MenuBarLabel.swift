import SwiftUI
import AppKit
import UsageCore

struct MenuBarLabel: View {
    @ObservedObject var service: UsageService
    @ObservedObject var settings: AppSettings

    var body: some View {
        if settings.prefs.menuBarMode == .iconOnly {
            Image(systemName: "gauge.with.dots.needle.50percent")
        } else {
            let t = MenuBarText.make(limits: service.limits, todayCost: service.summary.today.cost,
                                     items: settings.prefs.effectiveMenuBarItems,
                                     showRemaining: settings.prefs.showRemaining, now: Date())
            // Keep a visible item in the bar even if every toggle is off.
            if t.isEmpty { Image(systemName: "gauge.with.dots.needle.50percent") } else { Text(t) }
        }
    }
}

extension MenuBarLabel {
    /// Short hover text that explains exactly the items shown in the menu bar label.
    static func tooltip(service: UsageService, prefs: Prefs, now: Date = Date()) -> String {
        MenuBarText.tooltip(limits: service.limits, todayCost: service.summary.today.cost,
                            items: prefs.effectiveMenuBarItems, showRemaining: prefs.showRemaining, now: now)
    }
}

/// MenuBarExtra doesn't forward `.help` to its status item button, so set the tooltip on the button directly.
enum StatusItemTooltip {
    @MainActor static func apply(_ text: String) {
        for w in NSApp.windows where String(describing: type(of: w)).contains("StatusBar") {
            set(text, in: w.contentView)
        }
    }
    @MainActor private static func set(_ text: String, in view: NSView?) {
        guard let view else { return }
        if let b = view as? NSButton { b.toolTip = text }
        view.subviews.forEach { set(text, in: $0) }
    }
}
