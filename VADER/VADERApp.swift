import SwiftUI
import BackgroundTasks
import UserNotifications
import UIKit

/// Makes BGTask completion idempotent when normal completion races expiration.
private final class BackgroundRefreshCompletion {
    private let lock = NSLock()
    private var hasCompleted = false

    func finish(_ task: BGAppRefreshTask, success: Bool) {
        lock.lock()
        guard !hasCompleted else {
            lock.unlock()
            return
        }
        hasCompleted = true
        lock.unlock()
        task.setTaskCompleted(success: success)
    }
}

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
        let earliestDate = Date(timeIntervalSinceNow: 30 * 60)
        request.earliestBeginDate = earliestDate
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "Regnvakt.backgroundRefresh.requestedAt")
        UserDefaults.standard.set(earliestDate.timeIntervalSince1970, forKey: "Regnvakt.backgroundRefresh.earliestAt")
        do {
            try BGTaskScheduler.shared.submit(request)
            UserDefaults.standard.set("Begäran registrerad hos iOS", forKey: "Regnvakt.backgroundRefresh.status")
        } catch {
            UserDefaults.standard.set("iOS avvisade begäran: \\(error.localizedDescription)", forKey: "Regnvakt.backgroundRefresh.status")
        }
    }

    private func handle(_ task: BGAppRefreshTask) {
        let defaults = UserDefaults.standard
        defaults.set(Date().timeIntervalSince1970, forKey: "Regnvakt.backgroundRefresh.startedAt")
        defaults.set("Bakgrundsuppdatering körs", forKey: "Regnvakt.backgroundRefresh.status")
        scheduleNextWeatherRefresh()
        let completion = BackgroundRefreshCompletion()
        let refresh = Task { @MainActor in
            let succeeded = await WeatherViewModel.refreshMonitoredForecastsInBackground()
            let expired = Task.isCancelled
            defaults.set(Date().timeIntervalSince1970, forKey: "Regnvakt.backgroundRefresh.completedAt")
            defaults.set(expired ? "Avbruten av iOS tidsgräns" : (succeeded ? "Prognos hämtad och vakter uppdaterade" : "Ingen prognos kunde uppdateras"), forKey: "Regnvakt.backgroundRefresh.status")
            completion.finish(task, success: succeeded && !expired)
        }
        task.expirationHandler = {
            refresh.cancel()
            defaults.set("Avbruten av iOS tidsgräns", forKey: "Regnvakt.backgroundRefresh.status")
            // Complete immediately when iOS revokes the execution window. The
            // async work may take time to observe cancellation while suspended
            // in URLSession or UserNotifications.
            completion.finish(task, success: false)
        }
    }
}

@MainActor
final class RegnvaktNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = RegnvaktNotificationDelegate()

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let locationID = userInfo["locationID"] as? String,
           let place = userInfo["place"] as? String {
            // Persist before publishing: on a cold launch SwiftUI may not yet
            // have installed ContentView's NotificationCenter subscription.
            NotificationRouteStore.save(locationID: locationID, place: place)
            NotificationCenter.default.post(
                name: .regnvaktOpenWeatherPlace,
                object: nil,
                userInfo: ["locationID": locationID, "place": place]
            )
        }
        completionHandler()
    }

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


extension Notification.Name {
    static let regnvaktOpenWeatherPlace = Notification.Name("Regnvakt.openWeatherPlace")
}


/// Holds a notification destination until the SwiftUI root view is ready.
/// UserDefaults is used only as a tiny hand-off across app-launch timing.
enum NotificationRouteStore {
    private static let key = "Regnvakt.pendingNotificationRoute.v1"

    static func save(locationID: String, place: String) {
        UserDefaults.standard.set(
            ["locationID": locationID, "place": place],
            forKey: key
        )
    }

    static func consume() -> (locationID: String, place: String)? {
        guard let route = UserDefaults.standard.dictionary(forKey: key),
              let locationID = route["locationID"] as? String,
              let place = route["place"] as? String else { return nil }
        UserDefaults.standard.removeObject(forKey: key)
        return (locationID, place)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
