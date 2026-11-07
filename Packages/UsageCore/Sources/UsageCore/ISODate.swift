import Foundation

public enum ISODate {
    private static let frac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let plain = ISO8601DateFormatter()
    public static func parse(_ s: String) -> Date? { frac.date(from: s) ?? plain.date(from: s) }
}
