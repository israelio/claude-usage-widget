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

    let settings: AppSettings
    private let ingestor: UsageIngestor
    private let client: LimitsProviding
    private let groupID: String
    private var previous: LimitsSnapshot?
    private var fired: FiredState
    private var loop: Task<Void, Never>?
    private static let firedKey = "fired.v1"

    init(settings: AppSettings, client: LimitsProviding = OAuthLimitsClient()) {
        self.settings = settings
        self.client = client
        self.groupID = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? ""
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeUsageWidget")
        let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        self.ingestor = UsageIngestor(logsRoot: logs, storeURL: support.appendingPathComponent("history.json"))
        if let d = UserDefaults.standard.data(forKey: Self.firedKey), let f = try? JSONDecoder().decode(FiredState.self, from: d) { fired = f } else { fired = FiredState() }
    }

    func start() {
        guard loop == nil else { return }
        Notifier.requestAuthorization()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refreshNow() } }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let secs = max(15, self.settings.prefs.pollSeconds)
                self.nextRefresh = Date().addingTimeInterval(Double(secs))
                try? await Task.sleep(for: .seconds(secs))
            }
        }
    }

    func refreshNow() { Task { await refresh() } }

    func refresh() async {
        let now = Date()
        let prefs = settings.prefs
        let hist = await ingestor.refreshLogs(now: now)

        // Publish local data immediately so the UI/widget don't wait on Keychain or network.
        let estimate = LocalEstimator.estimate(records: hist.recent, limits: prefs.planLimits, now: now)
        let early = Aggregator.summarize(await ingestor.current(), prices: prefs.prices, now: now)
        let earlyHist = await ingestor.current()
        history = earlyHist; summary = early
        if limits == nil {
            limits = estimate
            writeSnapshot(estimate, early, earlyHist, now)
        }

        var snap: LimitsSnapshot
        do {
            snap = try await client.fetch()
            error = nil
            await ingestor.record(snap)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            snap = estimate
        }
        let hist2 = await ingestor.current()
        let sum = Aggregator.summarize(hist2, prices: prefs.prices, now: now)

        var msgs: [AlertMessage] = []
        if !snap.isEstimated {
            msgs += AlertEngine.evaluate(current: snap, previous: previous, settings: prefs.alerts, fired: &fired, now: now)
        }
        msgs += AlertEngine.digests(summary: sum, settings: prefs.alerts, fired: &fired, now: now)
        msgs.forEach(Notifier.post)
        if let d = try? JSONEncoder().encode(fired) { UserDefaults.standard.set(d, forKey: Self.firedKey) }

        if !snap.isEstimated { previous = snap }
        limits = snap; summary = sum; history = hist2
        writeSnapshot(snap, sum, hist2, now)
    }

    func daily(days: Int) -> [DailyPoint] {
        Aggregator.daily(history, prices: settings.prefs.prices, days: days, now: Date())
    }

    private func writeSnapshot(_ l: LimitsSnapshot, _ s: UsageSummary, _ h: HistoryData, _ now: Date) {
        let snap = SharedSnapshot(limits: l, today: s.today, last7: s.last7,
                                  daily: Aggregator.daily(h, prices: settings.prefs.prices, days: 7, now: now), updatedAt: now)
        let url = SharedSnapshot.groupURL(groupID: groupID)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ClaudeUsageWidget/snapshot.json")
        try? snap.save(to: url)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
