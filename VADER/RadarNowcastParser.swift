import Foundation

struct NowcastPoint: Identifiable, Equatable {
    let time: Date
    let precipitationRate: Double?
    let amountNextHour: Double?

    var id: TimeInterval { time.timeIntervalSince1970 }
}

enum RadarNowcastCoverage: String, Equatable {
    case ok
    case temporarilyUnavailable = "temporarily unavailable"
    case noCoverage = "no coverage"
    case unknown
}

struct RadarNowcastResult: Equatable {
    let coverage: RadarNowcastCoverage
    let points: [NowcastPoint]
}

enum RadarNowcastParser {
    enum ParseError: Error {
        case invalidDocument
    }

    static func parse(_ data: Data) throws -> RadarNowcastResult {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let properties = root["properties"] as? [String: Any],
            let timeseries = properties["timeseries"] as? [[String: Any]]
        else {
            throw ParseError.invalidDocument
        }

        let rawCoverage = (properties["meta"] as? [String: Any])?["radar_coverage"] as? String
        let coverage = rawCoverage.flatMap(RadarNowcastCoverage.init(rawValue:)) ?? .unknown
        let formatter = ISO8601DateFormatter()

        let points = timeseries.compactMap { item -> NowcastPoint? in
            guard
                let stamp = item["time"] as? String,
                let date = formatter.date(from: stamp),
                let data = item["data"] as? [String: Any]
            else {
                return nil
            }

            let instantDetails = (data["instant"] as? [String: Any])?["details"] as? [String: Any]
            let nextHourDetails = (data["next_1_hours"] as? [String: Any])?["details"] as? [String: Any]

            func finiteNonnegativeNumber(_ value: Any?) -> Double? {
                guard let number = value as? NSNumber else { return nil }
                let result = number.doubleValue
                guard result.isFinite else { return nil }
                return max(0, result)
            }

            return NowcastPoint(
                time: date,
                precipitationRate: finiteNonnegativeNumber(instantDetails?["precipitation_rate"]),
                amountNextHour: finiteNonnegativeNumber(nextHourDetails?["precipitation_amount"])
            )
        }
        .sorted { $0.time < $1.time }

        return RadarNowcastResult(coverage: coverage, points: points)
    }
}
