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
    private let lastFetchURL: URL
    private let planURL: URL
    private static let planMaxAge: TimeInterval = 6 * 3600
    private let groupID: String
    private var previous: LimitsSnapshot?
    private var fired: FiredState
    private var loop: Task<Void, Never>?
    private var isRefreshing = false
    private var lastFetchSuccess: Date?
    /// Last time a request that counts against the API budget was made (success or failure).
    private var lastAttempt: Date?
    /// Set when the incremental log scan found new records since the last successful fetch.
    private var activitySinceFetch = false
    /// When the most recent 429 block ends; drives the slow mode afterwards.
    private var lastBlockEnd: Date?
    /// True while `error` is only a "try again later" notice from the refresh button, not a failed refresh.
    private var transientNotice = false
    /// Consecutive HTTP 429s; while `blockedUntil` is in the future the API is not called at all.
    private var rateLimitStreak = 0
    private var blockedUntil: Date?
    private var wakeRetry: Task<Void, Never>?
    private var lockedRetry: Task<Void, Never>?
    private static let wakeSettle = 15.0
    private static let wakeRetryDelays: [Double] = [60, 120]   // cumulative +60s, +180s after the settle wait
    /// The loop wakes this often to rescan logs (local only); the API is called only when `FetchPolicy` allows.
    private static let tick = 60
    private static let lockedRetrySeconds = 60.0
    private var lastWritten: SharedSnapshot?
    private var lastReload: Date?
    /// WidgetKit budgets reloads per day; the widget's own 15-minute timeline covers the baseline.
    private static let reloadInterval: TimeInterval = 15 * 60
    /// False when the App Group container isn't provisioned (unsigned build): widgets can't see our data.
    let groupAvailable: Bool
    static let minPoll = 120
    private static let idleGap: TimeInterval = 900
    private static let firedKey = "fired.v1"

    init(settings: AppSettings, client: LimitsProviding = OAuthLimitsClient()) {
        self.settings = settings
        self.client = client
        self.planClient = client as? PlanProviding
        self.groupID = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? ""
        self.groupAvailable = SharedSnapshot.groupURL(groupID: groupID) != nil
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeUsageWidget")
        self.lastFetchURL = support.appendingPathComponent("last-limits.json")
        self.planURL = support.appendingPathComponent("plan.json")
        let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        self.ingestor = UsageIngestor(logsRoot: logs, storeURL: support.appendingPathComponent("history.json"))
        if let d = UserDefaults.standard.data(forKey: Self.firedKey), let f = try? JSONDecoder().decode(FiredState.self, from: d) { fired = f } else { fired = FiredState() }
        // Last-known data from a previous launch, so a relaunch shows numbers at once and doesn't spend a request.
        if let lf = LastFetch.load(from: lastFetchURL) { limits = lf.limits; lastFetchSuccess = lf.lastFetchSuccess }
        if let cp = CachedPlan.load(from: planURL) { plan = cp.plan; planFetchedAt = cp.fetchedAt }
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
                self.nextRefresh = self.nextFetchEstimate(now: Date())
                try? await Task.sleep(for: .seconds(Self.tick))
            }
        }
    }

    private func gaps(now: Date) -> (min: TimeInterval, idle: TimeInterval) {
        let mult = FetchPolicy.gapMultiplier(sinceLastBlock: lastBlockEnd.map { now.timeIntervalSince($0) })
        let minGap = Double(max(Self.minPoll, settings.prefs.pollSeconds)) * mult
        return (minGap, max(Self.idleGap * mult, minGap))
    }

    /// The most recent request that counts against the budget (a failed one counts too).
    private var lastRequest: Date? { [lastFetchSuccess, lastAttempt].compactMap { $0 }.max() }

    /// Earliest time the next API call can happen, for the "next refresh" display.
    private func nextFetchEstimate(now: Date) -> Date {
        let g = gaps(now: now)
        var t = lastRequest.map { $0.addingTimeInterval(activitySinceFetch || limits?.isEstimated != false ? g.min : g.idle) } ?? now
        if let b = blockedUntil { t = max(t, b) }
        return max(t, now)
    }

    private var isBlocked: Bool { blockedUntil.map { Date() < $0 } ?? false }

    /// Backs off after an HTTP 429; the generic failure counter is left alone.
    private func noteRateLimited(retryAfter: TimeInterval?) {
        rateLimitStreak += 1
        let until = Date().addingTimeInterval(RateLimitBackoff.delay(consecutive429: rateLimitStreak, retryAfter: retryAfter))
        blockedUntil = until
        lastBlockEnd = until
    }

    private func blockedMessage() -> String? {
        guard let b = blockedUntil else { return nil }
        return LimitsError.rateLimited(retryAfter: max(0, b.timeIntervalSinceNow)).errorDescription
    }

    /// User-initiated refresh (button): may show a Keychain dialog if needed. At most once a minute.
    func refreshNow() {
        guard !isRefreshing else { return }
        if !isBlocked, let last = lastRequest {
            let wait = Int((FetchPolicy.manualGap - Date().timeIntervalSince(last)).rounded(.up))
            if wait > 0 {
                error = "Refreshed just now — you can refresh again in \(wait)s"
                transientNotice = true
                return
            }
        }
        Task {
            KeychainTokenProvider.allowUserInteraction = true
            await refresh(manual: true)
            KeychainTokenProvider.allowUserInteraction = false
        }
    }

    /// The network usually isn't up right after wake: settle, run a normal policy-gated refresh (no request if the
    /// last fetch is recent), and retry a failure (not a 429) at +60s and +180s.
    private func retryAfterWake() {
        wakeRetry?.cancel()
        wakeRetry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.wakeSettle))
            guard !Task.isCancelled, let self else { return }
            var result = await self.refresh()
            for delay in Self.wakeRetryDelays where result == .failed {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                result = await self.refresh(manual: true)
            }
        }
    }

    /// Locked keychain: keep the last data and quietly retry in a minute instead of backing off.
    private func scheduleLockedRetry() {
        lockedRetry?.cancel()
        lockedRetry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.lockedRetrySeconds))
            guard !Task.isCancelled else { return }
            await self?.refresh(manual: true)
        }
    }

    enum RefreshResult { case fetched, rateLimited, failed, skipped }

    /// Rescans logs and republishes local data; calls the usage API only if `FetchPolicy` allows it.
    /// `manual` (button, retries) is limited to once a minute instead of the activity/idle gaps.
    @discardableResult
    func refresh(manual: Bool = false) async -> RefreshResult {
        guard !isRefreshing else { return .skipped }
        isRefreshing = true
        defer { isRefreshing = false }
        var result = RefreshResult.skipped
        if transientNotice { error = nil; transientNotice = false }

        let now = Date()
        let prefs = settings.prefs
        let hist = await ingestor.refreshLogs(now: now)
        if await ingestor.lastScanNewCount() > 0 { activitySinceFetch = true }

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
        } else if !shouldFetchNow(now: now, manual: manual) {
            if let l = limits, !l.isEstimated { snap = l } else { snap = estimate }   // just rescan logs
        } else {
            do {
                snap = try await client.fetch()
                error = nil
                rateLimitStreak = 0
                blockedUntil = nil
                fetched = true
                result = .fetched
                activitySinceFetch = false
                lastFetchSuccess = Date()
                lastAttempt = lastFetchSuccess
                LastFetch(lastFetchSuccess: snap.fetchedAt, limits: snap).save(to: lastFetchURL)
                await ingestor.record(snap)
            } catch let LimitsError.rateLimited(retryAfter) {
                result = .rateLimited
                lastAttempt = Date()
                noteRateLimited(retryAfter: retryAfter)
                self.error = blockedMessage()
                if let l = limits, !l.isEstimated { snap = l } else { snap = estimate }
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                result = .failed
                // No request reached the API for these, so they don't count against the budget.
                let local: [LimitsError] = [.noToken, .keychainLocked, .keychainBusy]
                if let e = error as? LimitsError, local.contains(e) { if e == .keychainLocked { scheduleLockedRetry() } }
                else { lastAttempt = Date() }
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
        writeSnapshot(snap, sum, hist2, now2, refreshError: snap.isEstimated || transientNotice ? nil : self.error)
        if fetched, !snap.isEstimated { await WidgetWatchdogRunner.check(groupID: groupID) }
        nextRefresh = nextFetchEstimate(now: Date())
        return result
    }

    private func shouldFetchNow(now: Date, manual: Bool) -> Bool {
        let g = gaps(now: now)
        let noRealData = limits?.isEstimated != false
        return FetchPolicy.shouldFetch(
            now: now, lastFetch: lastRequest, newLogActivitySinceLastFetch: activitySinceFetch || noRealData,
            windowResetPassed: FetchPolicy.windowResetPassed(limits: limits, lastFetch: lastFetchSuccess, now: now),
            manual: manual, blockedUntil: blockedUntil, minGap: g.min, idleGap: g.idle)
    }

    /// Silent on failure: keeps the previous plan and retries on a later successful poll.
    private func refreshPlanIfNeeded() async {
        if plan != nil, let t = planFetchedAt, Date().timeIntervalSince(t) < Self.planMaxAge { return }
        guard let planClient else { return }
        do {
            let p = try await planClient.fetchPlan()
            plan = p; planFetchedAt = Date()
            CachedPlan(plan: p, fetchedAt: planFetchedAt!).save(to: planURL)
        } catch LimitsError.rateLimited(let after) {
            noteRateLimited(retryAfter: after)   // the usage data is fresh, so no error is shown; the next fetches wait
        } catch {}
    }

    func daily(days: Int) -> [DailyPoint] {
        Aggregator.daily(history, prices: settings.prefs.prices, days: days, now: Date())
    }

    private func writeSnapshot(_ l: LimitsSnapshot, _ s: UsageSummary, _ h: HistoryData, _ now: Date,
                               refreshError: String? = nil) {
        // A kept last-known snapshot keeps its own age, so widgets don't look freshly updated after a failed refresh
        // or when the data comes from an earlier fetch (persisted from a previous launch, or not yet due again).
        let snap = SharedSnapshot(limits: l, today: s.today, last7: s.last7,
                                  daily: Aggregator.daily(h, prices: settings.prefs.prices, days: 7, now: now),
                                  updatedAt: refreshError == nil && (l.isEstimated || now.timeIntervalSince(l.fetchedAt) < 5) ? now : l.fetchedAt,
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
