import Foundation
import WidgetKit
import UsageCore

/// Notices when the system has stopped serving the desktop widgets (the extension's heartbeat goes quiet) and
/// nudges it: first a timeline reload, then a full extension/chronod restart if that didn't help.
@MainActor
enum WidgetWatchdogRunner {
    private static let startedAt = Date()
    private static var lastKick: Date?
    private static var lastRestart: Date?
    private static var running = false

    /// For testing: CLAUDEUSAGE_WATCHDOG_SECONDS=N shrinks the thresholds (stale N, kick N/2, restart N*4).
    private static var thresholds: (stale: TimeInterval, kick: TimeInterval, restart: TimeInterval) {
        if let s = ProcessInfo.processInfo.environment["CLAUDEUSAGE_WATCHDOG_SECONDS"], let n = Double(s), n > 0 { return (n, n / 2, n * 4) }
        return (20 * 60, 5 * 60, 2 * 3600)
    }

    static func check(groupID: String) async {
        guard !running else { return }
        running = true
        defer { running = false }
        let configs: [WidgetInfo] = await withCheckedContinuation { c in
            WidgetCenter.shared.getCurrentConfigurations { c.resume(returning: (try? $0.get()) ?? []) }   // error: treat as no widgets
        }
        let beat = WidgetHeartbeat.url(groupID: groupID).flatMap { WidgetHeartbeat.read(from: $0) }
        let t = thresholds
        let now = Date()
        switch WidgetWatchdog.decide(now: now, heartbeat: beat, appStartedAt: startedAt, hasWidgets: !configs.isEmpty,
                                     lastKick: lastKick, lastRestart: lastRestart,
                                     staleAfter: t.stale, kickCooldown: t.kick, restartCooldown: t.restart) {
        case .none: break
        case .reload:
            lastKick = now
            WidgetCenter.shared.reloadAllTimelines()
        case .restart:
            lastKick = now; lastRestart = now
            await WidgetHealer.forceRestart()
        }
    }
}
