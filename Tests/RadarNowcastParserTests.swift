import XCTest

final class RadarNowcastParserTests: XCTestCase {
    func testParsesAndSortsTimeseriesWithRadarCoverage() throws {
        let data = Data("""
        {
          "properties": {
            "meta": { "radar_coverage": "ok" },
            "timeseries": [
              {
                "time": "2026-11-24T07:10:00Z",
                "data": {
                  "instant": { "details": { "precipitation_rate": 0.8 } },
                  "next_1_hours": { "details": { "precipitation_amount": 0.4 } }
                }
              },
              {
                "time": "2026-11-24T07:05:00Z",
                "data": {
                  "instant": { "details": { "precipitation_rate": 0.2 } },
                  "next_1_hours": { "details": { "precipitation_amount": 0.1 } }
                }
              }
            ]
          }
        }
        """.utf8)

        let result = try RadarNowcastParser.parse(data)

        XCTAssertEqual(result.coverage, .ok)
        XCTAssertEqual(result.points.count, 2)
        XCTAssertEqual(result.points[0].time, ISO8601DateFormatter().date(from: "2026-11-24T07:05:00Z"))
        XCTAssertEqual(result.points[0].precipitationRate, 0.2)
        XCTAssertEqual(result.points[1].amountNextHour, 0.4)
    }

    func testMissingOrNonNumericMeasurementsRemainUnknown() throws {
        let data = Data("""
        {
          "properties": {
            "meta": { "radar_coverage": "no coverage" },
            "timeseries": [{
              "time": "2026-11-24T07:05:00Z",
              "data": {
                "instant": { "details": { "precipitation_rate": "not-a-number" } },
                "next_1_hours": { "details": {} }
              }
            }]
          }
        }
        """.utf8)

        let result = try RadarNowcastParser.parse(data)

        XCTAssertEqual(result.coverage, .noCoverage)
        XCTAssertNil(result.points.first?.precipitationRate)
        XCTAssertNil(result.points.first?.amountNextHour)
    }

    func testNegativeMeasurementsAreClampedToZero() throws {
        let data = Data("""
        {
          "properties": {
            "timeseries": [{
              "time": "2026-11-24T07:05:00Z",
              "data": {
                "instant": { "details": { "precipitation_rate": -0.4 } },
                "next_1_hours": { "details": { "precipitation_amount": -1.2 } }
              }
            }]
          }
        }
        """.utf8)

        let result = try RadarNowcastParser.parse(data)

        XCTAssertEqual(result.coverage, .unknown)
        XCTAssertEqual(result.points.first?.precipitationRate, 0)
        XCTAssertEqual(result.points.first?.amountNextHour, 0)
    }

    func testMalformedDocumentThrows() {
        XCTAssertThrowsError(try RadarNowcastParser.parse(Data("{}".utf8)))
    }
}
