import SwiftUI
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
