import SwiftUI
import BackgroundTasks
import UserNotifications
import UIKit

@MainActor
final class RegnvaktAppDelegate: NSObject, UIApplicationDelegate {
    private static let weatherRefreshIdentifier = "app.walnut8211.vadra.weather-refresh"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = RegnvaktNotificationDelegate.shared
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.weatherRefreshIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handle(refreshTask)
        }
        scheduleNextWeatherRefresh()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        scheduleNextWeatherRefresh()
    }

    private func scheduleNextWeatherRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.weatherRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // iOS may reject or defer refresh requests. Existing local alerts
            // remain scheduled independently of this opportunistic refresh.
        }
    }

    private func handle(_ task: BGAppRefreshTask) {
        scheduleNextWeatherRefresh()
        let refresh = Task { @MainActor in
            let succeeded = await WeatherViewModel.refreshMonitoredForecastsInBackground()
            task.setTaskCompleted(success: succeeded)
        }
        task.expirationHandler = {
            refresh.cancel()
        }
    }
}

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
    @UIApplicationDelegateAdaptor(RegnvaktAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView().preferredColorScheme(.dark)
        }
    }
}
