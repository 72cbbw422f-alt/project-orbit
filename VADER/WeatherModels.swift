import Foundation

/// Shared thresholds used by the watch dashboard and notification engine.
enum WeatherWatchRules {
    static let forecastHorizonHours: TimeInterval = 8
    static let notificationHorizonHours: TimeInterval = 8
    static let windGustThreshold = 15.0

    static func forecastHorizon(from date: Date) -> Date {
        date.addingTimeInterval(forecastHorizonHours * 60 * 60)
    }

    static func notificationForecastHorizon(from date: Date) -> Date {
        date.addingTimeInterval(notificationHorizonHours * 60 * 60)
    }
}

/// Shared frost and ice thresholds used by both the watch UI and notification scheduler.
/// Forecast temperatures are supplied as whole degrees by the current forecast model.
enum FrostRiskRules {
    static func temperatureThreshold(forLocalHour hour: Int) -> Int {
        (hour >= 18 || hour < 9) ? 1 : 0
    }

    static func isFrostRisk(temperature: Int, localHour: Int) -> Bool {
        temperature <= temperatureThreshold(forLocalHour: localHour)
    }

    static func isWetNearFreeze(
        temperature: Int,
        hasRecentWetWeather: Bool,
        freezingPrecipitation: Bool
    ) -> Bool {
        temperature <= 1 && (hasRecentWetWeather || freezingPrecipitation)
    }
}


struct WeatherRiskAssessment {
    let rain: Bool
    let snow: Bool
    let thunder: Bool
    let wind: Bool
    let frost: Bool
    let wetNearFreeze: Bool
    let wetNearFreezeHour: HourForecast?
    let forecastFrostHour: HourForecast?
    let hasForecastData: Bool
    let hasOfficialWarning: Bool
    let hasRedOfficialWarning: Bool

    var anyRisk: Bool {
        rain || snow || thunder || wind || frost || hasOfficialWarning
    }

    var isRed: Bool { hasRedOfficialWarning }

    static func evaluate(
        weather: WeatherSnapshot,
        hours: [HourForecast],
        smhiActive: Bool,
        smhiLevel: String,
        now: Date = Date()
    ) -> WeatherRiskAssessment {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let horizon = WeatherWatchRules.forecastHorizon(from: now)
        let upcoming = hours.compactMap { hour -> (HourForecast, Date)? in
            guard let date = formatter.date(from: hour.id), date >= now, date <= horizon else { return nil }
            return (hour, date)
        }.sorted { $0.1 < $1.1 }.map { $0.0 }

        let rain = upcoming.contains { hour in
            let condition = hour.condition.lowercased()
            let isRain = condition.contains("regn") || condition.contains("duggregn") || condition.contains("skur")
            return isRain && (hour.precipitationChance >= 40 || hour.precipitation >= 0.3)
        }
        let snow = upcoming.contains {
            $0.condition.localizedCaseInsensitiveContains("snö")
                && ($0.precipitationChance >= 40 || $0.precipitation >= 0.2)
        }
        let thunder = upcoming.contains { $0.condition.localizedCaseInsensitiveContains("åska") }
        let maxGust = max(weather.windGust, upcoming.map(\.gust).max() ?? 0)
        let maxWind = max(weather.wind, upcoming.map(\.wind).max() ?? 0)
        let wind = maxGust >= WeatherWatchRules.windGustThreshold || maxWind >= 11

        var swedishCalendar = Calendar(identifier: .gregorian)
        swedishCalendar.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
        let currentHour = swedishCalendar.component(.hour, from: now)
        let currentFrost = FrostRiskRules.isFrostRisk(temperature: weather.temperature, localHour: currentHour)
        let forecastFrost = upcoming.contains { hour in
            guard let date = formatter.date(from: hour.id) else { return false }
            let localHour = swedishCalendar.component(.hour, from: date)
            return FrostRiskRules.isFrostRisk(temperature: hour.temperature, localHour: localHour)
        }
        let timedUpcoming = upcoming.compactMap { hour -> (HourForecast, Date)? in
            guard let date = formatter.date(from: hour.id) else { return nil }
            return (hour, date)
        }
        let wetNearFreezeHour = timedUpcoming.first { candidate in
            let (hour, date) = candidate
            guard hour.temperature <= 1 else { return false }
            let condition = hour.condition.lowercased()
            let wetCondition = condition.contains("regn") || condition.contains("dugg") ||
                condition.contains("skur") || condition.contains("snö") || condition.contains("underkylt")
            let wetNow = hour.precipitation >= 0.2 || (hour.precipitationChance >= 50 && wetCondition)
            let recentWet = timedUpcoming.contains { previous, previousDate in
                let elapsed = date.timeIntervalSince(previousDate)
                guard elapsed > 0, elapsed <= 3 * 60 * 60 else { return false }
                let previousCondition = previous.condition.lowercased()
                let previousWetCondition = previousCondition.contains("regn") || previousCondition.contains("dugg") ||
                    previousCondition.contains("skur") || previousCondition.contains("snö") ||
                    previousCondition.contains("underkylt")
                return previous.precipitation >= 0.2 ||
                    (previous.precipitationChance >= 50 && previousWetCondition)
            }
            return FrostRiskRules.isWetNearFreeze(
                temperature: hour.temperature,
                hasRecentWetWeather: wetNow || recentWet,
                freezingPrecipitation: condition.contains("underkylt")
            )
        }?.0

        let level = smhiLevel.lowercased()
        let redWarning = smhiActive && (level.contains("röd") || level.contains("red"))
        return WeatherRiskAssessment(
            rain: rain,
            snow: snow,
            thunder: thunder,
            wind: wind,
            frost: currentFrost || forecastFrost || wetNearFreezeHour != nil,
            wetNearFreeze: wetNearFreezeHour != nil,
            wetNearFreezeHour: wetNearFreezeHour,
            forecastFrostHour: upcoming.first { hour in
                guard let date = formatter.date(from: hour.id) else { return false }
                let localHour = swedishCalendar.component(.hour, from: date)
                return FrostRiskRules.isFrostRisk(temperature: hour.temperature, localHour: localHour)
            },
            hasForecastData: !upcoming.isEmpty,
            hasOfficialWarning: smhiActive,
            hasRedOfficialWarning: redWarning
        )
    }
}

struct WeatherSnapshot: Codable {
    let place: String
    let condition: String
    let temperature: Int
    let feelsLike: Int
    let wind: Double
    let windGust: Double
    let windDirectionDegrees: Double
    let windDirectionText: String
    let humidity: Int
    let uvIndex: Int
    let precipitationToday: Double
    var pressure: Double = 0
    var cloudCover: Int = 0
    var dewPoint: Double = 0
    var visibilityKm: Double = 0
    var sunriseTime: String = "—:—"
    var sunsetTime: String = "—:—"
    var daylightMinutes: Int = 0
    var daylightChangeMinutes: Int = 0


}

struct HourForecast: Identifiable, Codable {
    let id: String
    let time: String
    let symbol: String
    let condition: String
    let precipitationChance: Int
    let temperature: Int
    let precipitation: Double
    let wind: Double
    let gust: Double
}

struct DayForecast: Identifiable, Codable {
    var id: Date { date }
    let date: Date
    let day: String
    let symbol: String
    let condition: String
    let precipitationChance: Int
    let precipitation: Double
    let low: Int
    let high: Int
    let wind: Double
    let gust: Double
    let uv: Double
}

enum WeatherTab: String, CaseIterable, Identifiable {
    case weather = "Väder"
    case radar = "Radar"
    case watch = "Vakter"
    case places = "Platser"
    case more = "Mer"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .weather: return "cloud.sun.fill"
        case .radar: return "dot.radiowaves.left.and.right"
        case .watch: return "bell.badge.fill"
        case .places: return "map.fill"
        case .more: return "slider.horizontal.3"
        }
    }
}
