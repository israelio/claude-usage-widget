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
