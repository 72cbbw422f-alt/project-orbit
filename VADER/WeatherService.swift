import Foundation
import CoreLocation
import Combine

struct PlaceSearchResult: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
}

struct SavedWeatherPlace: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var isFavorite: Bool
}

@MainActor
final class WeatherViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var snapshot: WeatherSnapshot?
    @Published var lastUpdated: Date?
    @Published var currentCoordinate: CLLocationCoordinate2D?
    @Published var days: [DayForecast] = []
    @Published var hours: [HourForecast] = []
    @Published var status = "Väntar på platsåtkomst…"
    @Published var placeSearchResults: [PlaceSearchResult] = []
    @Published var placeSearchStatus = ""
    @Published var isSearchingPlaces = false
    @Published private(set) var savedPlaces: [SavedWeatherPlace] = []
    @Published private(set) var monitoredPlaceIDs: Set<UUID> = []
    private let savedPlacesKey = "Regnvakt.savedPlaces.v1"
    private let monitoredPlacesKey = "Regnvakt.monitoredPlaces.v1"
    private let cachedForecastKey = "Regnvakt.cachedForecast.v1"

    private struct CachedForecast: Codable {
        let snapshot: WeatherSnapshot
        let days: [DayForecast]
        let hours: [HourForecast]
        let savedAt: Date
    }
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var lastFetch: Date?
    private var weatherRequestID = UUID()
    // A manually selected or notification-targeted place must not be replaced
    // by the delayed startup GPS callback. Explicit refresh re-enables GPS.
    private var prefersExplicitPlaceSelection = false
    // Invalidates forecast fetches started by an older monitoring toggle.
    private var monitoringRequestIDs: [UUID: UUID] = [:]

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: savedPlacesKey),
           let places = try? JSONDecoder().decode([SavedWeatherPlace].self, from: data) {
            savedPlaces = places
        }
        if let ids = UserDefaults.standard.array(forKey: monitoredPlacesKey) as? [String] {
            monitoredPlaceIDs = Set(ids.compactMap(UUID.init(uuidString:)))
        }
        if let data = UserDefaults.standard.data(forKey: cachedForecastKey),
           let cached = try? JSONDecoder().decode(CachedForecast.self, from: data) {
            snapshot = cached.snapshot
            days = cached.days
            hours = cached.hours
            lastUpdated = cached.savedAt
            status = "Senast visade prognos • uppdaterar…"
        }
        WeatherNotificationScheduler.clearLegacyWeatherNotificationsOnce()
        // Reconcile persisted notification schedules at launch. This removes
        // alerts backed by cached forecasts that have aged beyond the freshness
        // window, even when the app starts offline and cannot fetch new data.
        WeatherNotificationScheduler.refreshFromStoredForecast()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 1500
        requestLocation()
    }

    /// Opportunistic background refresh for explicitly monitored places.
    /// iOS controls when this runs; it is not guaranteed after a user force-quits the app.
    static func refreshMonitoredForecastsInBackground() async -> Bool {
        let defaults = UserDefaults.standard
        let startedAt = Date()
        let diagnosticPrefix = "Regnvakt.backgroundRefresh."
        func saveDiagnostic(_ key: String, _ value: Any) {
            defaults.set(value, forKey: diagnosticPrefix + key)
        }

        guard let placesData = defaults.data(forKey: "Regnvakt.savedPlaces.v1"),
              let places = try? JSONDecoder().decode([SavedWeatherPlace].self, from: placesData),
              let storedIDs = defaults.array(forKey: "Regnvakt.monitoredPlaces.v1") as? [String] else {
            saveDiagnostic("placeCount", 0)
            saveDiagnostic("successCount", 0)
            saveDiagnostic("failureCount", 0)
            saveDiagnostic("skippedCount", 0)
            saveDiagnostic("diagnostic", "Inga sparade bevakningsdata kunde läsas")
            return false
        }
        let monitoredIDs = Set(storedIDs.compactMap(UUID.init(uuidString:)))
        let monitoredPlaces = places.filter { monitoredIDs.contains($0.id) }
        guard !monitoredPlaces.isEmpty else {
            saveDiagnostic("placeCount", 0)
            saveDiagnostic("successCount", 0)
            saveDiagnostic("failureCount", 0)
            saveDiagnostic("skippedCount", 0)
            saveDiagnostic("diagnostic", "Inga aktiva vädervakter")
            return false
        }

        // This background task is dedicated to ordinary forecast watches.
        // SMHI detection is intentionally excluded: its network/geometry work
        // must not consume the limited BGAppRefresh window needed by Open-Meteo.
        // SMHI remains on its existing foreground flow until server push is approved.
        var refreshedCount = 0
        var failedCount = 0
        var skippedCount = 0
        var lastFailure = ""

        for place in monitoredPlaces {
            guard !Task.isCancelled else {
                skippedCount += 1
                break
            }
            do {
                let forecast = try await OpenMeteoService.fetch(
                    latitude: place.latitude,
                    longitude: place.longitude
                )
                // An iOS expiration can cancel this task while URLSession is
                // suspended. Never schedule from a response that arrived after
                // the background execution budget was revoked.
                guard !Task.isCancelled else {
                    skippedCount += 1
                    break
                }

                // Re-read both persisted collections after suspension: a place
                // may have been disabled, removed, or edited while fetching.
                let latestIDs = Set(
                    (defaults.array(forKey: "Regnvakt.monitoredPlaces.v1") as? [String] ?? [])
                        .compactMap(UUID.init(uuidString:))
                )
                let latestPlaces = (try? JSONDecoder().decode(
                    [SavedWeatherPlace].self,
                    from: defaults.data(forKey: "Regnvakt.savedPlaces.v1") ?? Data()
                )) ?? []
                guard latestIDs.contains(place.id),
                      let latestPlace = latestPlaces.first(where: { $0.id == place.id }),
                      abs(latestPlace.latitude - place.latitude) < 0.000001,
                      abs(latestPlace.longitude - place.longitude) < 0.000001 else {
                    skippedCount += 1
                    continue
                }
                WeatherNotificationScheduler.refresh(
                    place: place.name,
                    latitude: place.latitude,
                    longitude: place.longitude,
                    hours: forecast.hours,
                    currentTemperature: forecast.current.temperature
                )
                refreshedCount += 1
            } catch {
                failedCount += 1
                // Store only the error type and numeric code, never a URL,
                // coordinates, or place name.
                let nsError = error as NSError
                lastFailure = "\(nsError.domain) (kod \(nsError.code))"
            }
        }

        saveDiagnostic("placeCount", monitoredPlaces.count)
        saveDiagnostic("successCount", refreshedCount)
        saveDiagnostic("failureCount", failedCount)
        saveDiagnostic("skippedCount", skippedCount)
        saveDiagnostic("diagnostic", lastFailure.isEmpty ? "Inga hämtfel registrerade" : "Senaste hämtfel: \(lastFailure)")
        saveDiagnostic("durationSeconds", Date().timeIntervalSince(startedAt))
        if refreshedCount > 0 {
            saveDiagnostic("lastSuccessAt", Date().timeIntervalSince1970)
        }
        return refreshedCount > 0 && !Task.isCancelled
    }

    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            status = "Tillåt platsåtkomst eller sök efter en ort"
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            status = "Hämtar din position…"
            manager.requestLocation()
        case .denied, .restricted:
            status = "Platsåtkomst avstängd – sök efter ort eller stad"
        @unknown default:
            status = "Kan inte läsa platsåtkomst"
        }
    }

    func refresh() {
        prefersExplicitPlaceSelection = false
        lastFetch = nil
        requestLocation()
    }

    func searchPlaces(_ query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            placeSearchResults = []
            placeSearchStatus = "Skriv en ort eller stad."
            return
        }
        isSearchingPlaces = true
        placeSearchStatus = "Söker…"
        Task {
            do {
                let placemarks = try await geocoder.geocodeAddressString(query, in: nil, preferredLocale: Locale(identifier: "sv_SE"))
                placeSearchResults = placemarks.compactMap { placemark in
                    guard let location = placemark.location else { return nil }
                    let name = [placemark.locality, placemark.subAdministrativeArea, placemark.administrativeArea]
                        .compactMap { $0 }.reduce(into: [String]()) { parts, part in
                            if !parts.contains(part) { parts.append(part) }
                        }.prefix(2).joined(separator: ", ")
                    return PlaceSearchResult(name: name.isEmpty ? (placemark.name ?? query) : name,
                                              coordinate: location.coordinate)
                }
                placeSearchStatus = placeSearchResults.isEmpty ? "Hittade ingen ort. Prova ett annat namn." : "Välj plats för att hämta väder."
            } catch {
                placeSearchResults = []
                placeSearchStatus = "Sökningen misslyckades. Kontrollera anslutningen och försök igen."
            }
            isSearchingPlaces = false
        }
    }

    func selectPlace(_ place: PlaceSearchResult) {
        prefersExplicitPlaceSelection = true
        savePlace(place)
        lastFetch = nil
        status = "Hämtar prognos för \(place.name)…"
        loadWeather(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude, placeName: place.name)
    }

    func selectSavedPlace(_ place: SavedWeatherPlace) {
        prefersExplicitPlaceSelection = true
        lastFetch = nil
        loadWeather(latitude: place.latitude, longitude: place.longitude, placeName: place.name)
    }

    func openWeatherPlaceFromNotification(locationID: String, placeName: String) {
        let coordinates = locationID.split(separator: ",")
        guard coordinates.count == 2,
              let latitude = Double(coordinates[0]),
              let longitude = Double(coordinates[1]),
              (-90.0...90.0).contains(latitude),
              (-180.0...180.0).contains(longitude) else { return }

        prefersExplicitPlaceSelection = true
        lastFetch = nil
        loadWeather(latitude: latitude, longitude: longitude, placeName: placeName)
    }

    func savePlace(_ place: PlaceSearchResult) {
        let latitude = place.coordinate.latitude
        let longitude = place.coordinate.longitude
        if let index = savedPlaces.firstIndex(where: {
            abs($0.latitude - latitude) < 0.015 && abs($0.longitude - longitude) < 0.015
        }) {
            savedPlaces[index].name = place.name
        } else {
            savedPlaces.append(SavedWeatherPlace(id: UUID(), name: place.name,
                latitude: latitude, longitude: longitude, isFavorite: savedPlaces.isEmpty))
        }
        persistSavedPlaces()
    }

    func toggleFavorite(_ place: SavedWeatherPlace) {
        guard let index = savedPlaces.firstIndex(where: { $0.id == place.id }) else { return }
        let makeFavorite = !savedPlaces[index].isFavorite
        if makeFavorite {
            for i in savedPlaces.indices { savedPlaces[i].isFavorite = false }
        }
        savedPlaces[index].isFavorite = makeFavorite
        persistSavedPlaces()
    }

    func isMonitored(_ place: SavedWeatherPlace) -> Bool {
        monitoredPlaceIDs.contains(place.id)
    }

    func setMonitoring(_ place: SavedWeatherPlace, enabled: Bool) {
        // Every toggle supersedes any fetch started by the previous state.
        let requestID = UUID()
        monitoringRequestIDs[place.id] = requestID

        if enabled {
            monitoredPlaceIDs.insert(place.id)
            persistMonitoredPlaces()
            refreshSMHIWarnings()
            Task {
                do {
                    let forecast = try await OpenMeteoService.fetch(latitude: place.latitude, longitude: place.longitude)
                    guard monitoringRequestIDs[place.id] == requestID,
                          monitoredPlaceIDs.contains(place.id),
                          let activePlace = savedPlaces.first(where: { $0.id == place.id }),
                          abs(activePlace.latitude - place.latitude) < 0.000001,
                          abs(activePlace.longitude - place.longitude) < 0.000001 else { return }

                    WeatherNotificationScheduler.refresh(
                        place: activePlace.name,
                        latitude: activePlace.latitude,
                        longitude: activePlace.longitude,
                        hours: forecast.hours,
                        currentTemperature: forecast.current.temperature
                    )
                    // refresh(place:) reconciles the complete monitored registry.
                } catch {
                    guard monitoringRequestIDs[place.id] == requestID,
                          monitoredPlaceIDs.contains(place.id),
                          savedPlaces.contains(where: { $0.id == place.id }) else { return }
                    status = "Kunde inte uppdatera bevakningen för \(place.name)."
                }
            }
        } else {
            monitoredPlaceIDs.remove(place.id)
            persistMonitoredPlaces()
            WeatherNotificationScheduler.removeNotifications(latitude: place.latitude, longitude: place.longitude)
            refreshSMHIWarnings()
        }
    }

    private func persistMonitoredPlaces() {
        UserDefaults.standard.set(monitoredPlaceIDs.map(\.uuidString), forKey: monitoredPlacesKey)
    }

    func removePlace(_ place: SavedWeatherPlace) {
        monitoringRequestIDs[place.id] = UUID()
        monitoredPlaceIDs.remove(place.id)
        persistMonitoredPlaces()
        WeatherNotificationScheduler.removeNotifications(latitude: place.latitude, longitude: place.longitude)
        savedPlaces.removeAll { $0.id == place.id }
        if !savedPlaces.contains(where: \.isFavorite), let first = savedPlaces.first,
           let index = savedPlaces.firstIndex(where: { $0.id == first.id }) {
            savedPlaces[index].isFavorite = true
        }
        persistSavedPlaces()
        // Notification cleanup triggers one global reconciliation after the
        // removed location's pending and delivered requests have been cleared.
        refreshSMHIWarnings()
    }

    private func persistSavedPlaces() {
        if let data = try? JSONEncoder().encode(savedPlaces) {
            UserDefaults.standard.set(data, forKey: savedPlacesKey)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let isAuthorized = status == .authorizedAlways || status == .authorizedWhenInUse
        let isDenied = status == .denied || status == .restricted
        Task { @MainActor [weak self] in
            guard let self else { return }
            if isAuthorized {
                requestLocation()
            } else if isDenied {
                self.status = "Platsåtkomst avstängd – sök efter ort eller stad"
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.status = message.isEmpty
                ? "Kunde inte hämta position – sök efter ort eller stad."
                : "Kunde inte hämta position – sök efter ort eller stad. (\(message))"
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        Task { @MainActor [weak self] in
            guard let self, !self.prefersExplicitPlaceSelection else { return }
            if let lastFetch, Date().timeIntervalSince(lastFetch) < 300 { return }
            lastFetch = Date()
            // Claim the request before reverse geocoding. Otherwise a slow
            // location lookup can finish after a manual place selection and
            // unexpectedly replace the user's chosen town with GPS weather.
            let locationRequestID = UUID()
            weatherRequestID = locationRequestID
            status = "Hämtar prognos för din position…"
            let location = CLLocation(latitude: latitude, longitude: longitude)
            let placeName: String
            do {
                let marks = try await geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "sv_SE"))
                if let mark = marks.first {
                    placeName = [mark.locality, mark.subAdministrativeArea, mark.administrativeArea]
                        .compactMap { $0 }
                        .reduce(into: [String]()) { parts, part in
                            if !parts.contains(part) { parts.append(part) }
                        }.prefix(2).joined(separator: ", ")
                } else {
                    placeName = "Min position"
                }
            } catch {
                placeName = "Min position"
            }
            guard weatherRequestID == locationRequestID else { return }
            currentCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            loadWeather(latitude: latitude, longitude: longitude, placeName: placeName)
        }
    }

    func refreshSMHIWarnings() {
        // Check the currently selected place plus every explicitly monitored
        // saved place. This keeps SMHI coverage nationwide rather than tying
        // alerts only to the phone's current GPS position.
        var coordinates: [CLLocationCoordinate2D] = []
        if let currentCoordinate { coordinates.append(currentCoordinate) }
        let monitoredPlaces = savedPlaces.filter { monitoredPlaceIDs.contains($0.id) }
        for place in monitoredPlaces {
            let coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
            let isDuplicate = coordinates.contains {
                abs($0.latitude - coordinate.latitude) < 0.015 &&
                abs($0.longitude - coordinate.longitude) < 0.015
            }
            if !isDuplicate { coordinates.append(coordinate) }
        }
        guard !coordinates.isEmpty else {
            // Invalidate an older network response before clearing its notifications.
            // Otherwise a request for the previous location snapshot could still
            // finish later and overwrite the empty-location status.
            _ = SMHIWarningService.beginCheck()
            UserDefaults.standard.set(false, forKey: "Regnvakt.smhi.active")
            UserDefaults.standard.set("Välj en plats för att visa lokala SMHI-varningar", forKey: "Regnvakt.smhi.summary")
            UserDefaults.standard.set("", forKey: "Regnvakt.smhi.level")
            SMHIWarningService.clearPendingNotifications()
            return
        }
        let checkGeneration = SMHIWarningService.beginCheck()
        Task {
            await SMHIWarningService.checkAndNotify(at: coordinates, generation: checkGeneration)
        }
    }

    private func loadWeather(latitude: Double, longitude: Double, placeName: String) {
        weatherRequestID = UUID()
        let requestID = weatherRequestID
        currentCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        // Check official warnings independently from the forecast request so a
        // failed Open-Meteo response can never prevent an SMHI warning check.
        refreshSMHIWarnings()
        status = "Hämtar prognos för \(placeName)…"
        Task {
            do {
                let result = try await OpenMeteoService.fetch(latitude: latitude, longitude: longitude)
                guard requestID == weatherRequestID else { return }
                let updatedSnapshot = result.current.replacingPlace(placeName)
                let updateTime = Date()
                // Persist the last complete forecast so launch never starts in demo mode
                // and then visibly replaces the entire home screen when live data arrives.
                let cached = CachedForecast(snapshot: updatedSnapshot, days: result.days, hours: result.hours, savedAt: updateTime)
                if let data = try? JSONEncoder().encode(cached) {
                    UserDefaults.standard.set(data, forKey: cachedForecastKey)
                }
                snapshot = updatedSnapshot
                lastUpdated = updateTime
                days = result.days
                hours = result.hours
                let selectedPlace = savedPlaces.first {
                    abs($0.latitude - latitude) < 0.015 && abs($0.longitude - longitude) < 0.015
                }
                if let selectedPlace, monitoredPlaceIDs.contains(selectedPlace.id) {
                    // A GPS fix can drift slightly between refreshes. Use the
                    // saved place's stable coordinates for notification identity
                    // so one monitored town cannot accumulate several location IDs.
                    WeatherNotificationScheduler.refresh(
                        place: selectedPlace.name,
                        latitude: selectedPlace.latitude,
                        longitude: selectedPlace.longitude,
                        hours: result.hours,
                        currentTemperature: updatedSnapshot.temperature
                    )
                }

                // Only explicitly enabled places receive notifications.
                let otherPlaces = savedPlaces.filter {
                    monitoredPlaceIDs.contains($0.id) &&
                    (abs($0.latitude - latitude) > 0.015 || abs($0.longitude - longitude) > 0.015)
                }
                // Every place the user explicitly enabled must receive a fresh
                // forecast and notification schedule; there is no UI limit of five.
                for savedPlace in otherPlaces {
                    do {
                        let placeForecast = try await OpenMeteoService.fetch(
                            latitude: savedPlace.latitude,
                            longitude: savedPlace.longitude
                        )
                        // The user may disable or remove this watch while the
                        // network request is suspended. Never restore its forecast
                        // registry from an obsolete snapshot of otherPlaces.
                        guard requestID == weatherRequestID,
                              monitoredPlaceIDs.contains(savedPlace.id),
                              let activePlace = savedPlaces.first(where: { $0.id == savedPlace.id }),
                              abs(activePlace.latitude - savedPlace.latitude) < 0.000001,
                              abs(activePlace.longitude - savedPlace.longitude) < 0.000001 else {
                            continue
                        }
                        WeatherNotificationScheduler.refresh(
                            place: activePlace.name,
                            latitude: activePlace.latitude,
                            longitude: activePlace.longitude,
                            hours: placeForecast.hours,
                            currentTemperature: placeForecast.current.temperature
                        )
                    } catch {
                        // Keep the last valid schedule for this place if a refresh fails.
                    }
                }

                status = "Liveprognos • Open-Meteo"
            } catch {
                guard requestID == weatherRequestID else { return }
                status = "Kunde inte hämta väderdata. Försök igen."
            }
        }
    }
}

private enum OpenMeteoService {
    static func fetch(latitude: Double, longitude: Double) async throws -> (current: WeatherSnapshot, days: [DayForecast], hours: [HourForecast]) {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m,pressure_msl,cloud_cover,dew_point_2m,visibility"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,precipitation,weather_code,wind_speed_10m,wind_gusts_10m"),
            URLQueryItem(name: "forecast_hours", value: "48"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,wind_speed_10m_max,wind_gusts_10m_max,uv_index_max,sunrise,sunset"),
            URLQueryItem(name: "past_days", value: "1"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "wind_speed_unit", value: "ms")
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let current = root["current"] as? [String: Any],
              let daily = root["daily"] as? [String: Any],
              let hourly = root["hourly"] as? [String: Any],
              let dailyTimestamps = daily["time"] as? [NSNumber],
              let hourlyTimestamps = hourly["time"] as? [NSNumber],
              let utcOffset = root["utc_offset_seconds"] as? NSNumber else { throw URLError(.cannotParseResponse) }
        // Required values must be present and finite. A missing API field is
        // unknown weather, never a safe zero (especially for wind and temperature).
        let requiredCurrentKeys = [
            "temperature_2m", "relative_humidity_2m", "apparent_temperature",
            "precipitation", "weather_code", "wind_speed_10m",
            "wind_direction_10m", "wind_gusts_10m", "pressure_msl",
            "cloud_cover", "dew_point_2m", "visibility"
        ]
        guard requiredCurrentKeys.allSatisfy({ key in
            guard let value = current[key] as? NSNumber else { return false }
            return value.doubleValue.isFinite
        }) else { throw URLError(.cannotParseResponse) }

        func number(_ dict: [String: Any], _ key: String) -> Double {
            (dict[key] as? NSNumber)?.doubleValue ?? 0
        }
        let lows = daily["temperature_2m_min"] as? [NSNumber] ?? []
        let highs = daily["temperature_2m_max"] as? [NSNumber] ?? []
        let codes = daily["weather_code"] as? [NSNumber] ?? []
        let chances = daily["precipitation_probability_max"] as? [NSNumber] ?? []
        let amounts = daily["precipitation_sum"] as? [NSNumber] ?? []
        let winds = daily["wind_speed_10m_max"] as? [NSNumber] ?? []
        let gusts = daily["wind_gusts_10m_max"] as? [NSNumber] ?? []
        let uv = daily["uv_index_max"] as? [NSNumber] ?? []
        let sunrises = daily["sunrise"] as? [NSNumber] ?? []
        let sunsets = daily["sunset"] as? [NSNumber] ?? []
        let dailyNumericArrays = [lows, highs, codes, chances, amounts, winds, gusts, uv]
        guard !dailyTimestamps.isEmpty,
              dailyNumericArrays.allSatisfy({ $0.count >= dailyTimestamps.count }),
              sunrises.count >= dailyTimestamps.count,
              sunsets.count >= dailyTimestamps.count,
              dailyTimestamps.allSatisfy({ $0.doubleValue.isFinite }),
              sunrises.prefix(dailyTimestamps.count).allSatisfy({ $0.doubleValue.isFinite }),
              sunsets.prefix(dailyTimestamps.count).allSatisfy({ $0.doubleValue.isFinite }),
              dailyNumericArrays.allSatisfy({ values in values.prefix(dailyTimestamps.count).allSatisfy { $0.doubleValue.isFinite } }) else {
            throw URLError(.cannotParseResponse)
        }
        let hourlyTemps = hourly["temperature_2m"] as? [NSNumber] ?? []
        let hourlyChances = hourly["precipitation_probability"] as? [NSNumber] ?? []
        let hourlyAmounts = hourly["precipitation"] as? [NSNumber] ?? []
        let hourlyCodes = hourly["weather_code"] as? [NSNumber] ?? []
        let hourlyWinds = hourly["wind_speed_10m"] as? [NSNumber] ?? []
        let hourlyGusts = hourly["wind_gusts_10m"] as? [NSNumber] ?? []

        // Risk evaluation depends on every hourly field. Reject an incomplete
        // forecast rather than silently replacing missing precipitation/wind
        // values with zero and reporting false "no risk".
        let hourlyArrays = [hourlyTemps, hourlyChances, hourlyAmounts, hourlyCodes, hourlyWinds, hourlyGusts]
        guard !hourlyTimestamps.isEmpty,
              hourlyArrays.allSatisfy({ $0.count >= hourlyTimestamps.count }),
              hourlyTimestamps.allSatisfy({ $0.doubleValue.isFinite && $0.doubleValue > 0 }),
              hourlyArrays.allSatisfy({ values in values.prefix(hourlyTimestamps.count).allSatisfy { $0.doubleValue.isFinite } }) else {
            throw URLError(.cannotParseResponse)
        }
        let apiTimeZone = TimeZone(identifier: root["timezone"] as? String ?? "") ?? .current
        let dailyDateFormatter = DateFormatter()
        dailyDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dailyDateFormatter.timeZone = apiTimeZone
        dailyDateFormatter.dateFormat = "yyyy-MM-dd"
        let localDates = dailyTimestamps.map {
            dailyDateFormatter.string(from: Date(timeIntervalSince1970: $0.doubleValue + utcOffset.doubleValue))
        }
        let hourlyDates = hourlyTimestamps.map { Date(timeIntervalSince1970: $0.doubleValue) }
        let displayHour = DateFormatter()
        displayHour.locale = Locale(identifier: "sv_SE")
        displayHour.timeZone = apiTimeZone
        displayHour.dateFormat = "HH"
        let now = Date()
        // Start at the first actual future hourly timestamp. Using the start
        // of the current clock hour can label a timestamp already in the past as "Nu".
        // Never fall back to index zero when the API returns only past hours.
        guard let startIndex = hourlyDates.firstIndex(where: { $0 >= now }) else {
            throw URLError(.cannotParseResponse)
        }
        let hours: [HourForecast] = hourlyTimestamps.indices
            .filter { $0 >= startIndex && $0 < startIndex + 168 }
            .compactMap { i in
                guard i < hourlyTemps.count, i < hourlyCodes.count else { return nil }
                let code = hourlyCodes[i].intValue
                let date = hourlyDates[i]
                let label = i == startIndex ? "Nu" : displayHour.string(from: date)
                return HourForecast(
                    id: "@\(Int64(hourlyTimestamps[i].doubleValue.rounded()))", time: label, symbol: weatherSymbol(code),
                    condition: conditionText(code),
                    precipitationChance: i < hourlyChances.count ? hourlyChances[i].intValue : 0,
                    temperature: hourlyTemps[i].intValue,
                    precipitation: i < hourlyAmounts.count ? hourlyAmounts[i].doubleValue : 0,
                    wind: i < hourlyWinds.count ? hourlyWinds[i].doubleValue : 0,
                    gust: i < hourlyGusts.count ? hourlyGusts[i].doubleValue : 0)
            }
        let direction = number(current, "wind_direction_10m")
        let todayKey = dailyDateFormatter.string(from: Date())
        guard let todayIndex = localDates.firstIndex(of: todayKey) else { throw URLError(.cannotParseResponse) }
        let clockFormatter = DateFormatter()
        clockFormatter.locale = Locale(identifier: "sv_SE")
        clockFormatter.timeZone = apiTimeZone
        clockFormatter.dateFormat = "HH:mm"
        func clockTime(_ values: [NSNumber], _ index: Int) -> String {
            guard values.indices.contains(index) else { return "—:—" }
            return clockFormatter.string(from: Date(timeIntervalSince1970: values[index].doubleValue))
        }
        func daylight(_ index: Int) -> Int {
            guard sunrises.indices.contains(index), sunsets.indices.contains(index) else { return 0 }
            let rise = Date(timeIntervalSince1970: sunrises[index].doubleValue)
            let set = Date(timeIntervalSince1970: sunsets[index].doubleValue)
            return max(0, Int(set.timeIntervalSince(rise) / 60))
        }
        let todayDaylight = daylight(todayIndex)
        let yesterdayDaylight = daylight(max(0, todayIndex - 1))
        let snapshot = WeatherSnapshot(
            place: "Din position", condition: conditionText(Int(number(current, "weather_code"))),
            temperature: Int(number(current, "temperature_2m").rounded()),
            feelsLike: Int(number(current, "apparent_temperature").rounded()),
            wind: number(current, "wind_speed_10m"), windGust: number(current, "wind_gusts_10m"),
            windDirectionDegrees: direction, windDirectionText: compassDirection(direction),
            humidity: Int(number(current, "relative_humidity_2m")),
            uvIndex: Int(todayIndex < uv.count ? uv[todayIndex].doubleValue : 0),
            precipitationToday: number(current, "precipitation"),
            pressure: number(current, "pressure_msl"),
            cloudCover: Int(number(current, "cloud_cover")),
            dewPoint: number(current, "dew_point_2m"),
            visibilityKm: number(current, "visibility") / 1000,
            sunriseTime: clockTime(sunrises, todayIndex),
            sunsetTime: clockTime(sunsets, todayIndex),
            daylightMinutes: todayDaylight,
            daylightChangeMinutes: todayDaylight - yesterdayDaylight)
        let weekday = DateFormatter()
        weekday.locale = Locale(identifier: "sv_SE")
        weekday.dateFormat = "EEEE"
        let days = localDates.indices.filter { localDates[$0] >= todayKey }.map { i -> DayForecast in
            let date = dailyDateFormatter.date(from: localDates[i]) ?? Date(timeIntervalSince1970: dailyTimestamps[i].doubleValue + utcOffset.doubleValue)
            let code = i < codes.count ? codes[i].intValue : 0
            return DayForecast(date: date, day: i == todayIndex ? "Idag" : weekday.string(from: date).capitalized,
                symbol: weatherSymbol(code), condition: conditionText(code),
                precipitationChance: i < chances.count ? chances[i].intValue : 0,
                precipitation: i < amounts.count ? amounts[i].doubleValue : 0,
                low: i < lows.count ? lows[i].intValue : 0,
                high: i < highs.count ? highs[i].intValue : 0,
                wind: i < winds.count ? winds[i].doubleValue : 0,
                gust: i < gusts.count ? gusts[i].doubleValue : 0,
                uv: i < uv.count ? uv[i].doubleValue : 0)
        }
        return (snapshot, days, hours)
    }

    private static func compassDirection(_ degrees: Double) -> String {
        ["N","NÖ","Ö","SÖ","S","SV","V","NV"][Int((degrees / 45).rounded()) % 8]
    }
    private static func conditionText(_ code: Int) -> String {
        switch code {
        case 0: return "Klart"
        case 1: return "Mestadels klart"
        case 2: return "Växlande molnighet"
        case 3: return "Mulet"
        case 45, 48: return "Dimma"
        case 51, 53, 55: return "Duggregn"
        case 56, 57: return "Underkylt duggregn"
        case 61, 63, 65: return "Regn"
        case 66, 67: return "Underkylt regn"
        case 71, 73, 75, 77: return "Snöfall"
        case 80, 81, 82: return "Regnskurar"
        case 85, 86: return "Snöbyar"
        case 95, 96, 99: return "Åska"
        default: return "Varierande väder"
        }
    }
    private static func weatherSymbol(_ code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...67: return "cloud.drizzle.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 80...82: return "cloud.rain.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

private extension WeatherSnapshot {
    func replacingPlace(_ name: String) -> WeatherSnapshot {
        WeatherSnapshot(place: name, condition: condition, temperature: temperature, feelsLike: feelsLike,
            wind: wind, windGust: windGust, windDirectionDegrees: windDirectionDegrees,
            windDirectionText: windDirectionText, humidity: humidity, uvIndex: uvIndex,
            precipitationToday: precipitationToday, pressure: pressure,
            cloudCover: cloudCover, dewPoint: dewPoint, visibilityKm: visibilityKm,
            sunriseTime: sunriseTime, sunsetTime: sunsetTime,
            daylightMinutes: daylightMinutes, daylightChangeMinutes: daylightChangeMinutes)
    }
}
