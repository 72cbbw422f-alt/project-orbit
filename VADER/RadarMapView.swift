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
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("REGNVAKT")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .tracking(2.2)
                            .foregroundStyle(Color(red: 0.98, green: 0.58, blue: 0.40))
                        Text("Nederbördsradar")
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(place)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    Spacer()
                    Button { showRadar.toggle() } label: {
                        Image(systemName: showRadar ? "cloud.rain.fill" : "cloud")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(showRadar ? Color(red: 0.98, green: 0.58, blue: 0.40) : .white.opacity(0.75))
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.09), in: Circle())
                    }
                    .accessibilityLabel(showRadar ? "Dölj radar" : "Visa radar")
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
                        locationTitle: place
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    HStack(spacing: 7) {
                        Circle().fill(Color(red: 0.35, green: 0.88, blue: 0.83)).frame(width: 7, height: 7)
                        Text("RADAR • \(provider.rawValue.uppercased())")
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 13) {
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
                    VStack(alignment: .leading, spacing: 9) {
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
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.78))
                        if !nowcastPoints.isEmpty {
                            HStack(alignment: .bottom, spacing: 5) {
                                ForEach(nowcastPoints.prefix(8)) { point in
                                    VStack(spacing: 4) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.cyan.opacity(0.85))
                                            .frame(height: max(4, min(28, CGFloat(point.precipitationRate ?? 0) * 12)))
                                        Text(point.time.formatted(date: .omitted, time: .shortened))
                                            .font(.system(size: 9, weight: .medium).monospacedDigit())
                                            .foregroundStyle(.white.opacity(0.65))
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
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
        }
        .task {
            await refreshRadar()
            await refreshPrecipitationType()
            await refreshNowcast()
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
                nowcastStatus = "Radarbaserad korttidsprognos. Staplarna visar nederbördsintensitet (mm/h)."
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
        context.coordinator.latestImage = radarImage
        context.coordinator.latestTileURL = radarTileURL
        context.coordinator.updateLocationMarker(on: map, coordinate: coordinate, title: locationTitle)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.latestImage = radarImage
        context.coordinator.latestTileURL = radarTileURL
        context.coordinator.updateLocationMarker(on: map, coordinate: coordinate, title: locationTitle)
        context.coordinator.applyRadarIfReady()
        let previous = context.coordinator.lastCoordinate
        if previous == nil || abs(previous!.latitude - coordinate.latitude) > 0.001 ||
            abs(previous!.longitude - coordinate.longitude) > 0.001 {
            context.coordinator.lastCoordinate = coordinate
            map.setCenter(coordinate, zoomLevel: min(max(map.zoomLevel, 7.0), 7.0), animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MLNMapViewDelegate {
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
