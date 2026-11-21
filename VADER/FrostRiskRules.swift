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
