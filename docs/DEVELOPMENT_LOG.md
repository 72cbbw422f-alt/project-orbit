# Regnvakt – utvecklingslogg

Senast uppdaterad: 2026-11-16  
Arbetsgren: `feature/frost-notification-audit`

Det här dokumentet är projektets löpande tekniska logg. Uppdatera det vid varje relevant ändring, byggfel, verifiering och användartest. Skilj alltid på sådant som är **byggt**, **kompilerat**, **testat på enhet** och **ännu inte verifierat**.

## Projektmål och ramar

- Native iOS-väderapp byggd med SwiftUI.
- Ska fungera för platser i hela Sverige, inte enbart Hudiksvall.
- Byggs med XcodeGen och GitHub Actions på macOS-runner.
- CI producerar en osignerad IPA. Den kan inte installeras direkt på iPhone utan giltig signering och provisioning profile.
- Utvecklingsmiljö: användaren saknar för närvarande Mac och Apple Developer-konto; test sker via PC och sideload/signering där det är möjligt.
- Ingen XCTest-/UI-testsvit är för närvarande etablerad. En grön CI-build bekräftar kompilering och paketering, inte att alla funktioner fungerar på fysisk iPhone.
- Appens befintliga appikon ska bevaras. Inga demo-/låtsasdata ska introduceras.

## Användarrapporterade problem

Följande problem har rapporterats vid test och ska följas tills de verifierats lösta på enheten:

1. Frostnotiser kommer dubbelt eller upprepas.
2. Notiser upplevs komma endast när appen är öppen.
3. Molnlagret visas som en stor sammanhängande klump och upplevs flytta sig med kartan.
4. Nederbördslagret blinkar eller försvinner tillfälligt.
5. Nederbördstyp behöver vara tydligare än enbart färg.
6. Förklarings-/legendkortet längst ned tar onödigt mycket plats.
7. Radartidslinjens reglage ligger för långt ned; användaren tappar kartkontext när hen behöver scrolla.
8. Tidigare rapporter omfattade även problem med avstånd/safe-area högst upp på skärmen.

## Ändringar i build #379

**GitHub Actions:** [Build #379](https://github.com/72cbbw422f-alt/project-orbit/actions/runs/43917457956)  
**Run ID:** `43917457956`  
**Commit:** `68c6e4c00962fb50afdf3bb1aa5a0ad7f6d8458e`  
**Status:** Slutförd med resultat `success` den 2026-11-16.

### Radar och kartlager

- Radarkartans höjd ändrades från 430 till 340 punkter.
- Tidslinjens kontroller flyttades till direkt under kartan.
- Den tidigare tidslinjesektionen längre ned togs bort.
- Nederbördslegendens symboler byttes till tydligare SF Symbols.
- Molnlagret använder en beständig MapLibre-shapekälla som uppdateras i stället för att tas bort och skapas om vid varje uppdatering.
- Molnprover förankras vid provens geografiska koordinater; punktstorlek, opacitet och oskärpa reducerades.
- Regn, snö och blandad nederbörd har separata källor/lager med tydligare markörer, vit kontur och lägre oskärpa.
- Identiteter för moln- och nederbördsdata används för att undvika onödiga lageruppdateringar.

### Frostnotiser

- Prognoshorisonten för notisschemaläggning utökades från 6 till 24 timmar.
- Prognosbaserad frostnotis använder datumstämpel per lokal kalenderdag i stället för timstämpel, för att minska upprepningar under samma dag.
- Inkorgsvyn fick deduplicering av levererade respektive väntande frostnotiser.

### Kompileringsfel och korrigeringar under arbetet

- Build #375 misslyckades efter ändringar kring bakgrundsuppdatering och projektkonfiguration.
- Ett extra avslutande klammerparentes i `RadarMapView.swift` korrigerades.
- En bakgrundsprognosfunktion som anropade en tjänst/metod som inte fanns i projektets aktuella API togs bort.
- Registrering och konfiguration för den ofärdiga bakgrundsuppdateringen togs bort.
- En fristående `VADER/Info.plist` lades till under felsökningen men används inte av den nuvarande projektkonfigurationen; kontrollera och städa bort den om den inte behövs.
- Build #379 slutfördes därefter med lyckad CI-kompilering och paketering.

## Viktig teknisk begränsning: notiser när appen är stängd

- En redan schemalagd lokal iOS-notis kan levereras även när appen är stängd.
- Appen har i nuläget **inte** en fungerande implementering av schemalagd bakgrundshämtning av prognoser. Försöket togs bort eftersom det använde en inkompatibel/otillgänglig service-hook.
- iOS Background App Refresh är dessutom best-effort och kan inte garantera att appkod körs vid en exakt tid.
- Därför måste prognosen hämtas och lokala notiser schemaläggas medan appen har möjlighet att köra. Kontrollera när prognosuppdatering och notisschemaläggning sker, samt hur många väntande notiser som faktiskt finns.
- Påstå inte att notiserna fungerar i stängt läge förrän det verifierats med väntande lokala notiser på en fysisk iPhone.

## Status efter build #379

### Byggt och CI-verifierat
- Radarvyns tidslinje har flyttats.
- Kartlagrens uppdateringsstrategi har ändrats.
- Frostnotisernas datumidentitet och inkorgens grundläggande deduplicering har ändrats.
- CI-build #379 är grön.

### Inte verifierat på fysisk enhet
- Att molnlagret nu ser geografiskt korrekt ut och inte upplevs som en enda stor klump.
- Att nederbördslagret inte längre blinkar.
- Att regn/snö/blandat är tillräckligt tydligt.
- Att tidslinjens nya placering fungerar bra på olika iPhone-skärmstorlekar.
- Att frostnotiser inte längre dubbleras i alla kombinationer av aktuell temperatur, prognos, väntande notiser och redan levererade notiser.
- Att lokala notiser faktiskt levereras när appen är stängd.

## Frostfix – uppföljning efter build #380

**Utgångsläge:** Build #380 slutfördes med resultat `success` den 2026-11-16. Den bekräftar kompilering och paketering av dokumentationsändringen, inte enhetstest.

### Rotorsak som hittats i koden

- Aktuell frost och prognosfrost hade olika notis-ID:n: `.frost.current.yyyyMMdd` respektive `.frost.yyyyMMdd`.
- Prognosens dagsmängd startade tom även när aktuell frost redan var aktiv. Samma plats och dag kunde därför ge både en omedelbar notis och en prognosnotis.
- När aktuell temperatur blev inaktuell kunde en redan schemalagd aktuell frostnotis bevaras samtidigt som prognosnotisen återskapades.
- Inkorgens tidigare deduplicering använde två separata mängder för levererade respektive väntande notiser. Samma frostvarning kunde därför synas i båda avsnitten.
- Dessutom var interpoleringen i dedupliceringsnyckeln felaktigt escapad i Swift-strängen, så nyckeln riskerade att bli en bokstavlig sträng i stället för plats och dag.

### Ändringar genomförda

- `WeatherNotificationScheduler.swift`: dagens lokala kalenderdag markeras som redan täckt av frost när aktuell frost är aktiv **eller** när en aktuell frostnotis redan har schemalagts för dagen. Prognosloopen skapar då inte en andra frostnotis för samma dag.
- Kommentar om prognoshorisonten uppdaterades så att den inte felaktigt anger sex timmar.
- `NotificationInboxView.swift`: levererade och väntande notiser använder nu en gemensam dedupliceringsmängd. Levererad notis prioriteras framför väntande notis för samma plats/dag.
- Frostnyckeln använder korrekt Swift-interpolering.

### Commits

- `7dcfca4d0fdb4bd67a974f0236a0e78e06f606aa` – schemaläggningslogik.
- `6fc3435f0a008e06345d039a7fd6dedfb5a0c770` – inkorgens gemensamma deduplicering.

### Verifieringsstatus

- Källkod uppdaterad på `feature/frost-notification-audit`.
- CI för dessa ändringar inväntar körning/slutresultat.
- Inte testat på fysisk iPhone ännu. Testa särskilt: aktuell temperatur under frostgränsen, inaktuell temperatur med redan schemalagd aktuell frostnotis, prognosfrost senare samma dag samt kombinationen levererad + väntande notis.
- Kontrollera att olika bevakade platser fortfarande får separata notiser; dedupliceringen ska endast gälla samma plats och lokala kalenderdag.

## Nästa åtgärder

1. Granska frostlogiken så att aktuell frost och prognosfrost för samma plats och kalenderdag inte kan skapa två notiser med olika identifierare.
2. Dela en gemensam dedupliceringsmängd mellan levererade och väntande frostnotiser i inkorgen, så att samma plats/dag inte visas två gånger.
3. Granska hur väntande lokala notiser bevaras och ersätts när prognosen uppdateras.
4. Spåra hela flödet från prognoshämtning till `UNUserNotificationCenter.add`; lägg gärna till diagnostik för senaste schemaläggning och antal väntande notiser.
5. Testa molnlagrets geografiska förankring, täthet och beteende vid panorering/zoom.
6. Testa nederbördslagren för blinkning och uppdateringsstabilitet.
7. Testa tidslinjen och layouten på fysisk iPhone.
8. Dokumentera varje test med enhet/iOS-version, steg, förväntat resultat, faktiskt resultat och eventuell skärmbild/logg.

## Arbetsregel för kommande ändringar

Varje arbetsomgång ska dokumentera:
- datum och berörd version/build,
- berörda filer och tekniska ändringar,
- användarrapporterade buggar,
- rotorsak när den är känd (annars markera som hypotes),
- bygg-/kompileringsresultat,
- enhetstester och manuella tester separat,
- kvarstående risker och nästa steg.

Ändra inte status från “byggt” till “löst” förrän relevant funktion har verifierats. En lyckad CI-build är inte samma sak som ett godkänt användartest.
