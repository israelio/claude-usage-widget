import Foundation
import WidgetKit

/// One shared async wrapper around `WidgetCenter.getCurrentConfigurations`.
enum WidgetConfigurations {
    /// The widgets currently placed on the desktop, or nil if the system could not be asked.
    static func current() async -> [WidgetInfo]? {
        await withCheckedContinuation { c in
            WidgetCenter.shared.getCurrentConfigurations { c.resume(returning: try? $0.get()) }
        }
    }
}
