import SwiftUI
import AppKit
import UsageCore

struct MenuBarLabel: View {
    @ObservedObject var service: UsageService
    @ObservedObject var settings: AppSettings

    var body: some View {
        switch settings.prefs.menuBarMode {
        case .iconOnly: Image(systemName: "gauge.with.dots.needle.50percent")
        case .percent: Text(text(weekly: false, delta: false))
        case .sessionWeekly: Text(text(weekly: true, delta: true))
        }
    }

    private func text(weekly: Bool, delta: Bool) -> String {
        guard let l = service.limits, let five = l.fiveHour else { return "…" }
        let dot = five.utilization >= 85 ? "🔴" : five.utilization >= 60 ? "🟠" : "🟢"
        var s = "\(dot) \(Int(five.utilization.rounded()))%"
        if delta, let p = Pace.compute(window: five, length: Pace.fiveHours, now: Date()) {
            let d = Int(p.delta.rounded()); s += " \(d >= 0 ? "▲" : "▼")\(abs(d))%"
        }
        if weekly, let w = l.sevenDay { s += " · \(Int(w.utilization.rounded()))%" }
        return s
    }
}

extension MenuBarLabel {
    /// Multi-line hover text for the menu bar item.
    static func tooltip(for l: LimitsSnapshot?, now: Date = Date()) -> String {
        guard let l else { return "Claude Usage — loading…" }
        func line(_ name: String, _ w: LimitWindow, length: TimeInterval?) -> String {
            var t = "\(name): \(Int(w.utilization.rounded()))% used"
            if let r = w.resetsAt { t += " · resets in \(Format.resetsIn(r, now: now))" }
            if let length, let p = Pace.compute(window: w, length: length, now: now) {
                let d = Int(p.delta.rounded())
                t += d == 0 ? " · on even pace" : " · \(abs(d)) pts \(d < 0 ? "under" : "over") even pace"
            }
            return t
        }
        var lines = ["Claude Usage" + (l.isEstimated ? " (estimated)" : "")]
        if let w = l.fiveHour { lines.append(line("5-hour session", w, length: Pace.fiveHours)) }
        if let w = l.sevenDay { lines.append(line("Weekly limit", w, length: Pace.week)) }
        if let m = l.weeklyModel { lines.append(line("Weekly \(m.name.capitalized)", m.window, length: Pace.week)) }
        lines.append("Click to open")
        return lines.joined(separator: "\n")
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
