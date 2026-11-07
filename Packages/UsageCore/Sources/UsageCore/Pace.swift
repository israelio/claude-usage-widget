import Foundation

public enum PaceStatus: String, Codable, Sendable { case onTrack, ahead, over }

public struct Pace: Equatable, Sendable {
    public static let fiveHours: TimeInterval = 5 * 3600
    public static let week: TimeInterval = 7 * 86400

    /// Percent we'd be at under perfectly linear use.
    public var expected: Double
    /// utilization - expected (positive = burning faster than linear).
    public var delta: Double
    /// Extrapolated utilization at reset.
    public var projected: Double
    public var status: PaceStatus

    public static func compute(window: LimitWindow, length: TimeInterval, now: Date) -> Pace? {
        guard let reset = window.resetsAt else { return nil }
        let remaining = max(0, reset.timeIntervalSince(now))
        let frac = min(1, max(0, (length - remaining) / length))
        let expected = frac * 100
        let projected = frac < 0.02 ? window.utilization : window.utilization / frac
        let status: PaceStatus
        if window.utilization >= 100 || projected > 115 { status = .over }
        else if projected > 100 { status = .ahead }
        else { status = .onTrack }
        return Pace(expected: expected, delta: window.utilization - expected, projected: projected, status: status)
    }
}
