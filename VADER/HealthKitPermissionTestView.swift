import SwiftUI
import HealthKit

/// A user-initiated runtime check for the HealthKit entitlement and read path.
/// Apple intentionally does not reveal whether read access was denied; a returned
/// sample is positive proof, while an empty result is explicitly treated as inconclusive.
struct HealthKitPermissionTestView: View {
    @State private var isTesting = false
    @State private var resultText = "Inte testat på den här enheten ännu."
    @State private var resultIsPositive = false

    private let healthStore = HKHealthStore()
    private let cyan = Color(red: 0.04, green: 0.78, blue: 0.98)
    private let muted = Color(red: 0.69, green: 0.78, blue: 0.88)
    private let panel = Color(red: 0.015, green: 0.075, blue: 0.13).opacity(0.94)
    private let line = Color(red: 0.18, green: 0.52, blue: 0.72).opacity(0.48)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("BEHÖRIGHETSKONTROLL", systemImage: "checkmark.shield.fill")
                .font(.system(size: 12, weight: .heavy)).tracking(1).foregroundStyle(cyan)
            Text("HealthKit")
                .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            Text("Kontrollerar att HealthKit är tillgängligt, begär läsbehörighet för steg och provar sedan att läsa en datapost från Apple Hälsa.")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await runHealthKitTest() }
            } label: {
                HStack {
                    Image(systemName: "heart.text.square")
                    Text(isTesting ? "Kontrollerar HealthKit…" : "Testa HealthKit-behörighet")
                    Spacer()
                    if isTesting { ProgressView().tint(cyan) }
                }
                .font(.system(size: 12, weight: .bold)).foregroundStyle(cyan)
                .padding(12).background(cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isTesting)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: resultIsPositive ? "checkmark.circle.fill" : "info.circle")
                    .foregroundStyle(resultIsPositive ? Color.green : cyan)
                Text(resultText)
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Obs: Apple visar inte appar om användaren uttryckligen nekat läsning. En hittad datapost bekräftar läsåtkomst; ett tomt resultat är därför inte ett säkert bevis på nekad behörighet.")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(muted.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(line, lineWidth: 1))
    }

    @MainActor
    private func runHealthKitTest() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            resultIsPositive = false
            resultText = "HealthKit är inte tillgängligt på den här enheten."
            return
        }
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            resultIsPositive = false
            resultText = "Kunde inte skapa HealthKit-typen för steg."
            return
        }

        isTesting = true
        defer { isTesting = false }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                healthStore.requestAuthorization(toShare: [], read: [stepType]) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: NSError(
                            domain: "Regnvakt.HealthKit",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "iOS kunde inte slutföra HealthKit-begäran."]
                        ))
                    }
                }
            }

            let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
            let sample: HKQuantitySample? = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: stepType,
                    predicate: predicate,
                    limit: 1,
                    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
                ) { _, samples, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: samples?.first as? HKQuantitySample)
                    }
                }
                healthStore.execute(query)
            }

            if let sample {
                let count = Int(sample.quantity.doubleValue(for: .count()).rounded())
                resultIsPositive = true
                resultText = "HealthKit fungerar och Regnvakt kunde läsa en stegd datapost: \(count) steg, \(sample.endDate.formatted(date: .abbreviated, time: .shortened))."
            } else {
                resultIsPositive = false
                resultText = "HealthKit svarade och behörighetsbegäran slutfördes, men ingen stegd datapost hittades de senaste 7 dagarna. Resultatet är inte entydigt – kontrollera Apple Hälsa och försök igen."
            }
        } catch {
            resultIsPositive = false
            resultText = "HealthKit-testet misslyckades: \(error.localizedDescription)"
        }
    }
}
