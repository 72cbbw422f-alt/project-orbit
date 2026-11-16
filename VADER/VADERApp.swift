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
        completionHandler([.banner, .sound, .list])
    }
}

private enum RegnvaktBackgroundRefresh {
    static let identifier = "app.walnut8211.vadra.weather-refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
        scheduleNext()
    }

    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        scheduleNext()
        let work = Task {
            await WeatherNotificationScheduler.refreshMonitoredForecastsInBackground()
        }
        task.expirationHandler = { work.cancel() }
        Task {
            await work.value
            task.setTaskCompleted(success: !work.isCancelled)
        }
    }
}

@main
struct VADERApp: App {
    init() {
        UNUserNotificationCenter.current().delegate = RegnvaktNotificationDelegate.shared
        RegnvaktBackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
