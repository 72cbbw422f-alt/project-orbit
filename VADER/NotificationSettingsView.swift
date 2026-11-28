import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    var refreshSMHIWarnings: () -> Void = {}
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
    @State private var pendingWeatherSummary = ""
    @AppStorage("Regnvakt.notifications.scheduleStatus") private var scheduleStatus = "Kontrollerar schemaläggning…"
    @AppStorage("Regnvakt.notifications.scheduledCount") private var scheduledCount = 0
    @AppStorage("Regnvakt.notifications.scheduleUpdated") private var scheduleUpdatedTimestamp = 0.0
    @AppStorage("Regnvakt.backgroundRefresh.status") private var backgroundRefreshStatus = "Ingen bakgrundskörning registrerad"
    @AppStorage("Regnvakt.backgroundRefresh.startedAt") private var backgroundRefreshStartedAt = 0.0
    @AppStorage("Regnvakt.backgroundRefresh.completedAt") private var backgroundRefreshCompletedAt = 0.0
    @AppStorage("Regnvakt.backgroundRefresh.earliestAt") private var backgroundRefreshEarliestAt = 0.0
    @AppStorage("Regnvakt.backgroundRefresh.placeCount") private var backgroundRefreshPlaceCount = 0
    @AppStorage("Regnvakt.backgroundRefresh.successCount") private var backgroundRefreshSuccessCount = 0
    @AppStorage("Regnvakt.backgroundRefresh.failureCount") private var backgroundRefreshFailureCount = 0
    @AppStorage("Regnvakt.backgroundRefresh.skippedCount") private var backgroundRefreshSkippedCount = 0
    @AppStorage("Regnvakt.backgroundRefresh.lastSuccessAt") private var backgroundRefreshLastSuccessAt = 0.0
    @AppStorage("Regnvakt.backgroundRefresh.diagnostic") private var backgroundRefreshDiagnostic = ""
    @AppStorage("Regnvakt.backgroundRefresh.durationSeconds") private var backgroundRefreshDuration = 0.0

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
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(muted)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Balanserad profil", systemImage: "bell.badge.fill")
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        Spacer()
                        Text("REKOMMENDERAD").font(.system(size: 12, weight: .heavy)).tracking(0.6).foregroundStyle(cyan)
                    }
                    Text("Relevanta förvarningar, tydliga riskökningar och officiella varningar – utan upprepade notiser om samma händelse.")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                    Toggle("Aktivera aviseringar", isOn: $notificationsEnabled).tint(cyan)
                }
                .padding(14).background(panel, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(line, lineWidth: 1))

                VStack(alignment: .leading, spacing: 12) {
                    Text("VÄLJ VÄDERVAKTER").font(.system(size: 12, weight: .heavy)).tracking(1).foregroundStyle(cyan)
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
                    Text("FÖRVARNING").font(.system(size: 12, weight: .heavy)).tracking(1).foregroundStyle(cyan)
                    Text("När en händelse väntas närma sig")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(muted)
                    Picker("Förvarning", selection: $leadMinutes) {
                        Text("15 minuter").tag(15)
                        Text("30 minuter").tag(30)
                        Text("60 minuter").tag(60)
                    }.pickerStyle(.segmented).tint(cyan)
                    Divider().overlay(line)
                    Text("TYSTA TIMMAR").font(.system(size: 12, weight: .heavy)).tracking(1).foregroundStyle(cyan)
                    Picker("Tysta timmar", selection: $quietHours) {
                        Text("22:00–07:00").tag("22–07")
                        Text("23:00–06:00").tag("23–06")
                        Text("Av").tag("none")
                    }.pickerStyle(.menu).tint(cyan)
                }
                .padding(14).background(panel, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(line, lineWidth: 1))

                VStack(alignment: .leading, spacing: 9) {
                    Text("IPHONE-AVISERINGAR").font(.system(size: 12, weight: .heavy)).tracking(1).foregroundStyle(cyan)
                    Text(permissionStatus).font(.system(size: 12, weight: .medium)).foregroundStyle(muted)
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
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(muted)
                    }
                    Divider().overlay(line)
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: scheduledCount > 0 ? "bell.badge.fill" : "bell.slash")
                            .foregroundStyle(scheduledCount > 0 ? cyan : muted)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SCHEMALAGDA VÄDERAVISERINGAR")
                                .font(.system(size: 11, weight: .heavy)).tracking(0.7).foregroundStyle(cyan)
                            Text(scheduleStatus)
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(scheduledCount) väntande i iPhone" + (scheduleUpdatedTimestamp <= 0 ? "" : " • Kontrollerat \(Date(timeIntervalSince1970: scheduleUpdatedTimestamp).formatted(date: .omitted, time: .shortened))"))
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(muted)
                            if !pendingWeatherSummary.isEmpty {
                                Text(pendingWeatherSummary)
                                    .font(.system(size: 11, weight: .medium)).foregroundStyle(muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    Divider().overlay(line)
                    VStack(alignment: .leading, spacing: 5) {
                        Label("BAKGRUNDSUPPDATERING", systemImage: "arrow.clockwise.circle")
                            .font(.system(size: 11, weight: .heavy)).tracking(0.7).foregroundStyle(cyan)
                        Text(backgroundRefreshStatus)
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        if backgroundRefreshStartedAt > 0 {
                            Text("Senast startad: \(Date(timeIntervalSince1970: backgroundRefreshStartedAt).formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(muted)
                        } else {
                            Text("Ingen körning har registrerats ännu.")
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(muted)
                        }
                        if backgroundRefreshCompletedAt > 0 {
                            Text("Senast avslutad: \(Date(timeIntervalSince1970: backgroundRefreshCompletedAt).formatted(date: .omitted, time: .shortened))")
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(muted)
                        }
                        if backgroundRefreshEarliestAt > 0 {
                            Text("Nästa begärda tidigaste körning: \(Date(timeIntervalSince1970: backgroundRefreshEarliestAt).formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(muted)
                        }
                        Text("\(backgroundRefreshSuccessCount) av \(backgroundRefreshPlaceCount) platser uppdaterade • \(backgroundRefreshFailureCount) fel • \(backgroundRefreshSkippedCount) överhoppade")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(muted)
                        if backgroundRefreshLastSuccessAt > 0 {
                            Text("Senaste lyckade hämtning: \(Date(timeIntervalSince1970: backgroundRefreshLastSuccessAt).formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(muted)
                        }
                        if !backgroundRefreshDiagnostic.isEmpty {
                            Text(backgroundRefreshDiagnostic)
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(muted.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if backgroundRefreshDuration > 0 {
                            Text("Körtid: \(backgroundRefreshDuration, specifier: "%.1f") sekunder")
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(muted)
                        }
                        Text("iOS bestämmer när begäran faktiskt körs. Den angivna tiden är inte en garanti.")
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(muted.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14).background(panel, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(line, lineWidth: 1))

                LocationPermissionTestView()

                Text("Inställningarna sparas på den här enheten. Ändringar schemalägger om kommande lokala aviseringar från senast hämtade prognos. Frost- och halkvarningar kan skickas även under tysta timmar. iOS kan begränsa bakgrundsuppdateringar, så öppna appen regelbundet för att hålla prognosen aktuell.")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(muted.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 3)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 14)
            .padding(.top, 22)
        }
        .background(Color(red: 0.008, green: 0.025, blue: 0.055).ignoresSafeArea())
        .task {
            await refreshPermissionStatus()
            await refreshPendingWeatherNotifications()
        }
        .onChange(of: notificationsEnabled) { _, enabled in
            if !enabled {
                SMHIWarningService.clearPendingNotifications()
            } else {
                SMHIWarningService.notificationsReenabled()
                refreshSMHIWarnings()
            }
            WeatherNotificationScheduler.refreshFromStoredForecast()
        }
        .onChange(of: rainEnabled) { _, _ in WeatherNotificationScheduler.refreshFromStoredForecast() }
        .onChange(of: snowEnabled) { _, _ in WeatherNotificationScheduler.refreshFromStoredForecast() }
        .onChange(of: windEnabled) { _, _ in WeatherNotificationScheduler.refreshFromStoredForecast() }
        .onChange(of: thunderEnabled) { _, _ in WeatherNotificationScheduler.refreshFromStoredForecast() }
        .onChange(of: frostEnabled) { _, _ in WeatherNotificationScheduler.refreshFromStoredForecast() }
        .onChange(of: smhiEnabled) { _, enabled in
            if !enabled { SMHIWarningService.clearPendingNotifications() }
            else {
                SMHIWarningService.notificationsReenabled()
                WeatherNotificationScheduler.refreshFromStoredForecast()
                refreshSMHIWarnings()
            }
        }
        .onChange(of: leadMinutes) { _, _ in WeatherNotificationScheduler.refreshFromStoredForecast() }
        .onChange(of: quietHours) { _, _ in WeatherNotificationScheduler.refreshFromStoredForecast() }
    }

    private func watchToggle(_ title: String, subtitle: String, icon: String, value: Binding<Bool>) -> some View {
        let isEnabled = notificationsEnabled && value.wrappedValue
        let activeGreen = Color(red: 0.24, green: 0.66, blue: 0.43)
        return HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isEnabled ? activeGreen : cyan)
                .frame(width: 25)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 12, weight: .medium)).foregroundStyle(muted)
            }
            Spacer(minLength: 4)
            Circle()
                .fill(isEnabled ? activeGreen : muted.opacity(0.35))
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Toggle(title, isOn: value).labelsHidden().tint(isEnabled ? activeGreen : cyan)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            isEnabled ? Color(red: 0.035, green: 0.105, blue: 0.078) : .clear,
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isEnabled ? activeGreen.opacity(0.34) : .clear, lineWidth: 1)
        )
    }

    @MainActor
    private func refreshPendingWeatherNotifications() async {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let weatherRequests = requests.filter { $0.identifier.hasPrefix("regnvakt.weather.") }
        let upcomingWeatherRequests = weatherRequests.compactMap { request -> (Date, String)? in
            let fireDate: Date?
            if let calendarTrigger = request.trigger as? UNCalendarNotificationTrigger {
                fireDate = calendarTrigger.nextTriggerDate()
            } else if let intervalTrigger = request.trigger as? UNTimeIntervalNotificationTrigger {
                fireDate = intervalTrigger.nextTriggerDate()
            } else {
                fireDate = nil
            }
            guard let fireDate else { return nil }
            return (fireDate, request.content.title)
        }
        .sorted { $0.0 < $1.0 }

        // Keep the real request count separate from the subset whose trigger
        // date can be rendered. Most importantly, do not overwrite the
        // scheduler's diagnostic outcome with a generic UI status on view load.
        scheduledCount = weatherRequests.count
        scheduleUpdatedTimestamp = Date().timeIntervalSince1970
        if upcomingWeatherRequests.isEmpty {
            pendingWeatherSummary = weatherRequests.isEmpty
                ? ""
                : "Det finns väntande vädernotiser, men iOS gav inget visningsbart nästa klockslag."
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "sv_SE")
            formatter.timeZone = TimeZone(identifier: "Europe/Stockholm")
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            pendingWeatherSummary = upcomingWeatherRequests.prefix(5).map { item in
                "\(formatter.string(from: item.0)) • \(item.1)"
            }.joined(separator: "\n")
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
            // The test must be visible even while Regnvakt is foregrounded.
            // Routine weather alerts remain intentionally suppressed in the foreground.
            content.userInfo = ["watch": "test", "safetyCritical": true]
            let request = UNNotificationRequest(
                identifier: "regnvakt.test.\(UUID().uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 15, repeats: false)
            )
            UNUserNotificationCenter.current().add(request) { error in
                Task { @MainActor in
                    testNotificationMessage = error == nil
                        ? "Testavisering schemalagd om 15 sekunder. Gå till hemskärmen direkt för att testa leverans när appen är i bakgrunden."
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
                WeatherNotificationScheduler.refreshFromStoredForecast()
                requestingPermission = false
            }
        }
    }
}
