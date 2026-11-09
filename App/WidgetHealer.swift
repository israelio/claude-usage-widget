import Foundation
import WidgetKit
import UsageCore

/// A widget extension process that started before the app bundle was replaced on disk (update/reinstall) can sit
/// on the placeholder skeleton forever. Detect that, kill it and restart `chronod` so it gets a fresh timeline.
@MainActor
enum WidgetHealer {
    private static var scheduled = false

    /// Idempotent: schedules a single check a few seconds after launch.
    static func run() {
        guard !scheduled else { return }
        scheduled = true
        Task {
            try? await Task.sleep(for: .seconds(4))
            await heal()
        }
    }

    private static func heal() async {
        let exe = Bundle.main.bundleURL
            .appendingPathComponent("Contents/PlugIns/UsageWidgetExtension.appex/Contents/MacOS/UsageWidgetExtension").path
        let stale = await Task.detached { staleProcesses(executable: exe) }.value
        if !stale.isEmpty {
            await restart(pids: stale)
        } else {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Kills every running widget extension process and chronod, then reloads once they're back.
    static func forceRestart() async {
        let exe = Bundle.main.bundleURL
            .appendingPathComponent("Contents/PlugIns/UsageWidgetExtension.appex/Contents/MacOS/UsageWidgetExtension").path
        let pids = await Task.detached {
            run("/bin/ps", ["-axo", "pid=,etime=,command="]).map { WidgetHealth.matchingProcesses(psOutput: $0, executable: exe).map { $0.pid } } ?? []
        }.value
        await restart(pids: pids)
    }

    private static func restart(pids: [Int32]) async {
        await Task.detached {
            for pid in pids { _ = run("/bin/kill", [String(pid)]) }
            _ = run("/usr/bin/killall", ["chronod"])   // user-level agent; launchd restarts it
        }.value
        try? await Task.sleep(for: .seconds(3))
        WidgetCenter.shared.reloadAllTimelines()
    }

    nonisolated private static func staleProcesses(executable: String) -> [Int32] {
        guard let mtime = (try? FileManager.default.attributesOfItem(atPath: executable))?[.modificationDate] as? Date,
              let ps = run("/bin/ps", ["-axo", "pid=,etime=,command="]) else { return [] }
        let now = Date()
        return WidgetHealth.matchingProcesses(psOutput: ps, executable: executable)
            .filter { WidgetHealth.isStale(elapsed: $0.elapsed, binaryModified: mtime, now: now) }
            .map { $0.pid }
    }

    /// Runs a tool with an argument array (no shell); returns stdout, or nil if it couldn't run.
    nonisolated private static func run(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
