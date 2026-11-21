import SwiftUI
import CoreLocation

/// Device-side diagnostic for the location permission used by local weather.
struct LocationPermissionTestView: View {
    @StateObject private var diagnostic = LocationPermissionDiagnostic()
    private let cyan = Color(red: 0.04, green: 0.78, blue: 0.98)
    private let muted = Color(red: 0.69, green: 0.78, blue: 0.88)
    private let panel = Color(red: 0.015, green: 0.075, blue: 0.13).opacity(0.94)
    private let line = Color(red: 0.18, green: 0.52, blue: 0.72).opacity(0.48)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("PLATSTJÄNSTER", systemImage: "location.circle.fill")
                .font(.system(size: 12, weight: .heavy)).tracking(1).foregroundStyle(cyan)
            Text("Testa platsbehörighet")
                .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            Text("Kontrollerar om Regnvakt får använda iPhones position för lokalt väder. Testet hämtar position först efter att du tryckt på knappen.")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
            Text(diagnostic.statusText)
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            if !diagnostic.coordinateText.isEmpty {
                Text(diagnostic.coordinateText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(muted)
            }
            Button {
                diagnostic.runTest()
            } label: {
                HStack {
                    Image(systemName: "location.fill")
                    Text(diagnostic.isChecking ? "Hämtar position…" : "Testa platsbehörighet")
                    Spacer()
                    if diagnostic.isChecking { ProgressView().tint(cyan) }
                }
                .font(.system(size: 12, weight: .bold)).foregroundStyle(cyan)
                .padding(12).background(cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            }
            .disabled(diagnostic.isChecking)
            Text("Positionen används bara för testet och visas lokalt i appen.")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(muted.opacity(0.8))
        }
        .padding(14)
        .background(panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(line, lineWidth: 1))
    }
}

@MainActor
private final class LocationPermissionDiagnostic: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var statusText = "Inte testat på den här enheten ännu."
    @Published var coordinateText = ""
    @Published var isChecking = false
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func runTest() {
        guard CLLocationManager.locationServicesEnabled() else {
            statusText = "Platstjänster är avstängda på iPhone. Aktivera dem i Inställningar."
            return
        }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            statusText = "Platsbehörighet är tillåten. Hämtar en aktuell position…"
            isChecking = true
            manager.requestLocation()
        case .notDetermined:
            statusText = "iPhone frågar nu om Regnvakt får använda platsen."
            manager.requestWhenInUseAuthorization()
        case .denied:
            statusText = "Platsbehörighet är nekad. Ändra den under iPhone-inställningar."
        case .restricted:
            statusText = "Platsåtkomst är begränsad på den här enheten."
        @unknown default:
            statusText = "Kunde inte läsa av platsbehörigheten."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus == .authorizedAlways ||
              manager.authorizationStatus == .authorizedWhenInUse else { return }
        statusText = "Platsbehörighet beviljad. Hämtar en aktuell position…"
        isChecking = true
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            isChecking = false
            statusText = "iPhone returnerade ingen position."
            return
        }
        coordinateText = String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude)
        statusText = "Godkänt: Regnvakt kunde läsa en position från iPhone."
        isChecking = false
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        statusText = "Behörigheten kan vara tillåten, men positionshämtningen misslyckades: \(error.localizedDescription)"
        isChecking = false
    }
}
