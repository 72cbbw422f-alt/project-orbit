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

## Statusfärger för vädervakter och startsidans riskindikator – 2026-11-16

### Genomförda kodändringar

- VaktView.swift: vädervakternas kort har nu neutral bakgrund i stället för att hela kortet färgas grönt när bevakningen är aktiverad.
- Aktiverad/avstängd bevakning visas separat från prognosrisk: grön status betyder att bevakningen är på, grå betyder avstängd och orange visar upptäckt risk.
- En officiell röd SMHI-varning får röd riskstatus. Övriga prognosrisker visas orange; en vanlig prognosrisk får alltså inte felaktigt samma allvarlighetsfärg som en röd myndighetsvarning.
- En kompakt förklaring har lagts till under bevakningskorten med betydelsen av grönt, orange, rött och grått. Den förklarar också att en aktiverad bevakning inte betyder att en risk redan har upptäckts.
- ContentView.swift: startsidan har fått en diskret statusrad med färgprick och kort text. Den visar röd vid officiell röd SMHI-varning, orange vid upptäckt risk, grön när tillgänglig prognos inte visar någon av de kontrollerade riskerna och döljs när timprognos saknas.
- Statusraden är tryckbar och öppnar fliken Vädervakter.

### Viktig teknisk notering

- Startsidan räknar för närvarande ut riskindikatorn separat från VaktDashboard. De viktigaste trösklarna används, men riskberäkningen är ännu inte extraherad till en gemensam regelmotor. Nästa kodgranskning bör samla logiken så att startsidan och bevakningskorten aldrig kan visa motstridiga riskbedömningar.
- Färgerna beskriver två olika dimensioner: om bevakningen är aktiverad och om prognosen visar risk. Därför kan en avstängd bevakning fortfarande visa en separat orange riskmarkering.

### Verifieringsstatus

- Build #383 (43939629418) för föregående frostfix och dokumentation slutfördes med success.
- De nya statusfärgerna och startsidans indikator har committats efter build #383. Ny CI-build måste verifieras innan ändringarna betraktas som kompilerade.
- Inte testat på fysisk iPhone. Kontrollera särskilt att statusraden inte tränger undan plats-/väderinformationen, att tryck navigerar till Vädervakter, att röd endast används för röd SMHI-varning och att risk/status visas korrekt när en bevakning är avstängd.

## Gemensam regelmotor för riskbedömning – 2026-11-16

### Ändring

- WeatherModels.swift: infört WeatherRiskAssessment.evaluate(...) som gemensam källa för riskerna regn, snö, åska, vind, frost/halkrisk och officiell SMHI-varning.
- Samma sex timmars prognoshorisont och samma nederbörds-, vind- och frosttrösklar används nu av startsidans statusindikator, Vädervakternas kort och sammanfattningen på startsidan.
- Röd status härleds centralt och används endast när en aktiv officiell SMHI-varning har röd nivå. Övriga upptäckta risker ger orange status.
- Startsidan döljer indikatorn om det saknas timprognosdata, så frånvaro av data inte misstas för grönt/lugnt väder.
- Vädervakternas detaljerade förklaringar behålls; själva riskbeslutet kommer från den gemensamma bedömningen.

### Kvarstående granskning

- Kontrollera att SMHI:s lagrade nivåvärden konsekvent innehåller igenkännbara nivånamn (röd/red, orange etc.).
- Kontrollera trösklarna mot aviseringsmotorn och säkerställ att bevakningskort, startsidesammanfattning och notisschemaläggning inte driver isär.
- Frost/halkriskens förklarande text beräknas fortfarande lokalt i VaktView, medan själva riskflaggan kommer från den gemensamma regelmotorn. Nästa refaktor bör låta även detaljorsaken komma från samma bedömningsresultat.

### Verifieringsstatus

- Kod och dokumentation uppdaterade på feature/frost-notification-audit.
- CI för den samlade regelmotorändringen ska verifieras separat.
- Ingen fysisk iPhone-testning genomförd ännu.
- Testfall: regn på gränsvärde, snö på gränsvärde, vind/byvind på gränsvärde, frost dag/natt, fukt nära nollgradigt, aktiv SMHI-varning med röd nivå, annan SMHI-varning, tom timprognos och risk när respektive bevakning är avstängd.

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


## Frostbedömning och notifieringsregler – uppföljning 2026-11-16

- Build #394 (run 43949248526, commit 49bcb79c832513261add6f62af61daacdec51d1d) slutfördes med `success`: gemensam riskmotor kompilerar och osignerad IPA paketerades.
- Frostvakten använde tidigare samma beräkningsmönster i både `WeatherRiskAssessment` och `VaktDashboard`, men detaljkortet räknade ut första frostdygnet och fukt nära noll separat. Detaljvärdena flyttas nu till resultatet från riskbedömningen så att status och förklaring har samma källa.
- Aviseringsmotorn använder samma risktrösklar för regn (40 % eller 0,3 mm), snö (40 % eller 0,2 mm), vind (15 m/s byvind eller 11 m/s medelvind), åska och frost (1 °C nattetid, 0 °C dagtid). Notiserna har avsiktligt 24 timmars horisont medan skärmens sammanfattning använder 6 timmar; det är en skillnad i framförhållning, inte i tröskelvärden.
- Halknotisen har ett separat säkerhetsvillkor: fukt/nederbörd nu eller inom tre prognostimmar, alternativt underkyld nederbörd. Detta motsvarar riskmotorns halkbedömning, med notifieringens övergångs-/dedupliceringslogik ovanpå.
- Fysisk enhetstestning återstår. Verifiera särskilt att detaljtexten för frost/halkrisk överensstämmer med statusen och att aviseringar inom 24 timmar inte ger falska förväntningar om att samma risk måste visas i 6-timmarssammanfattningen.


## CI-fel och korrigering – 2026-11-17

- Build #397 (`43950797835`) nådde Swift-kompileringen men misslyckades i `VADER/WeatherModels.swift:101` eftersom den tidigare lokala variabeln `wetNearFreeze` hade ersatts av `wetNearFreezeHour`, medan returvärdet fortfarande refererade till den borttagna variabeln.
- Korrigerat frostflaggan så att den använder `wetNearFreezeHour != nil`. Det behåller den avsedda gemensamma riskbedömningen och tar bort kompileringsfelet.
- Ny CI-byggning behöver verifiera korrigeringen. Ingen fysisk enhetstestning är utförd.


## Prognosdatakvalitet och tidszonssäkring – 2026-11-17

- Open-Meteo-hämtningen avvisar nu svar där obligatoriska aktuella mätvärden saknas/är ogiltiga eller där någon av de sex timvisa riskserierna är kortare än tidsserien. Saknade värden får inte längre tyst bli 0 och därmed se ut som vindstilla eller nederbördsfritt väder.
- Dagliga prognosserier valideras mot antal datum innan de visas; ofullständiga dagsvärden ska inte fyllas med nollor.
- Starttimmen avrundas i API-platsens tidszon. Riskbedömning, vaktfilter och notifieringsschema tolkar prognosernas lokala tidsstämplar med Europe/Stockholm, vilket är rätt tidszon för appens svenska orter även om telefonen befinner sig i en annan tidszon.
- Notisschemaläggaren sorterar timprognosen kronologiskt och halkans tre-timmarsfönster kräver nu ett tidsavstånd mellan 0 och 3 timmar; en timme i fel ordning kan inte längre räknas som framtida fukt.
- Detta är kodgranskning och defensiv validering, inte bevis på API-tillgänglighet eller fysisk enhetstest. Vid ofullständigt Open-Meteo-svar visas hämtningsfel i stället för en falskt lugn prognos; tidigare cache kan fortfarande finnas kvar och statusen måste därför läsas tillsammans med senaste uppdatering.

### Återstående verifiering

- Granska SMHI-tjänstens geografiska täckning och felhantering separat; koordinatbaserad kontroll av vald/bevakad plats är inte samma sak som en nationell varningsöversikt.
- Lägg till testbar risklogik/testmål och kör gränsvärdestester för regn, snö, vind, frost och halka.
- Fysisk iPhone-testning av radar, notiser, behörigheter, bakgrundsbeteende och layout återstår.


## Vädervakter, nederbördstyp och radarfokus – 2026-11-17

- Användartest på iPhone visade upprepade frost-/halkkort med samma riskbeskrivning men olika prognostider (bl.a. 17:00 och 20:00). Detta är förenligt med att halkrisken kan försvinna en prognostimme och sedan återkomma; den tidigare övergångsdetekteringen kunde då skapa en ny avisering.
- Gemensam prognoshorisont ändrad till 8 timmar för både skärmens riskbedömning och lokala prognosaviseringar (WeatherWatchRules).
- Notisschemaläggaren deduplicerar nu per risktyp över hela åttatimmarsfönstret. En risktyp ger högst en prognosavisering per plats och schemaläggningsomgång, även om timserien har korta luckor. Aktuell frostnotis förblir separat och säkerhetskritisk.
- Molnlagret har tagits bort från de synliga radarkontrollerna. Fokus ligger på nederbördsradar, vind och nederbördstyp.
- Korrigerat klassificeringsfel i Open-Meteo-fältet: väderkoderna 80–82 (regnskurar) räknades tidigare in i snöintervallet 71–86. Snö klassificeras nu med 71–77 och 85–86; 80–82 går till regn.
- Nederbördstypens kartpunkter är fortsatt modellbedömningar från Open-Meteo, inte en direkt klassificering av radarbildens pixlar. Blandad nederbörd kräver samtidig regn-/skur- och snöindikering i modellvärdena.
- Radarproblemet är INTE verifierat löst. Senaste iPhone-bilden visar RainViewer som aktiv reservkälla; separat test av SMHI-bildhämtning, RainViewer-rasterlager, kartpositionering och bildruteväxling återstår.
- Kodändringar: WeatherModels.swift, WeatherNotificationScheduler.swift, RadarMapView.swift.
- Commitkedja: 80679b2 (8 h horisonter), 3f4f1cb (deduplicering), 8b22c5c (molnkontroll bort + korrigerad nederbördstyp).
- CI och ny IPA inväntar verifiering. Fysisk iPhone-testning återstår.

- 2026-11-17 uppdaterades platsens aktuella nederbördstext till att även läsa Open-Meteos `rain`, `showers` och `snowfall`. Mängderna prioriteras framför generell väderkod för att kunna skilja regn, snö och blandad nederbörd; WMO-kod används som reserv när mängderna är noll. Detta är fortfarande en modellbedömning, inte radar-pixelklassificering. Kompilering av denna senaste ändring återstår.

- Nederbördsikonen följer nu även den nya klassificeringen: blandad nederbörd får slask-/blandikon och duggregn får egen symbol.


## Tidszonssäkring för prognosaviseringar – 2026-11-17

- WeatherNotificationScheduler.swift använder nu Europe/Stockholm konsekvent för frost-dagens jämförelse, datumstämpel i notis-ID, alertDay-metadata och kalenderkomponenterna som skickas till UNCalendarNotificationTrigger.
- NotificationInboxView.swift använder samma svenska kalenderdygn när frostnotiser dedupliceras mellan levererade och väntande aviseringar.
- Syftet är att en svensk prognosplats ska behålla samma lokala kalenderdag och aviseringsklockslag även om telefonens systemtidszon är en annan.
- Kodändringarna är committade men ännu inte CI-kompilerade eller testade på fysisk iPhone. Kontrollera särskilt övergången över svensk midnatt, vinter-/sommartid och enhet med annan systemtidszon.


## SMHI-datumvalidering – 2026-11-17

- SMHIWarningService avvisar nu varningsområden där starttiden saknas eller inte kan parsas. Tidigare användes `.distantPast` som reserv, vilket kunde göra en varning med trasigt datum till synes aktiv och därmed utlösa en omedelbar notis.
- Giltig starttid krävs nu innan varningsområdet tas med i aktiv/kommande-listan och notifieringsflödet. Detta är en defensiv datavalidering; kontrollera verkliga SMHI-payloads så att formatet täcks av parserns ISO-8601-varianter.
- Ändringen är committad men ännu inte CI-kompilerad eller testad mot live-API på enhet.


## Halkriskens tidsfönster – 2026-11-17

- WeatherRiskAssessment räknar nu föregående nederbörd som relevant för halkrisk endast när den faktiska prognostiden ligger inom de senaste tre timmarna före den kalla timmen.
- Tidigare användes de tre föregående prognosraderna, vilket kunde motsvara längre än tre timmar om prognosserien innehöll luckor. Bedömningen använder nu parsade datum/tider och ett strikt intervall större än 0 och högst 3 timmar.
- Ändringen gäller riskbedömningen som visas i vakt-/vädergränssnittet. Notisschemaläggaren har sedan tidigare motsvarande kontroll av faktiskt tidsavstånd.
- Kodändringen är committad. CI-kompilering, syntetiska gränsvärdestester och fysisk iPhone-verifiering återstår.


## SMHI-sluttid och aktivstatus – 2026-11-17

- Varningsområden med en angiven sluttid måste nu ha en giltig sluttid som inte redan passerat. Ett felaktigt datum avvisas i stället för att varningen riskerar att ligga kvar som aktiv.
- Aktivfiltreringen kräver nu uttryckligen en parsbar starttid och använder inte längre `.distantPast` som reserv. Det kompletterar valideringen i själva SMHI-parsern.
- SMHI-varningar med saknad sluttid tillåts fortfarande, eftersom API:t kan sakna ett sådant värde; om sluttid anges måste den däremot vara giltig.
- Ändringen är committad. Verifiering mot verkliga SMHI-payloads, CI och iPhone återstår.


## SMHI-notisidentifierare vid innehållsuppdatering – 2026-11-17

- Notisidentifieraren byggs nu från en deterministisk kompakt hash av varningsområdets ID, allvarlighetsgrad, rubrik och starttid samt aktuell notifieringsepok.
- Tidigare byggdes identifieraren av varnings-ID, nivå och starttid men inte rubrik. Om SMHI ändrade rubriken utan att ändra övriga fält kunde en gammal väntande notis därför felaktigt räknas som den nya versionen och uppdaterad text utebli.
- Den nya identifieraren gör att ändrad rubrik eller nivå får ett nytt väntande-notis-ID. Stale-rensningen tar samtidigt bort den äldre väntande varianten.
- Hashen är en stabil FNV-1a 64-bitars identifierare för notis-ID, inte en säkerhets- eller integritetsfunktion.
- Kodändringen är committad. Kompilering och test av ändrade varningar mot iOS-notiskön återstår.


## SMHI-signaturer och dubbletter i varningsområden – 2026-11-17

- SMHI-notissignaturer äldre än 90 dagar gallras nu från aktörens minne och den persistenta signaturlistan. Signaturer med okänt/äldre format behålls försiktigt för att undvika oavsiktliga återaviseringar.
- Gallringen görs tidsbaserat och inte genom att ersätta hela mängden med senaste nätverkssvarets varningar. Därmed kan en långsammare, äldre refresh inte radera en nyare lyckad notifieringsclaim.
- Samma SMHI warning-area-ID returneras nu högst en gång även om payloaden innehåller upprepade områdesposter. Resultatet sorteras deterministiskt efter allvarlighetsgrad, starttid och ID.
- Notis- och områdesändringarna är pushade. Kompilering och verklig SMHI-payload-/iOS-notistestning återstår.


## Strikt validering av SMHI GeoJSON – 2026-11-17

- SMHI-geometrins koordinatringar valideras nu innan både punkt-i-polygon och avståndsberäkning används.
- Varje position måste innehålla numerisk longitud/latitud, båda värdena måste vara ändliga och ligga inom giltiga geografiska intervall.
- En felaktig vertex gör att hela ringen/geometrin avvisas. Tidigare kunde en saknad koordinat tyst ersättas med 0,0 i punkt-i-polygon-testet, vilket riskerade felaktiga varningsträffar.
- Polygon och MultiPolygon använder nu samma validerade geometri för både innanför-test och närhetskontroll; hål i polygoner fortsätter att exkluderas från själva varningsytan.
- Kodändringen är committad. CI-kompilering och test mot riktiga SMHI-payloads återstår. Den befintliga 75 km-närhetsgränsen för marina områden är oförändrad och behöver fortsatt separat geografisk utvärdering.
## Grafiskt lager för nederbördstyp – 2026-11-17

- Nederbördstypens 25 geografiskt placerade Open-Meteo-modellpunkter visas nu som större, mjukt tonade områden i stället för små isolerade punkter.
- Regn, snö och blandad nederbörd behåller separata färger/lager. Kartans radarbilder är fortsatt ett separat observationslager.
- Lageridentiteten inkluderar nu nederbördsmängden, så stil-/datakällan uppdateras även när intensiteten ändras men klassificeringstypen förblir densamma.
- Detta är en visuell interpolation/utbredning av glesa modellpunkter, inte en högupplöst nederbördskarta eller klassificering av radarbildens pixlar. Fysisk iPhone-granskning krävs för att bedöma om utbredningen blir lagom och inte överdriver täckningen.
- Kodändringen är committad; CI-kompilering och kartkontroll på enhet återstår.

## Radar-justering och RainViewer-attribution – 2026-11-17

- Build #444 (run 44082008257, commit 6a7d4a18c84aaf8082010b5bb0709df038055281) slutfördes med `success`. iOS-appen kompilerades, osignerad IPA paketerades och artefakten `Regnvakt-unsigned-IPA` laddades upp (4 541 705 byte; SHA-256 `6ee38744b86c6f09e8cc74cf9a3c7dd8a706f847bfa75282d4040b80cadc32c6`). Artefakten löper ut 2026-12-01.
- Nederbördstypens kartmarkeringar justerades i samma commit till radie 14, opacitet 0,38 och blur 0,88 för att minska överlappning och låta baskartan synas bättre.
- Radarens leverantörsrad kompletteras nu med den synliga länken `Weather data by RainViewer` när RainViewer är aktiv reservkälla. Attributionen döljs för SMHI samt när vind-/molnvisning används.
- Attributionen är committad separat efter build #444 och behöver en egen CI-kompilering.
- Ingen fysisk iPhone-verifiering är utförd. Kontrollera att länken syns endast för RainViewer, går till RainViewer-webbplatsen och inte tränger undan kartans övriga attribution eller kontroller.



## Radaruppspelning och platsavläsning – 2026-11-17

- Platsavläsningen för RainViewer hämtar en separat kartplatta och analyserar pixlar runt vald koordinat. Den kontrollen kördes tidigare för varje vald radarbild, även under automatisk uppspelning med 1,5 sekunders intervall.
- Platsavläsningen hoppas nu över medan uppspelningen pågår och körs igen när användaren pausar. Manuell bildnavigering och vanlig uppdatering behåller platsavläsningen.
- Ändringen minskar onödiga nätverksanrop under animering och minskar risken för att långsamma platskontroller överlappar. Själva radarens kartlager och bildruteväxling ändras inte.
- CI-kompilering och fysisk iPhone-kontroll återstår.


## Skydd mot inaktuella radaravläsningar – 2026-11-17

- Build #448 (run 44087979106, commit 4c5d6d58a9a38ce5489b3b71124ab47eab300baa) slutfördes med `success`: iOS-enhetsbygget kompilerades, osignerad IPA paketerades och artefakten `Regnvakt-unsigned-IPA` laddades upp (4 545 496 byte; SHA-256 `427cef52f2ed8c8b30e82f40d00b9607d17d60408472185bdaecc5ce9dae861b`). Artefakten löper ut 2026-12-01 13:04 UTC.
- RadarMapView.swift: varje RainViewer-platsavläsning får nu ett unikt request-ID och fångar bildrutans ID samt koordinatnyckeln innan nätverksanropet.
- Resultat och felstatus får bara uppdateras om förfrågan fortfarande är den senaste, samma bildruta och koordinat är valda och uppspelningen inte har startat. Byte av bildruta eller koordinat invaliderar en pågående avläsning direkt.
- Detta skyddar gränssnittet mot sena svar från äldre nätverksanrop. Själva radarplattans rendering och bildruteväxling ändras inte.
- Kodändringen är committad. CI-kompilering återstår; fysisk iPhone-verifiering av snabb bildruteväxling, panorering och pausad uppspelning krävs innan beteendet betraktas som verifierat.


## Invalidering av platsavläsning vid radaruppspelning – 2026-11-17

- Build #450 (run 44092547270, commit a18fa7cbfe9ce61383b06661b6bf18315d1e16ae) slutfördes med `success`: iOS-enhetsbygget kompilerades, osignerad IPA paketerades och artefakten `Regnvakt-unsigned-IPA` laddades upp (4 547 142 byte; SHA-256 `2c1b591aee228cf6f2106acfbe28e9e0b4a8c24cd4f55f5e0d7355848b40e9df`). Artefakten löper ut 2026-12-01 13:28 UTC.
- Uppföljande granskning identifierade ett kompletterande kantfall: en platsavläsning som startat före uppspelning kunde fortfarande bli aktuell igen om användaren hann pausa efter att tidslinjen gått vidare.
- RadarMapView.swift invaliderar därför nu pågående platsavläsningar direkt när uppspelning startar. När uppspelningen pausas görs en ny avläsning för aktuell bildruta och koordinat.
- Detta är en defensiv komplettering till request-ID-kontrollen. Fysisk iPhone-testning av snabb uppspelning, paus och bildrutevarvning återstår.


## Skydd mot inaktuella modellresultat i radarkartan – 2026-11-17

- Lade till separata request-ID:n för nederbördstyp från Open-Meteo och närprognos från MET Norway.
- När kartans valda koordinat ändras ogiltigförklaras båda pågående begärandena direkt. Ett sent svar från föregående plats får därmed inte skriva över den nya platsens värden.
- Båda hämtningarna kontrollerar begärandets identitet och koordinat efter nätverksanropet samt före uppdatering av gränssnittet.
- Nederbördstypen kräver nu giltig temperatur och WMO-väderkod. Saknade temperaturvärden ersätts inte längre med 0 °C och kan därför inte ge en falsk klassificering.
- Ogiltiga/icke-finita nederbörds- och närprognosvärden filtreras bort i stället för att visas.
- Ingen fysisk iPhone-verifiering är utförd. CI-resultat inväntas för denna commit.

## Återställd projektstruktur och verifierad IPA – 2026-11-17

- Commit 3fb72168e57fbf0affd4d24b4dda74f2153381a7 återställde den kompletta projektstrukturen från senast kompletta byggbara snapshot och behöll senaste radarändringarna i RadarMapView.swift, CI-workflow och utvecklingsloggen. Trädet innehåller åter AppIcon.svg och project.yml.
- Build #452 (run 44109148542) nådde Swift-kompilering men misslyckades på grund av dubbla `@MainActor`-attribut på `refreshPrecipitationType()` i RadarMapView.swift. Felet var ett kompileringsfel; IPA skapades inte.
- Commit 22677d95e4fff2273f1e498cac49550bac69c67b tog bort den dubbla attributmarkeringen.
- Build #453 (run 44111422700) slutfördes med `success`: Xcode-projektet genererades, iOS Release kompilerades, osignerad IPA paketerades och artefakten `Regnvakt-unsigned-IPA` laddades upp.
- Artefakt: 4 549 465 byte. SHA-256: `6d3501d7459d41eb32ff3cd2ae86c356e5820ddc5cde65a1b89c6d6a426cd256`. Artefakt-ID 14340373438. Utgångsdatum 2026-12-01 15:16 UTC.
- Detta verifierar CI-kompilering och paketering, inte installation eller funktion på fysisk iPhone. Testa särskilt SMHI-bildrutor, RainViewer-reserv, platsavläsning, uppspelning/paus, panorering och lagerövergångar på enheten.


## Dubbletter i aviseringsinkorgen, SMHI-symbol och lättare vindrendering – 2026-11-17

- Aviseringar för samma prognoshändelse grupperas nu efter vakttyp, plats och händelsetimme. Förändrad sannolikhet eller text vid en prognosuppdatering skapar inte längre ett extra kort för samma regnhändelse.
- SMHI-vakten får en egen tydlig varningstriangel med SMHI-ordmärke i kortets ikonruta. Varningens allvarlighetsfärg behålls.
- Vindfältets Canvas-rendering har sänkts från 30 till 15 uppdateringar per sekund. Det beräknade interpolationsfältet har minskats från 36×28 till 20×16 celler och antalet partiklar från 132 till 76. Avsikten är att minska CPU-arbetet och visuellt släp på iPhone utan att ta bort vindlagret.
- Detta är kodändringar. CI-kompilering och fysisk iPhone-kontroll av lagerbyten, Typ-lagret och vindanimationen återstår.


## Typ-läget frikopplat från radarbilder – 2026-11-17

- Typ-läget stänger nu av SMHI-/RainViewer-rasterbilden och visar endast nederbördstypens Open-Meteo-lager ovanpå baskartan. Det undviker att en radarbilderuta visuellt konkurrerar med eller skymmer modellklassificeringen.
- Kartans källrad visar uttryckligen ”NEDERBÖRDSTYP • OPEN-METEO” i detta läge, så användaren ser vilken datakälla och vilken typ av lager som visas.
- Detta är en kodmässig korrigering av Typ-lägets lagerlogik. Kompilering och kontroll av att regn/snö/blandat faktiskt syns på iPhone återstår.


## SMHI QCOMP-kontroll och nederbördstypslager – 2026-11-17

- En ny kontroll av SMHI:s officiella katalog visade att den publicerar två parallella PNG-serier: standardprodukten `RADAR_SWE_EPSG3006_...` och kvalitetskompositerade `RADAR_SWE_EPSG3006_QCOMP_...`. Appen ska använda QCOMP-serien, vilket också var det ursprungliga avsedda filnamnet.
- En tillfällig ändring som valde standardserien har därför återställts. Koden matchar åter uttryckligen `RADAR_SWE_EPSG3006_QCOMP_YYYYMMDDHHMM.png`. Den tidigare slutsatsen att QCOMP saknades var felaktig; standardserien och QCOMP-serien finns båda i katalogen.
- SMHI-bildhämtningen på enheten är fortfarande inte bekräftad. Nästa felsökningssteg är att fånga exakt HTTP-status och bildavkodningsfel från iPhone om QCOMP fortsatt fallerar.
- Nederbördstypens Open-Meteo-punkter har större, mjukare cirkelyta (36 px radie, 0,94 blur och 0,30 opacitet) för att punkterna ska kunna läsas som ett regionalt modellfält. Detta är fortfarande modellvägledning, inte observerad radar.
- Kodändringarna är committade; CI-kompilering och fysisk iPhone-verifiering återstår.


## SMHI 401 från iPhone – diagnostik av bildåtkomst – 2026-11-17

- Test på användarens iPhone visar att kataloghämtningen fungerar men att direkt hämtning av QCOMP-PNG returnerar HTTP 401. Reservkällan RainViewer fungerar samtidigt.
- Oberoende kontroll av SMHI:s publika katalog visar att QCOMP-PNG-filer publiceras. Direkt öppning av en sådan PNG via webbläsarverktyget returnerar också 401. Det styrker att felet ligger i åtkomsten till själva filresursen, inte i regex eller att filnamnen saknas.
- Ny diagnostik: bildbegäran skickas med SMHI:s webbplats som Referer och utan den tidigare specialskrivna User-Agent-strängen. Vid fortsatt fel visas även en kort, sanerad autentiserings-/serversvarshänvisning när sådan finns.
- Ingen garanti att Referer löser 401; detta är ett avgränsat test av serverns åtkomstpolicy. Om 401 kvarstår behöver SMHI:s officiella portalflöde eller en annan dokumenterad radarleverans användas i stället för att fortsätta gissa headers.
- QCOMP behålls som förstahandsprodukt. RainViewer fortsätter som reserv.


## Bekräftat HTTP 401 Basic realm från iPhone – 2026-11-17

- Användarens test av build #462 visar fortsatt HTTP 401 och autentiseringsutmaningen `Basic realm=Secured` vid hämtning av SMHI:s QCOMP-PNG. RainViewer-reserven fungerar och visar nederbörd över Hudiksvall.
- Försöket med SMHI-Referer i build #462 löste inte åtkomstfelet. Den spekulativa Referer-headern tas därför bort i nästa kodversion; vi ska inte fortsätta lägga till obekräftade headers.
- SMHI:s publika radar-README bekräftar att QCOMP levereras som både HDF5 (`RADAR_SWE_2KM_BALTRAD_QCOMP`) och motsvarande PNG (`RADAR_SWE_EPSG3006_QCOMP`), med ny produkt var femte minut och sex timmars tillgänglighet. PNG-bildens georeferens är SWEREF 99 TM / EPSG:3006.
- Den officiella SMHI-sidan för aktuella och historiska radarbilder erbjuder också dygnsarkiv med PNG/TIFF och femminuterssteg. Det är en alternativ officiell distributionsväg att undersöka, men en direkt, dokumenterad maskin-API-adress för arkiven är ännu inte fastställd.
- HDF5 är ett möjligt alternativt format men kräver korrekt ODIM_H5/metadata-avkodning och georeferering; ingen sådan parser är implementerad eller verifierad i appen.
- QCOMP behålls som önskad SMHI-produkt. RainViewer förblir fungerande reserv. Nästa steg är att undersöka den officiella arkiv-/öppna-dataingången innan ytterligare nätverkskod skrivs.


## Stabiliserad live-radarleverantör – 2026-11-17

- Beslut: RainViewer används som aktiv live-radarkälla tills SMHI erbjuder en verifierad offentligt åtkomlig bild-/tile-endpoint för appklienter.
- Underlaget är användarens upprepade iPhone-test av build #461/#462: SMHI:s QCOMP-PNG returnerar HTTP 401 med `WWW-Authenticate: Basic realm=Secured`. Referer-testet i build #462 ändrade inte utfallet. RainViewer-manifest och kartplattor fungerar.
- Radarens ordinarie laddning försöker därför inte längre SMHI först. Det tar bort en onödig timeout/401 på varje uppdatering och undviker att användaren får ett felkort när reservkällan i praktiken är den fungerande källan.
- Kartans källmärkning fortsätter att visa `RADAR • RAINVIEWER`. SMHI QCOMP behålls som undersökningsspår men ska inte återaktiveras förrän en offentlig leveransväg har verifierats från iPhone/CI utan autentisering.
- SMHI:s officiella dygnsarkiv erbjuder PNG/TIF ZIP-filer för historiska bilder med femminuterssteg; det är lämpligt för eventuell separat historikfunktion men inte en verifierad direkt live-feed. HDF5 kräver en korrekt parser och georeferering och införs inte utan testdata och validering.
- RainViewer är enbart historisk radar i den nuvarande manifestmodellen (`radar.past`); ingen nowcast eller framtida nederbördsprognos ska utlovas. Prognos/Typ-lager fortsätter vara separata modellprodukter.
- CI-kompilering och fysisk iPhone-verifiering av den nya källprioriteringen återstår.


## Källinformation anpassad till aktiv RainViewer-drift – 2026-11-17

- Uppdaterade informationsdialogen så den inte längre påstår att SMHI används i första hand. Den anger nu RainViewer som aktiv källa och skiljer tydligt på observerad radar och modellbaserad nederbördstyp.
- Uppdaterade feltexten när radarmanifestet inte kan hämtas. Den nämner inte längre SMHI som en aktiv reservväg i det normala flödet.
- Detta är en text-/felhanteringskorrigering efter beslutet att använda RainViewer som primär live-radarkälla tills en öppet åtkomlig SMHI-leverans har verifierats.


## Korrekt källstatus och RainViewer-tidslinje – 2026-11-17

- Radarfoterns källtext anger nu `Radar: RainViewer • historik` när RainViewer används. Den kallas inte längre reservradar efter att den blivit aktiv primärkälla.
- RainViewer-manifestet som appen använder exponerar `radar.past`; appens tidslinje är därför historiska/observerade bildrutor och ska inte beskrivas som en framtidsprognos.
- Tidslinjen fortsätter använda tillgängliga bildrutor i stigande tidsordning, med senaste bildrutan vald initialt. Uppspelningen stegar genom dessa bildrutor; separat närprognos från MET Norway och nederbördstyp från Open-Meteo behålls som modellprodukter.
- Kod- och källtextändringen är pushad. CI och fysisk iPhone-kontroll återstår.


## Behovsstyrd hämtning av vind-/modellfält – 2026-11-17

- Radarens startflöde hämtar inte längre 25 geografiska Open-Meteo-punkter för vind/moln/nederbördstyp när användaren bara tittar på radarn.
- Fältet hämtas när användaren väljer Vind eller Typ och uppdateras vid kartförflyttning endast om ett sådant modellager är aktivt.
- Byte av vald plats uppdaterar fortfarande nederbördstyp, närprognos och radaravläsning. Vind-/modellfältet uppdateras bara när det behövs.
- Avsikten är färre onödiga nätverksanrop, snabbare start och lägre batteri-/databelastning utan att ta bort någon synlig funktion.
- CI-kompilering och fysisk iPhone-verifiering återstår.


## Parallelliserad startladdning – 2026-11-17

- Radarbilder, aktuell nederbördstyp och MET Norway-närprognos är oberoende nätverksflöden. Startvyn startar nu dessa tre laddningar parallellt i stället för att invänta varje flöde sekventiellt.
- Vind-/modellrutnätet fortsätter hämtas behovsstyrt när Vind eller Typ aktiveras.
- Målet är kortare upplevd starttid utan fler nätverksanrop eller ändrad datakvalitet. Fysisk enhetstestning och CI-kompilering krävs fortfarande.


## Vilande radarklocka när uppspelning är avstängd – 2026-11-17

- Ersatte den alltid aktiva Combine-timern (1,5 sekunders intervall) med en SwiftUI-task som bara kör medan radaranimationen är aktiv.
- När användaren pausar eller lämnar vyn avbryts vänteloopen automatiskt. Det eliminerar onödiga timerhändelser när radarn står stilla och ger tydligare livscykelhantering.
- Bildrutans takt är fortsatt 1,5 sekunder. Ingen ändring av radarens datakälla eller bildruteinnehåll.
- CI-kompilering och test av uppspelning/paus på iPhone återstår.


## 2026-11-17 — RainViewer playback cleanup
- Set RainViewer as the initial radar provider in view state, matching the only provider currently returned by the active radar service. This avoids a transient incorrect SMHI state before the first manifest response.
- Avoid invoking the legacy full-image loading path when the selected frame is a RainViewer tile frame. Frame changes continue to update the tile URL through SwiftUI state and still invalidate/update the selected-place radar inspection.
- The legacy SMHI image path remains isolated for future use only; it is not the active live radar source.
- Build verification is pending GitHub Actions runner availability. No IPA or device verification is claimed by this source change.


## 2026-11-17 — Deduplicering av prognosnotiser per händelsetimme

- Användarens iPhone-skärmbild visar två identiska regnnotiser för Hudiksvall, med samma prognostimme, sannolikhet och nederbördsmängd, levererade med två minuters mellanrum.
- Kodgranskningen visade att inkorgen redan grupperade prognoshändelser per lokal timme, men själva iOS-notisernas identifierare använde prognosdatumets exakta Unix-sekund. Om en prognosuppdatering justerade händelsetiden några sekunder/minuter kunde iOS därför behandla samma visade timhändelse som en ny notis.
- WeatherNotificationScheduler.swift använder nu svensk lokal timme (Europe/Stockholm, yyyyMMddHH) i identifieraren för vanliga prognosnotiser. Samma plats, vakttyp och händelsetimme får därmed samma ID och en uppdatering ersätter den väntande notisen i stället för att skapa en ny. Omedelbar frost och dagsbaserad prognosfrost behåller sina separata identitetsregler.
- Detta är en sannolik rotorsak som stöds av identifieringslogiken och skärmbilden; den faktiska historiska leveransvägen kan inte bevisas enbart från skärmbilden.
- Kodändringen är pushad. CI-kompilering och nytt iPhone-test återstår. Redan levererade dubbletter tas inte bort retroaktivt av ändringen.


## 2026-11-17 — Stabiliserad platsidentitet för prognosnotiser

- Fortsatt granskning av dubblettskärmbilden visade en andra möjlig källa: när telefonens GPS-position används direkt som plats-ID kan små positionsförändringar skapa flera koordinatnycklar för samma sparade/bevakade ort. Dessa nycklar ger olika iOS-notis-ID trots identiskt ortsnamn och prognosinnehåll.
- När den aktuella GPS-positionen matchar en sparad och aktivt bevakad plats schemaläggs notiser nu med den sparade platsens fasta koordinater och namn i stället för den rörliga GPS-fixen.
- Detta kompletterar timbaserad händelseidentitet i WeatherNotificationScheduler.swift. Ändringen förhindrar att nya GPS-avvikelser skapar nya identiteter för samma bevakade plats.
- Hypotesen om redan lagrade äldre koordinatnycklar är inte bekräftad mot användarens enhetsdata. Befintliga historiska dubbletter/nycklar rensas inte automatiskt av denna ändring.
- Kod pushad. CI-kompilering och iPhone-test återstår.


## 7-dagarsprognos och radarens lagerpresentation – 2026-11-17

### Ändringar
- `ContentView.swift`: varje dygnskort i 7-dagarsprognosen kan nu fällas ut. Detaljläget visar högsta/lägsta temperatur, medelvind, byvind, nederbördsrisk, total nederbörd och UV-index i samma visuella detaljnivå som övriga väderdetaljer.
- Dygnsvärdena presenteras uttryckligen som Open-Meteo-data. Timprognos har inte lagts till i 7-dagarsvyn eftersom den nuvarande modellen bara hämtar 48 timmar; längre timserier får inte fabriceras.
- `RadarMapView.swift`: RainViewer-attribution visas bara när RainViewer-rasterlagret faktiskt är aktivt. I nederbördstypläget används Open-Meteo som källa och RainViewer ska inte ta plats i samma källrad.
- Nederbördstypens modellpunkter har fått något bredare och mjukare symbolfält för att minska intrycket av isolerade små punkter. Detta är en visuell justering, inte en förbättring av modellens geografiska upplösning.

### Kvarstående radarproblem
- Användarens senaste skärmbild visar att nederbördstypslagret fortfarande ser fläckigt ut och att basemapens kontrast konkurrerar med väderlagret.
- Rotorsaken är delvis strukturell: nederbördstypen visas som 5×5 Open-Meteo-modellpunkter, inte som ett kontinuerligt radar- eller rasterfält. Att öka cirkelradien kan mildra glappen men kan inte skapa verklig upplösning mellan mätpunkterna.
- RainViewer publika API ger historiska radarplattor med 10-minuterssteg och har max zoomnivå 7; dess nuvarande publika API ska inte beskrivas som framtida radarprognos. Källa: https://www.rainviewer.com/api/weather-maps-api.html och https://www.rainviewer.com/api/transition-faq.html.
- Nästa tekniska steg bör vara att undersöka en tätare, geografiskt interpolerad Open-Meteo-visualisering eller en separat väderkartkälla med verkligt rasterstöd. Interpolering måste märkas som modellvisualisering och får inte presenteras som uppmätt radar.

### Verifiering
- Kodändringar är committade på `feature/frost-notification-audit`.
- CI-kompilering och IPA-paketering ska kontrolleras separat.
- Ingen fysisk iPhone-verifiering av den nya 7-dagarsvyn eller radarutseendet är ännu utförd.


## Tätare geografiskt modellfält för radarens väderlager – 2026-11-18

- Open-Meteo-fältet för vind, molntäcke och nederbördstyp har ändrats från 5×5 (25) till 9×9 (81) koordinater.
- Samma geografiska utbredning runt kartans mittpunkt behålls; avståndet mellan modellpunkterna minskar.
- Alla koordinater hämtas i ett samlat multi-location-anrop. Resultatstatusen visar nu 81 punkter och hanterar partiella svar.
- Detta ska ge ett tätare visuellt underlag och minska glappen mellan nederbördstypspunkter. Det är fortfarande modellbaserad interpolation/visualisering och inte en radarprodukt eller 81 oberoende observationer.
- Vindfältets interpolering använder samma provpunkter och samma geografiska utbredning, så dess normalisering behöver inte ändras.
- Kontrollera API-svarstid, svarsstorlek och rendering på fysisk iPhone. Ingen sådan prestandaverifiering är ännu utförd.


### Buildverifiering – build #488
- GitHub Actions run `44196934911` slutfördes med resultat `success` för commit `b75f297ad15759622d04757211ef44dba7d2eb3b`.
- IPA-artefakt `Regnvakt-unsigned-IPA` (4 558 233 byte) laddades ned och ZIP-/IPA-integriteten verifierades lokalt.
- Levererad fil: `Regnvakt-unsigned-build488.ipa`.
- SHA-256: `f571a235f51a50a10909390405657944a63edee8f584fcc650e04ea5d9091090`.
- CI bekräftar kompilering och paketering; ingen fysisk iPhone-testning är gjord.


## Uppföljning efter iPhone-skärmbilder – 2026-11-18

### 7-dagarsprognos
- Skärmbilderna visar att Dagens prognos och Dagens väder har en betydligt mer genomarbetad detaljvy än den separata 7-dagarslistan.
- Varje dagskort i 7-dagarsvyn öppnar nu den återanvända `ForecastDayDetails`-vyn med samma visuella struktur som dagens prognos: temperaturhero, tvåkolumners mätkort och timlista där data finns.
- Den befintliga timserien är 48 timmar. För senare dagar visas därför tydligt att timprognos saknas i stället för att fylla ut med påhittade timvärden.
- Kortet har en tydlig tryckindikator.

### Radar / nederbördstyp
- Skärmbilden visar att användaren har valt `Typ`, och att 59 modellpunkter klassificerats som snö. Detta är Open-Meteo-prognosdata, inte RainViewer-radar.
- 46 px cirklar med mycket hög oskärpa har smält samman till en stor vit fläck. Det är en konkret visuell orsak till att typ-lagret ser fel ut.
- Cirkelradien sänktes till 19 px, opaciteten justerades till 0.30 och oskärpan till 0.78; cirkelkonturen togs bort. Avsikten är att återfå geografisk läsbarhet.
- Den faktiska RainViewer-radarbilden ligger under knappen `Regn`; `Typ` är ett separat modellbaserat prognoslager. Gränsen mellan dessa ska kommuniceras tydligt i gränssnittet.
- Fysisk verifiering efter ändring krävs. Inga påståenden om att radarn nu fungerar görs innan användaren testat och en faktisk RainViewer-bild har bekräftats.


### Buildverifiering – build #494 – 2026-11-18
- GitHub Actions run `44250503508` slutfördes med `success` för branch `feature/frost-notification-audit`, commit `b804edb5992f251f21cd7b5eea720f7171612e66`.
- IPA-artefakt `Regnvakt-unsigned-IPA` laddades ned. ZIP-arkivet och den inre IPA-filen klarade integritetstest; `Payload/Regnvakt.app/PkgInfo` finns.
- Levererad fil: `Regnvakt-unsigned-build494.ipa` (4 591 683 byte).
- SHA-256: `59ed79737ddde6050b1147172823073088678d1d6862a9404946a2ecd1ddd160`.
- CI bekräftar kompilering och paketering. Fysisk iPhone-verifiering krävs fortfarande.


### Förtydligad dagdetalj – 2026-11-18
- Dagdetaljens navigeringstitel visar nu vald veckodag i stället för att alltid säga `Dagens prognos`.
- Sektionen benämns `PROGNOS FÖR DAGEN`, så samma detaljvy fungerar tydligt för både idag och kommande dagar.
- Matchning mellan dygnsdatum och timprognos använder uttryckligen `Europe/Stockholm` i stället för enhetens aktuella tidszon. Detta undviker att timrader hamnar under fel dygn om enheten befinner sig i en annan tidszon.


## Uppföljning av 7-dagarsdetaljer och radarförväxling – 2026-11-18

### Dagdetaljer
- `ForecastDayDetails` har byggts om för att följa samma visuella struktur som `TodayWeatherDetails`: samma gradientbakgrund, platsrubrik, temperaturhero, cyan sektionsrubriker, tvåkolumners mätkort, temperaturdiagram och timlista.
- Dagsspecifika dygnsvärden används i stället för att återanvända dagens aktuella vädervärden. Därmed visas inte lufttryck, luftfuktighet eller andra mätvärden som saknas för den valda framtida dagen.
- Timserien filtreras på datum i Europe/Stockholm. Om timmar saknas visas ett tydligt meddelande i samma panelstil.

### Radarens lagerkommunikation
- Senaste skärmbilden visar att `Typ`-läget är aktivt. Detta är Open-Meteos modellbaserade nederbördstypsfält, inte RainViewer-radar.
- Knapplabeln har ändrats från `Typ` till `Prognos` och förklaringen anger nu uttryckligen att `Regn` visar RainViewer-radarn.
- RainViewer-manifestet hämtar frame paths dynamiskt och dessa används direkt i tile-URL:en. Den officiella dokumentationen anger formatet `{host}{path}/512/{z}/{x}/{y}/{color}/{options}.png` och max zoom 7. Appen använder 512 px tiles och zoomtak 7.
- En aktuell manifestkontroll visar hash-baserade frame paths. Appen använder manifestets `path` dynamiskt och är inte beroende av tidsstämpelbaserade URL:er.
- Nästa iPhone-test måste göras med knappen `Regn` aktiv. Kontrollera att RainViewer-raster syns och att platsavläsningen kan läsa tile över vald position. Om det fortfarande är tomt behövs faktisk HTTP-status från tile-förfrågan/loggning; skärmbilden med `Prognos` kan inte ensam visa om RainViewer-tile fungerar.

### Verifiering
- Ingen fysisk iPhone-verifiering av dessa senaste ändringar är ännu utförd.


## LibreWXR som primär radarkälla – 2026-11-18

### Leverantörsbyte
- LibreWXR:s publika API provas som primär källa via `https://api.librewxr.net/public/weather-maps.json`.
- API:t dokumenteras som RainViewer v2-kompatibelt. Manifestet använder samma centrala fält (`host`, `radar.past[].time`, `radar.past[].path`) och befintlig MapLibre tile-konstruktion kan därför återanvändas.
- `RadarProvider.libreWXR` har lagts till. RainViewer ligger kvar som automatisk reserv om LibreWXR:s metadata eller tile inte kan hämtas/avkodas.
- Innan LibreWXR väljs verifieras en faktisk PNG-tile vid vald plats. Ett fungerande manifest räcker inte längre som bevis för att kartan kan visa bildrutor.
- LibreWXR får zoomnivå upp till 12 enligt dokumentationen; RainViewer-reserven begränsas fortsatt till zoom 7. Platsavläsningens tilezoom följer aktiv källa.
- Kartans attribution anger LibreWXR och CC BY 4.0 när den källan används. OpenStreetMap-attribution behålls.
- Färgprofilen är fortsatt ID 2 (Universal Blue), med smoothing och snow aktiverat. LibreWXR dokumenterar ID 2 som Universal Blue.

### Datatäckning och begränsningar
- LibreWXR beskriver europeisk radarbas som OPERA (184 radarstationer i 27 länder) och ett globalt RRQPE-lager som fyller områden utanför regional radar. I sådana områden är det satellitbaserad nederbördsuppskattning, inte lokal radarobservation.
- Hudiksvall ligger inom europeiskt område, men verklig tiletäckning och bildkvalitet måste verifieras i appen.
- Den publika servern är best-effort utan garanterad upptid eller hastighet. Gratis/öppen API innebär inte SLA.
- Testmiljön i denna utvecklingssession kunde inte nå api.librewxr.net direkt (DNS ej tillgänglig). Därför är API:t implementerat med runtime-tilevalidering och RainViewer-reserv, men dess faktiska svar från iPhone är ännu inte bekräftat.
- Dokumentationskälla: https://github.com/JoshuaKimsey/LibreWXR (README, API metadata/tileformat, färgscheman och täckningsbeskrivning).

### Verifiering
- Koden är committad på `feature/frost-notification-audit`.
- CI-kompilering/paketering inväntas.
- Fysisk iPhone-verifiering återstår.


### LibreWXR – inkludera prognosrutor i tidslinjen – 2026-11-18
- Vid kodgranskning upptäcktes att manifestavkodaren endast läste `radar.past`. LibreWXR publicerar även `radar.nowcast`, men dessa framtida bildrutor visades inte i Regnvakts tidslinje.
- Manifestmodellen läser nu `nowcast` som ett valfritt fält och kombinerar observerade bildrutor med prognosbildrutor i tidsordning.
- Leverantörsvalideringen kontrollerar fortfarande den senaste observerade bildrutan, inte den senaste framtida prognosrutan. Därmed ska en ofärdig nowcast-tile inte slå ut en i övrigt fungerande radarkälla.
- Upp till 31 bildrutor behålls för tidslinjen. Detta möjliggör upp till 25 historiska + 6 framtida rutor när servern tillhandahåller dem; faktisk mängd beror på manifestet.
- Källan dokumenterar cirka två timmars historik, 10-minutersuppdatering och upp till 60 minuters nowcast. Se LibreWXR Web Integration Guide: https://librewxr.net/docs/doc-viewer?doc=web-integration-guide.


### Radargranskning efter LibreWXR-integration – 2026-11-18
- Bygg #502 slutfördes med godkänt resultat, men den körningen innehåller inte nowcast-ändringen från commit `14a3eddf`.
- Build #506 är fortfarande köad i GitHub Actions. Den innehåller LibreWXR-manifest med `radar.nowcast`.
- Vid granskning hittades kvarvarande användartext som felaktigt beskrev RainViewer som aktiv radarkälla även när LibreWXR används. Informationsrutan och felmeddelandet är nu leverantörsneutrala.
- Tidslinjens rubrik visar nu aktiv källa (LibreWXR/RAINVIEWER) i stället för ett generiskt RADAR, så det går att se vilken leverantör som faktiskt valts.
- Viktigt: manifest- och tile-validering i koden bevisar inte att MapLibre visar rasterlagret korrekt i iPhone-appen. Det kräver fortfarande en fysisk enhetstest.


### Uppföljning – leveranssäkerhet för omedelbar frostrisk och testbarhet – 2026-11-20
- Granskning av schemaläggarens livscykel visade att en aktuell frostavisering kunde tas bort vid nästa prognosuppdatering innan iOS hade levererat den. Schemaläggaren markerade dessutom aviseringen som dagens redan hanterade när den endast hade lagts i kön.
- Ändrat så att väntande omedelbara frostaviseringar bevaras över prognosuppdateringar även när en ny aktuell temperatur finns.
- Dagens dedupliceringsdatum skrivs nu när samma identifierare återfinns bland iOS levererade notiser, inte när den bara läggs i väntande kö.
- Första CI-testkörningen (#44750142014) avslöjade ett testkonfigurationsfel: testmålet kunde inte importera appmodulen `VADER` (`No such module 'VADER'`). XcodeGen-genereringen passerade.
- Flyttat `FrostRiskRules` till `VADER/FrostRiskRules.swift`. Testmålet kompilerar nu samma källfil direkt i stället för att importera appmodulen.
- Senaste kodcommit: `83cf4e1a6ae1316d37343e74c2db488bd9b6625b`. CI för denna commit inväntas.
- Fysisk iPhone-leverans är fortsatt ej verifierad.


### Fortsatt regelgranskning – tidsfönster och tysta timmar – 2026-11-20
- Flyttat `WeatherWatchRules` till den fristående filen `VADER/WeatherWatchRules.swift` så även dessa regler kan testas utan att importera appmodulen.
- Schemaläggaren använder nu den gemensamma `WeatherWatchRules.isQuietTime`-funktionen i stället för en privat kopia.
- Tysta timmar tolkas i tidszonen `Europe/Stockholm`, inklusive intervall som passerar midnatt. `none`, ogiltiga intervall och identiska start-/sluttimmar ger inget tyst intervall (fail-open).
- Lagt till tester för 8-timmars prognos-/notishorisont samt gränserna 21:59, 22:00, 06:59 och 07:00 för standardintervallet 22–07.
- Bakgrundsgranskning: appens rotvy reagerar på `scenePhase == .active` och uppdaterar då SMHI-varningar. Jag hittar ingen registrerad `BGTaskScheduler`/`BGAppRefreshTask`-hantering i den granskade appkoden. Prognosbaserade lokala notiser är därför beroende av att aktuella prognoser hämtas när appen är aktiv eller när en platsbevakning aktiveras; en kontinuerlig bakgrundshämtning är inte verifierad och ska inte utlovas.
- Senaste kodcommit: `2f9c1056cb21bf0c962ec88f6d39afea73a82204`. CI-körning inväntas.


### Slutlig korrigering av väntande frostnotis – 2026-11-20
- Verifierade att föregående ändring av notisens livscykel inte låg kvar i den aktuella grenens schedulerfil efter senare träduppdateringar. Återinfört och verifierat ändringen direkt mot aktuell branch-head.
- `preserveCurrentFrost` är nu aktiv så länge Frostvakten är på, oberoende av om en färsk temperatur finns. Befintliga väntande `.frost.current.`-requests behålls vid prognosuppdatering.
- Daglig deduplicering markeras endast när request-ID återfinns bland iOS levererade notiser. En request som bara accepterats i väntande kö räknas inte som levererad.
- Verifierad filblob: `00b6a80761b92dc70e98bca2b2801e8968992df9`.
- Senaste kodcommit: `c60b2fbcca87705fea2a5f290a645433ca64b12d`. Ny CI-körning #44751029686 är köad; resultat inväntas.


### Ytterligare skydd – återhämtning av levererad aktuell frostavisering – 2026-11-20
- Hittade ett kvarvarande gränsfall: om en omedelbar frostavisering levererats och temperaturen sedan stigit innan nästa prognosuppdatering, kunde den tidigare leveransen missas av den vanliga händelselistan. Dagens frostmarkör riskerade då att inte återställas, vilket kunde tillåta en ny prognosbaserad frostavisering samma dag.
- Schemaläggaren läser nu levererade iOS-notiser för aktuell plats och återställer frostmarkören från levererade `.frost.current.`-identifierare och deras `alertDay`, även när aktuell temperatur inte längre innebär frostrisk.
- Verifierat ändringen i aktuell gren genom att läsa tillbaka den skapade filblobben. Automatisk CI-körning #44754835740 är köad för commit `ee8f7ad54fd00cf6695a120d9eabf2ff2f669c19`.
- Tidigare CI-körningar #44750850638 och #44750635575 har passerat samtliga steg inklusive tester, iOS-byggning och paketering av osignerad IPA. De körningarna föregår den senaste korrigeringen och utgör därför inte slutligt godkännande av aktuell HEAD.
- Fysisk leverans och notisvisning på iPhone är fortfarande ej verifierade.


### Utökad tidszonstestning – 2026-11-20
- Utökat `WeatherWatchRulesTests` med gränstester för det alternativa tystnadsintervallet 23–06.
- Lagt till test av svenska övergången från vintertid till sommartid den 29 mars 2026. Testet kontrollerar att intervallet 22–07 fortfarande bedöms efter svensk lokal klocktid trots att klockan hoppar från 01:59 till 03:00.
- Senaste kodcommit: `5fc3c7f9d0cd0d65c3357e4b45ab2e60b9d7dc2f`. CI-körning inväntas.


### Granskning av parallell schemaläggning för flera platser – 2026-11-20
- Läste aktuell `WeatherNotificationScheduler` från utvecklingsgrenen och följde flödet från platsregister till iOS pending/delivered-notiser.
- Bekräftat: varje plats har egen schemaläggningstoken och egna stabila notis-ID:n. Avaktivering roterar platsens token innan väntande notiser tas bort, vilket skyddar mot att en äldre asynkron körning återlägger notiser för platsen.
- Identifierat kvarstående samordningsrisk: varje platskörning skriver samma globala `scheduledCountKey`, `scheduleUpdatedKey` och `scheduleStatusKey`. När flera platser schemaläggs parallellt kan status därför representera en mellanliggande ögonblicksbild och skrivas över av en annan platskörning. Det är inte ett tillförlitligt aggregerat slutresultat.
- Identifierat gränsfall i budgeten: `perPlaceLimit = max(1, min(8, 52 / registryCount))` ger minst en notis per plats. Om antalet registrerade platser överstiger 52 kan summan av platsbudgetarna därför överskrida den avsedda gränsen 52. Bevarade omedelbara frostnotiser ligger dessutom utanför den nya urvalslistans budgetberäkning.
- Nästa tekniska åtgärd: införa en serialiserad global samordning/kapacitetsbudget som räknar befintliga väntande Regnvakt-notiser, reserverar utrymme för SMHI och prioriterar omedelbar frost/is innan vanliga prognosnotiser. Statusvärden ska räknas och skrivas efter en samlad reconciliation, inte från varje platskörning.
- Ingen kodändring gjord i denna granskningspass. Inga tester eller byggningar kördes. Fysisk iPhone-verifiering återstår.
- CI för aktuell branch-head är inte bekräftad via commit-status eller PR-körningslistan i denna kontroll; tidigare godkända körningar gäller äldre commits och får inte räknas som verifiering av aktuell HEAD.



### Fördjupad granskning – separering av SMHI- och prognosnotiser – 2026-11-20
- Följt avstängnings- och rensningsvägarna i `WeatherNotificationScheduler`.
- Bekräftat att den globala avstängningsgrenen tar bort samtliga väntande `regnvakt.weather.`-notiser och anropar dessutom `SMHIWarningService.clearPendingNotifications()`. Det innebär att den vanliga aviseringsinställningen i denna kodväg även påverkar väntande SMHI-varningar. Detta ska inte ändras utan att inställningarnas avsedda semantik och SMHI-tjänstens egen livscykel har verifierats.
- Bekräftat att `removeAll()` rensar både `regnvakt.weather.` och `smhi.` från väntande och levererade notiser. Denna metod är en bred totalrensning och får inte återanvändas som en vanlig plats- eller prognosreconciliation.
- Bekräftat att per-plats schemaläggning endast filtrerar och ersätter sina egna `regnvakt.weather.<plats>.`-identifierare. SMHI-notiser räknas inte in i den nuvarande 52-gränsen; kommentaren om reserverat utrymme är därför inte en faktisk kapacitetsreservation.
- Arkitekturkrav för nästa implementation: behåll tydliga ägarskapsgränser mellan prognosnotiser och SMHI-varningar. Reconciliation ska endast ta bort identifierare som Regnvakt-schemaläggaren äger, räkna verkligt kvarvarande pending-notiser innan kapacitet väljs och aldrig radera SMHI-varningar som bieffekt av en vanlig prognosuppdatering.
- Ytterligare verifiering krävs av SMHI-tjänstens egna inställningar och identifierarformat innan ändring av avstängningsbeteendet. Ingen kodändring gjord i denna granskning.
- Tester/build kördes inte i denna dokumentationspass. Branchens aktuella CI-resultat är fortsatt inte bekräftat; fysisk iPhone-verifiering återstår.



### Kapacitetsmodell och SMHI-kö – fördjupad verifiering – 2026-11-20
- Återkontrollerade aktuell branch-head: `feature/frost-notification-audit` är identisk med dokumenterad commit `d0377eb86805a29b319f21c722b8b45cfdd96d05`. Draft PR #1 är fortsatt öppen. Inga workflow-körningar returnerades för denna commit; aktuell kod är därför inte CI-verifierad.
- Lokaliserade SMHI-implementationen till `VADER/NotificationInboxView.swift` och följde dess faktiska köhantering, inte bara anropsställena i inställningsvyn.
- Bekräftat att SMHI har en egen actor (`SMHIWarningNotificationGate`) för deduplicering och samtidiga anspråk. SMHI-tjänsten räknar befintliga väntande `smhi.`-requests och tillåter högst åtta aktiva SMHI-requests i sin egen kö. Varningar prioriteras röd, orange, gul.
- Bekräftat att SMHI:s kö och prognosschemaläggarens urval är två separata budgetar. Prognosschemaläggaren väljer upp till 52 notiser i teorin, medan SMHI separat kan lägga till upp till åtta. Prognosbudgeten läser inte in övriga väntande appnotiser som en faktisk global kapacitetsbudget.
- Förtydligat att enbart ändra `perPlaceLimit` inte löser problemet: platskörningarna skapar, tar bort och ersätter requests asynkront och skriver globala statusfält oberoende av varandra. En korrekt lösning behöver samla kandidater från samtliga registrerade platser, ta hänsyn till redan väntande requests och bevarade omedelbara frostnotiser, göra ett enda globalt urval och skriva status först efter avslutad reconciliation.
- Säkerhetskrav: omedelbar frost och halkrisk ska ha högsta prioritet; SMHI:s befintliga kö och varningsägarskap ska bevaras; prognosreconciliation får endast ersätta `regnvakt.weather.`-identifierare. Huvudreglagets avsiktliga avstängning av båda kanalerna ska fortsatt hanteras explicit, inte som sidoeffekt av vanlig prognosuppdatering.
- Ingen kodändring gjord: befintlig arkitektur behöver först omformas till en global reconciliation för att undvika att en isolerad budgethjälpare ger falsk trygghet. Inga tester eller byggen kördes. iPhone-verifiering återstår.
- Nästa implementation: extrahera en ren, testbar urvalsmodell och koppla den till en enda samlad schemaläggningsoperation. Tester ska omfatta 1, 8, 52 och fler än 52 bevakade platser, kvarvarande frostrequests, SMHI-reserv, redan väntande notiser, noll tillgängliga platser och samtidig uppdatering/avaktivering.


### Första implementationen av global notisbudget – 2026-11-20
- Branch-head vid arbetets start var `a9295161ec3a509ce9f7c75e0d1ffaf0146b6ca9`; draft PR #1 var öppen mot `feature/wind-radar`.
- Tillagt `VADER/WeatherNotificationBudget.swift`: Foundation-baserad och deterministisk urvalsmodell med prioritetsklasserna omedelbar frost, säkerhetskritisk frost/is och vanlig prognos.
- Urvalsmodellen deduplicerar stabila identifierare, sorterar deterministiskt, filtrerar redan levererade identifierare och räknar bevarade väntande omedelbara frostnotiser före övriga kandidater. Redan väntande frostnotiser behålls även om de ensamma överskrider inmatad kapacitet; säkerhetsnotiser tas inte bort för att passa ett budgettal.
- Tillagt `Tests/WeatherNotificationBudgetTests.swift` med tester för kapacitetsgränserna 0, 1, 8 och 52 (80 kandidater från 57 plats-ID:n), global prioritetsordning över flera platser, bevarad frost, leveransdeduplicering, dubbla identifierare och deterministisk sortering.
- Uppdaterat `project.yml` så att produktionskällan även kompileras direkt i testmålet, i linje med tidigare lösning för fristående regeltester.
- Uppdaterat `docs/NOTIFICATION_RECONCILIATION_DESIGN.md` med implementeringsstatus och tydlig avgränsning.
- Verifiering: samtliga fyra ändrade/nya filer återlästa från GitHub. Produktionskällan för urvalsmodellen har klarat `swiftc -typecheck` med Swift 6.2.1 på Linux. Detta är endast syntax-/typkontroll av den fristående filen, inte XCTest, XcodeGen, iOS-bygg eller integrationstest.
- CI: inga PR-workflow-körningar returnerades för aktuell HEAD `07b66ff07676e32d69f665123e8698d11b6415c4`. Ingen Xcode-miljö finns lokalt. Tester och iOS-build är därför inte verifierade.
- Viktig begränsning: urvalsmodellen är ännu inte inkopplad i `WeatherNotificationScheduler`. Den globala reconciliationen, kapacitetsberäkningen mot verkliga pending SMHI/övriga requests, samtidighetsskyddet och samlad statusuppdatering återstår. Funktionen får inte betraktas som färdig.
- Branch/commit: `feature/frost-notification-audit`, aktuell HEAD `07b66ff07676e32d69f665123e8698d11b6415c4`. Draft PR #1 är fortsatt öppen och har inte slagits ihop.
- Fysisk iPhone-verifiering och IPA är inte aktuella förrän global scheduler-integration och CI har passerat.


## SMHI-ägarskap vid avstängning av prognosnotiser – 2026-11-20

### Ändring
- `VADER/WeatherNotificationScheduler.swift`: den globala avstängningsgrenen för prognosschemaläggaren tar inte längre bort `smhi.*`-notiser.
- Prognosschemaläggaren äger endast `regnvakt.weather.*`. SMHI:s notisägare ansvarar för `smhi.*`.
- Huvudreglaget i `NotificationSettingsView` har redan en uttrycklig avstängningshantering som anropar `SMHIWarningService.clearPendingNotifications()`. Därmed ligger den avsiktliga användaråtgärden kvar hos inställningsflödet i stället för att en vanlig prognosuppdatering kan radera SMHI-notiser.

### Verifiering
- Källan och inställningsflödet granskades på `feature/frost-notification-audit`.
- Bekräftat i koden: huvudreglagets `onChange` städar SMHI-notiser när användaren stänger av alla aviseringar; den vanliga prognosschemaläggaren behöver därför inte göra samma sak.
- Ingen iOS-build eller XCTest körd i denna miljö. Ingen fysisk enhetstestning utförd.

### Filer
- `VADER/WeatherNotificationScheduler.swift`
- `docs/DEVELOPMENT_LOG.md`

### Kvarstår
- Den globala schemaläggaren är fortfarande inte integrerad. Per-plats-jobben och delade statusnycklarna kvarstår och måste ersättas av en enda global reconciliation innan budgetfunktionen kan betraktas som färdig.


## Förberedande kapacitetsberäkning för global notisbudget – 2026-11-20

### Ändringar
- `VADER/WeatherNotificationBudget.swift`: tillagt `availableForecastCapacity` som räknar tillgängligt utrymme efter total appbudget, reserverad marginal, väntande SMHI-notiser och väntande notiser i andra namespace.
- `Tests/WeatherNotificationBudgetTests.swift`: tre tester tillagda för avräkning av externa notiser, nollgolv och negativa indata.
- `docs/NOTIFICATION_RECONCILIATION_DESIGN.md`: beskriver formeln och markerar att den ännu inte används av produktionsschemaläggaren.

### Verifiering
- Ändrade käll- och testfiler återlästa från GitHub efter uppdatering.
- Ingen XCTest, XcodeGen eller iOS-build körd. Ingen CI-körning bekräftad.
- Funktionen är fristående och inte inkopplad i `WeatherNotificationScheduler`; detta är förberedande logik, inte färdig global budgetering.

### Filer
- `VADER/WeatherNotificationBudget.swift`
- `Tests/WeatherNotificationBudgetTests.swift`
- `docs/NOTIFICATION_RECONCILIATION_DESIGN.md`
- `docs/DEVELOPMENT_LOG.md`

### Kvarstår
- Fastställ appens konservativa budget/reserv som produktpolicy, utan att kalla den iOS-plattformsgräns.
- Implementera en enda global reconciliation och koppla in både kapacitetsberäkningen och urvalsmodellen.
- Lägg till integrationstester för verkliga pending requests, samtidighet, borttagning av platser och aggregerad status.


### Fördjupad spårning av anropsflödet för global reconciliation – 2026-11-20

#### GitHub-status vid arbetets start
- PR #1 är öppen, draft och inte sammanslagen. Aktuell head är `83fb73a3a96dbc346b5ecd534b61127b2fb19038`.
- GitHub rapporterar nu `mergeable: true`; den tidigare observationen `mergeable: false` är inte längre aktuell.
- Jämförelsen mot `feature/wind-radar` visar 428 commits före och 0 bakom. Inga PR-workflow-körningar returnerades för den kontrollerade committen. Detta bekräftar inte att CI har passerat.

#### Verifierade anropsvägar
- `WeatherViewModel.init()` anropar `refreshFromStoredForecast()` vid start.
- `NotificationSettingsView` anropar `refreshFromStoredForecast()` vid ändringar av huvudreglage, vädervaktsreglage, förvarningstid och tysta timmar.
- `WeatherViewModel.setMonitoring(enabled: true)` hämtar en prognos, anropar `refresh(...)` och därefter `refreshFromStoredForecast()`. Det ger både ett direkt platsjobb och en ny omgång platsjobb från registret.
- `WeatherViewModel.setMonitoring(enabled: false)` tar bort platsens requests och registerpost, och anropar därefter `refreshFromStoredForecast()`.
- `WeatherViewModel.removePlace()` använder samma borttagnings- och omplaneringsflöde.
- `WeatherViewModel.loadWeather()` anropar `refresh(...)` för den valda platsen om den bevakas och hämtar sedan prognoser för övriga bevakade platser med separata `refresh(...)`-anrop.
- Varje `refresh(...)` startar omedelbart ett eget asynkront `schedule(...)`-jobb. `refreshFromStoredForecast()` skapar dessutom ett separat jobb per registrerad plats. Det bekräftar att samtidighetsproblemet inte bara gäller statusnycklarna utan även att samma plats kan få överlappande schemaläggningsjobb.

#### Konsekvenser som måste hanteras i implementationen
- `refresh(...)` måste bli en registeruppdatering följd av en enda global reconciliation, inte starta ett eget platsjobb.
- `refreshFromStoredForecast()` måste ta en enda snapshot av hela registret och starta exakt en reconciliation.
- Borttagning måste invalidiera pågående reconciliation och starta en ny global reconciliation efter att registerändringen är synlig. En platsvis asynkron rensning får inte kunna lämna kvar ett gammalt urval eller skriva status efter den nya körningen.
- Den nuvarande `schedule(...)`-metoden blandar händelsegenerering, iOS-requestkonstruktion, behörighetskontroll, per-plats urval, rensning, add och global statusrapportering. Dessa ansvar måste delas innan en global commit kan göras säkert.
- Nuvarande urval bevarar väntande aktuell frost per plats, men budgeten väljs före pending-snapshot och räknar inte SMHI eller övriga namespace. En global implementation måste bygga bevarade kandidater från den faktiska pending-snapshoten och därefter välja alla platser gemensamt.
- Den nuvarande metoden skriver global status även från felhantering inne i varje platsjobb. Fel måste i stället samlas och rapporteras från den globala reconciliationens slutresultat.

#### Verifiering och avgränsning
- Granskat aktuell scheduler, budgetmodell, budgettester, NotificationSettingsView och WeatherService på utvecklingsgrenen.
- Ingen källkod ändrades i denna granskning. Inga XCTest, XcodeGen, iOS-build eller enhetstester kördes.
- Nästa kodsteg är att extrahera requestbyggandet från den gamla platsvisa `schedule(...)`-metoden och införa en enda global reconciliation med generationskontroll före borttagning och varje tillägg.
- Ingen IPA har byggts. Fysisk iPhone-verifiering återstår.


### Klassificering av väntande notiser per namespace – 2026-11-20

- Lade till `WeatherNotificationPendingCounts` och `WeatherNotificationBudget.countExternalPendingRequests(...)`.
- Klassificeringen räknar `smhi.*` separat, räknar alla andra externa namespace som unrelated och exkluderar `regnvakt.weather.*`, eftersom forecast-namespace ska ersättas av reconciliation.
- Lade till två XCTest-fall för blandade namespace samt tomma/okända namespace.
- `WeatherNotificationBudget.swift` och `WeatherNotificationBudgetTests.swift` ändrades. Ändringen är en testbar byggsten och är ännu inte inkopplad i live-schemaläggaren.
- Lokal kontroll: `swiftc -typecheck` av den isolerade Foundation-baserade budgetkällan passerade. XCTest/XcodeGen/iOS-build kan inte köras i denna Linux-miljö.
- Commit: `cfdc03e0ee798f12931870a0c7e30664c09a2de1` (budgetmodell), följt av `c69925f168d63bec9daabe91c9f979ed18c46ee9` (tester).
- Kvar: koppla klassificeringen till en enda pending-snapshot i global reconciliation och verifiera med integrationstester. Ingen IPA eller fysisk enhetstestning.


### Kantfallstestning av global notisbudget – 2026-11-20
- GitHub kontrollerades före arbetet: `feature/frost-notification-audit` låg på `1166a073790ee6a45722f20b475ec7676abff1dc`; PR #1 var öppen, draft och `mergeable: true`. Commit-status var `pending` utan statuskontroller och inga PR-workflow-körningar returnerades.
- Utökade `Tests/WeatherNotificationBudgetTests.swift` med två fall: samtliga redan väntande aktuella frostnotiser bevaras även när de tillsammans överstiger kapaciteten, och tomma identifierare ignoreras när kapaciteten är negativ.
- Uppdaterade `docs/NOTIFICATION_RECONCILIATION_DESIGN.md` så att status och verifieringsgränser speglar testtillägget.
- Verifiering: en fristående Swift-exekvering av budgetmodellens relevanta logik passerade fem kontroller: namespace-klassificering, avräkning av externa notiser, global säkerhetsprioritet, bevarad frost vid noll kapacitet och deduplicering av levererade ID:n. Detta var en separat harness, inte XCTest och inte full verifiering av repositoryts testmål.
- Inga iOS-ramverk, XcodeGen, iOS-build eller fysisk iPhone kunde verifieras i Linux-miljön. Ingen IPA byggd.
- Filer: `Tests/WeatherNotificationBudgetTests.swift`, `docs/NOTIFICATION_RECONCILIATION_DESIGN.md`, `docs/DEVELOPMENT_LOG.md`.
- Kodens globala reconciliation är fortfarande inte integrerad. Per-plats `schedule(...)`-jobb, separata pending-snapshots och delade statusuppdateringar kvarstår. Nästa steg är att extrahera requestgenereringen och koppla kandidaterna till en enda generationsskyddad reconciliation.


### Fastställd kapacitetspolicy inför global scheduler – 2026-11-20

- GitHub kontrollerades före ändring: PR #1 är fortsatt öppen, draft och osammanslagen. Grenen `feature/frost-notification-audit` låg på `f5647bbfaab27551f16401eaaa5d21108d99e4df`; PR rapporterade `mergeable: true`.
- Fastställde en första konservativ Regnvakt-policy: total pending-budget 52 och extra reserverat utrymme 8. Detta är appens interna budget, inte en iOS-plattformsgräns. Faktiskt väntande SMHI- och övriga notiser ska dras av utöver reserven.
- `VADER/WeatherNotificationBudget.swift`: lade till namngivna konstanter för totalbudget och reserv.
- `Tests/WeatherNotificationBudgetTests.swift`: kapacitetstester använder nu konstanterna och ett uttryckligt policytest verifierar grundkapaciteten 44.
- `docs/NOTIFICATION_RECONCILIATION_DESIGN.md`: dokumenterade beslutet och dess avgränsning.
- Verifiering: ändringarna sparades sekventiellt via GitHub och ska återläsas i slutkontrollen. XCTest och iOS-build är inte körda i denna miljö. Ingen CI-körning har ännu verifierats för den nya HEAD.
- Kvar: implementera den enda generationsskyddade globala reconciliationen och koppla in budget, pending-klassificering och urval. Inga IPA- eller iPhone-tester är genomförda.


### Interimistiskt skydd mot notisbudgetens platsöverskridande – 2026-11-20

- GitHub kontrollerades före arbetet: PR #1 var öppen, draft och inte sammanslagen; utvecklingsgrenen var `feature/frost-notification-audit`.
- `VADER/WeatherNotificationBudget.swift`: lade till `interimPerPlaceLimit(registryCount:)`, som fördelar grundkapaciteten 44 (total appbudget 52 minus reserv 8) mellan registrerade platser och aldrig tvingar fram minst en notis per plats.
- `VADER/WeatherNotificationScheduler.swift`: den gamla beräkningen `max(1, min(8, 52 / registryCount))` ersattes med den nya tillfälliga hjälpfunktionen. Därmed kan fler än 44 platser inte automatiskt ge minst en ny prognosnotis var.
- `Tests/WeatherNotificationBudgetTests.swift`: test tillagt för 1, 8, 44, 45, 52 och 0 registrerade platser.
- `docs/NOTIFICATION_RECONCILIATION_DESIGN.md`: begränsningarna för interimslösningen dokumenterade.
- Verifiering: GitHub-uppdateringarna lyckades; slutlig återläsning och branch/PR-kontroll följer. XCTest, Xcode/iOS-build och fysisk enhetstestning är inte körda i denna miljö.
- Begränsning: detta är inte global reconciliation. Kapaciteten tar inte hänsyn till live-pending SMHI/övriga requests, kandidater väljs fortfarande per plats och parallella statusuppdateringar kvarstår.
- Kvar: implementera en enda global read/select/replace/add/status-cykel med generationsskydd. Ingen IPA byggd.

### Skydd mot föråldrade schemaläggningsfel – 2026-11-20

- GitHub kontrollerades före arbetet: PR #1 var öppen, draft och osammanslagen. Grenen feature/frost-notification-audit pekade på df6d6d8c3a02cc4e5f4afba79dc207ca2e2c688c; PR var mergeable vid kontrollen.
- VADER/WeatherNotificationScheduler.swift: felhanteringen efter UNUserNotificationCenter.add kontrollerar nu platsens token och globala token innan den skriver ett schemaläggningsfel till delad status.
- Syfte: ett äldre asynkront platsjobb som misslyckas efter att ha blivit ogiltigförklarat ska inte kunna skriva över status från en nyare uppdatering.
- Verifiering: ändringen är avgränsad till felgrenen och bygger på befintliga tokenkontroller i samma metod. Filen ska återläsas och diffen granskas efter commit. XCTest/iOS-build kan inte köras i denna Linux-miljö.
- Filer: VADER/WeatherNotificationScheduler.swift, docs/DEVELOPMENT_LOG.md.
- Kvar: detta löser endast en sen status-skrivning; flera platsjobb och separata statusuppdateringar finns fortfarande. Nästa större steg är requestgenerering som gemensam kandidatlista och en enda global reconciliation.

### Extraherad prognosbaserad notisgenerering – 2026-11-21

- GitHub kontrollerades före arbetet: PR #1 var öppen, draft och osammanslagen; grenen feature/frost-notification-audit låg på fe9ca77fb32945743e46060971193e891580a051 och PR rapporterade mergeable true.
- VADER/WeatherNotificationScheduler.swift: flyttade omvandlingen från prognoshändelser till UNNotificationRequest till den separata funktionen makeRequests(place:hours:currentTemperature:defaults:locationID:). Den befintliga schemaläggaren anropar nu funktionen och behåller därefter sin nuvarande sortering, urvalsgräns och platsvisa ersättning.
- Syfte: separera renare prognos-/notisgenerering från själva schemaläggningscykeln, så att nästa steg kan samla requests från flera platser i en gemensam kandidatlista utan att duplicera innehålls- och identifierarlogiken.
- Bevarade befintliga regler för svensk tidszon, tystnadstider, frost/halkprioritet, stabila identifierare och innehåll. Ingen ändring av budget- eller urvalspolicy i denna del.
- Verifiering: filen återlästes efter ändringen; kontroll visade att makeRequests returnerar request-listan och att anropsstället använder var eftersom den befintliga sorteringen muterar listan. XCTest, Xcode/iOS-build och fysisk enhetstestning är inte körda.
- Filer: VADER/WeatherNotificationScheduler.swift, docs/DEVELOPMENT_LOG.md.
- Kvar: schedule(...) är fortfarande platsvis, använder interimistisk per-platsgräns och skriver delad status per jobb. Nästa steg är att extrahera en kandidatmetadatafunktion och därefter införa en enda generationsskyddad global reconciliation.

### Kandidatmetadata inkopplad i befintligt notisurval – 2026-11-21

- GitHub kontrollerades före arbetet: PR #1 var öppen, draft och osammanslagen; feature/frost-notification-audit låg på ae05f52b2af5428a67646c758de1868cad4c8dd2 och PR rapporterade mergeable true.
- VADER/WeatherNotificationBudget.swift: lade till makeCandidate(...) för gemensam och testbar mappning av notiser till immediateFrost, safetyCritical eller forecast samt flagga för redan väntande aktuell frost.
- Tests/WeatherNotificationBudgetTests.swift: lade till tester för prioritetsmappning och bevarandeflagga.
- VADER/WeatherNotificationScheduler.swift: lade till makeCandidates(...) som mappar UNNotificationRequest till kandidatmetadata. Den platsvisa schedule(...) läser nu pending/delivered innan urval och använder WeatherNotificationBudget.select(...) i stället för egen sortering/prefix-selektion. Urvalet bevarar deterministisk ordning från select.
- docs/NOTIFICATION_RECONCILIATION_DESIGN.md: dokumenterade inkopplingen och avgränsningen.
- Verifiering: samtliga ändrade filer återlästes efter GitHub-uppdatering. Inga XCTest-, XcodeGen- eller iOS-build-resultat finns; GitHub workflow-körning för HEAD har ännu inte verifierats. Ingen fysisk enhet eller IPA.
- Filer: VADER/WeatherNotificationBudget.swift, Tests/WeatherNotificationBudgetTests.swift, VADER/WeatherNotificationScheduler.swift, docs/NOTIFICATION_RECONCILIATION_DESIGN.md, docs/DEVELOPMENT_LOG.md.
- Kvar: urvalet är fortfarande per plats med interimistisk kapacitet. Global pending-snapshot, globalt urval, en enda destructive replace/add-cykel, generationsskydd och en enda aggregerad statusuppdatering är inte implementerade.


### Kapacitet från gemensam pending-snapshot – 2026-11-21

- GitHub kontrollerades före arbetet: PR #1 var öppen, draft och osammanslagen; feature/frost-notification-audit låg på 305cef57c4a54b4117879c15da47f2061acbd36e och PR rapporterade mergeable true.
- VADER/WeatherNotificationBudget.swift: lade till availableForecastCapacity(pendingIdentifiers:), som klassificerar en pending-snapshot och beräknar prognosutrymmet med appens budget 52, reserverat utrymme 8 samt avräkning för väntande SMHI- och övriga notiser. Regnvakts egna forecast-ID:n räknas inte av eftersom reconciliation ska ersätta dem.
- Tests/WeatherNotificationBudgetTests.swift: lade till tester för blandade namespaces och för att kapaciteten aldrig blir negativ när externa notiser fyller budgeten.
- Verifiering: ändringarna skrevs till GitHub. XCTest och iOS-build är inte körda i denna miljö; återläsning och slutlig branch-/PR-kontroll ska genomföras.
- Filer: VADER/WeatherNotificationBudget.swift, Tests/WeatherNotificationBudgetTests.swift, docs/NOTIFICATION_RECONCILIATION_DESIGN.md, docs/DEVELOPMENT_LOG.md.
- Kvar: helpern är ännu inte inkopplad i live-schemaläggaren. Nästa steg är den globala reconciliationen som använder en enda pending-/delivered-snapshot för samtliga platser.


### Korrigerat förväntat kapacitetsvärde i test – 2026-11-21

- Vid eftergranskning av det nya testet för blandade pending-namespace upptäcktes ett fel i testets förväntade värde: 52 totalbudget − 8 reserverade − 2 SMHI − 2 övriga = 40, inte 34.
- Tests/WeatherNotificationBudgetTests.swift: korrigerade förväntat värde till 40. Produktionslogiken ändrades inte.
- Verifiering: aritmetiken kontrollerad manuellt och ändringen sparad i GitHub. XCTest är inte körda.
- Filer: Tests/WeatherNotificationBudgetTests.swift, docs/DEVELOPMENT_LOG.md.
- Kvar: global reconciliation är fortfarande inte inkopplad i live-schemaläggaren.


### Serialiserad prognosuppdatering med global generationsspärr – 2026-11-21

- GitHub kontrollerades före arbetet: PR #1 var öppen, draft och osammanslagen; feature/frost-notification-audit låg på a1e0079cd42db79aeca288efeb807189f02fec28 och PR rapporterade mergeable true.
- VADER/WeatherNotificationScheduler.swift: refresh(place:...) uppdaterar nu registret och startar en gemensam refreshFromStoredForecast()-batch i stället för ett separat schedule-task för den enskilda platsen.
- refreshFromStoredForecast() roterar nu globalScheduleTokenKey vid varje ny batch, skapar platsvisa token för ett sorterat register-snapshot och schemalägger platserna sekventiellt i en enda Task. Äldre batcher stoppas när deras globala token inte längre gäller. Stale forecasts äldre än två timmar hanteras fortsatt utan att armera nya prognosnotiser.
- Samma metods legacy-grenar kontrollerar nu global token efter asynkron pending-läsning eller före schemaläggning. Detta skyddar även migreringsvägen mot att en gammal batch skriver status eller startar ett föråldrat jobb.
- Kodgranskning hittade även en felaktigt dubblerad backslash i ett Swift key path-uttryck för pending identifiers; den är korrigerad till `\.identifier`.
- Verifiering: ändrad fil återlästes och kontrollerades för sekventiell loop, global generationskontroll, frånvaro av direkt schedule-task i refresh(place:) samt korrekta key paths. XCTest, Swift/iOS-build och fysisk enhetstestning är inte körda.
- Filer: VADER/WeatherNotificationScheduler.swift, docs/DEVELOPMENT_LOG.md, docs/NOTIFICATION_RECONCILIATION_DESIGN.md.
- Viktig begränsning: detta är en serialiserad övergångslösning, inte den färdiga globala urvalsalgoritmen. Varje plats använder fortfarande interimistisk kapacitet och läser notification-center snapshots separat. Ett enda globalt kandidatval och en enda replace/add/status-cykel återstår.


### Användarrapporterat fel: aviseringar utlöses vid appstart – 2026-11-21

**Rapport:** Användaren får en ny notisbanner ovanpå appen direkt när Regnvakt öppnas. Det gäller både vanliga väderaviseringar och SMHI-aviseringar; SMHI-innehållet upplevs ofta som gammalt. Användaren upplever dessutom att SMHI-aviseringar inte kommer när appen är stängd.

**Källkodsspårning på `feature/frost-notification-audit` (HEAD före denna dokumentationsändring: `4e3f84fc273014dc9320533d59bf0196b388a873`):**

- `VADER/ContentView.swift`: `scenePhase == .active` anropar `weatherModel.refreshSMHIWarnings()`. Detta sker när appen går till aktivt läge.
- `VADER/WeatherService.swift`: `refreshSMHIWarnings()` startar `SMHIWarningService.checkAndNotify(at:)`. Samma kontroll startas även från `loadWeather(...)`.
- `VADER/NotificationInboxView.swift`: varje aktiv SMHI-varning som inte redan är deduplicerad skapas som en lokal notis med `UNTimeIntervalNotificationTrigger(timeInterval: 2)`. Det innebär att en kontroll som startar vid appöppning kan skapa en banner ungefär två sekunder senare. Det är en konkret kodväg som matchar användarens observation.
- `VADER/WeatherService.swift`: `WeatherViewModel.init()` kör `WeatherNotificationScheduler.refreshFromStoredForecast()` vid appstart.
- `VADER/WeatherNotificationScheduler.swift`: sparad aktuell temperatur kan generera en omedelbar frostrisknotis med två sekunders trigger om prognosposten är högst två timmar gammal och dagens frostdeduplicering inte redan är satt. Detta är en andra konkret kodväg för en notis vid appstart.
- SMHI-kontrollen filtrerar bort varningar vars sluttid har passerat och skiljer aktiva från kommande varningar. En gammal banner kan därför bero på att varningen fortfarande är aktiv enligt SMHI, eller på att en tidigare lokal begäran redan hunnit köas; detta måste verifieras mot faktisk pending-/delivered-status på enheten.
- SMHI:s signatur-gate försöker deduplicera accepterade notiser, men källkodsläsning ensam bevisar inte varför användaren ändå ser upprepning. Behöver testa persisted signatures, epoch och pending identifiers på enheten.

**Bedömning:** Det är verifierat i källkoden att appaktivering kan starta en SMHI-kontroll som lägger en tvåsekundersnotis, och att appstart kan återställa en omedelbar frostnotis från sparad prognos. Det är ännu inte verifierat att dessa två vägar ensamma förklarar samtliga banners. Att SMHI-notiser uteblir när appen är stängd behöver separat undersökning av iOS leverans/foreground-presentation och hur ofta SMHI-data faktiskt kontrolleras när appen inte är aktiv. Nuvarande kod visar en kontroll vid appaktivering och väderladdning; någon verifierad serverbaserad pushkanal finns inte i denna implementation.

**Ändringar i denna arbetsinsats:** Endast dokumentation av rapport och källkodsspårning. Ingen produktionslogik ändrad. Ingen notisrensning eller beteendeförändring införs innan pending/delivered-ägarskap och förväntat beteende har verifierats.

**Filer granskade:** `VADER/ContentView.swift`, `VADER/WeatherService.swift`, `VADER/NotificationInboxView.swift`, `VADER/WeatherNotificationScheduler.swift`.

**Verifiering:** GitHub-källkod återläst på PR #1:s head. Ingen iOS-build, XCTest eller fysisk enhetstestning utförd. PR #1 är öppen, draft och omerslagen; inga workflow runs hittades för aktuell head vid kontrollen.

**Nästa steg:**
1. Spåra `UNUserNotificationCenterDelegate`-registrering och `willPresent`-hantering för att fastställa foreground-presentation.
2. Kontrollera samtliga anropsvägar för `refreshSMHIWarnings()` och eventuell bakgrundsuppgift.
3. Lägg till diagnostik/testbar ren logik för att inte schemalägga en ny omedelbar SMHI-notis enbart för att appen aktiveras; notifiering ska styras av ny/ändrad varning och korrekt giltighet, inte av att vyn öppnas.
4. Granska aktuell-frostens appstartsbeteende så att en gammal sparad temperatur inte orsakar en oönskad omedelbar banner.
5. Verifiera på iPhone med appen i förgrund, bakgrund och helt avslutad innan felet markeras löst.


### Förgrundspresentation – ytterligare rotorsak identifierad – 2026-11-21

Fortsatt granskning hittade appens notisdelegat i `VADER/VADERApp.swift`:

```swift
completionHandler([.banner, .sound, .list])
```

`RegnvaktNotificationDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:)` begär alltså banner, ljud och notiscenterlista för **varje** notis som levereras medan appen är i förgrunden. Detta förklarar varför en redan köad eller nyss utlöst notis kan visas ovanpå appen när användaren öppnar den. Det är en separat mekanism från att scheduler/SMHI skapar själva notisbegäran.

**Verifierad kedja:**
- `VADER/VADERApp.swift`: alla förgrundsnotiser presenteras med banner och ljud.
- `VADER/ContentView.swift`: appaktivering startar SMHI-kontroll.
- `VADER/NotificationInboxView.swift`: nya aktiva SMHI-varningar kan schemaläggas med två sekunders fördröjning.
- `VADER/WeatherService.swift`: appstart startar även återställning av prognosnotiser.
- `VADER/WeatherNotificationScheduler.swift`: aktuell frost kan schemaläggas om sparad prognos/temperatur fortfarande är färsk.

**Designbeslut som krävs före ändring:** Ska appen visa banner/ljud när en notis levereras medan Regnvakt redan är öppen, eller ska den bara uppdatera notisinkorgen/olästmarkeringen och låta iOS visa notisen när appen ligger i bakgrunden? Nuvarande kod väljer alltid banner + ljud + lista. Att tysta alla förgrundsnotiser kan även dölja en genuint ny säkerhetsvarning medan användaren tittar på appen. Ingen ändring görs utan att definiera detta beteende.

**Bakgrundsbegränsning:** `VADERApp.swift` importerar `BackgroundTasks`, men den granskade app-entry-filen registrerar ingen BGTask. Källkodsspårningen har ännu inte visat någon verifierad återkommande bakgrundsuppgift som hämtar SMHI-data när appen är avslutad. Lokala notiser kan levereras när de redan är schemalagda, men kan inte på egen hand upptäcka en senare publicerad varning utan att appen körs eller extern push används.

**Status:** Rotorsak för att förgrundsnotiser visas som banners är verifierad i källkoden. Orsaken till upprepade/gamla SMHI-notiser är delvis spårad men behöver pending/delivered-diagnostik på enheten. Ingen produktionskod ändrad.


### SMHI-notisernas giltighet och appaktiveringsflöde – fördjupad granskning 2026-11-21

- Återläst hela SMHI-flödet i `VADER/NotificationInboxView.swift`, inklusive `SMHIWarningNotificationGate`, `checkAndNotify(at:)`, identifierargenerering och pending-rensning.
- Bekräftat att SMHI-signaturen består av varningsområdets ID, nivå, rubrik och starttid. Gate sparar accepterade signaturer i UserDefaults och återanvänder dem endast när de fortfarande finns i den aktuella aktiva mängden. En redan pending request med samma deterministiska ID återhämtas som accepterad i gaten i stället för att läggas till igen.
- Bekräftat att pending SMHI-requests som inte längre finns i mängden aktiva varningar för de bevakade koordinaterna tas bort vid nästa lyckade SMHI-kontroll. Den kontrollen läser pending-kön och skyddar rensningen med notification epoch.
- Identifierad begränsning: den skapade SMHI-notisens `userInfo` innehåller endast `watch`, `warningID` och `area`; själva notisen saknar start-/sluttid och explicit giltighetstid. Triggern är två sekunder. Giltighetskontrollen sker alltså före schemaläggning och vid nästa lyckade kontroll/rensning, inte som en separat expiration-policy på den redan skapade notisen.
- Den här konstruktionen gör inte en gammal varning automatiskt felaktig: en varning som SMHI fortfarande anger som aktiv och som påverkar en bevakad koordinat kan vara legitim att visa. För att avgöra användarens upplevda gamla varning krävs därför jämförelse mellan notisens warningID/area, SMHI:s aktuella start/slut och enhetens pending-/delivered-lista.
- Ingen kodändring genomförd i denna omgång. Vi ska inte ändra deduplicering eller rensa pending-notiser utan att först fånga faktisk köstatus; det riskerar att förlora giltiga säkerhetsvarningar.
- Nästa tekniska steg: skapa en ren, testbar notifieringspolicy som skiljer (1) kontroll/uppdatering av varningsdata, (2) ny eller ändrad aktiv varning, (3) tillägg av lokal notis och (4) förgrundspresentation. Appaktivering ska inte ensam vara skäl att återavisera en oförändrad aktiv varning.
- Verifiering: GitHub-källkod återläst på utvecklingsgrenen. Inga XCTest-, Xcode-/iOS-build- eller fysiska enhetstester har körts. Ingen IPA byggd.


### Första-baseline för SMHI-varningar – 2026-11-21

- VADER/NotificationInboxView.swift: infört en separat baseline för aktiva SMHI-signaturer. Vid första lyckade kontrollen efter installation/uppgradering sparas de varningar som redan är aktiva utan att skapa nya lokala notiser. De visas fortfarande i varningsflödet.
- Vid senare lyckade kontroller jämförs aktuell signaturmängd med föregående snapshot. Endast nytillkomna eller ändrade aktiva signaturer går vidare till notisschemaläggningen. Att appen aktiveras är därmed inte ensamt skäl att spela upp en tidigare aktiv varning.
- Baseline uppdateras bara efter att SMHI-data hämtats och notisbehörigheten är tillgänglig. Om schemaläggningen misslyckas eller notiser stängs av under den asynkrona operationen släpps signaturen ur baselinen, så nästa kontroll kan försöka igen.
- VADER/SMHIWarningNotificationPolicy.swift: tillagd Foundation-baserad, ren urvalsregel för nytillkomna signaturer.
- Tests/SMHIWarningNotificationPolicyTests.swift: fyra XCTest-fall för första baseline, ny/ändrad varning, återkomst efter att en varning försvunnit samt oförändrad varning.
- project.yml: den rena policyfilen inkluderad i VADERTests-källorna.
- Säkerhetsavgränsning: befintliga pending-notiser rensas inte blint. En redan köad giltig SMHI-varning kan därför fortfarande levereras; stale pending-requests tas bort enligt befintlig kontroll mot aktuell aktiv mängd. Förgrundspresentationen är ännu inte ändrad.
- Verifiering: GitHub-ändringar sparade. Källkod och testfall ska återläsas; XCTest, XcodeGen, iOS-build och fysisk iPhone-testning är inte körda i denna miljö. Ingen IPA byggd.
- Kvar: verifiera att testmålet kompilerar, kontrollera race mellan överlappande SMHI-kontroller samt besluta/implementera separat foreground-policy utan att tysta genuint nya säkerhetsvarningar.


#### Eftergranskning: baseline får inte konsumera oschemalagda varningar

- Kodgranskning av den första baseline-implementationen hittade en viktig kant: om hela aktuella mängden markerades som hanterad före kökapacitetskontrollen kunde varningar som inte fick plats i SMHI:s åttaplatser aldrig notifieras vid senare kontroll.
- Korrigerat i VADER/NotificationInboxView.swift: tidigare baseline-signaturer behålls endast så länge de fortfarande är aktiva. Nya signaturer markeras som hanterade först när motsvarande request redan finns pending eller när iOS har accepterat en ny request. Varningar som inte får plats eller vars schemaläggning misslyckas förblir nya och kan försökas igen.
- Ingen ändring av prioriteringsordning eller befintliga aktiva varningar i flödet.
- Verifiering: källkoden återlästes efter ändringen. XCTest och iOS-build är ännu inte körda.

## Förgrundspresentation – skydd mot gamla köade notiser

**Ändrat:** 2026-11-21  
**Gren:** `feature/frost-notification-audit`

### Ändringar
- `VADER/VADERApp.swift`: förgrundsdelegaten visar inte längre alla notiser automatiskt. Vanliga prognosnotiser tystas när appen är aktiv, men ligger kvar i iOS notiscenter.
- Säkerhetskritiska prognosnotiser (exempelvis aktuell frost och halkrisk) får fortfarande banner, ljud och notiscenterpresentation.
- SMHI-notiser kräver nu en igenkänd gul/orange/röd nivå, att varningen har startat, att den inte har passerat sluttiden samt att notisen schemalagts under de senaste tio minuterna. Detta ska hindra gamla SMHI-notiser som legat kvar i kön från att visas som nya vid appstart.
- `VADER/NotificationInboxView.swift`: SMHI-notisernas metadata innehåller nu nivå, start, slut och tidpunkt för schemaläggning.

### Avgränsningar och risker
- Tio minuters färskhetsgräns är en lokal presentationsregel, inte en garanti för att iOS levererar inom tio minuter.
- SMHI:s tidsstämplar måste kunna läsas av ISO-8601-parsern. Om starttid saknas eller inte kan tolkas tystas notisen i förgrunden; varningen ska fortfarande finnas i varningsflödet.
- Redan schemalagda SMHI-notiser från äldre appversioner saknar metadata och kommer därför inte att visas som banner i förgrunden. De kan fortfarande finnas i notiscenter.
- Detta löser inte att appen saknar garanterad bakgrundshämtning när den är helt avslutad. Nya SMHI-varningar kan inte upptäckas i realtid utan att appen får köra eller att en extern pushlösning införs.

### Verifiering
- Källkod uppdaterad på utvecklingsgrenen. Återläsning av de slutliga filerna och kontroll av GitHub Actions ska göras innan ändringen betraktas som byggverifierad.
- Inga fysiska iPhone-tester har genomförts i denna arbetsinsats.

## Aktuell frost vid appstart – stoppa återspelning från cache

**Ändrat:** 2026-11-21  
**Gren:** `feature/frost-notification-audit`

### Rotorsak
- Vid appstart körs `refreshFromStoredForecast()` för att återställa schemalagda prognosnotiser.
- Den tidigare logiken tillät en sparad aktuell temperatur så länge den sparade prognosen var högst två timmar gammal.
- Om den sparade temperaturen visade frost kunde appstart därför skapa en ny omedelbar frostnotis, trots att ingen ny temperatur hade hämtats i den aktuella sessionen.

### Ändringar
- `VADER/WeatherNotificationScheduler.swift`: `refresh(place:...)` markerar nu den interna reconciliation-körningen som baserad på en nyhämtad prognos och får därför utvärdera aktuell frost.
- Den publika `refreshFromStoredForecast()`, som används vid appstart och vid ändringar i bevakningslistan, återställer prognosnotiser men skickar inte en ny omedelbar aktuell-frostnotis från enbart lagrad temperatur.
- Redan schemalagda omedelbara frostnotiser bevaras av den befintliga pending-current-frost-regeln. Framtida prognosbaserade frost- och halknotiser fortsätter att schemaläggas från färsk prognos.
- `VADER/WeatherService.swift`: tog bort en redundant andra reconciliation direkt efter `refresh(place:...)`. Den andra körningen skapade en ny generationstoken och kunde ogiltigförklara den batch som just hade startats med den nyhämtade prognosen.

### Avgränsningar
- Regeln skiljer mellan en nyhämtad prognos och en återställd sparad prognos. Den bevisar inte att upstream-leverantörens temperatur är observationsmässigt färskare än själva API-svaret.
- Befintliga redan schemalagda säkerhetsnotiser raderas inte av denna ändring.
- Fortsatt fysisk testning behövs: aktuell frost vid live-refresh, appstart med gammal frost-cache, redan väntande frostnotis och flera bevakade platser.

### Verifiering
- Källkodsändringarna ska återläsas från GitHub och workflow-status kontrolleras.
- XCTest, XcodeGen, iOS-build och fysisk iPhone-testning är inte körda i denna arbetsinsats.


## SMHI-datumparser och förgrundspolicy – 2026-11-21

### Ändringar
- `VADER/SMHIWarningNotificationPolicy.swift`: lade till en gemensam Foundation-baserad datumparser som accepterar ISO-8601 med och utan fractional seconds samt SMHI:s tidszonlösa format som svensk lokal tid (`Europe/Stockholm`). Lade till ren policy för om en SMHI-notis får visas i förgrunden.
- Policyn kräver igenkänd gul/orange/röd nivå, schemaläggning högst tio minuter tidigare och inte i framtiden, giltig starttid som har inträffat samt tom eller giltig sluttid som inte passerat.
- `VADER/VADERApp.swift`: förgrundsdelegaten använder nu den testbara policyn. Säkerhetskritiska forecast-notiser har oförändrat beteende.
- `VADER/NotificationInboxView.swift`: den befintliga privata parsern är kvar tills vidare; nästa städsteg är att ersätta den med den gemensamma parsern.
- `Tests/SMHIWarningNotificationPolicyTests.swift`: lade till tester för fractional ISO8601, standard ISO8601, tidszonlös svensk lokal tid, felaktigt datum, okänd nivå, färsk aktiv varning samt stale/future/expired/malformed varningar.

### Filer
- `VADER/SMHIWarningNotificationPolicy.swift`
- `VADER/VADERApp.swift`
- `Tests/SMHIWarningNotificationPolicyTests.swift`
- `docs/DEVELOPMENT_LOG.md`

### Verifiering
- Källkod uppdaterad på `feature/frost-notification-audit`. Efterföljande återläsning och kontroll av aktuell Actions-körning krävs.
- XCTest, XcodeGen, iOS-build och fysisk iPhone-testning är inte körda i denna arbetsinsats. Ingen IPA byggd.

### Kvar
- Byt den privata parsern i `NotificationInboxView.swift` till den gemensamma implementationen.
- Kontrollera aktuell GitHub Actions-build och granska eventuella fel.
- Global notification reconciliation är fortsatt inte implementerad.
