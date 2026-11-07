import Foundation

public struct ScanState: Codable, Equatable, Sendable {
    public var offsets: [String: UInt64] = [:]
    public var seen: Set<String> = []
    public init() {}
}

/// Incrementally reads Claude Code JSONL logs. Not thread-safe; own it from one actor.
public final class LogScanner {
    public private(set) var state: ScanState
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
        for case let url as URL in en where url.pathExtension == "jsonl" {
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
                if state.seen.insert(r.id).inserted { out.append(r) }
            }
            state.offsets[url.path] = off + UInt64(complete.count)
        }
        return out
    }
}
