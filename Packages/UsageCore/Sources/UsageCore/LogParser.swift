import Foundation

public enum LogParser {
    public static func parse(_ line: Data) -> UsageRecord? {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              obj["type"] as? String == "assistant",
              let msg = obj["message"] as? [String: Any],
              let usage = msg["usage"] as? [String: Any],
              let model = msg["model"] as? String, model != "<synthetic>",
              let ts = obj["timestamp"] as? String, let date = ISODate.parse(ts)
        else { return nil }
        func n(_ k: String) -> Int { (usage[k] as? NSNumber)?.intValue ?? 0 }
        let mid = (msg["id"] as? String) ?? (obj["uuid"] as? String) ?? ""
        guard !mid.isEmpty else { return nil }
        let id = mid + ":" + ((obj["requestId"] as? String) ?? "")
        let tokens = TokenCounts(input: n("input_tokens"), output: n("output_tokens"),
                                 cacheWrite: n("cache_creation_input_tokens"), cacheRead: n("cache_read_input_tokens"))
        return UsageRecord(id: id, timestamp: date, model: model, tokens: tokens)
    }
}
