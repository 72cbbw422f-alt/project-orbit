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

    static func loadFrames() async throws -> (String, RadarProvider, [RadarFrame]) {
        if let smhi = try? await loadSMHIFrames(), !smhi.isEmpty {
            return ("", .smhi, smhi)
        }
        let (host, frames) = try await loadRainViewerFrames()
        return (host, .rainViewer, frames)
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
        guard !recent.isEmpty else { throw URLError(.cannotParseResponse) }
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
}

private enum WindLayer: String, CaseIterable {
    case speed = "Vind"
    case gust = "Byvind"
}

private struct WindFieldOverlay: View {
    let samples: [WindSample]
    let show: Bool
    let gustMode: Bool

    private func tint(_ speed: Double) -> Color {
        switch speed {
        case ..<4: return Color(red: 0.25, green: 0.82, blue: 0.96)
        case ..<8: return Color(red: 0.20, green: 0.88, blue: 0.56)
        case ..<12: return Color(red: 1.0, green: 0.82, blue: 0.18)
        case ..<17: return Color(red: 1.0, green: 0.48, blue: 0.18)
        default: return Color(red: 0.98, green: 0.20, blue: 0.28)
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !show || samples.count < 9)) { timeline in
            Canvas { context, size in
                guard show, samples.count >= 9 else { return }

                func vector(at point: CGPoint) -> (u: Double, v: Double, speed: Double) {
                    var total = 0.0
                    var u = 0.0
                    var v = 0.0
                    var speed = 0.0
                    for sample in samples {
                        let sx = 0.5 + (sample.longitude - samples[samples.count / 2].longitude) / 0.90
                        let sy = 0.5 - (sample.latitude - samples[samples.count / 2].latitude) / 0.80
                        let dx = Double(point.x / max(size.width, 1)) - sx
                        let dy = Double(point.y / max(size.height, 1)) - sy
                        let weight = 1.0 / max(dx * dx + dy * dy, 0.0025)
                        let magnitude = gustMode ? sample.gust : sample.speed
                        let radians = (sample.direction + 180) * .pi / 180
                        u += -sin(radians) * magnitude * weight
                        v += cos(radians) * magnitude * weight
                        speed += magnitude * weight
                        total += weight
                    }
                    return (u / total, v / total, speed / total)
                }

                let now = timeline.date.timeIntervalSinceReferenceDate
                let particleCount = 420
                for index in 0..<particleCount {
                    // Deterministic pseudo-random seed points; particles drift continuously
                    // through the interpolated Open-Meteo wind field and then respawn.
                    let seedX = CGFloat((index * 73 + 19) % 997) / 997.0
                    let seedY = CGFloat((index * 193 + 47) % 991) / 991.0
                    let seed = CGPoint(x: seedX * size.width, y: seedY * size.height)
                    let duration = 5.2 + Double(index % 9) * 0.48
                    let phase = (now / duration + Double(index) * 0.137).truncatingRemainder(dividingBy: 1.0)
                    let progress = phase * 42.0
                    let steps = Int(progress)
                    let remainder = progress - Double(steps)
                    var point = seed
                    var trail: [CGPoint] = [seed]
                    var localSpeed = 0.0

                    for _ in 0..<steps {
                        let field = vector(at: point)
                        localSpeed = field.speed
                        let magnitude = max(0.1, hypot(field.u, field.v))
                        let step = min(6.5, max(2.8, magnitude * 0.48))
                        point = CGPoint(
                            x: point.x + CGFloat(field.u / magnitude) * step,
                            y: point.y - CGFloat(field.v / magnitude) * step
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
                    if trail.count > 1 {
                        let first = max(0, trail.count - 22)
                        for segment in first..<trail.count - 1 {
                            var path = Path()
                            path.move(to: trail[segment])
                            path.addLine(to: trail[segment + 1])
                            let opacity = Double(segment - first + 1) / Double(trail.count - first)
                            context.stroke(path, with: .color(color.opacity(0.12 + opacity * 0.58)),
                                           style: StrokeStyle(lineWidth: 1.2 + opacity * 1.5, lineCap: .round))
                        }
                    }
                    let radius: CGFloat = 1.25 + CGFloat(min(localSpeed, 20)) * 0.055
                    let particle = Path(ellipseIn: CGRect(x: head.x - radius, y: head.y - radius,
                                                          width: radius * 2, height: radius * 2))
                    context.fill(particle, with: .color(color.opacity(0.98)))
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
    @State private var isLoading = false
    @State private var errorMessage: String?
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
    @State private var windStatus = "Hämtar vindfält…"
    @State private var windUpdated: Date?

    private let playback = Timer.publish(every: 0.75, on: .main, in: .common).autoconnect()

    private var mapCoordinate: CLLocationCoordinate2D {
        let value = coordinate ?? CLLocationCoordinate2D(latitude: 61.7274, longitude: 17.1058)
        return CLLocationCoordinate2D(
            latitude: value.latitude.isFinite ? min(85, max(-85, value.latitude)) : 61.7274,
            longitude: value.longitude.isFinite ? min(180, max(-180, value.longitude)) : 17.1058
        )
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
                        onRegionChange: { center in
                            windMapCenter = center
                            if showWind {
                                Task { await refreshWindField(center: center) }
                            }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    WindFieldOverlay(samples: windSamples, show: showWind, gustMode: windLayer == .gust)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    HStack(spacing: 7) {
                        Circle().fill(Color(red: 0.35, green: 0.88, blue: 0.83)).frame(width: 7, height: 7)
                        Text(showWind ? "VIND • OPEN-METEO" : "RADAR • \(provider.rawValue.uppercased())")
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
                .frame(height: 300)

                VStack(spacing: 13) {
                    HStack(spacing: 10) {
                        Button {
                            showWind = false
                            showRadar = true
                        } label: {
                            Label("Regn", systemImage: "cloud.rain.fill")
                                .font(.system(size: 15, weight: .bold))
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .foregroundStyle(!showWind ? Color(red: 0.10, green: 0.13, blue: 0.17) : .white)
                                .background(!showWind ? Color(red: 0.98, green: 0.62, blue: 0.43) : Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                                .overlay(RoundedRectangle(cornerRadius: 13).stroke(!showWind ? Color.white.opacity(0.35) : Color.white.opacity(0.16), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        Button {
                            showWind = true
                            showRadar = false
                            if windSamples.isEmpty { Task { await refreshWindField() } }
                        } label: {
                            Label("Vind", systemImage: "wind")
                                .font(.system(size: 15, weight: .bold))
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .foregroundStyle(showWind ? Color(red: 0.05, green: 0.12, blue: 0.15) : .white)
                                .background(showWind ? Color.cyan : Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                                .overlay(RoundedRectangle(cornerRadius: 13).stroke(showWind ? Color.white.opacity(0.38) : Color.white.opacity(0.16), lineWidth: 1))
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
                            if let sample = windSamples.first(where: { $0.id == 4 }) {
                                Text("\(windLayer == .gust ? "Byvind" : "Vind") vid \(place): \(String(format: "%.1f", windLayer == .gust ? sample.gust : sample.speed)) m/s • \(Int(sample.direction.rounded()))°")
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
                    if !showWind {
                    HStack(spacing: 9) {
                        Image(systemName: precipitationSymbol)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(Color(red: 0.98, green: 0.58, blue: 0.40))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(precipitationType).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                            Text(typeDetail).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.68))
                            Text(radarAtPlace).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(red: 0.35, green: 0.88, blue: 0.83))
                        }
                        Spacer()
                        Button { showTypeInfo = true } label: {
                            Image(systemName: "info.circle").font(.system(size: 19)).foregroundStyle(Color(red: 0.98, green: 0.58, blue: 0.40))
                        }
                    }
                    .padding(12)
                    .background(Color(red: 0.12, green: 0.16, blue: 0.21), in: RoundedRectangle(cornerRadius: 15))
                    }


                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView().tint(.cyan)
                            Text("Hämtar radarobservationer…")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    } else if let errorMessage {
                        Text(errorMessage).font(.system(size: 12, weight: .medium)).foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !showWind {
                    if let selectedFrame {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("VALD RADARTID").font(.system(size: 12, weight: .heavy)).tracking(1).foregroundStyle(Color.cyan)
                                Text(selectedFrame.time.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(.white)
                            }
                            Spacer()
                            Text("SENASTE 2 TIMMARNA").font(.system(size: 12, weight: .heavy)).tracking(0.8).foregroundStyle(.white.opacity(0.6))
                        }
                        Slider(value: Binding(
                            get: { Double(selectedIndex) },
                            set: { selectedIndex = Int($0.rounded()) }
                        ), in: 0...Double(max(0, frames.count - 1)), step: 1)
                        .tint(Color(red: 0.98, green: 0.58, blue: 0.40))
                        .disabled(frames.count < 2)
                        HStack(spacing: 18) {
                            Button { selectedIndex = max(0, selectedIndex - 1) } label: { Image(systemName: "backward.end.fill").font(.system(size: 17)) }
                            Button { isPlaying.toggle() } label: {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(Color(red: 0.07, green: 0.10, blue: 0.14))
                                    .frame(width: 48, height: 48)
                                    .background(Color(red: 0.98, green: 0.66, blue: 0.47), in: Circle())
                            }
                            Button { selectedIndex = min(frames.count - 1, selectedIndex + 1) } label: { Image(systemName: "forward.end.fill").font(.system(size: 17)) }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("UPPDATERAD").font(.system(size: 12, weight: .heavy)).tracking(0.8).foregroundStyle(.white.opacity(0.48))
                                Text(lastUpdated?.formatted(date: .omitted, time: .shortened) ?? "—")
                                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                            }
                        }
                        .foregroundStyle(Color(red: 0.98, green: 0.66, blue: 0.47))
                    } else {
                        Text("Radarhistorik visas här när data har hämtats.")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                        if !nowcastPoints.isEmpty {
                            HStack(alignment: .bottom, spacing: 5) {
                                ForEach(nowcastPoints.prefix(6)) { point in
                                    VStack(spacing: 2) {
                                        Text(String(format: "%.1f", point.precipitationRate ?? 0))
                                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                                            .foregroundStyle(.white)
                                        Capsule()
                                            .fill(Color.cyan.opacity(0.9))
                                            .frame(maxWidth: 38)
                                            .frame(height: max(3, min(30, CGFloat(point.precipitationRate ?? 0) * 18)))
                                        Text(point.time.formatted(date: .omitted, time: .shortened))
                                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                            .foregroundStyle(.white.opacity(0.82))
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

                    }

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
        .onReceive(playback) { _ in
            guard isPlaying, !frames.isEmpty else { return }
            selectedIndex = selectedIndex >= frames.count - 1 ? 0 : selectedIndex + 1
        }
        .alert("Om nederbördstyp", isPresented: $showTypeInfo) {
            Button("Stäng", role: .cancel) {}
        } message: {
            Text("Radarn visar observerad nederbörd. SMHI används i första hand. RainViewer används som reserv om SMHI:s radarflöde inte är tillgängligt. Nederbördstypen hämtas separat från en vädermodell och är en bedömning, inte en direkt klassificering av varje radar-pixel.")
        }
    }

    private var precipitationSymbol: String {
        let text = precipitationType.lowercased()
        if text.contains("snö") { return "cloud.snow.fill" }
        if text.contains("hagel") { return "cloud.hail.fill" }
        if text.contains("regn") { return "cloud.rain.fill" }
        return "cloud.fill"
    }

    @MainActor
    private func refreshRadar() async {
        guard !isLoading else { return }
        isLoading = true
        isPlaying = false
        errorMessage = nil
        do {
            let result = try await RadarService.loadFrames()
            radarHost = result.0
            provider = result.1
            frames = result.2
            selectedIndex = frames.count - 1
            await loadSelectedImage()
            await refreshRadarAtPlace()
            lastUpdated = Date()
        } catch {
            frames = []
            selectedImage = nil
            errorMessage = "Varken SMHI eller reservradarn kunde nås. Kontrollera anslutningen och försök igen."
        }
        isLoading = false
    }

    @MainActor
    private func loadSelectedImage() async {
        guard let frame = selectedFrame else { selectedImage = nil; return }
        guard frame.provider == .smhi else { selectedImage = nil; return }
        do {
            selectedImage = try await RadarService.loadImage(for: frame)
            errorMessage = nil
        } catch {
            selectedImage = nil
            errorMessage = "SMHI-bilden kunde inte hämtas. Försöker använda reservradarn."
            do {
                let (host, fallback) = try await RadarService.loadRainViewerFrames()
                radarHost = host
                provider = .rainViewer
                frames = fallback
                selectedIndex = max(0, frames.count - 1)
                errorMessage = nil
                await refreshRadarAtPlace()
            } catch {
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
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
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
            precipitationType = Self.precipitationName(code: code, temperature: temp)
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
        windStatus = "Hämtar vinddata över området…"
        let center = requestedCenter ?? windMapCenter ?? mapCoordinate
        windMapCenter = center
        let grid = [-0.40, -0.20, 0.0, 0.20, 0.40]
        let offsets: [(Double, Double)] = grid.flatMap { lat in
            grid.map { lon in (lat, lon) }
        }
        var results: [WindSample] = []
        await withTaskGroup(of: WindSample?.self) { group in
            for (index, offset) in offsets.enumerated() {
                let lat = center.latitude + offset.0
                let lon = center.longitude + offset.1
                group.addTask {
                    var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
                    components.queryItems = [
                        URLQueryItem(name: "latitude", value: String(lat)),
                        URLQueryItem(name: "longitude", value: String(lon)),
                        URLQueryItem(name: "current", value: "wind_speed_10m,wind_direction_10m,wind_gusts_10m"),
                        URLQueryItem(name: "wind_speed_unit", value: "ms"),
                        URLQueryItem(name: "timezone", value: "auto")
                    ]
                    guard let url = components.url,
                          let (data, response) = try? await URLSession.shared.data(from: url),
                          (response as? HTTPURLResponse)?.statusCode == 200,
                          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let current = root["current"] as? [String: Any],
                          let speed = (current["wind_speed_10m"] as? NSNumber)?.doubleValue,
                          let direction = (current["wind_direction_10m"] as? NSNumber)?.doubleValue,
                          let gust = (current["wind_gusts_10m"] as? NSNumber)?.doubleValue else { return nil }
                    return WindSample(id: index, latitude: lat, longitude: lon, speed: speed, direction: direction, gust: gust)
                }
            }
            for await sample in group { if let sample { results.append(sample) } }
        }
        windSamples = results.sorted { $0.id < $1.id }
        windUpdated = Date()
        windStatus = results.count == offsets.count
            ? "Vindfält • 25 modellpunkter runt \(place)"
            : "Vindfält delvis tillgängligt • \(results.count) av 25 punkter"
    }

    private static func precipitationName(code: Int, temperature: Double) -> String {
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
        context.coordinator.onRegionChange = onRegionChange
        context.coordinator.updateLocationMarker(on: map, coordinate: coordinate, title: locationTitle)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.latestImage = radarImage
        context.coordinator.latestTileURL = radarTileURL
        context.coordinator.updateLocationMarker(on: map, coordinate: coordinate, title: locationTitle)
        context.coordinator.applyRadarIfReady()
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
        var lastCoordinate: CLLocationCoordinate2D?
        private var styleReady = false
        private var appliedIdentity: String?
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
            applyRadarIfReady()
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
        }
    }
}
