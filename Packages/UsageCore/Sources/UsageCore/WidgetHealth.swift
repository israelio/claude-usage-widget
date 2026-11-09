import Foundation

/// Pure helpers for detecting a stale widget extension process (started before its binary was replaced on disk).
public enum WidgetHealth {
    /// Parses `ps` etime, `[[dd-]hh:]mm:ss`, into seconds. Nil for anything else.
    public static func parseEtime(_ s: String) -> TimeInterval? {
        var rest = s.trimmingCharacters(in: .whitespaces)
        var days = 0
        if let dash = rest.firstIndex(of: "-") {
            guard let d = Int(rest[..<dash]), d >= 0 else { return nil }
            days = d; rest = String(rest[rest.index(after: dash)...])
        }
        let parts = rest.split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
        guard (2...3).contains(parts.count), !parts.contains(where: { $0 == nil || $0! < 0 }) else { return nil }
        let nums = parts.map { $0! }
        let (h, m, sec) = nums.count == 3 ? (nums[0], nums[1], nums[2]) : (0, nums[0], nums[1])
        return TimeInterval(days * 86400 + h * 3600 + m * 60 + sec)
    }

    /// Stale when the process started more than `tolerance` seconds before the binary was last modified.
    public static func isStale(elapsed: TimeInterval, binaryModified: Date, now: Date, tolerance: TimeInterval = 5) -> Bool {
        now.addingTimeInterval(-elapsed) < binaryModified.addingTimeInterval(-tolerance)
    }

    /// Parses `ps -axo pid=,etime=,command=` output into (pid, elapsed) for lines whose command is exactly `executable`
    /// (or starts with it followed by a space, i.e. arguments). Odd lines are skipped.
    public static func matchingProcesses(psOutput: String, executable: String) -> [(pid: Int32, elapsed: TimeInterval)] {
        var out: [(Int32, TimeInterval)] = []
        for line in psOutput.split(whereSeparator: \.isNewline) {
            let f = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard f.count == 3, let pid = Int32(f[0]), pid > 1, let e = parseEtime(String(f[1])) else { continue }
            let cmd = String(f[2])
            if cmd == executable || cmd.hasPrefix(executable + " ") { out.append((pid, e)) }
        }
        return out
    }
}
