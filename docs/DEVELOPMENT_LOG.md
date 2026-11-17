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
