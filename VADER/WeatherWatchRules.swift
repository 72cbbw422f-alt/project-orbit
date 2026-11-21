import Foundation

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

    static func isQuietTime(_ date: Date, setting: String) -> Bool {
        guard setting != "none" else { return false }
        let parts = setting.split(separator: "–").compactMap { Int($0) }
        guard parts.count == 2,
              (0...23).contains(parts[0]),
              (0...23).contains(parts[1]),
              parts[0] != parts[1] else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
        let hour = calendar.component(.hour, from: date)
        let start = parts[0], end = parts[1]
        return start < end ? (hour >= start && hour < end) : (hour >= start || hour < end)
    }
}