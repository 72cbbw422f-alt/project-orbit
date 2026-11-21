import SwiftUI
import BackgroundTasks
import UserNotifications

@MainActor
final class RegnvaktNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = RegnvaktNotificationDelegate()

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        let watch = userInfo["watch"] as? String ?? ""

        // Routine forecast notices remain in Notification Center without interrupting the user.
        if watch == "smhi" {
            let shouldPresent = SMHIWarningNotificationPolicy.shouldPresentInForeground(
                level: userInfo["level"] as? String ?? "",
                scheduledAt: userInfo["scheduledAt"] as? TimeInterval ?? 0,
                start: userInfo["start"] as? String ?? "",
                end: userInfo["end"] as? String ?? "",
                now: Date()
            )
            completionHandler(shouldPresent ? [.banner, .sound, .list] : [])
            return
        }

        let isSafetyCritical = (userInfo["safetyCritical"] as? Bool) ?? false
        completionHandler(isSafetyCritical ? [.banner, .sound, .list] : [])
    }
}

@main
struct VADERApp: App {
    init() {
        UNUserNotificationCenter.current().delegate = RegnvaktNotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView().preferredColorScheme(.dark)
        }
    }
}
