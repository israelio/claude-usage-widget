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
    /// Short hover text that explains exactly the numbers shown in the menu bar label.
    static func tooltip(for l: LimitsSnapshot?, mode: MenuBarMode, now: Date = Date()) -> String {
        guard let l, let five = l.fiveHour else { return "Claude Usage — loading…" }
        let suffix = l.isEstimated ? " (estimated)" : ""
        var lines = ["\(Int(five.utilization.rounded()))% — 5-hour session used\(suffix)"]
        guard mode != .iconOnly else { return lines[0] }
        if mode == .sessionWeekly {
            if let p = Pace.compute(window: five, length: Pace.fiveHours, now: now) {
                let d = Int(p.delta.rounded())
                lines.append("\(d >= 0 ? "▲" : "▼")\(abs(d))% — \(d >= 0 ? "above" : "below") an even pace (\(d >= 0 ? "faster" : "slower") than average use)")
            }
            if let w = l.sevenDay { lines.append("\(Int(w.utilization.rounded()))% — weekly limit used") }
        }
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
