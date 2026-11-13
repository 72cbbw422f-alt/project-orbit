import Foundation
import UserNotifications

/// Schedules local, forecast-based alerts after a fresh Open-Meteo response.
/// These alerts are device-local; they do not replace server-driven push alerts.
enum WeatherNotificationScheduler {
    private static let prefix = "regnvakt.weather."
    private static let formatter: DateFormatter = {
        let value = DateFormatter()
        value.locale = Locale(identifier: "en_US_POSIX")
        value.timeZone = .current
        value.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return value
    }()

    private struct Event {
        let type: String
        let title: String
        let body: String
        let date: Date
    }

    static func refresh(place: String, hours: [HourForecast]) {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "Regnvakt.notifications.enabled") as? Bool ?? true else {
            removePendingAlerts()
            return
        }

        let settings = UNUserNotificationCenter.current()
        settings.getNotificationSettings { authorization in
            guard authorization.authorizationStatus == .authorized ||
                  authorization.authorizationStatus == .provisional else { return }
            let events = makeEvents(hours: hours, defaults: defaults)
            settings.getPendingNotificationRequests { pending in
                let oldIDs = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
                settings.removePendingNotificationRequests(withIdentifiers: oldIDs)

                let requests = events.compactMap { event -> UNNotificationRequest? in
                    let fireDate = event.date.addingTimeInterval(-Double(max(0, defaults.integer(forKey: "Regnvakt.notifications.leadMinutes"))) * 60)
                    guard fireDate > Date().addingTimeInterval(30),
                          !isQuietTime(fireDate, setting: defaults.string(forKey: "Regnvakt.notifications.quietHours") ?? "22–07") else { return nil }
                    let content = UNMutableNotificationContent()
                    content.title = event.title
                    content.body = "\(event.body) • \(place)"
                    content.sound = .default
                    content.userInfo = ["watch": event.type, "place": place]
                    let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                    let id = prefix + event.type + "." + String(Int(event.date.timeIntervalSince1970))
                    return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                }

                for request in requests {
                    settings.add(request) { _ in }
                }
            }
        }
    }

    private static func makeEvents(hours: [HourForecast], defaults: UserDefaults) -> [Event] {
        let lead = max(0, defaults.integer(forKey: "Regnvakt.notifications.leadMinutes"))
        let _ = lead
        var result: [Event] = []
        var previousTypes = Set<String>()

        for hour in hours {
            guard let date = formatter.date(from: hour.id), date > Date() else { continue }
            let condition = hour.condition.lowercased()
            var active = [(String, String, String)]()

            if defaults.object(forKey: "Regnvakt.notifications.rain") as? Bool ?? true,
               (condition.contains("regn") || condition.contains("dugg") || condition.contains("skur")),
               hour.precipitationChance >= 60 || hour.precipitation >= 0.3 {
                active.append(("rain", "Regn väntas", "Regn väntas omkring \(hour.time)."))
            }
            if defaults.object(forKey: "Regnvakt.notifications.snow") as? Bool ?? true,
               condition.contains("snö") {
                active.append(("snow", "Snö väntas", "Snöfall väntas omkring \(hour.time)."))
            }
            if defaults.object(forKey: "Regnvakt.notifications.wind") as? Bool ?? true,
               hour.gust >= 14 {
                active.append(("wind", "Kraftiga vindbyar", String(format: "Vindbyar på cirka %.0f m/s väntas omkring %@.", hour.gust, hour.time)))
            }
            if defaults.object(forKey: "Regnvakt.notifications.thunder") as? Bool ?? true,
               condition.contains("åska") {
                active.append(("thunder", "Åskrisk", "Åska finns i prognosen omkring \(hour.time)."))
            }
            if defaults.object(forKey: "Regnvakt.notifications.frost") as? Bool ?? true,
               hour.temperature <= 0 {
                active.append(("frost", "Frost- och halkrisk", "Temperaturen väntas bli \(hour.temperature)° omkring \(hour.time)."))
            }

            let currentTypes = Set(active.map(\.0))
            for item in active where !previousTypes.contains(item.0) {
                result.append(Event(type: item.0, title: item.1, body: item.2, date: date))
            }
            previousTypes = currentTypes
        }
        return result
    }

    private static func isQuietTime(_ date: Date, setting: String) -> Bool {
        guard setting != "none" else { return false }
        let parts = setting.split(separator: "–").compactMap { Int($0) }
        guard parts.count == 2 else { return false }
        let hour = Calendar.current.component(.hour, from: date)
        let start = parts[0], end = parts[1]
        return start < end ? (hour >= start && hour < end) : (hour >= start || hour < end)
    }

    private static func removePendingAlerts() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
}
