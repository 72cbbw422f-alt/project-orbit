import Foundation

struct WeatherSnapshot {
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

    static let demo = WeatherSnapshot(
        place: "Din plats",
        condition: "Regn och kylig vind",
        temperature: 3,
        feelsLike: 0,
        wind: 3.0,
        windGust: 5.6,
        windDirectionDegrees: 315,
        windDirectionText: "NV",
        humidity: 98,
        uvIndex: 0,
        precipitationToday: 6.9
    )
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

struct DayForecast: Identifiable {
    let id = UUID()
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
