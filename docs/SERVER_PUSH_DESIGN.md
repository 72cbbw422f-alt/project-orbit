# Regnvakt – serverbaserade pushnotiser

## Syfte

Komplettera appens befintliga lokala notiser med serverbaserade pushnotiser för officiella SMHI-varningar. Servern ska kunna upptäcka en ny eller uppdaterad varning och skicka den även när iOS inte har gett appen tid för en bakgrundsuppdatering.

Detta är en teknisk målbild. Ingen server, APNs-nyckel, push-entitlement eller driftmiljö är ännu konfigurerad.

## Föreslagen arkitektur

**Förslag: Supabase (Postgres + Edge Functions + schemalagd körning) som första serverplattform.** Det är en rekommendation, inte ett fattat konto- eller driftsbeslut.

1. **iOS-app**
   - Begär användarens uttryckliga tillstånd för notiser.
   - Hämtar APNs-enhetstoken efter att push-capability och provisioning är konfigurerade.
   - Registrerar token och de platser användaren uttryckligen har valt att bevaka hos backend.
   - Uppdaterar eller avregistrerar prenumerationer när platser ändras eller användaren stänger av notiser.
   - Fortsätter använda nuvarande lokala prognosnotiser som kompletterande kanal.

2. **Schemalagd serverkontroll**
   - En schemalagd Edge Function hämtar SMHI:s officiella varningsdata med ett intervall som bestäms efter belastning, aktualitet och SMHI:s villkor.
   - Servern normaliserar varningsidentitet, geometri, nivå, giltighetstid och uppdateringsversion.
   - Endast nya eller materiellt ändrade varningar går vidare till geografisk matchning.

3. **Geografisk matchning och deduplicering**
   - Matcha varningens geografiska område mot användarens uttryckligen bevakade platser.
   - Använd samma varningsidentitet + version + prenumeration som dedupliceringsnyckel.
   - Skicka uppdatering när varningens nivå, giltighet eller relevanta innehåll ändras; skicka inte samma oförändrade varning om och om igen.
   - Hantera återkallade/utgångna varningar separat så att de inte skapar falska nya larm.

4. **APNs**
   - Edge Function skickar push via Apples HTTP/2 APNs-gränssnitt.
   - APNs Auth Key (.p8), Key ID, Team ID och miljö lagras endast som serverhemligheter.
   - Skicka till rätt sandbox/production-miljö och hantera ogiltiga token genom att avregistrera dem.
   - Push-payload ska vara liten och innehålla en stabil varningsreferens; appen hämtar detaljer vid öppning.

## Föreslagen datamodell

- `devices`: intern installationsidentifierare, APNs-token, miljö, appversion, senaste kontakt och aktiv/inaktiv status.
- `watch_locations`: installationsreferens, användarens plats-ID, koordinater eller annan minsta nödvändiga geografiska representation, aktiv status.
- `smhi_warning_events`: SMHI-varnings-ID, version/hash, nivå, geometri/giltighet, första/senaste observation och status.
- `push_deliveries`: installationsreferens, varnings-ID/version, status, APNs-resultat och tidsstämplar.

Token ska vara unik per APNs-miljö och installation. Databasens unika constraint för leveransnyckeln ska vara sista skyddet mot dubbla pushar vid samtidiga jobb.

## Integritet och säkerhet

- Registrera endast de bevakade platser som användaren aktivt valt. Skicka inte kontinuerlig GPS-position till servern.
- Dokumentera ändamål, lagringstid och radering av installationstoken och platsdata.
- Använd RLS och service-role-hemligheter endast på servern. Service-role-nyckel får aldrig byggas in i iOS-appen.
- Validera alla registreringsanrop och begränsa antal installationer/platser per installation.
- APNs .p8-nyckel, Key ID och Team ID får aldrig checkas in i GitHub eller skrivas i klientloggar.
- Logga inte fullständiga APNs-token eller exakta koordinater i vanliga driftloggar.
- Stöd avregistrering och radering när användaren stänger av servernotiser eller tar bort en plats.

## Felhantering och driftsäkerhet

- Retry med exponentiell backoff för tillfälliga SMHI-/APNs-fel; respektera rate limit och svar från APNs.
- Skilj mellan tillfälliga fel, ogiltig token, autentiseringsfel och avvisad payload.
- Spara körningscheckpoint så en avbruten poll inte tappar varningar.
- Ha idempotent bearbetning så omkörning inte dubblar push.
- Mät senaste lyckade SMHI-poll, antal matchade varningar, skickade pushar och fel.
- Serverpush kompletterar, men ersätter inte, lokala notiser och appens synkronisering.

## Apple-beroenden

När Apple Developer Program är aktivt behöver vi:
1. Aktivera Push Notifications för appens Bundle ID.
2. Skapa/konfigurera APNs Auth Key och säkert överföra nödvändiga värden till serverns secret store.
3. Konfigurera entitlements och provisioning för appens faktiska Bundle ID `app.walnut8211.vadra`.
4. Implementera tokenregistrering i appen och backend-endpoint.
5. Testa sandbox på fysisk enhet innan produktionsmiljön aktiveras.

Ett betalt utvecklarkonto är en förutsättning för normal APNs-distribution, men kontot skapar inte servern automatiskt.

## Genomförandeordning

### Före utvecklarkontot
- Hålla befintlig lokal notisväg stabil.
- Fastställa datakontrakt, dedupliceringsregler, integritetskrav och serveransvar.
- Välja och skapa backend-projekt först när ägande, region, kostnad och åtkomst är beslutade.
- Bygga inte en klient som låtsas registrera push innan APNs-entitlement finns.

### Efter utvecklarkontot
- Konfigurera APNs capability, entitlements och nyckel.
- Implementera serverns databas, registreringsfunktion och schemalagda SMHI-poll.
- Implementera iOS-tokenregistrering och prenumerationssynk.
- Testa nya, uppdaterade, återkallade och geografiskt irrelevanta varningar samt ogiltiga token.
- Verifiera push när appen är aktiv, i bakgrunden och avslutad av systemet. Tvångsavslut kan påverka leverans/hantering och ska testas separat.

## Öppna beslut

- Bekräfta Supabase som backend eller välj annan driftplattform.
- Välja databasregion och retention för plats-/enhetsdata.
- Bestämma pollintervall utifrån SMHI:s datatjänster och tillåtna användningsmönster.
- Fastställa vilka varningsnivåer och ändringar som ska generera push.
- Bestämma om serverpush ska vara valbar separat från lokala notiser.

## Status

**Planerad – ej implementerad eller driftsatt.** Ingen APNs-nyckel, serverfunktion, databas, push-tokenregistrering eller faktisk pushleverans finns verifierad i nuläget.
