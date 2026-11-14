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
    private let savedPlacesKey = "Regnvakt.savedPlaces.v1"
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

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: savedPlacesKey),
           let places = try? JSONDecoder().decode([SavedWeatherPlace].self, from: data) {
            savedPlaces = places
        }
        if let data = UserDefaults.standard.data(forKey: cachedForecastKey),
           let cached = try? JSONDecoder().decode(CachedForecast.self, from: data) {
            snapshot = cached.snapshot
            days = cached.days
            hours = cached.hours
            lastUpdated = cached.savedAt
            status = "Senast visade prognos • uppdaterar…"
        }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 1500
        requestLocation()
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
        savePlace(place)
        lastFetch = nil
        status = "Hämtar prognos för \(place.name)…"
        loadWeather(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude, placeName: place.name)
    }

    func selectSavedPlace(_ place: SavedWeatherPlace) {
        lastFetch = nil
        loadWeather(latitude: place.latitude, longitude: place.longitude, placeName: place.name)
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

    func removePlace(_ place: SavedWeatherPlace) {
        savedPlaces.removeAll { $0.id == place.id }
        if !savedPlaces.contains(where: \.isFavorite), let first = savedPlaces.first,
           let index = savedPlaces.firstIndex(where: { $0.id == first.id }) {
            savedPlaces[index].isFavorite = true
        }
        persistSavedPlaces()
    }

    private func persistSavedPlaces() {
        if let data = try? JSONEncoder().encode(savedPlaces) {
            UserDefaults.standard.set(data, forKey: savedPlacesKey)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            requestLocation()
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            status = "Platsåtkomst avstängd – sök efter ort eller stad"
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = "Kunde inte hämta position – sök efter ort eller stad."
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        if let lastFetch, Date().timeIntervalSince(lastFetch) < 300 { return }
        lastFetch = Date()
        currentCoordinate = location.coordinate
        status = "Hämtar prognos för din position…"
        Task {
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
            loadWeather(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, placeName: placeName)
        }
    }

    private func loadWeather(latitude: Double, longitude: Double, placeName: String) {
        currentCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        status = "Hämtar prognos för \(placeName)…"
        Task {
            do {
                let result = try await OpenMeteoService.fetch(latitude: latitude, longitude: longitude)
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
                WeatherNotificationScheduler.refresh(place: placeName, hours: result.hours)
                Task { await SMHIWarningService.checkAndNotify(at: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) }
                status = "Liveprognos • Open-Meteo"
            } catch {
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
            URLQueryItem(name: "wind_speed_unit", value: "ms")
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let current = root["current"] as? [String: Any],
              let daily = root["daily"] as? [String: Any],
              let hourly = root["hourly"] as? [String: Any],
              let dates = daily["time"] as? [String],
              let hourlyTimes = hourly["time"] as? [String] else { throw URLError(.cannotParseResponse) }
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
        let sunrises = daily["sunrise"] as? [String] ?? []
        let sunsets = daily["sunset"] as? [String] ?? []
        let hourlyTemps = hourly["temperature_2m"] as? [NSNumber] ?? []
        let hourlyChances = hourly["precipitation_probability"] as? [NSNumber] ?? []
        let hourlyAmounts = hourly["precipitation"] as? [NSNumber] ?? []
        let hourlyCodes = hourly["weather_code"] as? [NSNumber] ?? []
        let hourlyWinds = hourly["wind_speed_10m"] as? [NSNumber] ?? []
        let hourlyGusts = hourly["wind_gusts_10m"] as? [NSNumber] ?? []
        let apiTimeZone = TimeZone(identifier: root["timezone"] as? String ?? "") ?? .current
        let hourFormatter = DateFormatter()
        hourFormatter.locale = Locale(identifier: "en_US_POSIX")
        hourFormatter.timeZone = apiTimeZone
        hourFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let displayHour = DateFormatter()
        displayHour.locale = Locale(identifier: "sv_SE")
        displayHour.timeZone = apiTimeZone
        displayHour.dateFormat = "HH"
        let now = Date()
        let currentHour = Calendar.current.date(bySetting: .minute, value: 0, of: now) ?? now
        let startIndex = hourlyTimes.firstIndex { (hourFormatter.date(from: $0) ?? .distantPast) >= currentHour } ?? 0
        let hours: [HourForecast] = hourlyTimes.indices
            .filter { $0 >= startIndex && $0 < startIndex + 168 }
            .compactMap { i in
                guard i < hourlyTemps.count, i < hourlyCodes.count else { return nil }
                let code = hourlyCodes[i].intValue
                let date = hourFormatter.date(from: hourlyTimes[i])
                let label = i == startIndex ? "Nu" : date.map { displayHour.string(from: $0) } ?? "--"
                return HourForecast(
                    id: hourlyTimes[i], time: label, symbol: weatherSymbol(code),
                    condition: conditionText(code),
                    precipitationChance: i < hourlyChances.count ? hourlyChances[i].intValue : 0,
                    temperature: hourlyTemps[i].intValue,
                    precipitation: i < hourlyAmounts.count ? hourlyAmounts[i].doubleValue : 0,
                    wind: i < hourlyWinds.count ? hourlyWinds[i].doubleValue : 0,
                    gust: i < hourlyGusts.count ? hourlyGusts[i].doubleValue : 0)
            }
        let direction = number(current, "wind_direction_10m")
        let localDateFormatter = DateFormatter()
        localDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        localDateFormatter.timeZone = apiTimeZone
        localDateFormatter.dateFormat = "yyyy-MM-dd"
        let todayKey = localDateFormatter.string(from: Date())
        guard let todayIndex = dates.firstIndex(of: todayKey) else { throw URLError(.cannotParseResponse) }
        func clockTime(_ values: [String], _ index: Int) -> String {
            guard values.indices.contains(index) else { return "—:—" }
            return String(values[index].suffix(5))
        }
        func daylight(_ index: Int) -> Int {
            guard sunrises.indices.contains(index), sunsets.indices.contains(index),
                  let rise = hourFormatter.date(from: sunrises[index]),
                  let set = hourFormatter.date(from: sunsets[index]) else { return 0 }
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
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = apiTimeZone
        let weekday = DateFormatter()
        weekday.locale = Locale(identifier: "sv_SE")
        weekday.dateFormat = "EEEE"
        let days = dates.indices.filter { dates[$0] >= todayKey }.map { i -> DayForecast in
            let date = dateFormatter.date(from: dates[i]) ?? Date()
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
