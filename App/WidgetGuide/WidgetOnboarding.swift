import Foundation
import UsageCore

/// Offers the widget guide once, on a fresh install.
@MainActor
enum WidgetOnboarding {
    private static let shownKey = "onboarding.widgets.shown.v1"
    private static var fresh = false
    private static var offered = false

    /// Call before `AppSettings()` creates/saves prefs.
    static func captureFreshInstall() {
        let d = UserDefaults.standard
        fresh = FirstRun.isFreshInstall(hasPrefs: d.data(forKey: "prefs.v1") != nil, shownFlag: d.object(forKey: shownKey) != nil)
    }

    /// Shows the guide ~3 s after the menu bar item appears (once per launch, once per install).
    static func offerIfFresh() {
        guard fresh, !offered else { return }
        offered = true
        UserDefaults.standard.set(true, forKey: shownKey)
        Task {
            try? await Task.sleep(for: .seconds(3))
            WidgetGuideWindowController.shared.show(firstRun: true)
        }
    }
}
