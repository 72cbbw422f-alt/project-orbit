import SwiftUI
import UserNotifications

@MainActor
final class RegnvaktNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = RegnvaktNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}

@main
struct VADERApp: App {
    init() {
        UNUserNotificationCenter.current().delegate = RegnvaktNotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
