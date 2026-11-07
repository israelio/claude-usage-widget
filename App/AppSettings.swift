import Foundation
import UsageCore

enum MenuBarMode: String, Codable, CaseIterable, Identifiable {
    case percent = "Session %", sessionWeekly = "Session + Weekly", iconOnly = "Icon only"
    var id: String { rawValue }
}

struct Prefs: Codable, Equatable {
    var menuBarMode: MenuBarMode = .sessionWeekly
    var floatingPanel = false
    var pollSeconds = 60
    var alerts = AlertSettings()
    var planLimits = PlanLimits()
    var prices = PriceTable.defaults

    init() {}
    private enum CodingKeys: String, CodingKey { case menuBarMode, floatingPanel, pollSeconds, alerts, planLimits, prices }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        menuBarMode = try c.decodeIfPresent(MenuBarMode.self, forKey: .menuBarMode) ?? .sessionWeekly
        floatingPanel = try c.decodeIfPresent(Bool.self, forKey: .floatingPanel) ?? false
        pollSeconds = try c.decodeIfPresent(Int.self, forKey: .pollSeconds) ?? 60
        alerts = try c.decodeIfPresent(AlertSettings.self, forKey: .alerts) ?? AlertSettings()
        planLimits = try c.decodeIfPresent(PlanLimits.self, forKey: .planLimits) ?? PlanLimits()
        prices = try c.decodeIfPresent(PriceTable.self, forKey: .prices) ?? .defaults
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private static let key = "prefs.v1"
    @Published var prefs: Prefs { didSet { save() } }

    init() {
        if let d = UserDefaults.standard.data(forKey: Self.key),
           let p = try? JSONDecoder().decode(Prefs.self, from: d) { prefs = p } else { prefs = Prefs() }
    }
    private func save() {
        if let d = try? JSONEncoder().encode(prefs) { UserDefaults.standard.set(d, forKey: Self.key) }
    }
}
