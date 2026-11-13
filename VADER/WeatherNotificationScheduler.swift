import Foundation
import UserNotifications

/// Forecast-based local notifications. iOS may defer app execution in the background,
/// so future alerts are scheduled whenever a fresh forecast is available.
enum WeatherNotificationScheduler {
    private static let prefix = "regnvakt.weather."
    private static let forecastKey = "Regnvakt.notifications.lastForecast.v1"
    private static let placeKey = "Regnvakt.notifications.lastPlace.v1"

    private struct Event {
        let type: String
        let title: String
        let body: String
        let date: Date
        let safetyCritical: Bool
    }

    static func refresh(place: String, hours: [HourForecast]) {
        guard let data = try? JSONEncoder().encode(hours) else { return }
        UserDefaults.standard.set(data, forKey: forecastKey)
        UserDefaults.standard.set(place, forKey: placeKey)
        Task { await schedule(place: place, hours: hours) }
    }

    static func refreshFromStoredForecast() {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: forecastKey),
              let hours = try? JSONDecoder().decode([HourForecast].self, from: data),
              let place = defaults.string(forKey: placeKey) else { return }
        Task { await schedule(place: place, hours: hours) }
    }

    static func removeAll() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) || $0.hasPrefix("smhi.") }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    private static func schedule(place: String, hours: [HourForecast]) async {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "Regnvakt.notifications.enabled") as? Bool ?? true else {
            removeAll()
            return
        }

        let center = UNUserNotificationCenter.current()
        let authorization = await center.notificationSettings()
        guard authorization.authorizationStatus == .authorized ||
              authorization.authorizationStatus == .provisional ||
              authorization.authorizationStatus == .ephemeral else {
            // Do not silently pretend that alerts are armed. The settings screen
            // reports the actual permission state and offers the system prompt.
            return
        }

        let events = makeEvents(hours: hours, defaults: defaults)
        let lead = defaults.object(forKey: "Regnvakt.notifications.leadMinutes") == nil
            ? 30 : max(0, defaults.integer(forKey: "Regnvakt.notifications.leadMinutes"))
        let quietSetting = defaults.string(forKey: "Regnvakt.notifications.quietHours") ?? "22–07"

        var requests: [UNNotificationRequest] = []
        for event in events {
            let fireDate = event.date.addingTimeInterval(-Double(lead) * 60)
            guard fireDate > Date().addingTimeInterval(30) else { continue }
            // Frost and ice alerts are safety-critical and intentionally bypass quiet hours.
            guard event.safetyCritical || !isQuietTime(fireDate, setting: quietSetting) else { continue }

            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = "\(event.body) • \(place)"
            content.sound = .default
            content.userInfo = ["watch": event.type, "place": place, "safetyCritical": event.safetyCritical]
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let stamp = Int(event.date.timeIntervalSince1970)
            let identifier = prefix + event.type + "." + stamp
            requests.append(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }

        // Keep well below iOS's pending local-notification limit and prioritize
        // safety-critical frost/ice alerts before ordinary weather notices.
        requests.sort {
            let left = ($0.content.userInfo["safetyCritical"] as? Bool) ?? false
            let right = ($1.content.userInfo["safetyCritical"] as? Bool) ?? false
            if left != right { return left && !right }
            return ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture <
                   (($1.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture)
        }
        let selected = Array(requests.prefix(48))

        let pending = await center.pendingNotificationRequests()
        let oldIDs = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: oldIDs)
        for request in selected {
            do { try await center.add(request) } catch {
                // A later successful forecast refresh will retry scheduling.
            }
        }
    }

    private static func makeEvents(hours: [HourForecast], defaults: UserDefaults) -> [Event] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

        var result: [Event] = []
        var previousTypes = Set<String>()
        var previousWet = false

        for hour in hours {
            guard let date = formatter.date(from: hour.id), date > Date() else { continue }
            let condition = hour.condition.lowercased()
            let isRain = condition.contains("regn") || condition.contains("dugg") || condition.contains("skur")
            let isSnow = condition.contains("snö")
            let isThunder = condition.contains("åska")
            let wetNow = hour.precipitation >= 0.2 || (hour.precipitationChance >= 50 && (isRain || isSnow))
            var active: [Event] = []

            if defaults.object(forKey: "Regnvakt.notifications.rain") as? Bool ?? true,
               isRain,
               (hour.precipitationChance >= 60 || hour.precipitation >= 0.3) {
                active.append(Event(type: "rain", title: "Regn väntas",
                    body: "Regn väntas omkring \(hour.time). Nederbördsrisk \(hour.precipitationChance)%.",
                    date: date, safetyCritical: false))
            }
            if defaults.object(forKey: "Regnvakt.notifications.snow") as? Bool ?? true, isSnow {
                active.append(Event(type: "snow", title: "Snö väntas",
                    body: "Snöfall väntas omkring \(hour.time).", date: date, safetyCritical: false))
            }
            if defaults.object(forKey: "Regnvakt.notifications.wind") as? Bool ?? true, hour.gust >= 14 {
                active.append(Event(type: "wind", title: "Kraftiga vindbyar",
                    body: String(format: "Vindbyar på cirka %.0f m/s väntas omkring %@.", hour.gust, hour.time),
                    date: date, safetyCritical: false))
            }
            if defaults.object(forKey: "Regnvakt.notifications.thunder") as? Bool ?? true, isThunder {
                active.append(Event(type: "thunder", title: "Åskrisk",
                    body: "Åska finns i prognosen omkring \(hour.time).", date: date, safetyCritical: false))
            }

            if defaults.object(forKey: "Regnvakt.notifications.frost") as? Bool ?? true {
                let calendar = Calendar.current
                let localHour = calendar.component(.hour, from: date)
                let overnight = localHour >= 18 || localHour < 9
                let frostThreshold = overnight ? 1 : 0
                if hour.temperature <= frostThreshold {
                    active.append(Event(type: "frost", title: overnight ? "Frostnatt väntas" : "Frostrisk",
                        body: "Temperaturen väntas nå \(hour.temperature)° omkring kl. \(hour.time).",
                        date: date, safetyCritical: true))
                }
                if hour.temperature <= 1 && (wetNow || previousWet) {
                    active.append(Event(type: "ice", title: "Risk för halka",
                        body: "Fukt eller nederbörd kan frysa när temperaturen ligger kring \(hour.temperature)°. Var extra försiktig på vägar och gångbanor.",
                        date: date, safetyCritical: true))
                }
            }

            let currentTypes = Set(active.map(\.type))
            for event in active where !previousTypes.contains(event.type) {
                result.append(event)
            }
            previousTypes = currentTypes
            previousWet = wetNow
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
}
