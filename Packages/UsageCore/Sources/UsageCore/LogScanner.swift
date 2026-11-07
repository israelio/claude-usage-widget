import Foundation

public struct ScanState: Codable, Equatable, Sendable {
    public var offsets: [String: UInt64] = [:]
    /// record id -> day key of the record (so old ids can be pruned).
    public var seen: [String: String] = [:]
    public init() {}

    private enum CodingKeys: String, CodingKey { case offsets, seen }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        offsets = try c.decodeIfPresent([String: UInt64].self, forKey: .offsets) ?? [:]
        if let m = try? c.decodeIfPresent([String: String].self, forKey: .seen) {
            seen = m
        } else if let legacy = try? c.decodeIfPresent([String].self, forKey: .seen) {
            // Old format: a plain set of ids. Stamp with today so they age out normally.
            let today = DayKey.string(Date())
            seen = Dictionary(legacy.map { ($0, today) }, uniquingKeysWith: { a, _ in a })
        }
    }

    /// Drops ids older than `cutoff` (a day key). Returns true if anything was removed.
    @discardableResult
    mutating func pruneSeen(before cutoff: String) -> Bool {
        let n = seen.count
        seen = seen.filter { $0.value >= cutoff }
        return seen.count != n
    }
}

/// Incrementally reads Claude Code JSONL logs. Not thread-safe; own it from one actor.
public final class LogScanner {
    public internal(set) var state: ScanState
    private let root: URL
    private let maxAge: TimeInterval

    public init(root: URL, state: ScanState, maxAge: TimeInterval = 91 * 86400) {
        self.root = root; self.state = state; self.maxAge = maxAge
    }

    public func scan(now: Date = Date()) -> [UsageRecord] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                      options: [.skipsHiddenFiles]) else { return [] }
        var out: [UsageRecord] = []
        var present = Set<String>()
        for case let url as URL in en where url.pathExtension == "jsonl" {
            present.insert(url.path)
            let vals = try? url.resourceValues(forKeys: Set(keys))
            if let m = vals?.contentModificationDate, now.timeIntervalSince(m) > maxAge { continue }
            let size = UInt64(vals?.fileSize ?? 0)
            var off = state.offsets[url.path] ?? 0
            if size < off { off = 0 }
            if size == off { continue }
            guard let h = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? h.close() }
            do { try h.seek(toOffset: off) } catch { continue }
            guard let data = try? h.readToEnd(), let lastNL = data.lastIndex(of: 0x0A) else { continue }
            let complete = data[data.startIndex...lastNL]
            for line in complete.split(separator: 0x0A, omittingEmptySubsequences: true) {
                guard let r = LogParser.parse(Data(line)) else { continue }
                if state.seen[r.id] == nil {
                    state.seen[r.id] = DayKey.string(r.timestamp)
                    out.append(r)
                }
            }
            state.offsets[url.path] = off + UInt64(complete.count)
        }
        // Forget offsets of files that no longer exist.
        for k in state.offsets.keys where !present.contains(k) { state.offsets[k] = nil }
        return out
    }
}
