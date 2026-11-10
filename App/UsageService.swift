import Foundation
import SwiftUI
import AppKit
import WidgetKit
import UsageCore

@MainActor
final class UsageService: ObservableObject {
    @Published private(set) var limits: LimitsSnapshot?
    @Published private(set) var summary = UsageSummary.empty
    @Published private(set) var history = HistoryData()
    @Published private(set) var error: String?
    @Published private(set) var nextRefresh = Date()
    @Published private(set) var plan: PlanInfo?

    let settings: AppSettings
    private let ingestor: UsageIngestor
    private let client: LimitsProviding
    /// The same client instance (and so the same cached token provider) as `client`: no extra Keychain reads.
    private let planClient: PlanProviding?
    private var planFetchedAt: Date?
    private static let planMaxAge: TimeInterval = 6 * 3600
    private let groupID: String
    private var previous: LimitsSnapshot?
    private var fired: FiredState
    private var loop: Task<Void, Never>?
    private var isRefreshing = false
    private var lastFetchSuccess: Date?
    private var failures = 0
    /// Consecutive HTTP 429s; while `blockedUntil` is in the future the API is not called at all.
    private var rateLimitStreak = 0
    private var blockedUntil: Date?
    private var wakeRetry: Task<Void, Never>?
    private var lockedRetry: Task<Void, Never>?
    private static let wakeDelays: [Double] = [8, 22, 60]   // cumulative +8s, +30s, +90s
    private static let lockedRetrySeconds = 60.0
    private var lastWritten: SharedSnapshot?
    private var lastReload: Date?
    /// WidgetKit budgets reloads per day; the widget's own 15-minute timeline covers the baseline.
    private static let reloadInterval: TimeInterval = 15 * 60
    /// False when the App Group container isn't provisioned (unsigned build): widgets can't see our data.
    let groupAvailable: Bool
    private static let minPoll = 30
    private static let maxBackoff = 600
    private static let fetchCooldown: TimeInterval = 10
    private static let firedKey = "fired.v1"

    init(settings: AppSettings, client: LimitsProviding = OAuthLimitsClient()) {
        self.settings = settings
        self.client = client
        self.planClient = client as? PlanProviding
        self.groupID = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? ""
        self.groupAvailable = SharedSnapshot.groupURL(groupID: groupID) != nil
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeUsageWidget")
        let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        self.ingestor = UsageIngestor(logsRoot: logs, storeURL: support.appendingPathComponent("history.json"))
        if let d = UserDefaults.standard.data(forKey: Self.firedKey), let f = try? JSONDecoder().decode(FiredState.self, from: d) { fired = f } else { fired = FiredState() }
    }

    func start() {
        guard loop == nil else { return }
        Notifier.requestAuthorization()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.retryAfterWake() } }
        WidgetHealer.run()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                var secs = self.currentInterval()
                if let b = self.blockedUntil, b > Date() { secs = max(secs, Int(b.timeIntervalSinceNow.rounded(.up)) + 1) }
                self.nextRefresh = Date().addingTimeInterval(Double(secs))
                try? await Task.sleep(for: .seconds(secs))
            }
        }
    }

    /// Poll interval, doubled per consecutive failure up to 10 minutes; resets on success.
    private func currentInterval() -> Int {
        let base = max(Self.minPoll, settings.prefs.pollSeconds)
        guard failures > 0 else { return base }
        return min(max(base, Self.maxBackoff), base << min(failures, 10))
    }

    private var isBlocked: Bool { blockedUntil.map { Date() < $0 } ?? false }

    /// Backs off after an HTTP 429; the generic failure counter is left alone.
    private func noteRateLimited(retryAfter: TimeInterval?) {
        rateLimitStreak += 1
        blockedUntil = Date().addingTimeInterval(RateLimitBackoff.delay(consecutive429: rateLimitStreak, retryAfter: retryAfter))
    }

    private func blockedMessage() -> String? {
        guard let b = blockedUntil else { return nil }
        return LimitsError.rateLimited(retryAfter: max(0, b.timeIntervalSinceNow)).errorDescription
    }

    /// User-initiated refresh (button): may show a Keychain dialog if needed.
    func refreshNow() {
        guard !isRefreshing else { return }
        Task {
            KeychainTokenProvider.allowUserInteraction = true
            await refresh()
            KeychainTokenProvider.allowUserInteraction = false
        }
    }

    /// The network usually isn't up right after wake, so retry with growing delays until a fetch succeeds.
    private func retryAfterWake() {
        wakeRetry?.cancel()
        wakeRetry = Task { [weak self] in
            for delay in Self.wakeDelays {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                await self.refresh()
                if self.isBlocked { break }   // rate limited: stop hammering the API
                if self.error == nil, self.limits?.isEstimated == false { break }
            }
            self?.failures = 0
        }
    }

    /// Locked keychain: keep the last data and quietly retry in a minute instead of backing off.
    private func scheduleLockedRetry() {
        lockedRetry?.cancel()
        lockedRetry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.lockedRetrySeconds))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let now = Date()
        let prefs = settings.prefs
        let hist = await ingestor.refreshLogs(now: now)

        // Publish local data immediately so the UI/widget don't wait on Keychain or network.
        let estimate = LocalEstimator.estimate(records: hist.recent, limits: prefs.planLimits, now: now)
        let early = Aggregator.summarize(hist, prices: prefs.prices, now: now)
        history = hist; summary = early
        if limits == nil {
            limits = estimate
            writeSnapshot(estimate, early, hist, now)
        }

        var snap: LimitsSnapshot
        var fetched = false
        if isBlocked {
            self.error = blockedMessage()   // rate limited: no network call, keep the last real data
            if let l = limits, !l.isEstimated { snap = l } else { snap = estimate }
        } else if let t = lastFetchSuccess, now.timeIntervalSince(t) < Self.fetchCooldown, let l = limits, !l.isEstimated {
            snap = l   // fetched very recently; just rescan logs
        } else {
            do {
                snap = try await client.fetch()
                error = nil
                failures = 0
                rateLimitStreak = 0
                blockedUntil = nil
                fetched = true
                lastFetchSuccess = Date()
                await ingestor.record(snap)
            } catch let LimitsError.rateLimited(retryAfter) {
                noteRateLimited(retryAfter: retryAfter)
                self.error = blockedMessage()
                if let l = limits, !l.isEstimated { snap = l } else { snap = estimate }
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                if (error as? LimitsError) == .keychainLocked { scheduleLockedRetry() } else { failures += 1 }
                // Keep the last real snapshot (now stale); only fall back to the estimate if there is none.
                if let l = limits, !l.isEstimated { snap = l } else { snap = estimate }
            }
        }
        if fetched, !isBlocked { await refreshPlanIfNeeded() }
        let now2 = Date()   // the fetch may have blocked on a Keychain prompt for a long time
        let hist2 = await ingestor.current()
        let sum = Aggregator.summarize(hist2, prices: prefs.prices, now: now2)

        var msgs: [AlertMessage] = []
        if fetched, !snap.isEstimated, !AlertEngine.isQuiet(prefs.alerts, now: now2, calendar: .current) {
            msgs += AlertEngine.evaluate(current: snap, previous: previous, settings: prefs.alerts, fired: &fired, now: now2)
            // Only advance `previous` when alerts actually ran, so a reset during quiet hours isn't lost.
            previous = snap
        }
        msgs += AlertEngine.digests(summary: sum, settings: prefs.alerts, fired: &fired, now: now2)
        msgs.forEach(Notifier.post)
        if let d = try? JSONEncoder().encode(fired) { UserDefaults.standard.set(d, forKey: Self.firedKey) }

        limits = snap; summary = sum; history = hist2
        writeSnapshot(snap, sum, hist2, now2, refreshError: snap.isEstimated ? nil : self.error)
        if fetched, !snap.isEstimated { await WidgetWatchdogRunner.check(groupID: groupID) }
    }

    /// Silent on failure: keeps the previous plan and retries on a later successful poll.
    private func refreshPlanIfNeeded() async {
        if plan != nil, let t = planFetchedAt, Date().timeIntervalSince(t) < Self.planMaxAge { return }
        guard let planClient else { return }
        do {
            plan = try await planClient.fetchPlan(); planFetchedAt = Date()
        } catch LimitsError.rateLimited(let after) {
            noteRateLimited(retryAfter: after)   // the usage data is fresh, so no error is shown; the next fetches wait
        } catch {}
    }

    func daily(days: Int) -> [DailyPoint] {
        Aggregator.daily(history, prices: settings.prefs.prices, days: days, now: Date())
    }

    private func writeSnapshot(_ l: LimitsSnapshot, _ s: UsageSummary, _ h: HistoryData, _ now: Date,
                               refreshError: String? = nil) {
        // A kept last-known snapshot keeps its own age, so widgets don't look freshly updated after a failed refresh.
        let snap = SharedSnapshot(limits: l, today: s.today, last7: s.last7,
                                  daily: Aggregator.daily(h, prices: settings.prefs.prices, days: 7, now: now),
                                  updatedAt: refreshError == nil ? now : l.fetchedAt,
                                  showRemaining: settings.prefs.showRemaining, refreshError: refreshError)
        let url = SharedSnapshot.groupURL(groupID: groupID)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ClaudeUsageWidget/snapshot.json")
        try? snap.save(to: url)
        // Reload timelines only when what's displayed changed, or at most every 15 minutes otherwise.
        let changed = !(lastWritten?.displayEquals(snap) ?? false)
        lastWritten = snap
        if changed || lastReload.map({ now.timeIntervalSince($0) >= Self.reloadInterval }) ?? true {
            lastReload = now
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
