import SwiftUI
import UsageCore

enum Theme {
    static func color(forUtilization u: Double) -> Color { u >= 85 ? .red : u >= 60 ? .orange : .green }
    static func color(for s: PaceStatus) -> Color {
        switch s { case .onTrack: return .green; case .ahead: return .orange; case .over: return .red }
    }
    static func label(for s: PaceStatus) -> String {
        switch s { case .onTrack: return "On track"; case .ahead: return "Ahead of pace"; case .over: return "Will exceed" }
    }
}
