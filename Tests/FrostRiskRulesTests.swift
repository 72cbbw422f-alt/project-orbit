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

    func testRoutineForecastMustRetainConfiguredLeadTime() {
        let now = stockholmDate("2026-11-20T12:00:00+01:00")
        let leadEvent = now.addingTimeInterval(60 * 60)

        XCTAssertTrue(WeatherWatchRules.canScheduleForecastEvent(
            eventDate: leadEvent, safetyCritical: false, leadMinutes: 30,
            now: now, quietHours: "none"
        ))
        XCTAssertFalse(WeatherWatchRules.canScheduleForecastEvent(
            eventDate: now.addingTimeInterval(20 * 60), safetyCritical: false,
            leadMinutes: 30, now: now, quietHours: "none"
        ))
    }

    func testSafetyCriticalEventCanBecomeImmediateWhenLeadTimeHasPassed() {
        let now = stockholmDate("2026-11-20T12:00:00+01:00")
        let overdueEvent = now.addingTimeInterval(10 * 60)

        XCTAssertTrue(WeatherWatchRules.canScheduleForecastEvent(
            eventDate: overdueEvent, safetyCritical: true, leadMinutes: 30,
            now: now, quietHours: "22–07"
        ))
        XCTAssertFalse(WeatherWatchRules.canScheduleForecastEvent(
            eventDate: overdueEvent, safetyCritical: false, leadMinutes: 30,
            now: now, quietHours: "22–07"
        ))
    }

    func testSafetyCriticalImmediateAlertBypassesQuietHoursButRoutineDoesNot() {
        let now = stockholmDate("2026-11-20T21:30:00+01:00")
        let event = now.addingTimeInterval(60 * 60)

        XCTAssertFalse(WeatherWatchRules.canScheduleForecastEvent(
            eventDate: event, safetyCritical: false, leadMinutes: 30,
            now: now, quietHours: "22–07"
        ))
        XCTAssertTrue(WeatherWatchRules.canScheduleForecastEvent(
            eventDate: event, safetyCritical: true, leadMinutes: 30,
            now: now, quietHours: "22–07"
        ))
    }

    func testLeadTimeBoundaryUsesThirtySecondSafetyMargin() {
        let now = stockholmDate("2026-11-20T12:00:00+01:00")

        XCTAssertFalse(WeatherWatchRules.canScheduleForecastEvent(
            eventDate: now.addingTimeInterval(30 * 60 + 30),
            safetyCritical: false, leadMinutes: 30, now: now, quietHours: "none"
        ))
        XCTAssertTrue(WeatherWatchRules.canScheduleForecastEvent(
            eventDate: now.addingTimeInterval(30 * 60 + 31),
            safetyCritical: false, leadMinutes: 30, now: now, quietHours: "none"
        ))
    }


    func testQuietHoursRemainCorrectAcrossSwedishAutumnClockChange() {
        // On 2026-10-25, 02:30 occurs twice: once in CEST and once in CET.
        XCTAssertTrue(WeatherWatchRules.isQuietTime(
            stockholmDate("2026-10-25T02:30:00+02:00"), setting: "22–07"
        ))
        XCTAssertTrue(WeatherWatchRules.isQuietTime(
            stockholmDate("2026-10-25T02:30:00+01:00"), setting: "22–07"
        ))
        XCTAssertFalse(WeatherWatchRules.isQuietTime(
            stockholmDate("2026-10-25T07:00:00+01:00"), setting: "22–07"
        ))
    }

    func testForecastHourIdentifierDistinguishesRepeatedAutumnHour() {
        let summerOffsetOccurrence = stockholmDate("2026-10-25T02:30:00+02:00")
        let winterOffsetOccurrence = stockholmDate("2026-10-25T02:30:00+01:00")

        XCTAssertNotEqual(
            WeatherWatchRules.forecastHourIdentifier(for: summerOffsetOccurrence),
            WeatherWatchRules.forecastHourIdentifier(for: winterOffsetOccurrence)
        )
        XCTAssertEqual(
            WeatherWatchRules.forecastHourIdentifier(for: stockholmDate("2026-11-20T12:00:00+01:00")),
            WeatherWatchRules.forecastHourIdentifier(for: stockholmDate("2026-11-20T12:00:00+01:00"))
        )
    }

    func testNegativeLeadTimeIsClampedToZero() {
        let now = stockholmDate("2026-11-20T12:00:00+01:00")
        XCTAssertFalse(WeatherWatchRules.canScheduleForecastEvent(
            eventDate: now.addingTimeInterval(20),
            safetyCritical: false, leadMinutes: -15,
            now: now, quietHours: "none"
        ))
        XCTAssertTrue(WeatherWatchRules.canScheduleForecastEvent(
            eventDate: now.addingTimeInterval(60),
            safetyCritical: false, leadMinutes: -15,
            now: now, quietHours: "none"
        ))
    }

}
