import Foundation

/// The widget extension stamps this file whenever WidgetKit asks it for a snapshot or timeline, so the app can tell
/// whether the system is still serving the widgets. Lives next to snapshot.json in the App Group container.
public enum WidgetHeartbeat {
    public static func url(groupID: String) -> URL? {
        SharedSnapshot.groupURL(groupID: groupID)?.deletingLastPathComponent().appendingPathComponent("widget-heartbeat.txt")
    }

    public static func write(to url: URL, date: Date = Date()) {
        try? Data(ISO8601DateFormatter().string(from: date).utf8).write(to: url, options: .atomic)
    }

    /// Nil when the file is missing or unparseable.
    public static func read(from url: URL) -> Date? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return ISO8601DateFormatter().date(from: String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
