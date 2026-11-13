import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @AppStorage("Regnvakt.notifications.enabled") private var notificationsEnabled = true
    @AppStorage("Regnvakt.notifications.rain") private var rainEnabled = true
    @AppStorage("Regnvakt.notifications.snow") private var snowEnabled = true
    @AppStorage("Regnvakt.notifications.wind") private var windEnabled = true
    @AppStorage("Regnvakt.notifications.thunder") private var thunderEnabled = true
    @AppStorage("Regnvakt.notifications.frost") private var frostEnabled = true
    @AppStorage("Regnvakt.notifications.smhi") private var smhiEnabled = true
    @AppStorage("Regnvakt.notifications.leadMinutes") private var leadMinutes = 30
    @AppStorage("Regnvakt.notifications.quietHours") private var quietHours = "22–07"
    @State private var permissionStatus = "Kontrollerar behörighet…"
    @State private var requestingPermission = false
    @State private var testNotificationMessage = ""

    private let cyan = Color(red: 0.04, green: 0.78, blue: 0.98)
    private let muted = Color(red: 0.69, green: 0.78, blue: 0.88)
    private let panel = Color(red: 0.015, green: 0.075, blue: 0.13).opacity(0.94)
    private let line = Color(red: 0.18, green: 0.52, blue: 0.72).opacity(0.48)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("AVISERINGAR").font(.system(size: 25, weight: .black, design: .rounded)).foregroundStyle(.white)
                    Text("Styr när Regnvakt ska uppmärksamma dig på väderförändringar.")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(muted)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Balanserad profil", systemImage: "bell.badge.fill")
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        Spacer()
                        Text("REKOMMENDERAD").font(.system(size: 8, weight: .heavy)).tracking(0.6).foregroundStyle(cyan)
                    }
                    Text("Relevanta förvarningar, tydliga riskökningar och officiella varningar – utan upprepade notiser om samma händelse.")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                    Toggle("Aktivera aviseringar", isOn: $notificationsEnabled).tint(cyan)
                }
                .padding(14).background(panel, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(line, lineWidth: 1))

                VStack(alignment: .leading, spacing: 12) {
                    Text("VÄLJ VÄDERVAKTER").font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(cyan)
                    watchToggle("Regnvakten", subtitle: "Regn, skurar och kraftig nederbörd", icon: "cloud.rain.fill", value: $rainEnabled)
                    Divider().overlay(line)
                    watchToggle("Snövakten", subtitle: "Snöfall, blötsnö och halka", icon: "cloud.snow.fill", value: $snowEnabled)
                    Divider().overlay(line)
                    watchToggle("Vindvakten", subtitle: "Hård vind och kraftiga vindbyar", icon: "wind", value: $windEnabled)
                    Divider().overlay(line)
                    watchToggle("Åskvakten", subtitle: "Åska och blixtaktivitet", icon: "cloud.bolt.rain.fill", value: $thunderEnabled)
                    Divider().overlay(line)
                    watchToggle("Frostvakten", subtitle: "Frost, minusgrader och halkrisk", icon: "thermometer.snowflake", value: $frostEnabled)
                    Divider().overlay(line)
                    watchToggle("SMHI-varningar", subtitle: "Nya och ändrade officiella varningar", icon: "exclamationmark.triangle.fill", value: $smhiEnabled)
                }
                .padding(14).background(panel, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(line, lineWidth: 1))

                VStack(alignment: .leading, spacing: 12) {
                    Text("FÖRVARNING").font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(cyan)
                    Text("När en händelse väntas närma sig")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(muted)
                    Picker("Förvarning", selection: $leadMinutes) {
                        Text("15 minuter").tag(15)
                        Text("30 minuter").tag(30)
                        Text("60 minuter").tag(60)
                    }.pickerStyle(.segmented).tint(cyan)
                    Divider().overlay(line)
                    Text("TYSTA TIMMAR").font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(cyan)
                    Picker("Tysta timmar", selection: $quietHours) {
                        Text("22:00–07:00").tag("22–07")
                        Text("23:00–06:00").tag("23–06")
                        Text("Av").tag("none")
                    }.pickerStyle(.menu).tint(cyan)
                }
                .padding(14).background(panel, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(line, lineWidth: 1))

                VStack(alignment: .leading, spacing: 9) {
                    Text("IPHONE-AVISERINGAR").font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(cyan)
                    Text(permissionStatus).font(.system(size: 11, weight: .medium)).foregroundStyle(muted)
                    Button {
                        requestNotificationPermission()
                    } label: {
                        HStack {
                            Image(systemName: "bell.badge")
                            Text(requestingPermission ? "Begär behörighet…" : "Aktivera i iPhone")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(cyan)
                        .padding(12).background(cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(requestingPermission)

                    Button {
                        sendTestNotification()
                    } label: {
                        Label("Skicka testavisering", systemImage: "paperplane.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    }
                    if !testNotificationMessage.isEmpty {
                        Text(testNotificationMessage)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(muted)
                    }
                }
                .padding(14).background(panel, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(line, lineWidth: 1))

                Text("Inställningarna sparas på den här enheten. Ändringar schemalägger om kommande lokala aviseringar från senast hämtade prognos. Frost- och halkvarningar kan skickas även under tysta timmar. iOS kan begränsa bakgrundsuppdateringar, så öppna appen regelbundet för att hålla prognosen aktuell.")
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(muted.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 3)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 14)
            .padding(.top, 22)
        }
        .background(Color(red: 0.008, green: 0.025, blue: 0.055).ignoresSafeArea())
        .task { await refreshPermissionStatus() }
        .onChange(of: notificationsEnabled) { _, _ in WeatherNotificationScheduler.refreshFromStoredForecast() }
        .onChange(of: rainEnabled) { _, _ in WeatherNotificationScheduler.refreshFromStoredForecast() }
        .onChange(of: snowEnabled) { _, _ in WeatherNotificationScheduler.refreshFromStoredForecast() }
        .onChange(of: windEnabled) { _, _ in WeatherNotificationScheduler.refreshFromStoredForecast() }
        .onChange(of: thunderEnabled) { _, _ in WeatherNotificationScheduler.refreshFromStoredForecast() }
        .onChange(of: frostEnabled) { _, _ in WeatherNotificationScheduler.refreshFromStoredForecast() }
        .onChange(of: leadMinutes) { _, _ in WeatherNotificationScheduler.refreshFromStoredForecast() }
        .onChange(of: quietHours) { _, _ in WeatherNotificationScheduler.refreshFromStoredForecast() }
    }

    private func watchToggle(_ title: String, subtitle: String, icon: String, value: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(cyan).frame(width: 25)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 9, weight: .medium)).foregroundStyle(muted)
            }
            Spacer(minLength: 4)
            Toggle(title, isOn: value).labelsHidden().tint(cyan)
        }
    }

    @MainActor
    private func refreshPermissionStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: permissionStatus = "Aviseringar är tillåtna i iPhone."
        case .denied: permissionStatus = "Aviseringar är blockerade. Ändra behörigheten i iPhone-inställningarna."
        case .notDetermined: permissionStatus = "iPhone har ännu inte fått frågan om aviseringar."
        @unknown default: permissionStatus = "Kunde inte läsa aviseringsbehörigheten."
        }
    }

    private func sendTestNotification() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized ||
                  settings.authorizationStatus == .provisional ||
                  settings.authorizationStatus == .ephemeral else {
                Task { @MainActor in
                    testNotificationMessage = "Testet kunde inte skickas: aviseringar är inte tillåtna i iPhone."
                }
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "Regnvakt fungerar"
            content.body = "Det här är en testavisering. Om du ser den fungerar iPhones lokala notiskanal."
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "regnvakt.test.\(UUID().uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            )
            UNUserNotificationCenter.current().add(request) { error in
                Task { @MainActor in
                    testNotificationMessage = error == nil
                        ? "Testavisering schemalagd. Den ska visas inom cirka 5 sekunder."
                        : "Kunde inte schemalägga testaviseringen: \(error!.localizedDescription)"
                }
            }
        }
    }

    private func requestNotificationPermission() {
        requestingPermission = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            Task { @MainActor in
                await refreshPermissionStatus()
                requestingPermission = false
            }
        }
    }
}
