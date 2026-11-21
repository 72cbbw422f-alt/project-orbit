# Global notification reconciliation

Status: pure selector and edge-case tests implemented; scheduler integration not implemented
Branch: `feature/frost-notification-audit`
Updated: 2026-11-20

## Why a global reconciliation is required

`WeatherNotificationScheduler.schedule(place:hours:currentTemperature:token:globalToken:locationID:)` currently builds and commits requests for one location at a time. Each invocation independently reads the notification center, selects up to its per-place limit, removes/replaces only that location's identifiers, adds requests, and writes shared global status keys.

The current limit `max(1, min(8, 52 / registryCount))` is not a global cap:
- The lower bound of one allows more than 52 requests when there are more than 52 registered locations.
- Preserved immediate-frost requests are not included in the selected request count.
- SMHI independently allows up to eight pending `smhi.` requests.
- Other app-owned local notifications are not counted.
- Parallel location jobs can make decisions from overlapping snapshots and overwrite the same status keys with intermediate counts.

An actor by itself is not a sufficient fix if its method suspends: Swift actors are reentrant at suspension points. A global operation must also use a revision/generation check so an older refresh cannot commit after a newer refresh or a watch removal.

## Ownership boundaries

| Identifier namespace | Owner | Normal forecast reconciliation |
|---|---|---|
| `regnvakt.weather.<location>.*` | Weather forecast scheduler | May replace/reconcile |
| `smhi.*` | SMHIWarningService | Must preserve; never remove as a side effect |
| Other identifiers | Other app features / system | Must preserve |

The master notifications switch may explicitly disable both forecast and SMHI channels, as its settings handler already calls SMHI cleanup. The forecast scheduler's ordinary refresh path must not clear SMHI requests. The individual SMHI switch remains independently authoritative.

## Required reconciliation sequence

1. Capture a monotonically changing global revision and a snapshot of the stored forecast registry.
2. Read notification authorization and current pending requests.
3. If global notifications are disabled or permission is unavailable, remove only forecast-owned pending identifiers, update aggregate status once, and return. Explicit SMHI cleanup remains the responsibility of the settings/SMHI owner.
4. Build forecast candidates for every registered location from the same registry snapshot. Reject stale forecasts using the existing two-hour freshness rule.
5. Recover already delivered immediate-frost markers and collect pending immediate-frost requests that must be preserved.
6. Re-read pending requests before committing. Classify forecast-owned, SMHI-owned, and unrelated requests by identifier prefix. Never delete SMHI or unrelated requests during this operation.
7. Calculate available capacity from the actual pending set and a documented safety ceiling/reserve. Do not assume the historical value 52 is an iOS platform limit. Keep an explicit reserve for SMHI and other app notifications, accounting for already pending requests in those namespaces.
8. Select candidates globally, not per location. Stable priority order:
   - preserved pending immediate-frost requests (not recreated or displaced);
   - newly due immediate frost alerts;
   - safety-critical frost/ice alerts;
   - ordinary forecast alerts, ordered by fire date, then deterministic location and identifier tie-breakers.
9. Deduplicate by stable request identifier. A delivered identifier remains deduplicated; a pending immediate-frost request retains its original near-immediate trigger.
10. Before removing/replacing forecast-owned requests and before each add, verify that the captured global revision is still current. A stale reconciliation must abort without overwriting newer state.
11. Replace only forecast-owned pending requests with the globally selected set. If a watch is removed during the operation, its revision/token must invalidate its candidates and the next reconciliation must rebalance the remaining locations.
12. Read pending requests once more after adds and write scheduled count, timestamp, and status once from the aggregate final snapshot. Count only `regnvakt.weather.` requests in the forecast count; show SMHI separately if the UI later needs a combined count.

## Data model and pure selection logic

Extract a Foundation-only value model (no UserNotifications dependency) for a candidate:
- stable identifier;
- location ID;
- fire date;
- priority class (immediate frost, safety-critical, ordinary);
- whether it is a preserved pending immediate-frost request.

The pure selector should accept:
- candidate list;
- preserved pending forecast identifiers;
- pending SMHI count;
- pending unrelated-app count;
- documented total app notification ceiling and reserve policy;
- delivered identifiers.

It should return a deterministic selected identifier list and a reason/count summary. Request construction and notification-center I/O remain in the scheduler.

## Required tests before integration

- Capacity boundaries: 0, 1, 8, 52, and more than 52 monitored locations.
- No selected forecast requests exceed the computed global capacity.
- Preserved current-frost requests consume capacity and are not displaced.
- Immediate frost and safety-critical ice/frost from one location outrank ordinary alerts from another.
- Existing SMHI requests are counted for capacity but never removed.
- Unrelated pending notifications are counted/preserved.
- Duplicate identifiers are selected once.
- Delivered identifiers are not re-armed.
- Stale/expired forecasts produce no new candidates.
- Permission-denied and global-disabled paths remove only forecast-owned requests.
- A newer refresh or location removal invalidates an older in-flight reconciliation.
- Aggregate status is written once after final reconciliation, not once per location.

## Implemented selector (2026-11-20)\n\nAdded `VADER/WeatherNotificationBudget.swift` and unit tests in `Tests/WeatherNotificationBudgetTests.swift`. The selector is deterministic, deduplicates stable identifiers, filters delivered requests, preserves already-pending current-frost requests even when they exceed the supplied capacity, and prioritizes immediate frost, safety-critical alerts, then ordinary forecasts. The caller must supply capacity after accounting for pending SMHI and unrelated notifications. This helper is not yet called by the live scheduler; it does not by itself fix parallel reconciliation.\n\n## Integration boundary

Do not replace the current scheduler with a helper-only change. The pure selector is useful only when wired into a single global reconciliation that owns the complete read/select/replace/add/status lifecycle. Until the integrated implementation passes CI and physical-device checks, this specification is not a completed feature.


## Kapacitetsberäkning – förberedande implementation (2026-11-20)

`WeatherNotificationBudget.availableForecastCapacity` har lagts till som en ren funktion för att räkna tillgängliga platser för nya prognosnotiser. Den drar av:
- appens valda totala budget;
- reserverat säkerhetsutrymme;
- det faktiska antalet väntande `smhi.*`-notiser;
- det faktiska antalet väntande notiser i andra namespace.

Negativa indata klampas till noll och resultatet kan aldrig bli negativt. Reserverat utrymme är uttryckligen extra marginal utöver de redan väntande notiserna. Funktionen är ännu inte inkopplad i schemaläggaren och anger inte någon dokumenterad iOS-plattformsgräns. Budgetvärden ska fastställas som app-policy innan integration.


## Verifierat anropsflöde och integrationskrav (2026-11-20)

Källkodens anropsvägar har följts genom `WeatherViewModel`, `NotificationSettingsView` och `WeatherNotificationScheduler`.

- Appstart: `WeatherViewModel.init()` → `refreshFromStoredForecast()`.
- Inställningsändring: respektive `onChange` i `NotificationSettingsView` → `refreshFromStoredForecast()`.
- Aktiverad platsbevakning: `setMonitoring` → `refresh(...)` → `refreshFromStoredForecast()`.
- Avaktiverad eller borttagen plats: `removeNotifications(...)` → `refreshFromStoredForecast()`.
- Prognosladdning: `loadWeather` anropar `refresh(...)` för den valda bevakade platsen och varje annan bevakad plats efter separat prognoshämtning.

Detta innebär att samma plats kan få både ett direkt `schedule(...)`-jobb och ett jobb som skapats av `refreshFromStoredForecast()`. En global reconciliation måste därför ersätta båda ingångarna; att bara samordna de befintliga platsjobben räcker inte.

### Refaktorordning
1. Gör `refresh(...)` till en synkron registeruppdatering och begär därefter en global reconciliation. Ta bort direktanropet till platsvis `schedule(...)`.
2. Gör `refreshFromStoredForecast()` till en enda reconciliation-begäran med en register-snapshot, inte en Task per plats.
3. Extrahera ren konstruktion av kandidater/UNNotificationRequest från den nuvarande `schedule(...)`-metoden. Behåll befintlig händelse- och identifierarlogik.
4. Inför monoton generationsidentifierare. Varje ny refresh eller registerändring invaliderar äldre arbete; kontrollera generationen efter varje `await` och före rensning/tillägg.
5. Läs pending, delivered och behörighet en gång per global körning. Bevara väntande aktuella frostnotiser och leveransmarkörer.
6. Räkna SMHI och övriga requests från samma pending-snapshot. Kör `availableForecastCapacity` och `select` på den samlade kandidatlistan.
7. Ersätt endast forecast-namespace och skriv aggregerad status en gång efter slutlig pending-avläsning.

### Viktig risk
En aktör eller ett serialiserat Task-flöde får inte antas vara tillräckligt utan generationskontroll: Swift actors kan återinträda vid `await`. Ingen destructive operation får utföras av en föråldrad generation.


## Klassificering av extern pending-kö

`WeatherNotificationBudget.countExternalPendingRequests(identifiers:forecastPrefix:smhiPrefix:)` klassificerar en och samma pending-snapshot i tre ägarkategorier:
- `regnvakt.weather.*`: forecast requests som reconciliation får ersätta; räknas inte som extern belastning.
- `smhi.*`: SMHI requests som ägs av SMHI-servicen och ska räknas in i den delade pending-kapaciteten.
- Alla andra identifierare: externa/övriga requests som inte får raderas av forecast-schemaläggaren och som också belastar kapaciteten.

Resultatet är `WeatherNotificationPendingCounts(smhi:unrelated:)`. Funktionen är ren och testad, men ännu inte anropad av live-schemaläggaren. Den globala implementationen måste använda samma pending-snapshot för klassificering och för bevarande/rensning, så att köbilden inte blandas från olika tidpunkter.


## Fördjupad kantfallstestning av urvalet – 2026-11-20

- Utökat `Tests/WeatherNotificationBudgetTests.swift` med två explicita kantfall: flera redan väntande aktuella frostnotiser ska alla bevaras även när de överstiger tillgänglig kapacitet, och tomma identifierare ska ignoreras även vid negativ kapacitet.
- Dessa tester dokumenterar säkerhetsprioriteringen i den rena urvalsmodellen. De innebär inte att modellen är inkopplad i `WeatherNotificationScheduler`.
- En fristående Swift-körning av budgetmodellens relevanta beteende passerade för namespace-klassificering, kapacitetsavräkning, global prioritetsordning, bevarad frost vid noll kapacitet och deduplicering av levererade identifierare.
- Den fristående körningen är inte XCTest och verifierar inte iOS/UserNotifications-integration.


## Fastställd app-policy för notiskapacitet – 2026-11-20

Första integrationsversionen använder följande konservativa app-policy:

- Total budget för Regnvakts samlade pending-kö: **52** notiser.
- Reserverat extra utrymme: **8** notiser.
- Befintliga väntande `smhi.*`-notiser och andra namespace räknas dessutom av från kapaciteten.
- Därmed är grundkapaciteten för prognosnotiser 44 när inga externa notiser väntar.
- Detta är Regnvakts egen försiktiga budget, inte ett påstående om iOS plattformsgräns.

Värdena är nu namngivna konstanter i `WeatherNotificationBudget` och testas uttryckligen. De kan justeras efter verklig enhetsverifiering utan att formeln behöver dupliceras i schemaläggaren. Bevarade omedelbara frostnotiser får fortsatt överstiga budgeten av säkerhetsskäl.

Status: policy fastställd och testfall tillagt; live-schemaläggaren använder ännu inte konstanterna.


## Tillfälligt skydd mot överbudget i legacy-schemaläggaren – 2026-11-20

Den gamla platsvisa schemaläggaren har fått ett begränsat skydd medan den globala reconciliationen byggs:

- Per-platsgränsen använder nu `WeatherNotificationBudget.interimPerPlaceLimit(registryCount:)`.
- Den utgår från appens grundkapacitet 44 (52 totalbudget minus 8 reserverade) och fördelar den över antalet registrerade platser, med max 8 per plats.
- Den gamla nedre gränsen på en notis per plats är borttagen. Vid 45 eller fler platser kan därför en enskild plats få noll nya vanliga prognosnotiser i denna interimslösning i stället för att summan överskrider grundkapaciteten.
- Tester täcker 1, 8, 44, 45, 52 och 0 registrerade platser.

**Viktig begränsning:** Detta är endast en skadebegränsande övergångslösning. Den läser ännu inte verkligt väntande SMHI-/övriga notiser vid kapacitetsvalet, gör inte ett globalt prioriterat urval och undanröjer inte parallella statusuppdateringar. Den globala reconciliationen är fortfarande nödvändig.

## Första inkoppling av kandidatmetadata – 2026-11-21

`WeatherNotificationBudget.makeCandidate(...)` centraliserar mappningen från notistyp till prioritetsklass: omedelbar aktuell frost, säkerhetskritisk frost/halka eller vanlig prognos. Ren XCTest-täckning verifierar mappningen och flaggan för bevarad väntande aktuell frost.

`WeatherNotificationScheduler.makeCandidates(...)` mappar nu skapade `UNNotificationRequest` till kandidatmetadata och markerar aktuell frost som bevarad när samma identifierare redan finns i pending-snapshoten. Den befintliga platsvisa schemaläggaren läser pending och delivered före urval och använder därefter den gemensamma `WeatherNotificationBudget.select(...)` i stället för sin separata manuella sortering.

**Avgränsning:** urvalet körs fortfarande en plats i taget och använder fortfarande interimistisk kapacitet per plats. Detta är en första inkoppling av kandidatmodellen, inte global reconciliation. Pending-/delivered-snapshots tas fortfarande separat för varje platsjobb, och aggregerad status skrivs fortfarande av flera jobb. Global generationsskyddad avstämning återstår.
