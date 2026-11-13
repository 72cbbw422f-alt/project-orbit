import SwiftUI
import MapKit
import Combine
import UIKit

private struct SMHIRadarFrame: Identifiable, Equatable {
    let timestamp: Date
    let url: URL
    var id: Date { timestamp }
}

private enum SMHIRadarService {
    static let directory = URL(string: "https://data-download.smhi.se/data/meteorology/radar/")!

    static func loadFrames() async throws -> [SMHIRadarFrame] {
        var request = URLRequest(url: directory)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            throw URLError(.badServerResponse)
        }

        let pattern = #"RADAR_SWE_EPSG3006_QCOMP_(\\d{12})\\.png"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(html.startIndex..., in: html)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmm"

        var found: [SMHIRadarFrame] = []
        for match in regex.matches(in: html, range: range) {
            guard let r = Range(match.range(at: 1), in: html) else { continue }
            let stamp = String(html[r])
            guard let date = formatter.date(from: stamp) else { continue }
            let name = "RADAR_SWE_EPSG3006_QCOMP_\\(stamp).png"
            found.append(SMHIRadarFrame(timestamp: date, url: directory.appendingPathComponent(name)))
        }
        let frames = Array(Dictionary(grouping: found, by: \\.timestamp).compactMap { $0.value.first }.sorted { $0.timestamp < $1.timestamp }.suffix(25))
        guard !frames.isEmpty else { throw URLError(.cannotParseResponse) }
        return frames
    }

    static func image(for frame: SMHIRadarFrame) async throws -> UIImage {
        var request = URLRequest(url: frame.url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
        return image
    }
}

// SMHI's PNG is georeferenced in SWEREF 99 TM (EPSG:3006).
// Convert the published image bounds to WGS84 for MapKit placement.
private enum SWEREF99 {
    static func toWGS84(easting: Double, northing: Double) -> CLLocationCoordinate2D {
        let a = 6378137.0
        let f = 1.0 / 298.257222101
        let k0 = 0.9996
        let e2 = f * (2 - f)
        let ep2 = e2 / (1 - e2)
        let n = f / (2 - f)
        let A = a / (1 + n) * (1 + pow(n, 2) / 4 + pow(n, 4) / 64)
        let beta1 = n / 2 - 2 * pow(n, 2) / 3 + 5 * pow(n, 3) / 16 + 41 * pow(n, 4) / 180
        let beta2 = 13 * pow(n, 2) / 48 - 3 * pow(n, 3) / 5 + 557 * pow(n, 4) / 1440
        let beta3 = 61 * pow(n, 3) / 240 - 103 * pow(n, 4) / 140
        let beta4 = 49561 * pow(n, 4) / 161280
        let xi = northing / (k0 * A)
        let eta = (easting - 500000) / (k0 * A)
        let xiPrime = xi - beta1 * sin(2 * xi) * cosh(2 * eta)
            - beta2 * sin(4 * xi) * cosh(4 * eta)
            - beta3 * sin(6 * xi) * cosh(6 * eta)
            - beta4 * sin(8 * xi) * cosh(8 * eta)
        let etaPrime = eta - beta1 * cos(2 * xi) * sinh(2 * eta)
            - beta2 * cos(4 * xi) * sinh(4 * eta)
            - beta3 * cos(6 * xi) * sinh(6 * eta)
            - beta4 * cos(8 * xi) * sinh(8 * eta)
        let sinhEta = sinh(etaPrime)
        let tauPrime = sin(xiPrime) / sqrt(sinhEta * sinhEta + cos(xiPrime) * cos(xiPrime))
        var tau = tauPrime
        for _ in 0..<5 {
            let sigma = sinh(eccentricityAtanh(tau * sqrt(e2)))
            let tauNew = tau * sqrt(1 + sigma * sigma) - sigma * sqrt(1 + tau * tau)
            if abs(tauNew - tau) < 1e-13 { tau = tauNew; break }
            tau = tauNew
        }
        let latitude = atan(tau)
        let longitude = atan2(sinhEta, cos(xiPrime)) + 15.0 * .pi / 180.0
        return CLLocationCoordinate2D(latitude: latitude * 180 / .pi, longitude: longitude * 180 / .pi)
    }

    private static func eccentricityAtanh(_ value: Double) -> Double {
        0.5 * log((1 + value) / (1 - value))
    }
}

private final class SMHIRasterOverlay: NSObject, MKOverlay {
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect
    let image: UIImage

    init(image: UIImage) {
        self.image = image
        let lowerLeft = SWEREF99.toWGS84(easting: 126648, northing: 5983984)
        let upperRight = SWEREF99.toWGS84(easting: 1075693, northing: 7771252)
        let corners = [
            MKMapPoint(lowerLeft),
            MKMapPoint(upperRight),
            MKMapPoint(SWEREF99.toWGS84(easting: 126648, northing: 7771252)),
            MKMapPoint(SWEREF99.toWGS84(easting: 1075693, northing: 5983984))
        ]
        let minX = corners.map(\\.x).min() ?? 0
        let maxX = corners.map(\\.x).max() ?? 0
        let minY = corners.map(\\.y).min() ?? 0
        let maxY = corners.map(\\.y).max() ?? 0
        boundingMapRect = MKMapRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        coordinate = CLLocationCoordinate2D(latitude: (lowerLeft.latitude + upperRight.latitude) / 2,
                                             longitude: (lowerLeft.longitude + upperRight.longitude) / 2)
        super.init()
    }
}

private final class SMHIRasterRenderer: MKOverlayRenderer {
    private let raster: SMHIRasterOverlay
    init(overlay: SMHIRasterOverlay) {
        raster = overlay
        super.init(overlay: overlay)
    }
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let rect = self.rect(for: raster.boundingMapRect)
        guard rect.intersects(self.rect(for: mapRect)), let cgImage = raster.image.cgImage else { return }
        context.saveGState()
        context.interpolationQuality = .high
        context.setAlpha(0.88)
        context.draw(cgImage, in: rect)
        context.restoreGState()
    }
}

struct RadarMapView: View {
    let coordinate: CLLocationCoordinate2D?
    let place: String

    @State private var frames: [SMHIRadarFrame] = []
    @State private var selectedIndex = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastUpdated: Date?
    @State private var isPlaying = false
    @State private var mapView: MKMapView?
    @State private var precipitationType = "Hämtar nederbördstyp…"
    @State private var typeDetail = "Modellbedömning vid vald plats"
    @State private var showTypeInfo = false

    private let playback = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

    private var mapCoordinate: CLLocationCoordinate2D {
        let value = coordinate ?? CLLocationCoordinate2D(latitude: 61.7274, longitude: 17.1058)
        return CLLocationCoordinate2D(
            latitude: value.latitude.isFinite ? min(85, max(-85, value.latitude)) : 61.7274,
            longitude: value.longitude.isFinite ? min(180, max(-180, value.longitude)) : 17.1058
        )
    }

    private var selectedFrame: SMHIRadarFrame? {
        frames.indices.contains(selectedIndex) ? frames[selectedIndex] : nil
    }

    var body: some View {
        ZStack {
            Color(red: 0.008, green: 0.025, blue: 0.055).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("NEDERBÖRDSRADAR")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text(place.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(.cyan)
                    }
                    Spacer()
                    Button { Task { await refreshRadar() } } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.cyan)
                            .padding(10)
                            .background(.white.opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel("Uppdatera radarn")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)

                SMHIMapView(coordinate: mapCoordinate, image: selectedImage)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 9) {
                    HStack(spacing: 7) {
                        Circle().fill(frames.isEmpty ? .orange : .cyan).frame(width: 7, height: 7)
                        Text(frames.isEmpty ? "RADAR" : "SMHI QCOMP • 5 MIN")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(0.8)
                            .foregroundStyle(.white)
                        Spacer()
                        Text("Källa: SMHI")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }

                    HStack(spacing: 8) {
                        Image(systemName: precipitationSymbol)
                            .foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(precipitationType)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                            Text(typeDetail)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.white.opacity(0.62))
                        }
                        Spacer()
                        Button { showTypeInfo = true } label: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.cyan)
                        }
                        .accessibilityLabel("Information om nederbördstyp")
                    }
                    .padding(9)
                    .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))

                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView().tint(.cyan)
                            Text("Hämtar SMHI-radar…")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    } else if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let selectedFrame {
                        HStack {
                            Text(selectedFrame.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Spacer()
                            Text("SENASTE 2 TIMMARNA")
                                .font(.system(size: 8, weight: .heavy))
                                .tracking(0.7)
                                .foregroundStyle(.cyan)
                        }
                        Slider(value: Binding(
                            get: { Double(selectedIndex) },
                            set: { selectedIndex = Int($0.rounded()) }
                        ), in: 0...Double(max(0, frames.count - 1)), step: 1)
                        .tint(.cyan)
                        .disabled(frames.count < 2)
                        HStack(spacing: 14) {
                            Button { selectedIndex = max(0, selectedIndex - 1) } label: {
                                Image(systemName: "backward.end.fill")
                            }
                            Button { isPlaying.toggle() } label: {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .frame(width: 40, height: 40)
                                    .background(Color.cyan.opacity(0.18), in: Circle())
                            }
                            Button { selectedIndex = min(frames.count - 1, selectedIndex + 1) } label: {
                                Image(systemName: "forward.end.fill")
                            }
                            Spacer()
                            if let lastUpdated {
                                Text("Uppdaterad \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.cyan)
                    }

                    HStack {
                        Text("SMHI • SWEREF 99 TM")
                        Spacer()
                        Text("Observerad radar")
                    }
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                }
                .padding(13)
                .background(Color(red: 0.015, green: 0.075, blue: 0.13).opacity(0.95), in: RoundedRectangle(cornerRadius: 18))
                .padding(10)
            }
        }
        .task {
            await refreshRadar()
            await refreshPrecipitationType()
        }
        .onChange(of: selectedIndex) { _, _ in
            Task { await loadSelectedImage() }
        }
        .onReceive(playback) { _ in
            guard isPlaying, !frames.isEmpty else { return }
            selectedIndex = selectedIndex >= frames.count - 1 ? 0 : selectedIndex + 1
        }
        .alert("Om nederbördstyp", isPresented: $showTypeInfo) {
            Button("Stäng", role: .cancel) {}
        } message: {
            Text("Radarkartan från SMHI visar nederbördsintensitet. Typen vid din valda plats hämtas separat från en vädermodell och är en bedömning – inte en direkt klassificering av varje radar-pixel.")
        }
    }

    @State private var selectedImage: UIImage?

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
            frames = try await SMHIRadarService.loadFrames()
            selectedIndex = frames.count - 1
            await loadSelectedImage()
            lastUpdated = Date()
        } catch {
            errorMessage = "SMHI:s radarbilder kunde inte hämtas just nu."
        }
        isLoading = false
    }

    @MainActor
    private func loadSelectedImage() async {
        guard let frame = selectedFrame else { return }
        do {
            selectedImage = try await SMHIRadarService.image(for: frame)
        } catch {
            errorMessage = "Kunde inte läsa vald radartid från SMHI."
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

private struct SMHIMapView: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    let image: UIImage?

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.mapType = .mutedStandard
        map.overrideUserInterfaceStyle = .dark
        map.showsCompass = true
        map.showsScale = true
        map.pointOfInterestFilter = .excludingAll
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.setRegion(MKCoordinateRegion(center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2)), animated: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        if context.coordinator.lastImage !== image {
            context.coordinator.lastImage = image
            map.removeOverlays(map.overlays.filter { $0 is SMHIRasterOverlay })
            if let image { map.addOverlay(SMHIRasterOverlay(image: image), level: .aboveLabels) }
        }
        let old = context.coordinator.lastCoordinate
        if old == nil || abs(old!.latitude - coordinate.latitude) > 0.001 ||
            abs(old!.longitude - coordinate.longitude) > 0.001 {
            context.coordinator.lastCoordinate = coordinate
            map.setRegion(MKCoordinateRegion(center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2)), animated: false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var lastImage: UIImage?
        var lastCoordinate: CLLocationCoordinate2D?
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let raster = overlay as? SMHIRasterOverlay { return SMHIRasterRenderer(overlay: raster) }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
