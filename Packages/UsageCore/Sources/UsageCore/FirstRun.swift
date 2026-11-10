import Foundation

public enum FirstRun {
    /// A fresh install has neither saved preferences nor a record that the widget guide was already offered.
    /// Upgrading users (prefs exist) are never treated as fresh.
    public static func isFreshInstall(hasPrefs: Bool, shownFlag: Bool) -> Bool { !hasPrefs && !shownFlag }
}
