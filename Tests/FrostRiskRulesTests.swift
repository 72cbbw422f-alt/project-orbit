import XCTest

final class FrostRiskRulesTests: XCTestCase {
    func testOvernightThresholdIncludesOneDegree() {
        XCTAssertEqual(FrostRiskRules.temperatureThreshold(forLocalHour: 18), 1)
        XCTAssertEqual(FrostRiskRules.temperatureThreshold(forLocalHour: 23), 1)
        XCTAssertEqual(FrostRiskRules.temperatureThreshold(forLocalHour: 0), 1)
        XCTAssertEqual(FrostRiskRules.temperatureThreshold(forLocalHour: 8), 1)
    }

    func testDaytimeThresholdRequiresZeroOrBelow() {
        XCTAssertEqual(FrostRiskRules.temperatureThreshold(forLocalHour: 9), 0)
        XCTAssertEqual(FrostRiskRules.temperatureThreshold(forLocalHour: 12), 0)
        XCTAssertEqual(FrostRiskRules.temperatureThreshold(forLocalHour: 17), 0)
    }

    func testFrostRiskBoundaryAcrossDayAndNight() {
        XCTAssertTrue(FrostRiskRules.isFrostRisk(temperature: 1, localHour: 22))
        XCTAssertFalse(FrostRiskRules.isFrostRisk(temperature: 2, localHour: 22))
        XCTAssertTrue(FrostRiskRules.isFrostRisk(temperature: 0, localHour: 12))
        XCTAssertFalse(FrostRiskRules.isFrostRisk(temperature: 1, localHour: 12))
        XCTAssertTrue(FrostRiskRules.isFrostRisk(temperature: -5, localHour: 12))
    }

    func testIceRiskRequiresMoistureOrFreezingPrecipitation() {
        XCTAssertTrue(FrostRiskRules.isWetNearFreeze(temperature: 1, hasRecentWetWeather: true, freezingPrecipitation: false))
        XCTAssertTrue(FrostRiskRules.isWetNearFreeze(temperature: 0, hasRecentWetWeather: false, freezingPrecipitation: true))
        XCTAssertFalse(FrostRiskRules.isWetNearFreeze(temperature: 1, hasRecentWetWeather: false, freezingPrecipitation: false))
        XCTAssertFalse(FrostRiskRules.isWetNearFreeze(temperature: 2, hasRecentWetWeather: true, freezingPrecipitation: true))
    }
}

final class WeatherWatchRulesTests: XCTestCase {
    private func stockholmDate(_ iso8601: String) -> Date {
        ISO8601DateFormatter().date(from: iso8601)!
    }

    func testForecastAndNotificationHorizonsAreEightHours() {
        let start = stockholmDate("2026-11-20T12:00:00+01:00")
        XCTAssertEqual(WeatherWatchRules.forecastHorizon(from: start).timeIntervalSince(start), 8 * 60 * 60)
        XCTAssertEqual(WeatherWatchRules.notificationForecastHorizon(from: start).timeIntervalSince(start), 8 * 60 * 60)
    }

    func testDefaultQuietHoursCrossMidnightInStockholmTime() {
        XCTAssertFalse(WeatherWatchRules.isQuietTime(stockholmDate("2026-11-20T21:59:00+01:00"), setting: "22–07"))
        XCTAssertTrue(WeatherWatchRules.isQuietTime(stockholmDate("2026-11-20T22:00:00+01:00"), setting: "22–07"))
        XCTAssertTrue(WeatherWatchRules.isQuietTime(stockholmDate("2026-11-21T06:59:00+01:00"), setting: "22–07"))
        XCTAssertFalse(WeatherWatchRules.isQuietTime(stockholmDate("2026-11-21T07:00:00+01:00"), setting: "22–07"))
    }

    func testQuietHoursCanBeDisabledAndMalformedSettingsFailOpen() {
        let date = stockholmDate("2026-11-20T23:00:00+01:00")
        XCTAssertFalse(WeatherWatchRules.isQuietTime(date, setting: "none"))
        XCTAssertFalse(WeatherWatchRules.isQuietTime(date, setting: "22-07"))
        XCTAssertFalse(WeatherWatchRules.isQuietTime(date, setting: "22–22"))
        XCTAssertFalse(WeatherWatchRules.isQuietTime(date, setting: "24–07"))
    }

    func testAlternateQuietHoursUseTheirOwnBoundaries() {
        XCTAssertFalse(WeatherWatchRules.isQuietTime(stockholmDate("2026-11-20T22:59:00+01:00"), setting: "23–06"))
        XCTAssertTrue(WeatherWatchRules.isQuietTime(stockholmDate("2026-11-20T23:00:00+01:00"), setting: "23–06"))
        XCTAssertTrue(WeatherWatchRules.isQuietTime(stockholmDate("2026-11-21T05:59:00+01:00"), setting: "23–06"))
        XCTAssertFalse(WeatherWatchRules.isQuietTime(stockholmDate("2026-11-21T06:00:00+01:00"), setting: "23–06"))
    }

    func testQuietHoursRemainCorrectAcrossSwedishDaylightSavingTime() {
        // Sweden moves from CET to CEST on 2026-03-29; local quiet hours
        // must remain 22:00–07:00 despite the skipped 02:00 hour.
        XCTAssertTrue(WeatherWatchRules.isQuietTime(stockholmDate("2026-03-29T01:59:00+01:00"), setting: "22–07"))
        XCTAssertTrue(WeatherWatchRules.isQuietTime(stockholmDate("2026-03-29T03:00:00+02:00"), setting: "22–07"))
        XCTAssertTrue(WeatherWatchRules.isQuietTime(stockholmDate("2026-03-29T06:59:00+02:00"), setting: "22–07"))
        XCTAssertFalse(WeatherWatchRules.isQuietTime(stockholmDate("2026-03-29T07:00:00+02:00"), setting: "22–07"))
    }
}
