import Foundation

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
