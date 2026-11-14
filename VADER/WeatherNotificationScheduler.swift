import Foundation
import UserNotifications

/// Forecast-based local notifications. iOS may defer app execution in the background,
/// so future alerts are scheduled whenever a fresh forecast is available.
enum WeatherNotificationScheduler {
    private static let prefix = "regnvakt.weather."
    private static let forecastKey = "Regnvakt.notifications.lastForecast.v1"
    private static let placeKey = "Regnvakt.notifications.lastPlace.v1"
    private static let currentFrostAlertDayKey = "Regnvakt.notifications.currentFrostAlertDay.v1"

    private struct Event {
        let type: String
        let title: String
        let body: String
        let date: Date
        let safetyCritical: Bool
        let immediate: Bool = false
    }

    static func refresh(place: String, hours: [HourForecast], currentTemperature: Int? = nil) {
        guard let data = try? JSONEncoder().encode(hours) else { return }
        UserDefaults.standard.set(data, forKey: forecastKey)
        UserDefaults.standard.set(place, forKey: placeKey)
        Task { await schedule(place: place, hours: hours, currentTemperature: currentTemperature) }
    }

    static func refreshFromStoredForecast() {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: forecastKey),
              let hours = try? JSONDecoder().decode([HourForecast].self, from: data),
              let place = defaults.string(forKey: placeKey) else { return }
        Task { await schedule(place: place, hours: hours, currentTemperature: nil) }
    }

    static func removeAll() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) || $0.hasPrefix("smhi.") }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    private static func schedule(place: String, hours: [HourForecast], currentTemperature: Int?) async {
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

        let events = makeEvents(hours: hours, currentTemperature: currentTemperature, defaults: defaults)
        let lead = defaults.object(forKey: "Regnvakt.notifications.leadMinutes") == nil
            ? 30 : max(0, defaults.integer(forKey: "Regnvakt.notifications.leadMinutes"))
        let quietSetting = defaults.string(forKey: "Regnvakt.notifications.quietHours") ?? "22–07"

        var requests: [UNNotificationRequest] = []
        for event in events {
            let fireDate = event.immediate ? Date().addingTimeInterval(2) : event.date.addingTimeInterval(-Double(lead) * 60)
            guard event.immediate || fireDate > Date().addingTimeInterval(30) else { continue }
            // Frost and ice alerts are safety-critical and intentionally bypass quiet hours.
            guard event.safetyCritical || !isQuietTime(fireDate, setting: quietSetting) else { continue }

            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = "\(event.body) • \(place)"
            content.sound = .default
            content.userInfo = ["watch": event.type, "place": place, "safetyCritical": event.safetyCritical, "immediate": event.immediate, "alertDay": Calendar.current.startOfDay(for: event.date), "forecastEventDate": event.date.timeIntervalSince1970, "leadMinutes": lead]
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger: UNNotificationTrigger
            if event.immediate {
                trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
            } else {
                trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            }
            let stamp: String
            if event.immediate {
                let day = DateFormatter()
                day.calendar = Calendar.current
                day.timeZone = .current
                day.dateFormat = "yyyyMMdd"
                stamp = day.string(from: Date())
            } else {
                stamp = String(Int(event.date.timeIntervalSince1970))
            }
            let identifier = prefix + event.type + (event.immediate ? ".current." : ".") + stamp
            requests.append(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }

        // Keep well below iOS's pending local-notification limit and prioritize
        // safety-critical frost/ice alerts before ordinary weather notices.
        requests.sort {
            let left = ($0.content.userInfo["safetyCritical"] as? Bool) ?? false
            let right = ($1.content.userInfo["safetyCritical"] as? Bool) ?? false
            if left != right { return left && !right }
            let leftDate = ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
            let rightDate = ($1.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
            return leftDate < rightDate
        }
        let selected = Array(requests.prefix(48))

        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        let desiredIDs = Set(selected.map(\.identifier))
        let preserveCurrentFrost = currentTemperature == nil
            && (defaults.object(forKey: "Regnvakt.notifications.frost") as? Bool ?? true)
        let oldIDs = pending.map(\.identifier).filter { identifier in
            guard identifier.hasPrefix(prefix), !desiredIDs.contains(identifier) else { return false }
            if preserveCurrentFrost && identifier.contains(".frost.current.") { return false }
            return true
        }
        center.removePendingNotificationRequests(withIdentifiers: oldIDs)
        let existingIDs = Set(pending.map(\.identifier)).union(delivered.map { $0.request.identifier })
        for request in selected {
            let isImmediate = (request.content.userInfo["immediate"] as? Bool) ?? false
            if existingIDs.contains(request.identifier) {
                if isImmediate, let alertDay = request.content.userInfo["alertDay"] as? Date {
                    defaults.set(alertDay, forKey: currentFrostAlertDayKey)
                }
                continue
            }
            do {
                try await center.add(request)
                if isImmediate, let alertDay = request.content.userInfo["alertDay"] as? Date {
                    defaults.set(alertDay, forKey: currentFrostAlertDayKey)
                }
            } catch {
                // A later successful forecast refresh will retry scheduling.
            }
        }
    }

    private static func makeEvents(hours: [HourForecast], currentTemperature: Int?, defaults: UserDefaults) -> [Event] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

        var result: [Event] = []
        var previousTypes = Set<String>()
        var lastWetForecastDate: Date?

        // Current frost is a separate, immediate safety alert. It is deduplicated
        // by a stable daily identifier and remains armed across forecast refreshes.
        let now = Date()
        let currentHour = Calendar.current.component(.hour, from: now)
        let currentOvernight = currentHour >= 18 || currentHour < 9
        let currentThreshold = currentOvernight ? 1 : 0
        let currentFrost = (defaults.object(forKey: "Regnvakt.notifications.frost") as? Bool ?? true)
            && (currentTemperature.map { $0 <= currentThreshold } ?? false)
        let lastCurrentFrostAlertDay = defaults.object(forKey: currentFrostAlertDayKey) as? Date
        let alreadyAlertedForCurrentFrostToday = lastCurrentFrostAlertDay.map {
            Calendar.current.isDate($0, inSameDayAs: now)
        } ?? false
        if currentFrost {
            // Seed the transition detector even when today's immediate alert was
            // already delivered, so the same continuous frost episode is not re-armed.
            previousTypes.insert("frost")
        }
        if currentFrost && !alreadyAlertedForCurrentFrostToday {
            result.append(Event(
                type: "frost",
                title: "Frostrisk just nu",
                body: "Den aktuella temperaturen är omkring \(currentTemperature ?? 0)°. Frost kan bildas även utan nederbörd. Detta är en riskbedömning.",
                date: now,
                safetyCritical: true,
                immediate: true
            ))
        }

        for hour in hours {
            guard let date = formatter.date(from: hour.id), date > Date() else { continue }

            let condition = hour.condition.lowercased()
            let isRain = condition.contains("regn") || condition.contains("dugg") || condition.contains("skur")
            let isSnow = condition.contains("snö")
            let isThunder = condition.contains("åska")
            let isFreezingPrecipitation = condition.contains("underkylt")
            let hasPrecipitation = hour.precipitation >= 0.2
            let forecastShowsWetWeather = isRain || isSnow || isFreezingPrecipitation
            let wetNow = hasPrecipitation ||
                (hour.precipitationChance >= 50 && forecastShowsWetWeather)
            let wetWithinThreeHours = wetNow ||
                (lastWetForecastDate.map { date.timeIntervalSince($0) <= 3 * 60 * 60 } ?? false)
            var active: [Event] = []

            // Rain: notify for a meaningful forecast probability or measurable amount.
            if defaults.object(forKey: "Regnvakt.notifications.rain") as? Bool ?? true,
               isRain,
               (hour.precipitationChance >= 40 || hour.precipitation >= 0.3) {
                active.append(Event(type: "rain", title: "Regn väntas",
                    body: "Regn väntas omkring \(hour.time). Sannolikhet \(hour.precipitationChance)%, mängd cirka \(String(format: "%.1f", hour.precipitation)) mm.",
                    date: date, safetyCritical: false))
            }
            // Snow: require either a reasonable probability or measurable snowfall.
            if defaults.object(forKey: "Regnvakt.notifications.snow") as? Bool ?? true,
               isSnow,
               (hour.precipitationChance >= 40 || hour.precipitation >= 0.2) {
                active.append(Event(type: "snow", title: "Snöfall väntas",
                    body: "Snöfall väntas omkring \(hour.time). Sannolikhet \(hour.precipitationChance)%.",
                    date: date, safetyCritical: false))
            }
            // Wind: consider both sustained wind and gusts; gusts carry the higher threshold.
            if defaults.object(forKey: "Regnvakt.notifications.wind") as? Bool ?? true,
               hour.gust >= 17 || hour.wind >= 11 {
                active.append(Event(type: "wind", title: "Kraftig vind väntas",
                    body: String(format: "Vind cirka %.0f m/s med byar upp mot %.0f m/s omkring %@.", hour.wind, hour.gust, hour.time),
                    date: date, safetyCritical: false))
            }
            if defaults.object(forKey: "Regnvakt.notifications.thunder") as? Bool ?? true, isThunder {
                active.append(Event(type: "thunder", title: "Åskrisk",
                    body: "Åska finns i prognosen omkring \(hour.time). Kontrollera SMHI:s lokala varningar och sök skydd vid åska.",
                    date: date, safetyCritical: false))
            }

            if defaults.object(forKey: "Regnvakt.notifications.frost") as? Bool ?? true {
                let localHour = Calendar.current.component(.hour, from: date)
                let overnight = localHour >= 18 || localHour < 9
                // Forecast temperatures are whole degrees. A 1°C buffer is used
                // overnight; during daytime, require freezing temperature.
                let frostThreshold = overnight ? 1 : 0

                if hour.temperature <= frostThreshold {
                    let calendar = Calendar.current
                    let today = calendar.startOfDay(for: Date())
                    let eventDay = calendar.startOfDay(for: date)
                    let dayOffset = calendar.dateComponents([.day], from: today, to: eventDay).day ?? 99
                    let currentHour = calendar.component(.hour, from: Date())
                    let isTonight = (dayOffset == 0 && (localHour >= 18 || (currentHour < 9 && localHour < 9)))
                        || (dayOffset == 1 && currentHour >= 9 && localHour < 9)
                    let dateLabel = date.formatted(date: .abbreviated, time: .omitted)
                    active.append(Event(
                        type: "frost",
                        title: isTonight ? "Möjlig frostrisk i natt" : "Möjlig frostrisk",
                        body: "Prognosen visar omkring \(hour.temperature)° den \(dateLabel) kl. \(hour.time). Frost kan bildas även utan nederbörd. Detta är en riskprognos, inte en säker händelse.",
                        date: date,
                        safetyCritical: true
                    ))
                }

                // Ice risk is distinct from frost: moisture must be present now,
                // or have occurred within the previous three forecast hours.
                // Freezing drizzle/rain is treated as wet even at low amounts.
                if hour.temperature <= 1 && (wetWithinThreeHours || isFreezingPrecipitation) {
                    active.append(Event(
                        type: "ice",
                        title: "Möjlig halkrisk",
                        body: "Fukt eller nederbörd kan frysa när temperaturen ligger kring \(hour.temperature)°. Det finns risk för halka – var extra försiktig på vägar och gångbanor.",
                        date: date,
                        safetyCritical: true
                    ))
                }
            }

            let currentTypes = Set(active.map(\.type))
            for event in active where !previousTypes.contains(event.type) {
                result.append(event)
            }
            previousTypes = currentTypes

            if wetNow {
                lastWetForecastDate = date
            }
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
