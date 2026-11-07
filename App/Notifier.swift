import Foundation
import UserNotifications
import UsageCore

enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    static func post(_ m: AlertMessage) {
        let c = UNMutableNotificationContent()
        c.title = m.title; c.body = m.body; c.sound = .default
        let req = UNNotificationRequest(identifier: m.id + "-" + UUID().uuidString, content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
