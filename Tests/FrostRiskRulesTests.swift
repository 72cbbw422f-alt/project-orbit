import XCTest
@testable import VADER

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