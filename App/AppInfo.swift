import Foundation

enum AppInfo {
    /// Marketing version stamped into the build (Config.xcconfig / release scripts).
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
