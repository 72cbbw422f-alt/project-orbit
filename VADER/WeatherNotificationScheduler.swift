import Foundation
import UserNotifications

/// Forecast-based local notifications. iOS may defer app execution in the background,
/// so future alerts are scheduled whenever a fresh forecast is available.
enum WeatherNotificationScheduler {
    private static let prefix = "regnvakt.weather."
    private static let forecastKey = "Regnvakt.notifications.lastForecast.v1"
    private static let placeKey = "Regnvakt.notifications.lastPlace.v1"
    private static let locationKey = "Regnvakt.notifications.lastLocation.v1"
    private static let scheduleTokenKey = "Regnvakt.notifications.scheduleToken.v1"
    private static let globalScheduleTokenKey = "Regnvakt.notifications.globalScheduleToken.v1"
    private static let currentFrostAlertDayKey = "Regnvakt.notifications.currentFrostAlertDay.v1"
    private static let scheduleStatusKey = "Regnvakt.notifications.scheduleStatus"
    private static let scheduledCountKey = "Regnvakt.notifications.scheduledCount"
    private static let scheduleUpdatedKey = "Regnvakt.notifications.scheduleUpdated"
    private static let currentTemperatureKey = "Regnvakt.notifications.lastCurrentTemperature.v1"
    private static let currentTemperatureUpdatedKey = "Regnvakt.notifications.lastCurrentTemperatureUpdated.v1"
    private static let forecastRegistryKey = "Regnvakt.notifications.forecastRegistry.v1"

    private struct StoredForecast: Codable {
        let place: String
        let locationID: String
        let hours: [HourForecast]
        let currentTemperature: Int?
        let savedAt: Date
    }

    private struct Event {
        let type: String
        let title: String
        let body: String
        let date: Date
        let safetyCritical: Bool
        var immediate: Bool = false
    }

    static func refresh(place: String, latitude: Double, longitude: Double, hours: [HourForecast], currentTemperature: Int? = nil) {
        guard let data = try? JSONEncoder().encode(hours) else { return }
        let defaults = UserDefaults.standard
        let locationKey = String(format: "%.4f,%.4f", latitude, longitude)
        let token = UUID().uuidString
        let globalToken = defaults.string(forKey: globalScheduleTokenKey) ?? "initial"
        defaults.set(token, forKey: scheduleTokenKey + "." + locationKey.replacingOccurrences(of: ",", with: "_"))
        defaults.set(locationKey, forKey: Self.locationKey)
        defaults.set(data, forKey: forecastKey)
        defaults.set(place, forKey: placeKey)
        var registry = (try? JSONDecoder().decode([String: StoredForecast].self, from: defaults.data(forKey: forecastRegistryKey) ?? Data())) ?? [:]
        registry[locationKey] = StoredForecast(place: place, locationID: locationKey, hours: hours, currentTemperature: currentTemperature, savedAt: Date())
        if let registryData = try? JSONEncoder().encode(registry) {
            defaults.set(registryData, forKey: forecastRegistryKey)
        }
        if let currentTemperature {
            defaults.set(currentTemperature, forKey: currentTemperatureKey)
            defaults.set(Date().timeIntervalSince1970, forKey: currentTemperatureUpdatedKey)
        }
        Task { await schedule(place: place, hours: hours, currentTemperature: currentTemperature, token: token, globalToken: globalToken, locationID: locationKey) }
    }

    static func refreshFromStoredForecast() {
        let defaults = UserDefaults.standard
        let globalToken = defaults.string(forKey: globalScheduleTokenKey) ?? "initial"
        let registryData = defaults.data(forKey: forecastRegistryKey)
        let registry = registryData.flatMap { try? JSONDecoder().decode([String: StoredForecast].self, from: $0) } ?? [:]

        // Reconcile every cached monitored location, not only the last place
        // whose forecast happened to be loaded in the foreground.
        if !registry.isEmpty {
            for stored in registry.values {
                let token = UUID().uuidString
                let tokenKey = scheduleTokenKey + "." + stored.locationID.replacingOccurrences(of: ",", with: "_")
                defaults.set(token, forKey: tokenKey)
                let temperatureIsFresh = Date().timeIntervalSince(stored.savedAt) <= 2 * 60 * 60
                let temperature = temperatureIsFresh ? stored.currentTemperature : nil
                Task {
                    await schedule(place: stored.place, hours: stored.hours, currentTemperature: temperature,
                                   token: token, globalToken: globalToken, locationID: stored.locationID)
                }
            }
            return
        }

        // The legacy single-place cache is only valid before explicit-place
        // monitoring migration. Never resurrect a removed/unmonitored location.
        let migrationKey = "Regnvakt.notifications.explicitPlaceMonitoringMigration.v1"
        if defaults.bool(forKey: migrationKey) {
            // No registered forecasts means no monitored place currently has a
            // schedulable forecast. Clear any orphaned weather requests and status.
            let registrySnapshot = registryData
            Task {
                let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
                guard defaults.data(forKey: forecastRegistryKey) == registrySnapshot else { return }
                let ids = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
                defaults.set(0, forKey: scheduledCountKey)
                defaults.set(Date().timeIntervalSince1970, forKey: scheduleUpdatedKey)
                defaults.set("Inga bevakade platser med sparad prognos", forKey: scheduleStatusKey)
            }
            return
        }

        // Migrate installations that only have the former single-place cache.
        if let data = defaults.data(forKey: forecastKey),
           let hours = try? JSONDecoder().decode([HourForecast].self, from: data) {
            let place = defaults.string(forKey: placeKey) ?? "vald plats"
            let storedLocationID = defaults.string(forKey: locationKey) ?? "unknown"
            let token = UUID().uuidString
            defaults.set(token, forKey: scheduleTokenKey + "." + storedLocationID.replacingOccurrences(of: ",", with: "_"))
            let temperatureAge = Date().timeIntervalSince1970 - defaults.double(forKey: currentTemperatureUpdatedKey)
            let recentTemperature = temperatureAge >= 0 && temperatureAge <= 2 * 60 * 60
                ? defaults.object(forKey: currentTemperatureKey) as? Int
                : nil
            Task { await schedule(place: place, hours: hours, currentTemperature: recentTemperature, token: token, globalToken: globalToken, locationID: storedLocationID) }
        } else {
            let token = UUID().uuidString
            let storedLocationID = defaults.string(forKey: locationKey) ?? "unknown"
            defaults.set(token, forKey: scheduleTokenKey + "." + storedLocationID.replacingOccurrences(of: ",", with: "_"))
            Task { await schedule(place: "vald plats", hours: [], currentTemperature: nil, token: token, globalToken: globalToken, locationID: storedLocationID) }
        }
    }

    static func removeAll() {
        // Invalidate every in-flight schedule before touching the notification center.
        UserDefaults.standard.set(UUID().uuidString, forKey: globalScheduleTokenKey)
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) || $0.hasPrefix("smhi.") }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
        center.getDeliveredNotifications { notifications in
            let ids = notifications.map { $0.request.identifier }.filter { $0.hasPrefix(prefix) || $0.hasPrefix("smhi.") }
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    static func removeNotifications(latitude: Double, longitude: Double) {
        let locationID = String(format: "%.4f,%.4f", latitude, longitude)
            .replacingOccurrences(of: ",", with: "_")
        // Rotate the location token synchronously so an older async schedule
        // cannot re-add notifications after this watch has been disabled.
        let defaults = UserDefaults.standard
        defaults.set(UUID().uuidString, forKey: scheduleTokenKey + "." + locationID)
        if let data = defaults.data(forKey: forecastRegistryKey),
           var registry = try? JSONDecoder().decode([String: StoredForecast].self, from: data) {
            registry.removeValue(forKey: String(format: "%.4f,%.4f", latitude, longitude))
            if let updated = try? JSONEncoder().encode(registry) {
                defaults.set(updated, forKey: forecastRegistryKey)
            }
        }
        let locationPrefix = prefix + locationID + "."
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(locationPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
        center.getDeliveredNotifications { notifications in
            let ids = notifications.map { $0.request.identifier }.filter { $0.hasPrefix(locationPrefix) }
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    static func clearLegacyWeatherNotificationsOnce() {
        let key = "Regnvakt.notifications.explicitPlaceMonitoringMigration.v1"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: key) else { return }

        let registry = defaults.data(forKey: forecastRegistryKey)
            .flatMap { try? JSONDecoder().decode([String: StoredForecast].self, from: $0) } ?? [:]
        let validPlacePrefixes = registry.values.map {
            prefix + $0.locationID.replacingOccurrences(of: ",", with: "_") + "."
        }
        // Mark migration complete before the asynchronous notification-center
        // read, so a legacy cache cannot be scheduled again during cleanup.
        defaults.set(true, forKey: key)

        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { identifier in
                identifier.hasPrefix(prefix) &&
                    !validPlacePrefixes.contains(where: { identifier.hasPrefix($0) })
            }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    private static func schedule(place: String, hours: [HourForecast], currentTemperature: Int?, token: String, globalToken: String, locationID: String) async {
        let defaults = UserDefaults.standard
        let center = UNUserNotificationCenter.current()
        let tokenKey = scheduleTokenKey + "." + locationID.replacingOccurrences(of: ",", with: "_")
        guard defaults.string(forKey: tokenKey) == token,
              (defaults.string(forKey: globalScheduleTokenKey) ?? "initial") == globalToken else { return }
        let globallyEnabled = defaults.object(forKey: "Regnvakt.notifications.enabled") as? Bool ?? true
        guard globallyEnabled else {
            
            let pending = await center.pendingNotificationRequests()
            guard defaults.string(forKey: tokenKey) == token,
                  (defaults.string(forKey: globalScheduleTokenKey) ?? "initial") == globalToken else { return }
            let staleIDs = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: staleIDs)
            SMHIWarningService.clearPendingNotifications()
            defaults.set("Aviseringar avstängda i Regnvakt", forKey: scheduleStatusKey)
            defaults.set(0, forKey: scheduledCountKey)
            defaults.set(Date().timeIntervalSince1970, forKey: scheduleUpdatedKey)
            return
        }

        let authorization = await center.notificationSettings()
        guard defaults.string(forKey: tokenKey) == token,
              (defaults.string(forKey: globalScheduleTokenKey) ?? "initial") == globalToken else { return }

        let allowed = authorization.authorizationStatus == .authorized ||
            authorization.authorizationStatus == .provisional ||
            authorization.authorizationStatus == .ephemeral
        guard allowed else {
            // Remove previously armed weather alerts immediately if permission was revoked.
            let pending = await center.pendingNotificationRequests()
            guard defaults.string(forKey: tokenKey) == token,
                  (defaults.string(forKey: globalScheduleTokenKey) ?? "initial") == globalToken else { return }
            let staleIDs = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: staleIDs)
            let status = authorization.authorizationStatus == .denied
                ? "iPhone blockerar notiser – inga väderaviseringar är schemalagda"
                : "Notisbehörighet saknas – inga väderaviseringar är schemalagda"
            defaults.set(status, forKey: scheduleStatusKey)
            defaults.set(0, forKey: scheduledCountKey)
            defaults.set(Date().timeIntervalSince1970, forKey: scheduleUpdatedKey)
            return
        }

        
        let frostDayKey = currentFrostAlertDayKey + "." + locationID.replacingOccurrences(of: ",", with: "_")
        let events = makeEvents(hours: hours, currentTemperature: currentTemperature, defaults: defaults, frostDayKey: frostDayKey)
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
            let weatherIcon: String
            switch event.type {
            case "rain": weatherIcon = "🌧️"
            case "snow": weatherIcon = "❄️"
            case "wind": weatherIcon = "💨"
            case "thunder": weatherIcon = "⛈️"
            case "frost": weatherIcon = "🥶"
            case "ice": weatherIcon = "🧊"
            default: weatherIcon = "🌦️"
            }
            let probabilityText = event.body.components(separatedBy: "Sannolikhet ").last?.components(separatedBy: "%").first
            let probability = probabilityText.flatMap { Int($0) }
            let riskLabel: String
            if event.safetyCritical {
                riskLabel = " • Hög risk"
            } else if let probability, probability >= 70 {
                riskLabel = " • Hög sannolikhet"
            } else if let probability, probability >= 50 {
                riskLabel = " • Medelhög sannolikhet"
            } else {
                riskLabel = " • Risk i prognosen"
            }
            content.title = "\(weatherIcon) \(event.title)\(riskLabel)"
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
            } else if event.type == "frost" {
                // Stable local-day identity: refreshed hourly forecasts must
                // update one frost warning, never create a new alert per hour.
                let day = DateFormatter()
                day.calendar = Calendar.current
                day.timeZone = .current
                day.dateFormat = "yyyyMMdd"
                stamp = day.string(from: Calendar.current.startOfDay(for: event.date))
            } else {
                stamp = String(Int(event.date.timeIntervalSince1970))
            }
            let locationToken = locationID.replacingOccurrences(of: ",", with: "_")
            let identifier = prefix + locationToken + "." + event.type + (event.immediate ? ".current." : ".") + stamp
            requests.append(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }

        // Keep well below iOS's pending local-notification limit and prioritize
        // safety-critical frost/ice alerts before ordinary weather notices.
        requests.sort {
            let leftImmediate = ($0.content.userInfo["immediate"] as? Bool) ?? false
            let rightImmediate = ($1.content.userInfo["immediate"] as? Bool) ?? false
            if leftImmediate != rightImmediate { return leftImmediate && !rightImmediate }
            let leftSafetyCritical = ($0.content.userInfo["safetyCritical"] as? Bool) ?? false
            let rightSafetyCritical = ($1.content.userInfo["safetyCritical"] as? Bool) ?? false
            if leftSafetyCritical != rightSafetyCritical { return leftSafetyCritical && !rightSafetyCritical }
            let leftDate = ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
            let rightDate = ($1.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
            return leftDate < rightDate
        }
        // Reserve headroom for official SMHI alerts and other app notifications.
        // Divide the weather-notification budget across every registered place.
        let registryCount: Int
        if let data = defaults.data(forKey: forecastRegistryKey),
           let registry = try? JSONDecoder().decode([String: StoredForecast].self, from: data) {
            registryCount = max(1, registry.count)
        } else {
            registryCount = 1
        }
        let perPlaceLimit = max(1, min(8, 52 / registryCount))
        let selected = Array(requests.prefix(perPlaceLimit))

        
        let pending = await center.pendingNotificationRequests()
        guard defaults.string(forKey: tokenKey) == token,
              (defaults.string(forKey: globalScheduleTokenKey) ?? "initial") == globalToken else { return }
        let delivered = await center.deliveredNotifications()
        guard defaults.string(forKey: tokenKey) == token,
              (defaults.string(forKey: globalScheduleTokenKey) ?? "initial") == globalToken else { return }
        let desiredIDs = Set(selected.map(\.identifier))
        let preserveCurrentFrost = currentTemperature == nil
            && (defaults.object(forKey: "Regnvakt.notifications.frost") as? Bool ?? true)
        let oldIDs = pending.map(\.identifier).filter { identifier in
            guard identifier.hasPrefix(prefix + locationID.replacingOccurrences(of: ",", with: "_") + "."), !desiredIDs.contains(identifier) else { return false }
            if preserveCurrentFrost && identifier.contains(".frost.current.") { return false }
            return true
        }
        center.removePendingNotificationRequests(withIdentifiers: oldIDs)
        let existingIDs = Set(pending.map(\.identifier)).union(delivered.map { $0.request.identifier })
        for request in selected {
            guard defaults.string(forKey: tokenKey) == token,
              (defaults.string(forKey: globalScheduleTokenKey) ?? "initial") == globalToken else { return }
            let isImmediate = (request.content.userInfo["immediate"] as? Bool) ?? false
            if existingIDs.contains(request.identifier) {
                if isImmediate, let alertDay = request.content.userInfo["alertDay"] as? Date {
                    defaults.set(alertDay, forKey: frostDayKey)
                }
                continue
            }
            do {
                try await center.add(request)
                guard defaults.string(forKey: tokenKey) == token,
                      (defaults.string(forKey: globalScheduleTokenKey) ?? "initial") == globalToken else {
                    center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
                    return
                }
                if isImmediate, let alertDay = request.content.userInfo["alertDay"] as? Date {
                    defaults.set(alertDay, forKey: frostDayKey)
                }
            } catch {
                defaults.set("Fel vid schemaläggning: \(error.localizedDescription)", forKey: scheduleStatusKey)
            }
        }
        let finalPending = await center.pendingNotificationRequests()
        guard defaults.string(forKey: tokenKey) == token,
              (defaults.string(forKey: globalScheduleTokenKey) ?? "initial") == globalToken else { return }
        let finalCount = finalPending.filter { $0.identifier.hasPrefix(prefix) }.count
        defaults.set(finalCount, forKey: scheduledCountKey)
        defaults.set(Date().timeIntervalSince1970, forKey: scheduleUpdatedKey)
        if defaults.string(forKey: scheduleStatusKey)?.hasPrefix("Fel vid schemaläggning:") != true {
            defaults.set(finalCount == 0
                ? "Inga framtida risker passerade aviseringsgränserna"
                : "\(finalCount) väderavisering(ar) schemalagda i iPhone", forKey: scheduleStatusKey)
        }
    }

    private static func makeEvents(hours: [HourForecast], currentTemperature: Int?, defaults: UserDefaults, frostDayKey: String) -> [Event] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

        var result: [Event] = []
        var emittedTypes = Set<String>()
        var forecastFrostDays = Set<Date>()
        var lastWetForecastDate: Date?

        // Current frost is a separate, immediate safety alert. It is deduplicated
        // by a stable daily identifier and remains armed across forecast refreshes.
        let now = Date()
        var swedishCalendar = Calendar(identifier: .gregorian)
        swedishCalendar.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
        let orderedHours = hours.compactMap { hour -> (HourForecast, Date)? in
            guard let date = formatter.date(from: hour.id) else { return nil }
            return (hour, date)
        }.sorted { $0.1 < $1.1 }
        // Only schedule forecast-driven alerts inside the configured notification horizon.
        // The current-temperature frost check above remains immediate and separate.
        let forecastHorizon = WeatherWatchRules.notificationForecastHorizon(from: now)
        let currentHour = swedishCalendar.component(.hour, from: now)
        let currentOvernight = currentHour >= 18 || currentHour < 9
        let currentThreshold = currentOvernight ? 1 : 0
        let currentFrost = (defaults.object(forKey: "Regnvakt.notifications.frost") as? Bool ?? true)
            && (currentTemperature.map { $0 <= currentThreshold } ?? false)
        let lastCurrentFrostAlertDay = defaults.object(forKey: frostDayKey) as? Date
        let alreadyAlertedForCurrentFrostToday = lastCurrentFrostAlertDay.map {
            Calendar.current.isDate($0, inSameDayAs: now)
        } ?? false
        if currentFrost {
            // Seed the transition detector even when today's immediate alert was
            // already delivered, so the same continuous frost episode is not re-armed.
            emittedTypes.insert("frost")
        }
        // A current frost alert and a forecast frost alert must never coexist
        // for the same monitored place and local calendar day. The stored day
        // also covers a previously armed current alert when cached temperature
        // has become stale and currentTemperature is temporarily nil.
        if currentFrost || alreadyAlertedForCurrentFrostToday {
            forecastFrostDays.insert(swedishCalendar.startOfDay(for: now))
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

        for (hour, date) in orderedHours {
            guard date > now, date <= forecastHorizon else { continue }

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
                (lastWetForecastDate.map {
                    let elapsed = date.timeIntervalSince($0)
                    return elapsed >= 0 && elapsed <= 3 * 60 * 60
                } ?? false)
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
            if (defaults.object(forKey: "Regnvakt.notifications.wind") as? Bool ?? true),
               (hour.gust >= WeatherWatchRules.windGustThreshold || hour.wind >= 11) {
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
                let localHour = swedishCalendar.component(.hour, from: date)
                let overnight = localHour >= 18 || localHour < 9
                // Forecast temperatures are whole degrees. A 1°C buffer is used
                // overnight; during daytime, require freezing temperature.
                let frostThreshold = overnight ? 1 : 0

                if hour.temperature <= frostThreshold {
                    let calendar = swedishCalendar
                    let eventDay = calendar.startOfDay(for: date)
                    // One forecast frost warning per local calendar day and
                    // monitored place. Hourly temperatures can oscillate around
                    // 0–1°C; do not create several near-identical alerts for
                    // the same overnight frost episode.
                    if forecastFrostDays.insert(eventDay).inserted {
                        let today = swedishCalendar.startOfDay(for: Date())
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

            // Emit at most one alert per risk type during this eight-hour
            // forecast window. Short gaps in hourly model data must not create
            // a second near-identical warning for the same ongoing episode.
            for event in active where emittedTypes.insert(event.type).inserted {
                result.append(event)
            }

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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
        let hour = calendar.component(.hour, from: date)
        let start = parts[0], end = parts[1]
        return start < end ? (hour >= start && hour < end) : (hour >= start || hour < end)
    }
}
