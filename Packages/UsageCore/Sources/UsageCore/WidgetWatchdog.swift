import Foundation

/// Decides what to do when the widgets seem to have stopped being served (no extension heartbeat for a while).
/// Soft kick first (reload timelines); if that didn't bring a heartbeat back, restart the extension and chronod.
public enum WidgetWatchdog {
    public enum Action: Equatable, Sendable { case none, reload, restart }

    /// Last sign of life: the heartbeat, but never earlier than app launch (the launch itself reloads the widgets,
    /// so a missing or old heartbeat only counts as stale once the app has been up for `staleAfter`).
    public static func decide(now: Date, heartbeat: Date?, appStartedAt: Date, hasWidgets: Bool, lastKick: Date?, lastRestart: Date?,
                              staleAfter: TimeInterval = 20 * 60, kickCooldown: TimeInterval = 5 * 60,
                              restartCooldown: TimeInterval = 2 * 3600) -> Action {
        guard hasWidgets else { return .none }
        let lastSign = max(heartbeat ?? .distantPast, appStartedAt)
        guard now.timeIntervalSince(lastSign) > staleAfter else { return .none }
        // No kick since the last sign of life: try the soft one.
        guard let kick = lastKick, kick > lastSign else { return .reload }
        let sinceKick = now.timeIntervalSince(kick)
        if sinceKick < kickCooldown { return .none }
        // The kick didn't help: escalate, but not too often.
        if sinceKick >= staleAfter / 2, lastRestart.map({ now.timeIntervalSince($0) >= restartCooldown }) ?? true { return .restart }
        return .none
    }
}
