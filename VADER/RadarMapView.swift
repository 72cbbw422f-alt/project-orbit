import SwiftUI
import MapLibre
import Combine
import UIKit

private enum RadarProvider: String {
    case smhi = "SMHI QCOMP"
    case rainViewer = "RainViewer"
}

private struct RadarFrame: Identifiable, Equatable {
    let time: Date
    let path: String
    let provider: RadarProvider
    var id: TimeInterval { time.timeIntervalSince1970 }
}

private struct NowcastPoint: Identifiable {
    let time: Date
    let precipitationRate: Double?
    let amountNextHour: Double?
    var id: TimeInterval { time.timeIntervalSince1970 }
}

private enum RadarService {
    private struct RainViewerManifest: Decodable {
        struct Radar: Decodable {
            struct Frame: Decodable {
                let time: TimeInterval
                let path: String
            }
            let past: [Frame]
        }
        let host: String
        let radar: Radar
    }

    static func loadFrames() async throws -> (String, RadarProvider, [RadarFrame], String?) {
        do {
            let smhi = try await loadSMHIFrames()
            if !smhi.isEmpty { return ("", .smhi, smhi, nil) }
            throw URLError(.cannotParseResponse)
        } catch {
            let reason = smhiFailureDescription(error)
            let (host, frames) = try await loadRainViewerFrames()
            return (host, .rainViewer, frames, reason)
        }
    }

    private static func smhiFailureDescription(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotLoadFromNetwork: return "SMHI:s senaste bild är för gammal"
            case .cannotParseResponse: return "SMHI:s bildlista kunde inte tolkas"
            case .timedOut: return "SMHI svarade inte i tid"
            case .notConnectedToInternet, .networkConnectionLost: return "Nätverksfel mot SMHI"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: return "SMHI:s server kunde inte nås"
            case .badServerResponse: return "SMHI skickade ett ogiltigt serversvar"
            default: return "SMHI:s radarflöde kunde inte läsas"
            }
        }
        return "SMHI:s bildlista kunde inte tolkas"
    }

    private static func loadSMHIFrames() async throws -> [RadarFrame] {
        let directory = URL(string: "https://data-download.smhi.se/data/meteorology/radar/")!
        var request = URLRequest(url: directory)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Regnvakt iOS", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            throw URLError(.badServerResponse)
        }

        // SMHI's official QCOMP PNGs are timestamped in UTC and generated every five minutes.
        let pattern = #"RADAR_SWE_EPSG3006_QCOMP_(\d{12})\.png"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(html.startIndex..., in: html)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmm"

        var frames: [RadarFrame] = []
        for match in regex.matches(in: html, range: range) {
            guard let matchRange = Range(match.range(at: 1), in: html) else { continue }
            let stamp = String(html[matchRange])
            guard let date = formatter.date(from: stamp) else { continue }
            let filename = "RADAR_SWE_EPSG3006_QCOMP_\(stamp).png"
            frames.append(RadarFrame(time: date, path: directory.appendingPathComponent(filename).absoluteString, provider: .smhi))
        }
        let unique = Dictionary(grouping: frames, by: { $0.time })
        let sorted = unique.values.compactMap { $0.first }.sorted { $0.time < $1.time }
        let recent = Array(sorted.suffix(25))
        guard let newest = recent.last?.time else { throw URLError(.cannotParseResponse) }

        // QCOMP frames are generated every five minutes. Do not keep presenting
        // an old SMHI image as live radar during an upstream outage; let the
        // RainViewer fallback take over when the newest frame is stale.
        let frameAge = Date().timeIntervalSince(newest)
        guard frameAge >= -5 * 60, frameAge <= 20 * 60 else {
            throw URLError(.cannotLoadFromNetwork)
        }
        return recent
    }

    static func loadRainViewerFrames() async throws -> (String, [RadarFrame]) {
        let url = URL(string: "https://api.rainviewer.com/public/weather-maps.json")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Regnvakt iOS", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let manifest = try JSONDecoder().decode(RainViewerManifest.self, from: data)
        let frames = manifest.radar.past.map {
            RadarFrame(time: Date(timeIntervalSince1970: $0.time), path: $0.path, provider: .rainViewer)
        }.sorted { $0.time < $1.time }
        guard !frames.isEmpty else { throw URLError(.dataNotAllowed) }
        return (manifest.host, Array(frames.suffix(25)))
    }

    static func hasPrecipitation(host: String, frame: RadarFrame, coordinate: CLLocationCoordinate2D) async throws -> Bool {
        let zoom = 7.0
        let tileCount = pow(2.0, zoom)
        let latitude = min(85.0511, max(-85.0511, coordinate.latitude))
        let xPosition = (coordinate.longitude + 180.0) / 360.0 * tileCount
        let latitudeRadians = latitude * .pi / 180.0
        let yPosition = (1.0 - log(tan(latitudeRadians) + 1.0 / cos(latitudeRadians)) / .pi) / 2.0 * tileCount
        let tileX = Int(floor(xPosition))
        let tileY = Int(floor(yPosition))
        let pixelX = min(511, max(0, Int((xPosition - Double(tileX)) * 512)))
        let pixelY = min(511, max(0, Int((yPosition - Double(tileY)) * 512)))
        let urlString = "\(host)\(frame.path)/512/\(tileX)/\(tileY)/2/1_1.png"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data),
              let cgImage = image.cgImage else { throw URLError(.cannotDecodeContentData) }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * bytesPerPixel,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { throw URLError(.cannotDecodeContentData) }

        var opaqueSamples = 0
        for dy in -2...2 {
            for dx in -2...2 {
                let px = min(width - 1, max(0, pixelX + dx))
                let py = min(height - 1, max(0, pixelY + dy))
                let alpha = pixels[(py * width + px) * bytesPerPixel + 3]
                if alpha > 24 { opaqueSamples += 1 }
            }
        }
        return opaqueSamples >= 2
    }

    static func loadImage(for frame: RadarFrame) async throws -> UIImage {
        guard frame.provider == .smhi, let url = URL(string: frame.path) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("image/png,image/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("Regnvakt iOS", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }
        return image
    }
}


private struct WindSample: Identifiable {
    let id: Int
    let latitude: Double
    let longitude: Double
    let speed: Double
    let direction: Double
    let gust: Double
    let cloudCover: Double
    let precipitationType: Int
    let precipitation: Double
}



private enum WindLayer: String, CaseIterable {
    case speed = "Vind"
    case gust = "Byvind"
}

private struct WindFieldOverlay: View {
    let samples: [WindSample]
    let center: CLLocationCoordinate2D
    let show: Bool
    let gustMode: Bool

    private func tint(_ speed: Double) -> Color {
        switch speed {
        case ..<4: return Color(red: 0.34, green: 0.76, blue: 0.88)
        case ..<8: return Color(red: 0.34, green: 0.78, blue: 0.58)
        case ..<12: return Color(red: 0.88, green: 0.73, blue: 0.30)
        case ..<17: return Color(red: 0.88, green: 0.52, blue: 0.32)
        default: return Color(red: 0.86, green: 0.36, blue: 0.40)
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !show || samples.count < 9)) { timeline in
            Canvas { context, size in
                guard show, samples.count >= 9 else { return }

                // Build a continuous vector field once per frame. Bilinear sampling
                // between grid cells avoids the stepped direction changes of nearest-cell
                // lookup, while keeping the 25 Open-Meteo observations as the only input.
                let nx = 36
                let ny = 28
                typealias WindVector = (u: Double, v: Double, speed: Double)
                var fieldGrid = [WindVector](repeating: (0, 0, 0), count: nx * ny)

                for gy in 0..<ny {
                    for gx in 0..<nx {
                        let px = (Double(gx) + 0.5) / Double(nx)
                        let py = (Double(gy) + 0.5) / Double(ny)
                        var total = 0.0
                        var u = 0.0
                        var v = 0.0
                        var speed = 0.0
                        for sample in samples {
                            // Anchor every sample to the actual camera center, not
                            // the middle element of the response array. The center sample
                            // can be missing when one of the parallel requests fails.
                            let sx = 0.5 + (sample.longitude - center.longitude) / 2.0
                            let sy = 0.5 - (sample.latitude - center.latitude) / 1.2
                            let dx = px - sx
                            let dy = py - sy
                            let weight = 1.0 / max(dx * dx + dy * dy, 0.0025)
                            let magnitude = gustMode ? sample.gust : sample.speed
                            // Open-Meteo reports the direction the wind comes FROM.
                            // Convert it to a screen-space vector pointing where it blows:
                            // east is positive X; north is negative Y on the map canvas.
                            let radians = sample.direction * .pi / 180
                            u += -sin(radians) * magnitude * weight
                            v += -cos(radians) * magnitude * weight
                            speed += magnitude * weight
                            total += weight
                        }
                        fieldGrid[gy * nx + gx] = (u / total, v / total, speed / total)
                    }
                }

                func vector(at point: CGPoint) -> WindVector {
                    let gx = min(Double(nx - 1), max(0, Double(point.x / max(size.width, 1)) * Double(nx) - 0.5))
                    let gy = min(Double(ny - 1), max(0, Double(point.y / max(size.height, 1)) * Double(ny) - 0.5))
                    let x0 = min(nx - 1, max(0, Int(gx)))
                    let y0 = min(ny - 1, max(0, Int(gy)))
                    let x1 = min(nx - 1, x0 + 1)
                    let y1 = min(ny - 1, y0 + 1)
                    let tx = gx - Double(x0)
                    let ty = gy - Double(y0)
                    let a = fieldGrid[y0 * nx + x0]
                    let b = fieldGrid[y0 * nx + x1]
                    let c = fieldGrid[y1 * nx + x0]
                    let d = fieldGrid[y1 * nx + x1]
                    func blend(_ key: (WindVector) -> Double) -> Double {
                        let top = key(a) * (1 - tx) + key(b) * tx
                        let bottom = key(c) * (1 - tx) + key(d) * tx
                        return top * (1 - ty) + bottom * ty
                    }
                    return (blend { $0.u }, blend { $0.v }, blend { $0.speed })
                }

                let now = timeline.date.timeIntervalSinceReferenceDate
                // Fewer, longer-lived trails create a calmer visual field and
                // leave more rendering headroom on older iPhones.
                let particleCount = 132
                for index in 0..<particleCount {
                    // Deterministic pseudo-random seed points; particles drift continuously
                    // through the interpolated Open-Meteo wind field and then respawn.
                    let seedX = CGFloat((index * 377 + 113) % 997) / 997.0
                    let seedY = CGFloat((index * 613 + 271) % 991) / 991.0
                    let seed = CGPoint(x: seedX * size.width, y: seedY * size.height)
                    let duration = 4.8 + Double((index * 7) % 13) * 0.43
                    let phase = (now / duration + Double(index) * 0.137).truncatingRemainder(dividingBy: 1.0)
                    let progress = phase * 68.0
                    let steps = Int(progress)
                    let remainder = progress - Double(steps)
                    var point = seed
                    var trail: [CGPoint] = [seed]
                    var localSpeed = 0.0

                    for _ in 0..<steps {
                        let field = vector(at: point)
                        let firstMagnitude = max(0.1, hypot(field.u, field.v))
                        let step = min(5.5, max(2.4, firstMagnitude * 0.42))
                        let midpoint = CGPoint(
                            x: point.x + CGFloat(field.u / firstMagnitude) * step * 0.5,
                            y: point.y - CGFloat(field.v / firstMagnitude) * step * 0.5
                        )
                        let midField = vector(at: midpoint)
                        localSpeed = midField.speed
                        let magnitude = max(0.1, hypot(midField.u, midField.v))
                        point = CGPoint(
                            x: point.x + CGFloat(midField.u / magnitude) * step,
                            y: point.y - CGFloat(midField.v / magnitude) * step
                        )
                        if point.x < -8 || point.x > size.width + 8 || point.y < -8 || point.y > size.height + 8 {
                            break
                        }
                        trail.append(point)
                    }

                    // A fractional final integration step removes the visible
                    // one-pixel jumps caused by rounding particle progress to frames.
                    if remainder > 0.015,
                       point.x >= -8, point.x <= size.width + 8,
                       point.y >= -8, point.y <= size.height + 8 {
                        let field = vector(at: point)
                        localSpeed = field.speed
                        let magnitude = max(0.1, hypot(field.u, field.v))
                        let step = min(6.5, max(2.8, magnitude * 0.48)) * remainder
                        point = CGPoint(
                            x: point.x + CGFloat(field.u / magnitude) * step,
                            y: point.y - CGFloat(field.v / magnitude) * step
                        )
                        trail.append(point)
                    }

                    guard let head = trail.last else { continue }
                    let color = tint(localSpeed)
                    if trail.count > 2 {
                        let visibleTrail = Array(trail.suffix(34))
                        var smoothPath = Path()
                        smoothPath.move(to: visibleTrail[0])
                        if visibleTrail.count > 2 {
                            for index in 1..<(visibleTrail.count - 1) {
                                let midpoint = CGPoint(
                                    x: (visibleTrail[index].x + visibleTrail[index + 1].x) * 0.5,
                                    y: (visibleTrail[index].y + visibleTrail[index + 1].y) * 0.5
                                )
                                smoothPath.addQuadCurve(to: midpoint, control: visibleTrail[index])
                            }
                        }
                        if let last = visibleTrail.last {
                            smoothPath.addLine(to: last)
                        }
                        // Soft halo plus a fine luminous core gives the trails
                        // the continuous, fluid appearance expected from a wind map.
                        context.stroke(smoothPath, with: .color(color.opacity(0.075)),
                                       style: StrokeStyle(lineWidth: 4.0, lineCap: .round, lineJoin: .round))
                        context.stroke(
                            smoothPath,
                            with: .linearGradient(
                                Gradient(colors: [color.opacity(0.015), color.opacity(0.62)]),
                                startPoint: visibleTrail[0],
                                endPoint: head
                            ),
                            style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round)
                        )
                    }
                    let radius: CGFloat = 0.9 + CGFloat(min(localSpeed, 20)) * 0.035
                    let halo = Path(ellipseIn: CGRect(x: head.x - radius * 2.2, y: head.y - radius * 2.2,
                                                      width: radius * 4.4, height: radius * 4.4))
                    context.fill(halo, with: .color(color.opacity(0.16)))
                    let particle = Path(ellipseIn: CGRect(x: head.x - radius, y: head.y - radius,
                                                          width: radius * 2, height: radius * 2))
                    context.fill(particle, with: .color(color.opacity(0.96)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}


private enum SWEREF99 {
    static func toWGS84(easting: Double, northing: Double) -> CLLocationCoordinate2D {
        let a = 6378137.0
        let f = 1.0 / 298.257222101
        let k0 = 0.9996
        let e2 = f * (2 - f)
        let n = f / (2 - f)
        let A = a / (1 + n) * (1 + pow(n, 2) / 4 + pow(n, 4) / 64)
        let b1 = n / 2 - 2 * pow(n, 2) / 3 + 5 * pow(n, 3) / 16 + 41 * pow(n, 4) / 180
        let b2 = 13 * pow(n, 2) / 48 - 3 * pow(n, 3) / 5 + 557 * pow(n, 4) / 1440
        let b3 = 61 * pow(n, 3) / 240 - 103 * pow(n, 4) / 140
        let b4 = 49561 * pow(n, 4) / 161280
        let xi = northing / (k0 * A)
        let eta = (easting - 500000) / (k0 * A)
        let xiP = xi - b1 * sin(2 * xi) * cosh(2 * eta) - b2 * sin(4 * xi) * cosh(4 * eta)
            - b3 * sin(6 * xi) * cosh(6 * eta) - b4 * sin(8 * xi) * cosh(8 * eta)
        let etaP = eta - b1 * cos(2 * xi) * sinh(2 * eta) - b2 * cos(4 * xi) * sinh(4 * eta)
            - b3 * cos(6 * xi) * sinh(6 * eta) - b4 * cos(8 * xi) * sinh(8 * eta)
        let sinhEta = sinh(etaP)
        let tauP = sin(xiP) / sqrt(sinhEta * sinhEta + cos(xiP) * cos(xiP))
        var tau = tauP
        for _ in 0..<5 {
            let tauE = tau * sqrt(e2)
            let sigma = sinh(0.5 * (log(1 + tauE) - log(1 - tauE)))
            let next = tau * sqrt(1 + sigma * sigma) - sigma * sqrt(1 + tau * tau)
            if abs(next - tau) < 1e-13 { tau = next; break }
            tau = next
        }
        let latitude = atan(tau)
        let longitude = atan2(sinhEta, cos(xiP)) + 15.0 * .pi / 180.0
        return CLLocationCoordinate2D(latitude: latitude * 180 / .pi, longitude: longitude * 180 / .pi)
    }

    static var imageQuad: MLNCoordinateQuad {
        // SMHI documents these EPSG:3006 image corners in its radar README.
        let sw = toWGS84(easting: 126648, northing: 5983984)
        let ne = toWGS84(easting: 1075693, northing: 7771252)
        let nw = toWGS84(easting: 126648, northing: 7771252)
        let se = toWGS84(easting: 1075693, northing: 5983984)
        return MLNCoordinateQuad(topLeft: nw, bottomLeft: sw, bottomRight: se, topRight: ne)
    }
}

struct RadarMapView: View {
    let coordinate: CLLocationCoordinate2D?
    let place: String

    @State private var radarHost = "https://tilecache.rainviewer.com"
    @State private var provider: RadarProvider = .smhi
    @State private var frames: [RadarFrame] = []
    @State private var selectedIndex = 0
    @State private var selectedImage: UIImage?
    @State private var radarImageCache: [TimeInterval: UIImage] = [:]
    @State private var imageLoadID = UUID()
    @State private var imageLoadingID: UUID?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var radarSourceStatus: String?
    @State private var lastUpdated: Date?
    @State private var isPlaying = false
    @State private var showRadar = true
    @State private var precipitationType = "Hämtar nederbördstyp…"
    @State private var typeDetail = "Modellbedömning vid vald plats"
    @State private var radarAtPlace = "Kontrollerar radar över vald plats…"
    @State private var showTypeInfo = false
    @State private var nowcastPoints: [NowcastPoint] = []
    @State private var nowcastStatus = "Hämtar närprognos…"
    @State private var nowcastUpdated: Date?
    @State private var windSamples: [WindSample] = []
    @State private var windLayer: WindLayer = .speed
    @State private var showWind = false
    @State private var showClouds = false
    @State private var showPrecipitationTypes = false
    @State private var windStatus = "Hämtar vindfält…"
    @State private var windUpdated: Date?
    @State private var windMapCenter: CLLocationCoordinate2D?
    @State private var windRequestID = UUID()
    @State private var windRefreshTask: Task<Void, Never>?

    private let playback = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    private var mapCoordinate: CLLocationCoordinate2D {
        let value = coordinate ?? CLLocationCoordinate2D(latitude: 61.7274, longitude: 17.1058)
        return CLLocationCoordinate2D(
            latitude: value.latitude.isFinite ? min(85, max(-85, value.latitude)) : 61.7274,
            longitude: value.longitude.isFinite ? min(180, max(-180, value.longitude)) : 17.1058
        )
    }

    private var coordinateKey: String {
        String(format: "%.5f,%.5f", mapCoordinate.latitude, mapCoordinate.longitude)
    }

    private var selectedFrame: RadarFrame? {
        frames.indices.contains(selectedIndex) ? frames[selectedIndex] : nil
    }

    private var radarTileURL: String? {
        guard showRadar, let frame = selectedFrame, frame.provider == .rainViewer else { return nil }
        return "\(radarHost)\(frame.path)/512/{z}/{x}/{y}/2/1_1.png"
    }

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.055, blue: 0.085).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
              VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("REGNVAKT")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .tracking(2.2)
                            .foregroundStyle(Color(red: 0.98, green: 0.58, blue: 0.40))
                        Text(showWind ? "Vindradar" : "Nederbördsradar")
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(place)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    Spacer()
                    Button {
                        showWind.toggle()
                        showClouds = false
                        showRadar = !showWind
                        if showWind && windSamples.isEmpty { Task { await refreshWindField() } }
                    } label: {
                        Image(systemName: showRadar ? "cloud.rain.fill" : "cloud")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(showRadar ? Color(red: 0.98, green: 0.58, blue: 0.40) : .white.opacity(0.75))
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.09), in: Circle())
                    }
                    .accessibilityLabel(showRadar ? "Byt till vind" : "Byt till nederbördsradar")
                    Button { Task { await refreshRadar() } } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.09), in: Circle())
                    }
                    .accessibilityLabel("Uppdatera radarn")
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 12)

                ZStack(alignment: .topLeading) {
                    RegnvaktMapView(
                        coordinate: mapCoordinate,
                        radarImage: showRadar && provider == .smhi ? selectedImage : nil,
                        radarTileURL: radarTileURL,
                        locationTitle: place,
                        cloudSamples: windSamples,
                        showClouds: showClouds,
                        showPrecipitationTypes: showPrecipitationTypes,
                        onRegionChange: { center in
                            windMapCenter = center
                            // Invalidate any response for the previous camera position immediately.
                            windRequestID = UUID()
                            if showWind || showClouds || showPrecipitationTypes {
                                // Never project old samples onto a new map center while the
                                // debounced request is waiting; that would show a convincing
                                // but geographically incorrect wind/cloud field.
                                windSamples = []
                                windUpdated = nil
                                windStatus = "Kartområdet ändras – hämtar nya modellvärden…"
                                // Debounce intermediate map-camera updates during a pan.
                                windRefreshTask?.cancel()
                                windRefreshTask = Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 700_000_000)
                                    guard !Task.isCancelled else { return }
                                    await refreshWindField(center: center)
                                }
                            }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    WindFieldOverlay(
                        samples: windSamples,
                        center: windMapCenter ?? mapCoordinate,
                        show: showWind,
                        gustMode: windLayer == .gust
                    )
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    HStack(spacing: 7) {
                        Circle().fill(Color(red: 0.35, green: 0.88, blue: 0.83)).frame(width: 7, height: 7)
                        Text(showWind ? "VIND • OPEN-METEO" : (showClouds ? "MOLNTÄCKE • OPEN-METEO" : "RADAR • \(provider.rawValue.uppercased())"))
                            .font(.system(size: 12, weight: .heavy))
                            .tracking(0.8)
                            .foregroundStyle(.white)
                        Spacer()
                        Text("© OpenStreetMap")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.black.opacity(0.48), in: Capsule())
                    .padding(12)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: 340)

                if let radarSourceStatus, !showWind {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Color(red: 0.98, green: 0.68, blue: 0.40))
                        Text(radarSourceStatus)
                            .foregroundStyle(.white.opacity(0.86))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 12)
                    .padding(.top, 5)
                }

                if !showWind, let selectedFrame {
                    HStack(spacing: 9) {
                        Button { selectedIndex = max(0, selectedIndex - 1) } label: {
                            Image(systemName: "backward.end.fill").font(.system(size: 12, weight: .bold))
                                .frame(width: 28, height: 34)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            HStack {
                                Text("RADAR").font(.system(size: 10, weight: .heavy)).tracking(0.8).foregroundStyle(Color.cyan)
                                Spacer()
                                Text(selectedFrame.time.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                            }
                            Slider(value: Binding(
                                get: { Double(selectedIndex) },
                                set: { selectedIndex = Int($0.rounded()) }
                            ), in: 0...Double(max(0, frames.count - 1)), step: 1)
                            .tint(Color(red: 0.98, green: 0.58, blue: 0.40))
                            .disabled(frames.count < 2)
                        }
                        Button { isPlaying.toggle() } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 13, weight: .bold))
                                .frame(width: 34, height: 34)
                                .background(Color(red: 0.98, green: 0.66, blue: 0.47), in: Circle())
                                .foregroundStyle(Color(red: 0.07, green: 0.10, blue: 0.14))
                        }
                        Button { selectedIndex = min(frames.count - 1, selectedIndex + 1) } label: {
                            Image(systemName: "forward.end.fill").font(.system(size: 12, weight: .bold))
                                .frame(width: 28, height: 34)
                        }
                    }
                    .foregroundStyle(Color(red: 0.98, green: 0.66, blue: 0.47))
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
                    .padding(.horizontal, 12).padding(.top, 7).padding(.bottom, 3)
                }

                VStack(spacing: 13) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        Button {
                            showWind = false
                            showClouds = false
                            showPrecipitationTypes = false
                            showRadar = true
                        } label: {
                            Label("Regn", systemImage: "cloud.rain.fill")
                                .font(.system(size: 15, weight: .bold))
                                .frame(maxWidth: .infinity).frame(height: 64)
                                .foregroundStyle(!showWind && !showPrecipitationTypes ? Color(red: 0.10, green: 0.13, blue: 0.17) : .white)
                                .background(!showWind && !showPrecipitationTypes ? Color(red: 0.98, green: 0.62, blue: 0.43) : Color(red: 0.15, green: 0.22, blue: 0.31), in: RoundedRectangle(cornerRadius: 13))
                                .overlay(RoundedRectangle(cornerRadius: 13).stroke(!showWind && !showPrecipitationTypes ? Color.white.opacity(0.55) : Color.white.opacity(0.18), lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Button {
                            showWind = true
                            showClouds = false
                            showPrecipitationTypes = false
                            showRadar = false
                            if windSamples.isEmpty { Task { await refreshWindField() } }
                        } label: {
                            Label("Vind", systemImage: "wind")
                                .font(.system(size: 15, weight: .bold))
                                .frame(maxWidth: .infinity).frame(height: 64)
                                .foregroundStyle(showWind ? Color(red: 0.10, green: 0.13, blue: 0.17) : .white)
                                .background(showWind ? Color(red: 0.98, green: 0.62, blue: 0.43) : Color(red: 0.15, green: 0.22, blue: 0.31), in: RoundedRectangle(cornerRadius: 13))
                                .overlay(RoundedRectangle(cornerRadius: 13).stroke(showWind ? Color.white.opacity(0.55) : Color.white.opacity(0.18), lineWidth: 1))
                        }
                        .buttonStyle(.plain)


                        Button {
                            showWind = false
                            showClouds = false
                            showPrecipitationTypes = true
                            showRadar = true
                            Task { await refreshWindField(center: windMapCenter ?? mapCoordinate) }
                        } label: {
                            Label("Typ", systemImage: "cloud.snow.fill")
                                .font(.system(size: 15, weight: .bold))
                                .frame(maxWidth: .infinity).frame(height: 64)
                                .foregroundStyle(showPrecipitationTypes ? Color(red: 0.10, green: 0.13, blue: 0.17) : .white)
                                .background(showPrecipitationTypes ? Color(red: 0.98, green: 0.62, blue: 0.43) : Color(red: 0.15, green: 0.22, blue: 0.31), in: RoundedRectangle(cornerRadius: 13))
                                .overlay(RoundedRectangle(cornerRadius: 13).stroke(showPrecipitationTypes ? Color.white.opacity(0.55) : Color.white.opacity(0.18), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    if showWind {
                        HStack(spacing: 10) {
                            ForEach(WindLayer.allCases, id: \.self) { layer in
                                Button {
                                    windLayer = layer
                                    if windSamples.isEmpty { Task { await refreshWindField() } }
                                } label: {
                                    Text(layer.rawValue)
                                        .font(.system(size: 13, weight: .bold))
                                        .frame(maxWidth: .infinity).frame(height: 38)
                                        .foregroundStyle(windLayer == layer ? Color.white : .white.opacity(0.72))
                                        .background(windLayer == layer ? Color(red: 0.10, green: 0.47, blue: 0.62) : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(windLayer == layer ? Color.cyan.opacity(0.9) : Color.white.opacity(0.14), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer(minLength: 0)
                            Text(windUpdated?.formatted(date: .omitted, time: .shortened) ?? "—")
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    if showWind {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(windStatus).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                            if let sample = windSamples.first(where: { $0.id == 12 }) {
                                Text("\(windLayer == .gust ? "Byvind" : "Vind") vid kartans mittpunkt: \(String(format: "%.1f", windLayer == .gust ? sample.gust : sample.speed)) m/s • \(Int(sample.direction.rounded()))°")
                                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.82))
                            }
                            HStack(spacing: 10) {
                                ForEach([("0–4", Color.cyan), ("4–8", Color.green), ("8–12", Color.yellow), ("12–17", Color.orange), ("17+", Color.red)], id: \.0) { item in
                                    HStack(spacing: 4) { Circle().fill(item.1).frame(width: 7, height: 7); Text(item.0).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.75)) }
                                }
                            }
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 0.12, green: 0.16, blue: 0.21), in: RoundedRectangle(cornerRadius: 15))
                    }
                    if showClouds {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("MOLNTÄCKE ÖVER KARTOMRÅDET")
                                .font(.system(size: 12, weight: .heavy)).tracking(0.8).foregroundStyle(Color.cyan)
                            Text("Open-Meteo-modell • geografiskt placerade mätpunkter, inte satellitbilder.")
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.68))
                            HStack {
                                Text(windStatus)
                                Spacer()
                                Text(windUpdated?.formatted(date: .omitted, time: .shortened) ?? "—")
                                    .monospacedDigit()
                            }
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.62))
                            if let center = windSamples.first(where: { $0.id == 12 }) {
                                Text("Molnighet vid kartans mittpunkt: \(Int(center.cloudCover.rounded())) %")
                                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                            }
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 0.12, green: 0.16, blue: 0.21), in: RoundedRectangle(cornerRadius: 15))
                    }
                    if showPrecipitationTypes {
                        let rainCount = windSamples.filter { $0.precipitationType == 1 && $0.precipitation >= 0.05 }.count
                        let snowCount = windSamples.filter { $0.precipitationType == 2 && $0.precipitation >= 0.05 }.count
                        let mixedCount = windSamples.filter { $0.precipitationType == 3 && $0.precipitation >= 0.05 }.count
                        VStack(alignment: .leading, spacing: 9) {
                            Text("NEDERBÖRDSTYP ÖVER KARTAN")
                                .font(.system(size: 12, weight: .heavy)).tracking(0.8).foregroundStyle(Color.cyan)
                            Text("Prognosmodell från Open-Meteo – inte en klassificering av radarbildens pixlar.")
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.68))
                            HStack(spacing: 12) {
                                legendItem("Regn", color: Color(red: 0.18, green: 0.58, blue: 0.96), count: rainCount)
                                legendItem("Snö", color: Color(red: 0.82, green: 0.92, blue: 1.0), count: snowCount)
                                legendItem("Blandat", color: Color(red: 0.68, green: 0.42, blue: 0.88), count: mixedCount)
                            }
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 0.12, green: 0.16, blue: 0.21), in: RoundedRectangle(cornerRadius: 15))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("NÄRPROGNOS")
                                    .font(.system(size: 12, weight: .heavy)).tracking(1).foregroundStyle(Color.cyan)
                                Text("MET Norway • upp till 2 timmar")
                                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.62))
                            }
                            Spacer()
                            Text(nowcastUpdated?.formatted(date: .omitted, time: .shortened) ?? "—")
                                .font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(.white.opacity(0.55))
                        }
                        Text(nowcastStatus)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.90))
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                        if !nowcastPoints.isEmpty {
                            HStack(alignment: .bottom, spacing: 5) {
                                ForEach(nowcastPoints.prefix(6)) { point in
                                    VStack(spacing: 2) {
                                        Text(String(format: "%.1f", point.precipitationRate ?? 0))
                                            .font(.system(size: 13, weight: .bold).monospacedDigit())
                                            .foregroundStyle(.white)
                                        Capsule()
                                            .fill(Color.cyan.opacity(0.9))
                                            .frame(maxWidth: 38)
                                            .frame(height: max(3, min(30, CGFloat(point.precipitationRate ?? 0) * 18)))
                                        Text(point.time.formatted(date: .omitted, time: .shortened))
                                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                            .foregroundStyle(.white.opacity(0.88))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(maxWidth: .infinity, alignment: .top)
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel("\(point.time.formatted(date: .omitted, time: .shortened)), \(String(format: "%.1f", point.precipitationRate ?? 0)) millimeter per hour")
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .background(Color(red: 0.12, green: 0.16, blue: 0.21), in: RoundedRectangle(cornerRadius: 15))

                    HStack {
                        Text(provider == .smhi ? "Radar: SMHI • 5 min" : "Reservradar: RainViewer")
                        Spacer()
                        Text("Karta © OpenStreetMap")
                    }
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                }
                .padding(16)
                .background(
                    LinearGradient(colors: [
                        Color(red: 0.09, green: 0.13, blue: 0.18),
                        Color(red: 0.06, green: 0.09, blue: 0.14)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.08), lineWidth: 1))
                .padding(12)
              }
              .padding(.bottom, 112)
            }
            .safeAreaPadding(.top, 10)
        }
        .task {
            await refreshRadar()
            await refreshPrecipitationType()
            await refreshNowcast()
            await refreshWindField()
        }
        .onChange(of: selectedIndex) { _, _ in
            Task {
                await loadSelectedImage()
                await refreshRadarAtPlace()
            }
        }
        .onChange(of: coordinateKey) { _, _ in
            // A newly selected town is a new geographic map context.
            Task {
                await refreshWindField(center: mapCoordinate)
                await refreshPrecipitationType()
                await refreshNowcast()
                await refreshRadarAtPlace()
            }
        }
        .onReceive(playback) { _ in
            guard isPlaying, !frames.isEmpty, imageLoadingID == nil else { return }
            selectedIndex = selectedIndex >= frames.count - 1 ? 0 : selectedIndex + 1
        }
        .alert("Om nederbördstyp", isPresented: $showTypeInfo) {
            Button("Stäng", role: .cancel) {}
        } message: {
            Text("Radarn visar observerad nederbörd. SMHI används i första hand. RainViewer används som reserv om SMHI:s radarflöde inte är tillgängligt. Nederbördstypen hämtas separat från en vädermodell och är en bedömning, inte en direkt klassificering av varje radar-pixel.")
        }
    }

    private func legendItem(_ title: String, color: Color, count: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: title == "Regn" ? "drop.fill" : title == "Snö" ? "snowflake" : "cloud.sleet.fill")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(color).frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                Text("\(count) punkter").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.58))
            }
        }
    }

    private var precipitationSymbol: String {
        let text = precipitationType.lowercased()
        if text.contains("blandad") { return "cloud.sleet.fill" }
        if text.contains("snö") { return "cloud.snow.fill" }
        if text.contains("hagel") { return "cloud.hail.fill" }
        if text.contains("duggregn") { return "cloud.drizzle.fill" }
        if text.contains("regn") { return "cloud.rain.fill" }
        return "cloud.fill"
    }

    @MainActor
    private func refreshRadar() async {
        guard !isLoading else { return }
        isLoading = true
        isPlaying = false
        errorMessage = nil
        radarSourceStatus = nil
        do {
            let result = try await RadarService.loadFrames()
            radarHost = result.0
            provider = result.1
            frames = result.2
            radarSourceStatus = result.3.map { "SMHI kunde inte användas: \($0). Visar RainViewer som reserv." }
            selectedIndex = frames.count - 1
            await loadSelectedImage()
            await refreshRadarAtPlace()
            lastUpdated = Date()
        } catch {
            frames = []
            selectedImage = nil
            radarSourceStatus = nil
            errorMessage = "Varken SMHI eller reservradarn kunde nås. Kontrollera anslutningen och försök igen."
        }
        isLoading = false
    }

    @MainActor
    private func loadSelectedImage() async {
        let requestID = UUID()
        imageLoadID = requestID
        imageLoadingID = nil
        guard let frame = selectedFrame else { selectedImage = nil; return }
        guard frame.provider == .smhi else { selectedImage = nil; return }
        imageLoadingID = requestID
        defer {
            if imageLoadingID == requestID { imageLoadingID = nil }
        }
        if let cached = radarImageCache[frame.id] {
            selectedImage = cached
            errorMessage = nil
            return
        }
        do {
            let image = try await RadarService.loadImage(for: frame)
            // Only the currently selected frame may be displayed. Keep a small
            // in-memory cache so playback does not redownload frames it revisits.
            guard imageLoadID == requestID, selectedFrame?.id == frame.id else { return }
            radarImageCache[frame.id] = image
            if radarImageCache.count > 30,
               let oldest = radarImageCache.keys.min() {
                radarImageCache.removeValue(forKey: oldest)
            }
            selectedImage = image
            errorMessage = nil
        } catch {
            guard imageLoadID == requestID, selectedFrame?.id == frame.id else { return }
            selectedImage = nil
            errorMessage = nil
            radarSourceStatus = "SMHI:s radarbild kunde inte hämtas. Byter till RainViewer."
            do {
                let (host, fallback) = try await RadarService.loadRainViewerFrames()
                guard imageLoadID == requestID, selectedFrame?.id == frame.id else { return }
                radarHost = host
                provider = .rainViewer
                frames = fallback
                selectedIndex = max(0, frames.count - 1)
                radarSourceStatus = "SMHI:s radarbild kunde inte hämtas. Visar RainViewer som reserv."
                await refreshRadarAtPlace()
            } catch {
                guard imageLoadID == requestID else { return }
                errorMessage = "SMHI-bilden kunde inte hämtas och reservradarn är inte tillgänglig."
            }
        }
    }

    @MainActor
    private func refreshRadarAtPlace() async {
        guard showRadar, let frame = selectedFrame, frame.provider == .rainViewer else {
            radarAtPlace = "Platsavläsning inte tillgänglig för denna radarkälla"
            return
        }
        do {
            let hit = try await RadarService.hasPrecipitation(
                host: radarHost,
                frame: frame,
                coordinate: mapCoordinate
            )
            radarAtPlace = hit ? "Radarträff vid vald plats" : "Ingen tydlig radarträff vid vald plats"
        } catch {
            radarAtPlace = "Kunde inte läsa av radar över vald plats"
        }
    }

    @MainActor
    private func refreshPrecipitationType() async {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(mapCoordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(mapCoordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,precipitation,rain,showers,snowfall"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components.url else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = root["current"] as? [String: Any] else { return }
            let temp = (current["temperature_2m"] as? NSNumber)?.doubleValue ?? 0
            let code = (current["weather_code"] as? NSNumber)?.intValue ?? 0
            let rain = (current["rain"] as? NSNumber)?.doubleValue ?? 0
            let showers = (current["showers"] as? NSNumber)?.doubleValue ?? 0
            let snow = (current["snowfall"] as? NSNumber)?.doubleValue ?? 0
            precipitationType = Self.precipitationName(
                code: code,
                temperature: temp,
                rain: rain + showers,
                snow: snow
            )
            typeDetail = "Modellbedömning • \(Int(temp.rounded()))°C vid \(place)"
        } catch {
            precipitationType = "Nederbördstyp saknas"
            typeDetail = "Kunde inte hämta modellbedömning"
        }
    }

    @MainActor
    private func refreshNowcast() async {
        var components = URLComponents(string: "https://api.met.no/weatherapi/nowcast/2.0/complete")!
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(mapCoordinate.latitude)),
            URLQueryItem(name: "lon", value: String(mapCoordinate.longitude))
        ]
        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Regnvakt/1.0 (iOS weather app)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/geo+json, application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let properties = root["properties"] as? [String: Any],
                  let timeseries = properties["timeseries"] as? [[String: Any]] else {
                nowcastPoints = []
                nowcastStatus = "Närprognosen är inte tillgänglig just nu."
                return
            }

            let meta = properties["meta"] as? [String: Any]
            let coverage = (meta?["radar_coverage"] as? String ?? "").lowercased()
            let formatter = ISO8601DateFormatter()
            let parsed = timeseries.compactMap { item -> NowcastPoint? in
                guard let stamp = item["time"] as? String,
                      let date = formatter.date(from: stamp),
                      let data = item["data"] as? [String: Any] else { return nil }
                let instant = data["instant"] as? [String: Any]
                let details = instant?["details"] as? [String: Any]
                let rate = (details?["precipitation_rate"] as? NSNumber)?.doubleValue
                let nextHour = data["next_1_hours"] as? [String: Any]
                let nextDetails = nextHour?["details"] as? [String: Any]
                let amount = (nextDetails?["precipitation_amount"] as? NSNumber)?.doubleValue
                return NowcastPoint(time: date, precipitationRate: rate, amountNextHour: amount)
            }
            nowcastPoints = Array(parsed.prefix(8))
            nowcastUpdated = Date()

            if coverage == "ok" {
                let hasPrecipitation = parsed.contains { ($0.precipitationRate ?? 0) >= 0.1 }
                nowcastStatus = hasPrecipitation
                    ? "Radarbaserad korttidsprognos. Staplarna visar nederbördsintensitet (mm/h)."
                    : "Ingen nederbörd väntas de närmaste prognostimmarna. Värdena visas i mm/h."
            } else if coverage == "temporarily unavailable" {
                nowcastStatus = "MET Norways radartäckning är tillfälligt ur funktion här."
                nowcastPoints = []
            } else if coverage == "no coverage" {
                nowcastStatus = "Ingen radarbaserad närprognos för den här platsen."
                nowcastPoints = []
            } else {
                nowcastStatus = parsed.isEmpty
                    ? "Närprognos saknas för vald plats."
                    : "Modellprognos tillgänglig; radarbaserad nederbördsintensitet saknas."
            }
        } catch {
            nowcastPoints = []
            nowcastStatus = "Kunde inte hämta MET Norways närprognos."
        }
    }


    @MainActor
    private func refreshWindField(center requestedCenter: CLLocationCoordinate2D? = nil) async {
        let requestID = UUID()
        windRequestID = requestID
        windStatus = "Hämtar vinddata över området…"
        let center = requestedCenter ?? windMapCenter ?? mapCoordinate
        windMapCenter = center

        // Keep the 5×5 geographic sample grid, but request all locations in
        // one Open-Meteo call instead of opening 25 parallel HTTP requests.
        let latitudeGrid = [-0.60, -0.30, 0.0, 0.30, 0.60]
        let longitudeGrid = [-1.00, -0.50, 0.0, 0.50, 1.00]
        let offsets: [(Double, Double)] = latitudeGrid.flatMap { lat in
            longitudeGrid.map { lon in (lat, lon) }
        }
        let coordinates = offsets.map { (center.latitude + $0.0, center.longitude + $0.1) }

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: coordinates.map { String($0.0) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: coordinates.map { String($0.1) }.joined(separator: ",")),
            URLQueryItem(name: "current", value: "wind_speed_10m,wind_direction_10m,wind_gusts_10m,cloud_cover,precipitation,rain,showers,snowfall,weather_code"),
            URLQueryItem(name: "wind_speed_unit", value: "ms"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        guard let url = components.url else {
            windStatus = "Kunde inte skapa begäran för vinddata."
            return
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled, windRequestID == requestID else { return }
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let locations = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw URLError(.cannotParseResponse)
            }

            var results: [WindSample] = []
            for (index, root) in locations.enumerated() {
                guard index < coordinates.count,
                      let current = root["current"] as? [String: Any],
                      let speed = (current["wind_speed_10m"] as? NSNumber)?.doubleValue,
                      let direction = (current["wind_direction_10m"] as? NSNumber)?.doubleValue,
                      let gust = (current["wind_gusts_10m"] as? NSNumber)?.doubleValue else { continue }

                let cloud = (current["cloud_cover"] as? NSNumber)?.doubleValue ?? 0
                let rain = (current["rain"] as? NSNumber)?.doubleValue ?? 0
                let showers = (current["showers"] as? NSNumber)?.doubleValue ?? 0
                let snow = (current["snowfall"] as? NSNumber)?.doubleValue ?? 0
                let precipitation = (current["precipitation"] as? NSNumber)?.doubleValue ?? max(rain + showers, snow)
                let code = (current["weather_code"] as? NSNumber)?.intValue ?? 0
                let type: Int
                if snow > 0.02 && rain + showers > 0.02 { type = 3 }
                else if snow > 0.02 || (71...77).contains(code) || (85...86).contains(code) { type = 2 }
                else if rain + showers > 0.02 || (51...67).contains(code) || (80...82).contains(code) { type = 1 }
                else { type = 0 }

                let coordinate = coordinates[index]
                results.append(WindSample(
                    id: index,
                    latitude: coordinate.0,
                    longitude: coordinate.1,
                    speed: speed,
                    direction: direction,
                    gust: gust,
                    cloudCover: cloud,
                    precipitationType: type,
                    precipitation: precipitation
                ))
            }

            guard !Task.isCancelled, windRequestID == requestID else { return }
            windSamples = results.sorted { $0.id < $1.id }
            windUpdated = Date()
            windStatus = results.count == offsets.count
                ? (showClouds ? "Molntäcke • 25 geografiskt placerade modellpunkter" : "Vindfält • 25 modellpunkter runt kartans mittpunkt")
                : (showClouds ? "Molntäcke delvis tillgängligt • \(results.count) av 25 punkter" : "Vindfält delvis tillgängligt • \(results.count) av 25 punkter")
        } catch {
            guard !Task.isCancelled, windRequestID == requestID else { return }
            windStatus = "Kunde inte hämta vinddata för kartområdet. Försök igen."
        }
    }

    private static func precipitationName(
        code: Int,
        temperature: Double,
        rain: Double,
        snow: Double
    ) -> String {
        // Prefer the model's current precipitation components when present.
        // This distinguishes mixed precipitation from a generic weather code.
        if rain > 0.02 && snow > 0.02 { return "Blandad nederbörd" }
        if snow > 0.02 { return "Snö" }
        if rain > 0.02 {
            return temperature <= 0 ? "Möjligen underkylt regn" : "Regn"
        }

        // Fall back to the WMO weather code when current amounts are zero.
        switch code {
        case 51...57: return temperature <= 0 ? "Möjligen underkylt duggregn" : "Duggregn"
        case 61...67: return temperature <= 0 ? "Möjligen underkylt regn" : "Regn"
        case 71...77, 85...86: return "Snö"
        case 80...82: return temperature <= 0 ? "Möjligen underkylda skurar" : "Regnskurar"
        case 95...99: return "Åska"
        default: return "Ingen nederbörd enligt modellen"
        }
    }
}

private struct RegnvaktMapView: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    let radarImage: UIImage?
    let radarTileURL: String?
    let locationTitle: String
    let cloudSamples: [WindSample]
    let showClouds: Bool
    let showPrecipitationTypes: Bool
    let onRegionChange: (CLLocationCoordinate2D) -> Void
    private let styleURL = URL(string: "https://tiles.openfreemap.org/styles/fiord")!

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: styleURL)
        map.delegate = context.coordinator
        map.logoView.isHidden = false
        map.attributionButton.isHidden = false
        map.compassView.isHidden = false
        map.showsUserLocation = false
        map.allowsRotating = false
        map.allowsTilting = false
        map.minimumZoomLevel = 3
        // RainViewer's radar tiles are not available at higher zoom levels.
        // Cap the map at the provider's supported detail level to avoid its
        // 'Zoom level not supported' tile placeholder covering the map.
        map.maximumZoomLevel = 7
        map.setCenter(coordinate, zoomLevel: 7.0, animated: false)
        context.coordinator.lastCoordinate = coordinate
        context.coordinator.latestImage = radarImage
        context.coordinator.latestTileURL = radarTileURL
        context.coordinator.latestCloudSamples = cloudSamples
        context.coordinator.cloudsVisible = showClouds
        context.coordinator.precipitationTypesVisible = showPrecipitationTypes
        context.coordinator.onRegionChange = onRegionChange
        context.coordinator.updateLocationMarker(on: map, coordinate: coordinate, title: locationTitle)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        // SMHI supplies a full-resolution national image, so allow closer inspection.
        // RainViewer tiles remain capped at the provider-supported zoom level.
        map.maximumZoomLevel = radarTileURL == nil ? 10 : 7
        context.coordinator.latestImage = radarImage
        context.coordinator.latestTileURL = radarTileURL
        context.coordinator.latestCloudSamples = cloudSamples
        context.coordinator.cloudsVisible = showClouds
        context.coordinator.precipitationTypesVisible = showPrecipitationTypes
        context.coordinator.onRegionChange = onRegionChange
        context.coordinator.updateLocationMarker(on: map, coordinate: coordinate, title: locationTitle)
        if let previous = context.coordinator.lastCoordinate,
           abs(previous.latitude - coordinate.latitude) > 0.001 ||
           abs(previous.longitude - coordinate.longitude) > 0.001 {
            context.coordinator.lastCoordinate = coordinate
            map.setCenter(coordinate, zoomLevel: max(map.zoomLevel, 7.0), animated: true)
        }
        context.coordinator.applyRadarIfReady()
        context.coordinator.applyCloudsIfReady()
        context.coordinator.applyPrecipitationTypesIfReady()
        // Deliberately do not recenter when GPS/model state changes.
        // The initial camera is set once in makeUIView; the location marker can move independently.
    }

    func makeCoordinator() -> Coordinator { Coordinator(onRegionChange: onRegionChange) }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var onRegionChange: (CLLocationCoordinate2D) -> Void
        init(onRegionChange: @escaping (CLLocationCoordinate2D) -> Void) {
            self.onRegionChange = onRegionChange
        }
        weak var mapView: MLNMapView?
        var latestImage: UIImage?
        var latestTileURL: String?
        var latestCloudSamples: [WindSample] = []
        var cloudsVisible = false
        var precipitationTypesVisible = false
        var lastCoordinate: CLLocationCoordinate2D?
        private var styleReady = false
        private var appliedIdentity: String?
        private var appliedCloudIdentity: String?
        private var appliedPrecipitationIdentity: String?
        private var locationMarker: MLNPointAnnotation?

        func updateLocationMarker(on map: MLNMapView, coordinate: CLLocationCoordinate2D, title: String) {
            if let marker = locationMarker {
                marker.coordinate = coordinate
                marker.title = title
            } else {
                let marker = MLNPointAnnotation()
                marker.coordinate = coordinate
                marker.title = title
                marker.subtitle = "Vald plats"
                locationMarker = marker
                map.addAnnotation(marker)
            }
        }

        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            guard annotation is MLNPointAnnotation else { return nil }
            let reuseIdentifier = "regnvakt-location-dot"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier)
                ?? MLNAnnotationView(reuseIdentifier: reuseIdentifier)
            view.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
            view.backgroundColor = UIColor(red: 0.18, green: 0.86, blue: 0.91, alpha: 1)
            view.layer.cornerRadius = 10
            view.layer.borderWidth = 3
            view.layer.borderColor = UIColor.white.cgColor
            view.layer.shadowColor = UIColor(red: 0.18, green: 0.86, blue: 0.91, alpha: 1).cgColor
            view.layer.shadowOpacity = 0.55
            view.layer.shadowRadius = 8
            view.layer.shadowOffset = .zero
            view.isEnabled = false
            view.centerOffset = .zero
            return view
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            onRegionChange(mapView.centerCoordinate)
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            self.mapView = mapView
            styleReady = true
            appliedIdentity = nil
            appliedCloudIdentity = nil
            appliedPrecipitationIdentity = nil
            applyRadarIfReady()
            applyCloudsIfReady()
            applyPrecipitationTypesIfReady()
        }

        func applyCloudsIfReady() {
            guard styleReady, let style = mapView?.style else { return }
            let identity = cloudsVisible
                ? latestCloudSamples.map { "\($0.id):\(String(format: "%.4f", $0.latitude)),\(String(format: "%.4f", $0.longitude)):\(Int($0.cloudCover.rounded()))" }.joined(separator: "|")
                : "hidden"
            guard identity != appliedCloudIdentity else { return }
            appliedCloudIdentity = identity

            let features: [MLNPointFeature] = latestCloudSamples.map { sample in
                let feature = MLNPointFeature()
                feature.coordinate = CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude)
                feature.attributes = ["cloudCover": NSNumber(value: sample.cloudCover)]
                return feature
            }
            let shape = MLNShapeCollectionFeature(shapes: features)
            let sourceID = "regnvakt-cloud-source"
            let source: MLNShapeSource
            if let existing = style.source(withIdentifier: sourceID) as? MLNShapeSource {
                existing.shape = shape
                source = existing
            } else {
                source = MLNShapeSource(identifier: sourceID, shape: shape, options: nil)
                style.addSource(source)
            }
            let layerID = "regnvakt-cloud-layer"
            if style.layer(withIdentifier: layerID) == nil {
                let layer = MLNCircleStyleLayer(identifier: layerID, source: source)
                // Small, geographically anchored points prevent the sampled
                // field from blending into one oversized blob.
                layer.circleColor = NSExpression(forConstantValue: UIColor(red: 0.38, green: 0.68, blue: 0.94, alpha: 1))
                layer.circleOpacity = NSExpression(format: "cloudCover / 100.0 * 0.22")
                // The samples are model grid points, not cloud-shaped polygons.
                // Keep their footprint restrained so the basemap remains readable.
                layer.circleRadius = NSExpression(forConstantValue: 8)
                layer.circleBlur = NSExpression(forConstantValue: 0.85)
                style.addLayer(layer)
            }
            if let layer = style.layer(withIdentifier: layerID) {
                layer.isVisible = cloudsVisible
            }
        }

        func applyPrecipitationTypesIfReady() {
            guard styleReady, let style = mapView?.style else { return }
            let identity = precipitationTypesVisible
                ? latestCloudSamples.map { "\($0.id):\(String(format: "%.4f", $0.latitude)),\(String(format: "%.4f", $0.longitude)):\($0.precipitationType):\(String(format: "%.2f", $0.precipitation))" }.joined(separator: "|")
                : "hidden"
            guard identity != appliedPrecipitationIdentity else { return }
            appliedPrecipitationIdentity = identity

            let definitions: [(name: String, type: Int, color: UIColor)] = [
                ("rain", 1, UIColor(red: 0.12, green: 0.56, blue: 0.98, alpha: 1)),
                ("snow", 2, UIColor(red: 0.82, green: 0.93, blue: 1.0, alpha: 1)),
                ("mixed", 3, UIColor(red: 0.72, green: 0.42, blue: 0.92, alpha: 1))
            ]
            for definition in definitions {
                let features: [MLNPointFeature] = latestCloudSamples.compactMap { sample in
                    guard sample.precipitationType == definition.type,
                          sample.precipitation >= 0.05 else { return nil }
                    let feature = MLNPointFeature()
                    feature.coordinate = CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude)
                    feature.attributes = ["precipitation": NSNumber(value: sample.precipitation)]
                    return feature
                }
                let sourceID = "regnvakt-precip-type-\(definition.name)-source"
                let layerID = "regnvakt-precip-type-\(definition.name)-layer"
                let shape = MLNShapeCollectionFeature(shapes: features)
                let source: MLNShapeSource
                if let existing = style.source(withIdentifier: sourceID) as? MLNShapeSource {
                    existing.shape = shape
                    source = existing
                } else {
                    source = MLNShapeSource(identifier: sourceID, shape: shape, options: nil)
                    style.addSource(source)
                }
                if style.layer(withIdentifier: layerID) == nil {
                    let layer = MLNCircleStyleLayer(identifier: layerID, source: source)
                    // Soft, geographically anchored forecast field instead of tiny isolated dots.
                    // These samples are model guidance, not classifications of radar pixels.
                    layer.circleColor = NSExpression(forConstantValue: definition.color)
                    layer.circleOpacity = NSExpression(forConstantValue: 0.46)
                    layer.circleRadius = NSExpression(forConstantValue: 20)
                    layer.circleBlur = NSExpression(forConstantValue: 0.88)
                    layer.circleStrokeColor = NSExpression(forConstantValue: definition.color.withAlphaComponent(0.18))
                    layer.circleStrokeWidth = NSExpression(forConstantValue: 1.0)
                    style.addLayer(layer)
                }
                if let layer = style.layer(withIdentifier: layerID) {
                    layer.isVisible = precipitationTypesVisible
                }
            }
        }

        func applyRadarIfReady() {
            guard styleReady, let style = mapView?.style else { return }
            let identity = latestImage.map { "smhi-\(ObjectIdentifier($0))" } ?? latestTileURL ?? "none"
            guard identity != appliedIdentity else { return }
            if let layer = style.layer(withIdentifier: "regnvakt-radar-layer") { style.removeLayer(layer) }
            if let source = style.source(withIdentifier: "regnvakt-radar-source") { style.removeSource(source) }
            appliedIdentity = identity

            if let image = latestImage {
                let source = MLNImageSource(
                    identifier: "regnvakt-radar-source",
                    coordinateQuad: SWEREF99.imageQuad,
                    image: image
                )
                let layer = MLNRasterStyleLayer(identifier: "regnvakt-radar-layer", source: source)
                layer.rasterOpacity = NSExpression(forConstantValue: 0.86)
                style.addSource(source)
                style.addLayer(layer)
            } else if let template = latestTileURL {
                let source = MLNRasterTileSource(
                    identifier: "regnvakt-radar-source",
                    tileURLTemplates: [template],
                    options: nil
                )
                let layer = MLNRasterStyleLayer(identifier: "regnvakt-radar-layer", source: source)
                layer.rasterOpacity = NSExpression(forConstantValue: 0.76)
                style.addSource(source)
                style.addLayer(layer)
            }
            applyCloudsIfReady()
            applyPrecipitationTypesIfReady()
        }
    }
}
