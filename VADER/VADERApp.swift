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

        // Only safety-relevant alerts are presented while Regnvakt is active.
        // Routine forecast notices remain in Notification Center without
        // interrupting the user when an old queued request fires on app launch.
        if watch == "smhi" {
            let level = (userInfo["level"] as? String ?? "").lowercased()
            let isRecognizedLevel = level.contains("röd") || level.contains("rod")
                || level.contains("orange") || level.contains("gul")
            let scheduledAt = userInfo["scheduledAt"] as? TimeInterval ?? 0
            let notificationAge = Date().timeIntervalSince1970 - scheduledAt
            let wasRecentlyScheduled = notificationAge >= 0 && notificationAge <= 10 * 60
            let start = userInfo["start"] as? String ?? ""
            let end = userInfo["end"] as? String ?? ""
            let formatter = ISO8601DateFormatter()
            let startDate = formatter.date(from: start)
            let endDate = formatter.date(from: end)
            let hasStarted = startDate.map { $0 <= Date() } ?? false
            let hasNotEnded = end.isEmpty || (endDate.map { $0 >= Date() } ?? false)
            completionHandler(
                isRecognizedLevel && wasRecentlyScheduled && hasStarted && hasNotEnded
                    ? [.banner, .sound, .list] : []
            )
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
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
