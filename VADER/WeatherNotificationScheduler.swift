import Foundation
import UserNotifications

/// Forecast-based local notifications. iOS may defer app execution in the background,
/// so future alerts are scheduled whenever a fresh forecast is available.
enum WeatherNotificationScheduler {
    private static let prefix = "regnvakt.weather."
    private static let swedishTimeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current

    private static var swedishCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = swedishTimeZone
        return calendar
    }
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
        // All registered forecasts are scheduled through one serialized batch.
        // This prevents each refresh from launching a competing per-place task.
        // A freshly fetched live forecast may evaluate an immediate current-frost alert.
        // Restoring persisted forecasts at launch must never replay that alert.
        refreshFromStoredForecast(allowImmediateCurrentFrost: true, immediateFrostLocationID: locationKey)
    }

    static func refreshFromStoredForecast() {
        refreshFromStoredForecast(allowImmediateCurrentFrost: false, immediateFrostLocationID: nil)
    }

    private static func refreshFromStoredForecast(allowImmediateCurrentFrost: Bool, immediateFrostLocationID: String?) {
        let defaults = UserDefaults.standard
        // Every new batch invalidates any older batch before it can continue
        // after an asynchronous notification-center operation.
        let globalToken = UUID().uuidString
        defaults.set(globalToken, forKey: globalScheduleTokenKey)
        let registryData = defaults.data(forKey: forecastRegistryKey)
        let registry = registryData.flatMap { try? JSONDecoder().decode([String: StoredForecast].self, from: $0) } ?? [:]

        if !registry.isEmpty {
            Task {
                await reconcileGlobally(
                    registry: registry,
                    registrySnapshot: registryData,
                    globalToken: globalToken,
                    allowImmediateCurrentFrost: allowImmediateCurrentFrost,
                    immediateFrostLocationID: immediateFrostLocationID
                )
            }
            return
        }

        // The legacy single-place cache is only valid before explicit-place
        // monitoring migration. Never resurrect a removed/unmonitored location.
        let migrationKey = "Regnvakt.notifications.explicitPlaceMonitoringMigration.v1"
        if defaults.bool(forKey: migrationKey) {
            // No registered forecasts means no monitored place currently has a
            // schedulable forecast. Clear orphaned forecast requests only if this
            // batch is still current.
            let registrySnapshot = registryData
            Task {
                let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
                guard (defaults.string(forKey: globalScheduleTokenKey) ?? "initial") == globalToken,
                      defaults.data(forKey: forecastRegistryKey) == registrySnapshot else { return }
                let ids = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
                defaults.set(0, forKey: scheduledCountKey)
                defaults.set(Date().timeIntervalSince1970, forKey: scheduleUpdatedKey)
                defaults.set("Inga bevakade platser med sparad prognos", forKey: scheduleStatusKey)
            }
            return
        }

        // Migrate installations that only have the former single-place cache.
        let storedLocationID = defaults.string(forKey: locationKey) ?? "unknown"
        let token = UUID().uuidString
        defaults.set(token, forKey: scheduleTokenKey + "." + storedLocationID.replacingOccurrences(of: ",", with: "_"))
        if let data = defaults.data(forKey: forecastKey),
           let hours = try? JSONDecoder().decode([HourForecast].self, from: data) {
            let place = defaults.string(forKey: placeKey) ?? "vald plats"
            let temperatureAge = Date().timeIntervalSince1970 - defaults.double(forKey: currentTemperatureUpdatedKey)
            let recentTemperature = temperatureAge >= 0 && temperatureAge <= 2 * 60 * 60
                ? defaults.object(forKey: currentTemperatureKey) as? Int
                : nil
            Task {
                guard (defaults.string(forKey: globalScheduleTokenKey) ?? "initial") == globalToken else { return }
                await schedule(place: place, hours: hours, currentTemperature: recentTemperature,
                               token: token, globalToken: globalToken, locationID: storedLocationID)
            }
        } else {
            Task {
                guard (defaults.string(forKey: globalScheduleTokenKey) ?? "initial") == globalToken else { return }
                await schedule(place: "vald plats", hours: [], currentTemperature: nil,
                               token: token, globalToken: globalToken, locationID: storedLocationID)
            }
        }
    }

    /// Reconciles every monitored location against one notification-center snapshot.
    /// Only Regnvakt forecast requests are replaced; SMHI and other owners are untouched.
    private static func reconcileGlobally(
        registry: [String: StoredForecast],
        registrySnapshot: Data?,
        globalToken: String,
        allowImmediateCurrentFrost: Bool,
        immediateFrostLocationID: String?
    ) async {
        let defaults = UserDefaults.standard
        let center = UNUserNotificationCenter.current()
        func isCurrentBatch() -> Bool {
            (defaults.string(forKey: globalScheduleTokenKey) ?? "initial") == globalToken &&
                defaults.data(forKey: forecastRegistryKey) == registrySnapshot
        }
        guard isCurrentBatch() else { return }

        let globallyEnabled = defaults.object(forKey: "Regnvakt.notifications.enabled") as? Bool ?? true
        let authorization = await center.notificationSettings()
        guard isCurrentBatch() else { return }
        let allowed = authorization.authorizationStatus == .authorized ||
            authorization.authorizationStatus == .provisional ||
            authorization.authorizationStatus == .ephemeral

        // A single pending and delivered snapshot is shared by all locations.
        let pending = await center.pendingNotificationRequests()
        guard isCurrentBatch() else { return }
        let delivered = await center.deliveredNotifications()
        guard isCurrentBatch() else { return }

        let pendingIDs = pending.map(\.identifier)
        let deliveredIDs = Set(delivered.map { $0.request.identifier })
        // Keep daily frost deduplication in sync in the global path too.
        // The legacy per-location scheduler did this; global reconciliation must
        // remember delivered immediate frost alerts across app launches as well.
        let deliveredFrostAlerts = delivered.map { notification in
            DeliveredCurrentFrostAlert(
                identifier: notification.request.identifier,
                alertDay: notification.request.content.userInfo["alertDay"] as? Date,
                isImmediate: (notification.request.content.userInfo["immediate"] as? Bool) == true &&
                    (notification.request.content.userInfo["watch"] as? String) == "frost"
            )
        }
        let deliveredFrostDays = WeatherNotificationBudget.latestDeliveredCurrentFrostDays(
            alerts: deliveredFrostAlerts,
            registeredLocationIDs: Set(registry.values.map(\.locationID)),
            forecastPrefix: prefix
        )
        for (locationID, alertDay) in deliveredFrostDays {
            let key = currentFrostAlertDayKey + "." + locationID.replacingOccurrences(of: ",", with: "_")
            let previous = defaults.object(forKey: key) as? Date
            if previous.map({ $0 < alertDay }) ?? true {
                defaults.set(alertDay, forKey: key)
            }
        }
        let preserveFrost = defaults.object(forKey: "Regnvakt.notifications.frost") as? Bool ?? true
        let preservedFrostIDs = WeatherNotificationBudget.preservedPendingCurrentFrostIdentifiers(
            pendingIdentifiers: pendingIDs,
            registeredLocationIDs: Set(registry.values.map(\.locationID)),
            isEnabled: preserveFrost,
            forecastPrefix: prefix
        )

        guard globallyEnabled, allowed else {
            let staleIDs = pendingIDs.filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: staleIDs)
            guard isCurrentBatch() else { return }
            defaults.set(0, forKey: scheduledCountKey)
            defaults.set(Date().timeIntervalSince1970, forKey: scheduleUpdatedKey)
            defaults.set(globallyEnabled
                ? (authorization.authorizationStatus == .denied
                    ? "iPhone blockerar notiser – inga väderaviseringar är schemalagda"
                    : "Notisbehörighet saknas – inga väderaviseringar är schemalagda")
                : "Aviseringar avstängda i Regnvakt", forKey: scheduleStatusKey)
            return
        }

        var requestsByID: [String: UNNotificationRequest] = [:]
        var candidates: [WeatherNotificationCandidate] = []
        var freshForecastCount = 0
        var staleForecastCount = 0
        var staleLocationIDs = Set<String>()
        for stored in registry.values.sorted(by: { $0.locationID < $1.locationID }) {
            guard isCurrentBatch() else { return }
            let age = Date().timeIntervalSince(stored.savedAt)
            let fresh = age >= 0 && age <= 2 * 60 * 60
            if fresh { freshForecastCount += 1 } else {
                staleForecastCount += 1
                staleLocationIDs.insert(stored.locationID)
            }
            let liveTemperature = allowImmediateCurrentFrost &&
                stored.locationID == immediateFrostLocationID && fresh ? stored.currentTemperature : nil
            let requests = makeRequests(
                place: stored.place,
                hours: fresh ? stored.hours : [],
                currentTemperature: liveTemperature,
                defaults: defaults,
                locationID: stored.locationID
            )
            for request in requests {
                requestsByID[request.identifier] = request
            }
            candidates.append(contentsOf: makeCandidates(
                requests: requests,
                locationID: stored.locationID,
                pendingIdentifiers: Set(pendingIDs)
            ))
        }

        // Existing pending current-frost alerts are preserved even if the
        // refreshed forecast no longer emits a current-frost event.
        // For an older stored forecast, retain only previously scheduled requests
        // with explicit snapshot metadata and a still-future event/trigger.
        let enabledWatchTypes = Set(["rain", "snow", "wind", "thunder", "frost", "ice"].filter {
            defaults.object(forKey: "Regnvakt.notifications.\($0)") as? Bool ?? true
        })
        let stalePendingAlerts = pending.compactMap { request -> PendingForecastAlert? in
            let info = request.content.userInfo
            guard let locationID = registry.values.first(where: {
                request.identifier.hasPrefix(prefix + $0.locationID.replacingOccurrences(of: ",", with: "_") + ".")
            })?.locationID,
            staleLocationIDs.contains(locationID),
            (info["immediate"] as? Bool) != true,
            let watch = info["watch"] as? String,
            let generatedAt = info["forecastSnapshotAt"] as? Date,
            let eventTimestamp = info["forecastEventDate"] as? TimeInterval,
            let nextFireDate = request.trigger?.nextTriggerDate() else { return nil }
            return PendingForecastAlert(
                identifier: request.identifier, locationID: locationID, watch: watch,
                generatedAt: generatedAt, eventDate: Date(timeIntervalSince1970: eventTimestamp),
                fireDate: nextFireDate
            )
        }
        let preservedStaleForecastIDs = WeatherNotificationBudget.preservablePendingForecastIdentifiers(
            alerts: stalePendingAlerts,
            registeredLocationIDs: Set(registry.values.map(\\.locationID)),
            enabledWatchTypes: enabledWatchTypes,
            now: Date()
        )
        let preservedPendingIDs = preservedFrostIDs.union(preservedStaleForecastIDs)
        let availableCapacity = WeatherNotificationBudget.availableForecastCapacity(pendingIdentifiers: pendingIDs)
        let candidateIdentifiers = Set(candidates.map(\\.identifier))
        let selectionCapacity = WeatherNotificationBudget.selectionCapacity(
            availableCapacity: availableCapacity,
            preservedPendingIdentifiers: preservedPendingIDs,
            candidateIdentifiers: candidateIdentifiers
        )
        let selectedIDs = WeatherNotificationBudget.select(
            candidates: candidates,
            capacity: selectionCapacity,
            deliveredIdentifiers: deliveredIDs
        )
        let plan = WeatherNotificationReconciliationPlan.make(
            selectedIdentifiers: selectedIDs,
            pendingIdentifiers: pendingIDs,
            deliveredIdentifiers: deliveredIDs,
            preservedPendingIdentifiers: preservedPendingIDs,
            forecastPrefix: prefix
        )

        guard isCurrentBatch() else { return }
        center.removePendingNotificationRequests(withIdentifiers: plan.pendingIdentifiersToRemove)

        var schedulingFailureCount = 0
        var firstSchedulingError: String?
        for identifier in plan.identifiersToAdd {
            guard isCurrentBatch(), let request = requestsByID[identifier] else { return }
            do {
                try await center.add(request)
            } catch {
                guard isCurrentBatch() else { return }
                schedulingFailureCount += 1
                if firstSchedulingError == nil {
                    firstSchedulingError = error.localizedDescription
                }
            }
            guard isCurrentBatch() else { return }
        }

        let finalPending = await center.pendingNotificationRequests()
        guard isCurrentBatch() else { return }
        let finalCount = finalPending.filter { $0.identifier.hasPrefix(prefix) }.count
        defaults.set(finalCount, forKey: scheduledCountKey)
        defaults.set(Date().timeIntervalSince1970, forKey: scheduleUpdatedKey)
        let outcome: String
        if schedulingFailureCount > 0 {
            let detail = firstSchedulingError.map { ": \($0)" } ?? ""
            outcome = "\(schedulingFailureCount) väderavisering(ar) kunde inte schemaläggas\(detail)"
        } else if finalCount == 0 {
            outcome = "Inga kommande vädernotiser schemalagda"
        } else {
            outcome = "\(finalCount) väderavisering(ar) schemalagda i iPhone"
        }
        let diagnostics = "\(registry.count) bevakade platser • \(freshForecastCount) färska prognoser • \(staleForecastCount) för gamla prognoser • \(candidates.count) riskhändelser • \(selectedIDs.count) valda"
        defaults.set("\(outcome) • \(diagnostics)", forKey: scheduleStatusKey)
    }

    static func removeAll() {
        // This scheduler owns only Regnvakt forecast notifications. SMHI cleanup
        // must remain explicit in SMHIWarningService / the notification settings.
        // Capture a generation so delayed callbacks cannot erase requests created
        // by a newer refresh after this full cleanup was superseded.
        let defaults = UserDefaults.standard
        let cleanupToken = UUID().uuidString
        defaults.set(cleanupToken, forKey: globalScheduleTokenKey)
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            guard defaults.string(forKey: globalScheduleTokenKey) == cleanupToken else { return }
            let ids = WeatherNotificationBudget.forecastIdentifiers(in: requests.map(\.identifier), forecastPrefix: prefix)
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
        center.getDeliveredNotifications { notifications in
            guard defaults.string(forKey: globalScheduleTokenKey) == cleanupToken else { return }
            let ids = WeatherNotificationBudget.forecastIdentifiers(in: notifications.map { $0.request.identifier }, forecastPrefix: prefix)
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    static func removeNotifications(latitude: Double, longitude: Double) {
        let rawLocationID = String(format: "%.4f,%.4f", latitude, longitude)
        let locationID = rawLocationID.replacingOccurrences(of: ",", with: "_")
        let defaults = UserDefaults.standard

        // Commit the registry removal and invalidate every batch that may still
        // contain this location before any notification-center await occurs.
        defaults.set(UUID().uuidString, forKey: scheduleTokenKey + "." + locationID)
        if let data = defaults.data(forKey: forecastRegistryKey),
           var registry = try? JSONDecoder().decode([String: StoredForecast].self, from: data) {
            registry.removeValue(forKey: rawLocationID)
            if let updated = try? JSONEncoder().encode(registry) {
                defaults.set(updated, forKey: forecastRegistryKey)
            }
        }
        let removalToken = UUID().uuidString
        defaults.set(removalToken, forKey: globalScheduleTokenKey)

        let center = UNUserNotificationCenter.current()
        Task {
            // Finish cleanup before starting the replacement global batch. This
            // avoids an old callback deleting a newly scheduled request that
            // reuses the same stable identifier after a rapid re-add.
            let pending = await center.pendingNotificationRequests()
            guard defaults.string(forKey: globalScheduleTokenKey) == removalToken else { return }
            let pendingIDs = WeatherNotificationBudget.forecastIdentifiers(
                for: rawLocationID,
                in: pending.map(\.identifier),
                forecastPrefix: prefix
            )
            center.removePendingNotificationRequests(withIdentifiers: pendingIDs)

            let delivered = await center.deliveredNotifications()
            // Delivered alerts from a removed location are stale even if another
            // location starts a newer global batch while this cleanup is running.
            // Clear them independently; never let a stale cleanup touch pending
            // requests after its generation token has been superseded.
            let deliveredIDs = WeatherNotificationBudget.forecastIdentifiers(
                for: rawLocationID,
                in: delivered.map { $0.request.identifier },
                forecastPrefix: prefix
            )
            center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)

            guard defaults.string(forKey: globalScheduleTokenKey) == removalToken else { return }
            refreshFromStoredForecast()
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
        let frostDayKey = currentFrostAlertDayKey + "." + locationID.replacingOccurrences(of: ",", with: "_")
        guard defaults.string(forKey: tokenKey) == token,
              (defaults.string(forKey: globalScheduleTokenKey) ?? "initial") == globalToken else { return }
        let globallyEnabled = defaults.object(forKey: "Regnvakt.notifications.enabled") as? Bool ?? true
        guard globallyEnabled else {
            
            let pending = await center.pendingNotificationRequests()
            guard defaults.string(forKey: tokenKey) == token,
                  (defaults.string(forKey: globalScheduleTokenKey) ?? "initial") == globalToken else { return }
            let staleIDs = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: staleIDs)
            // SMHI owns its notification namespace; the master settings handler
            // performs explicit SMHI cleanup when the user disables all alerts.
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


        let requests = makeRequests(
            place: place,
            hours: hours,
            currentTemperature: currentTemperature,
            defaults: defaults,
            locationID: locationID
        )

        // Read the notification center once for this scheduling pass. The
        // global reconciler will later lift this same snapshot/selection flow
        // across all registered locations.
        let pending = await center.pendingNotificationRequests()
        guard defaults.string(forKey: tokenKey) == token,
              (defaults.string(forKey: globalScheduleTokenKey) ?? "initial") == globalToken else { return }
        let delivered = await center.deliveredNotifications()
        guard defaults.string(forKey: tokenKey) == token,
              (defaults.string(forKey: globalScheduleTokenKey) ?? "initial") == globalToken else { return }

        // Temporary per-place capacity remains until the global reconciler is
        // integrated, but candidate ranking now uses the shared pure selector.
        let registryCount: Int
        if let data = defaults.data(forKey: forecastRegistryKey),
           let registry = try? JSONDecoder().decode([String: StoredForecast].self, from: data) {
            registryCount = registry.count
        } else {
            registryCount = 1
        }
        let perPlaceLimit = WeatherNotificationBudget.interimPerPlaceLimit(registryCount: registryCount)
        let pendingIdentifiers = Set(pending.map(\.identifier))
        let deliveredIdentifiers = Set(delivered.map { $0.request.identifier })
        let candidates = makeCandidates(
            requests: requests,
            locationID: locationID,
            pendingIdentifiers: pendingIdentifiers
        )
        let selectedIdentifiers = WeatherNotificationBudget.select(
            candidates: candidates,
            capacity: perPlaceLimit,
            deliveredIdentifiers: deliveredIdentifiers
        )
        let requestsByIdentifier = Dictionary(requests.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        let selected = selectedIdentifiers.compactMap { requestsByIdentifier[$0] }

        let locationPrefix = prefix + locationID.replacingOccurrences(of: ",", with: "_") + "."
        // Recover a current-frost alert delivered since the previous refresh,
        // even if the live temperature has warmed and makeEvents no longer
        // emits an immediate event. This prevents a second forecast-frost
        // notification for the same Swedish calendar day.
        let deliveredCurrentFrostDays = delivered.compactMap { notification -> Date? in
            let request = notification.request
            guard request.identifier.hasPrefix(locationPrefix),
                  request.identifier.contains(".frost.current."),
                  (request.content.userInfo["immediate"] as? Bool) == true else { return nil }
            return request.content.userInfo["alertDay"] as? Date
        }
        if let latestDeliveredCurrentFrostDay = deliveredCurrentFrostDays.max() {
            defaults.set(latestDeliveredCurrentFrostDay, forKey: frostDayKey)
        }

        // Keep a current-frost request pending until iOS confirms delivery.
        // A fresh forecast must not cancel an immediate safety alert already queued.
        let preserveCurrentFrost = defaults.object(forKey: "Regnvakt.notifications.frost") as? Bool ?? true

        // Replace pending requests for this location even when their stable
        // identifier is unchanged. Forecast refreshes can revise the event's
        // fire time, probability and wording while retaining the same local hour.
        // Keep a current-frost request armed when no fresh current temperature
        // is available; it must not be silently cancelled by a partial refresh.
        let preservedPendingIDs = Set(pending.map(\.identifier).filter {
            $0.hasPrefix(locationPrefix) && preserveCurrentFrost && $0.contains(".frost.current.")
        })
        let pendingIDsToReplace = pending.map(\.identifier).filter {
            $0.hasPrefix(locationPrefix) && !preservedPendingIDs.contains($0)
        }
        center.removePendingNotificationRequests(withIdentifiers: pendingIDsToReplace)

        // Delivered identifiers are retained as daily/event deduplication.
        // Pending identifiers are deliberately not included: those were just
        // replaced above and should be re-added with the latest forecast data.
        let deliveredIDs = Set(delivered.map { $0.request.identifier })
        for request in selected {
            guard defaults.string(forKey: tokenKey) == token,
              (defaults.string(forKey: globalScheduleTokenKey) ?? "initial") == globalToken else { return }
            let isImmediate = (request.content.userInfo["immediate"] as? Bool) ?? false
            if deliveredIDs.contains(request.identifier) {
                // Deduplicate only after iOS has actually delivered the alert.
                if isImmediate, let alertDay = request.content.userInfo["alertDay"] as? Date {
                    defaults.set(alertDay, forKey: frostDayKey)
                }
                continue
            }
            if preservedPendingIDs.contains(request.identifier) {
                // Keep the original near-immediate trigger and stable identifier.
                continue
            }
            do {
                try await center.add(request)
                guard defaults.string(forKey: tokenKey) == token,
                      (defaults.string(forKey: globalScheduleTokenKey) ?? "initial") == globalToken else {
                    center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
                    return
                }
                // Enqueueing is not delivery. The daily marker is set only
                // when this identifier appears in deliveredNotifications().
            } catch {
                // A failed add from an obsolete per-location task must not
                // overwrite status written by a newer refresh/reconciliation.
                guard defaults.string(forKey: tokenKey) == token,
                      (defaults.string(forKey: globalScheduleTokenKey) ?? "initial") == globalToken else { return }
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

    /// Converts one stored forecast into stable notification requests.
    /// Kept separate from scheduling so the global reconciler can build one
    /// candidate pool across every monitored location.
    private static func makeRequests(
        place: String,
        hours: [HourForecast],
        currentTemperature: Int?,
        defaults: UserDefaults,
        locationID: String
    ) -> [UNNotificationRequest] {
        let frostDayKey = currentFrostAlertDayKey + "." + locationID.replacingOccurrences(of: ",", with: "_")
        let events = makeEvents(hours: hours, currentTemperature: currentTemperature, defaults: defaults, frostDayKey: frostDayKey)
        let lead = defaults.object(forKey: "Regnvakt.notifications.leadMinutes") == nil
            ? 30 : max(0, defaults.integer(forKey: "Regnvakt.notifications.leadMinutes"))
        let quietSetting = defaults.string(forKey: "Regnvakt.notifications.quietHours") ?? "22–07"

        var requests: [UNNotificationRequest] = []
        for event in events {
            let now = Date()
            let plannedFireDate = event.immediate
                ? now.addingTimeInterval(2)
                : event.date.addingTimeInterval(-Double(lead) * 60)
            // Safety-critical frost/ice events must not disappear merely because
            // their lead-time trigger has already passed when a fresh forecast arrives.
            let deliverImmediately = WeatherNotificationBudget.shouldDeliverImmediately(
                alreadyImmediate: event.immediate,
                safetyCritical: event.safetyCritical,
                eventDate: event.date,
                leadMinutes: lead,
                now: now
            )
            let fireDate = deliverImmediately ? now.addingTimeInterval(2) : plannedFireDate
            guard deliverImmediately || fireDate > now.addingTimeInterval(30) else { continue }
            // Frost and ice alerts are safety-critical and intentionally bypass quiet hours.
            guard event.safetyCritical || !WeatherWatchRules.isQuietTime(fireDate, setting: quietSetting) else { continue }

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
            content.userInfo = ["watch": event.type, "place": place, "safetyCritical": event.safetyCritical, "immediate": deliverImmediately, "alertDay": swedishCalendar.startOfDay(for: event.date), "forecastEventDate": event.date.timeIntervalSince1970, "forecastSnapshotAt": now, "leadMinutes": lead]
            var components = swedishCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            components.timeZone = swedishTimeZone
            let trigger: UNNotificationTrigger
            if deliverImmediately {
                trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
            } else {
                trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            }
            let stamp: String
            if deliverImmediately {
                let day = DateFormatter()
                day.calendar = swedishCalendar
                day.timeZone = swedishTimeZone
                day.dateFormat = "yyyyMMdd"
                stamp = day.string(from: swedishCalendar.startOfDay(for: event.date))
            } else if event.type == "frost" {
                // Stable local-day identity: refreshed hourly forecasts must
                // update one frost warning, never create a new alert per hour.
                let day = DateFormatter()
                day.calendar = swedishCalendar
                day.timeZone = swedishTimeZone
                day.dateFormat = "yyyyMMdd"
                stamp = day.string(from: swedishCalendar.startOfDay(for: event.date))
            } else {
                // Forecast feeds can revise the exact timestamp by a few
                // seconds/minutes while still describing the same displayed
                // local-hour event. Key the notification by Swedish local hour
                // so a refresh replaces that event instead of delivering a copy.
                // Include UTC offset so the two real instances of the autumn repeated hour remain distinct.
                stamp = WeatherWatchRules.forecastHourIdentifier(for: event.date)
            }
            let locationToken = locationID.replacingOccurrences(of: ",", with: "_")
            let identifier = prefix + locationToken + "." + event.type + (deliverImmediately ? ".current." : ".") + stamp
            requests.append(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
        return requests
    }

    /// Converts generated requests into pure metadata for global selection.
    /// Pending current-frost requests are marked so the selector can preserve
    /// their original near-immediate trigger rather than recreating them.
    private static func makeCandidates(
        requests: [UNNotificationRequest],
        locationID: String,
        pendingIdentifiers: Set<String>
    ) -> [WeatherNotificationCandidate] {
        requests.map { request in
            let userInfo = request.content.userInfo
            let isImmediate = (userInfo["immediate"] as? Bool) ?? false
            let isFrost = (userInfo["watch"] as? String) == "frost"
            let isImmediateFrost = isImmediate && isFrost
            let fireDate: Date
            if let calendarTrigger = request.trigger as? UNCalendarNotificationTrigger,
               let nextDate = calendarTrigger.nextTriggerDate() {
                fireDate = nextDate
            } else if let intervalTrigger = request.trigger as? UNTimeIntervalNotificationTrigger {
                fireDate = Date().addingTimeInterval(intervalTrigger.timeInterval)
            } else {
                fireDate = Date().addingTimeInterval(2)
            }
            let isPreserved = isImmediateFrost && pendingIdentifiers.contains(request.identifier)
            return WeatherNotificationBudget.makeCandidate(
                identifier: request.identifier,
                locationID: locationID,
                fireDate: fireDate,
                isImmediateFrost: isImmediateFrost,
                isSafetyCritical: (userInfo["safetyCritical"] as? Bool) ?? false,
                isPreservedPendingCurrentFrost: isPreserved
            )
        }
    }

    private static func makeEvents(hours: [HourForecast], currentTemperature: Int?, defaults: UserDefaults, frostDayKey: String) -> [Event] {
        var result: [Event] = []
        var emittedTypes = Set<String>()
        var forecastFrostDays = Set<Date>()
        var lastWetForecastDate: Date?

        // Current frost is a separate, immediate safety alert. It is deduplicated
        // by a stable daily identifier and remains armed across forecast refreshes.
        let now = Date()
        let swedishCalendar = Self.swedishCalendar
        let orderedHours = hours.compactMap { hour -> (HourForecast, Date)? in
            guard let date = hour.date else { return nil }
            return (hour, date)
        }.sorted { $0.1 < $1.1 }
        // Only schedule forecast-driven alerts inside the configured notification horizon.
        // The current-temperature frost check above remains immediate and separate.
        let forecastHorizon = WeatherWatchRules.notificationForecastHorizon(from: now)
        let currentHour = swedishCalendar.component(.hour, from: now)
        let currentFrost = (defaults.object(forKey: "Regnvakt.notifications.frost") as? Bool ?? true)
            && (currentTemperature.map { FrostRiskRules.isFrostRisk(temperature: $0, localHour: currentHour) } ?? false)
        let lastCurrentFrostAlertDay = defaults.object(forKey: frostDayKey) as? Date
        let alreadyAlertedForCurrentFrostToday = lastCurrentFrostAlertDay.map {
            swedishCalendar.isDate($0, inSameDayAs: now)
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
                // Forecast temperatures are whole degrees. A 1°C buffer is used
                // overnight; during daytime, require freezing temperature.
                if FrostRiskRules.isFrostRisk(temperature: hour.temperature, localHour: localHour) {
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

            // Emit the first *schedulable* alert per risk type. Previously the
            // first matching hour claimed the type before lead-time and quiet-hour
            // filtering in makeRequests. If that first trigger was already in the
            // past, every later hour of the same rain/wind/snow episode was lost.
            // Evaluate the same scheduling gates here before consuming the type.
            let leadMinutes = defaults.object(forKey: "Regnvakt.notifications.leadMinutes") == nil
                ? 30 : max(0, defaults.integer(forKey: "Regnvakt.notifications.leadMinutes"))
            let quietSetting = defaults.string(forKey: "Regnvakt.notifications.quietHours") ?? "22–07"
            for event in active where !emittedTypes.contains(event.type) {
                guard WeatherWatchRules.canScheduleForecastEvent(
                    eventDate: event.date,
                    safetyCritical: event.safetyCritical,
                    leadMinutes: leadMinutes,
                    now: now,
                    quietHours: quietSetting
                ) else { continue }
                emittedTypes.insert(event.type)
                result.append(event)
            }

            if wetNow {
                lastWetForecastDate = date
            }
        }
        return result
    }

}
