## 2026-11-24 — per-run background forecast diagnostics

### Changes
- Background refresh now records the number of monitored places, successful updates, failed fetches and places skipped because monitoring changed during a request or the task was cancelled.
- Stores the last successful fetch timestamp, run duration and a sanitized latest error domain/code.
- Does not persist place names, coordinates, request URLs or raw error descriptions.
- Exposes the counters and sanitized diagnostic in Notification Settings.

### Files
- `VADER/WeatherService.swift`
- `VADER/NotificationSettingsView.swift`
- `DEVELOPMENT_LOG.md`

### Verification
- Source changes committed; GitHub Actions XCTest, Release build and unsigned IPA packaging must pass before device distribution.
- Physical iPhone execution and SwiftUI refresh of the diagnostic values remain unverified.
- Background refresh remains opportunistic and controlled by iOS; this change does not guarantee execution.

### Git
- Branch: `feature/frost-notification-audit`
- Commit: pending

---

## 2026-11-24 — background notification diagnostic

### Changes
- Extended the in-app local test notification delay from 5 to 15 seconds so the user has time to leave Regnvakt before delivery.
- Updated the confirmation text to explicitly instruct the user to return to the Home Screen, making the test distinguish iOS background delivery from foreground presentation.

### Files
- `VADER/NotificationSettingsView.swift`
- `DEVELOPMENT_LOG.md`

### Verification
- Source change committed; CI must compile and run the full XCTest suite before this diagnostic build is distributed.
- The test notification is a local UserNotifications request; it does not prove that weather-watch candidate generation or forecast scheduling is correct. Those require separate device validation.
- Physical iPhone background delivery remains unverified until the new IPA is installed and tested.

### Git
- Branch: `feature/frost-notification-audit`
- Code commit: `feb9fbe1c55ba5c050d34648378804285dfad5a8`

---

## 2026-11-24 — conservative trigger-date validation

### Changes
- Tightened stale pending-forecast preservation to accept only calendar triggers with a concrete next trigger date.
- Removed the interval-trigger fallback: its configured interval is the original delay, not a reliable remaining fire time for an already-pending request. Inferring a future date from it could preserve an alert incorrectly.

### Verification
- The preceding commit `47e6f734b691fa798607849bf311b591050c4758` passed the complete GitHub Actions workflow: frost-risk XCTest step, iOS device build, unsigned IPA packaging and artifact upload.
- This follow-up hardening change requires a new CI run. Physical iPhone delivery remains unverified.

### Git
- Branch: `feature/frost-notification-audit`
- Code commit: `154d7369f92e7d8e0bbc0d1511a8406944af3574`

---

## 2026-11-24 — follow-up compile correction

### Changes
- CI exposed a Swift syntax issue in the first trigger-type correction: a local declaration had been placed inside a multi-condition `guard` before its `else` clause.
- Moved trigger-date extraction after the metadata guard. The code now validates metadata first, then resolves the next fire date from the concrete calendar or interval trigger type.

### Verification
- Both CI attempts for commit `5656ab4d62af8a88c8cdb4bb0bc12ca668cbf56e` failed at compile time on this guard syntax; no tests executed and no IPA was packaged.
- Corrected in commit `40a94bfe43d5bbd9b9357fc9bbff9c4fecf1b758`. New CI result pending.

### Git
- Branch: `feature/frost-notification-audit`

---

## 2026-11-24 — correct notification trigger date extraction

### Changes
- Fixed the compile error in stale pending-alert inspection: `nextTriggerDate()` is called only on supported concrete trigger types (`UNCalendarNotificationTrigger` and `UNTimeIntervalNotificationTrigger`).
- Calendar triggers use their next matching date; interval triggers derive the next fire time from the stored interval. Unknown trigger types are not preserved.

### Verification
- Previous CI run #872 failed during Swift compilation because `UNNotificationTrigger` itself does not expose `nextTriggerDate()`.
- The failure was corrected in the scheduler. A fresh CI run is required; XCTest, Release build and IPA packaging are not yet verified.
- Physical iPhone notification delivery remains unverified.

### Git
- Branch: `feature/frost-notification-audit`
- Fix commit: `5656ab4d62af8a88c8cdb4bb0bc12ca668cbf56e`

---

## 2026-11-24 — bounded preservation of scheduled forecast alerts

### Changes
- Added forecast snapshot timestamps to newly scheduled local weather notifications.
- Added a pure validation rule for preserving already-pending forecast alerts while a monitored location only has a stale cached forecast.
- Preservation requires a registered location, an enabled watch, a snapshot no older than four hours, and both the weather event and notification trigger still being in the future.
- Legacy requests without snapshot metadata, expired requests, and requests for disabled/removed watches are not preserved. Stale forecasts still never generate new candidates.
- Included preserved stale requests in global pending-capacity accounting.

### Files
- `VADER/WeatherNotificationScheduler.swift`
- `VADER/WeatherNotificationBudget.swift`
- `Tests/WeatherNotificationBudgetTests.swift`
- `DEVELOPMENT_LOG.md`

### Verification
- Added deterministic unit tests for valid preservation, expired snapshots, passed event/trigger times, removed locations, disabled watches, future-dated metadata, and the maximum-age boundary.
- GitHub Actions build and XCTest results pending.
- Physical iPhone delivery in background/terminated states remains unverified.

### Git
- Branch: `feature/frost-notification-audit`
- Commit: pending

---

# Development log — frost notification audit

## 2026-11-24 — radar nowcast parser hardening

### Changes
- Extracted MET Norway nowcast JSON decoding into `VADER/RadarNowcastParser.swift` so the API response handling is deterministic and independently testable.
- The parser sorts time-series points chronologically, classifies radar coverage explicitly, keeps missing/non-numeric measurements unknown, and clamps negative precipitation values to zero.
- Updated `VADER/RadarMapView.swift` to consume the typed parser result instead of decoding nested JSON inline.
- Added four XCTest cases for chronological ordering, radar coverage, unknown measurements, negative-value handling and malformed payloads.
- Included the parser source in the XCTest target through `project.yml`.

### Files
- `VADER/RadarNowcastParser.swift` (new)
- `VADER/RadarMapView.swift`
- `Tests/RadarNowcastParserTests.swift` (new)
- `project.yml`
- `DEVELOPMENT_LOG.md`

### Verification
- Source changes and test coverage are committed to `feature/frost-notification-audit`.
- CI has not yet been observed for this parser change; compilation and the four new tests remain unverified until the GitHub Actions run completes.
- No physical-device radar test has been performed.

### Git
- Branch: `feature/frost-notification-audit`
- Parser commit: `4ffd0cae00b024663baa26e1507a0c7b02700ca2`
- Parser tests commit: `f424124f8e03e71c5c906974d60b8129406aa7ce`
- Radar integration commit: `b4338e1c0e4fc10eb07337300d54ef54bcd75b56`
- XCTest target commit: `f30a932b7a2acb6aafe14e3c8820eaf41cae8258`
- Validation cleanup commit: `27a6f8be127f26c0996a77b3dbe2d1304c5de74a`

---

## 2026-11-23

### Changes
- Fixed the in-app test notification: it now carries an explicit test/safety-critical marker so the notification delegate presents it while Regnvakt is foregrounded. Ordinary forecast notices remain suppressed in the foreground by design.
- Updated `.github/workflows/build.yml` so pushes to `feature/frost-notification-audit` also run the iOS CI workflow; feature commits are no longer dependent on opening/updating a PR against `feature/wind-radar` to receive CI coverage.
- Added `testLatestDeliveredCurrentFrostDaysUsesNewestImmediateAlertPerRegisteredLocation` to `Tests/WeatherNotificationBudgetTests.swift`.
- The test covers the global delivered-alert recovery path: newest immediate frost day wins per registered location; non-immediate forecast frost, removed locations, foreign SMHI identifiers, and alerts without an alert day are ignored.

### Files
- `VADER/NotificationSettingsView.swift`
- `.github/workflows/build.yml`
- `Tests/WeatherNotificationBudgetTests.swift`

### Verification
- Reviewed the implementation in `VADER/WeatherNotificationBudget.swift` and its call site in `VADER/WeatherNotificationScheduler.swift`.
- GitHub Actions run #845 completed successfully on commit `5a3cabfb738ee264a928af5b4b4b0d6050784c22`.
- All 91 XCTest cases passed (0 failures), including the newly added delivered-frost recovery test.
- Release device build succeeded; the workflow packaged and uploaded the unsigned IPA artifact.
- The built Info.plist was checked for bundle ID `app.walnut8211.vadra`, background task identifier `app.walnut8211.vadra.weather-refresh`, and `UIBackgroundModes: fetch`.

### CI note
- `.github/workflows/build.yml` runs on pushes to `main`, pull requests targeting `feature/wind-radar`, and manual dispatch.
- The successful run was a pull-request-triggered run for head branch `feature/frost-notification-audit`; the configured base-branch filter therefore did not block this PR.

### Git
- Branch: `feature/frost-notification-audit`
- Code commit: `afd55a44f8d2a30d46b54d48fda67673f0f3588d`
- Earlier documentation commits: `232014de2f6bcd200577a920dec52bdf45e930ac`, `5a3cabfb738ee264a928af5b4b4b0d6050784c22`
- Earlier documentation commit: `8af6e6da7959d7f2886dbb3df3861be82be824e5`
- CI trigger commit: `dec59b78dd9f208da9f66ba771c97683e88e08aa`
- CI run: [#845](https://github.com/72cbbw422f-alt/project-orbit/actions/runs/45272385945)
- IPA artifact: `Regnvakt-unsigned-IPA` (artifact ID `14866702664`, expires 2026-12-07)
- Artifact ZIP SHA-256: `d236fd0373579ec1102837e30d1406407f4bc2d3d489336831bc70bf5cd95a79`

### Remaining
- Install/sign the unsigned IPA with the user's authorized FlareStore signing workflow and test on the physical iPhone.
- Confirm the push-triggered CI run after commits `dec59b78dd9f208da9f66ba771c97683e88e08aa` and `383c25d243b8d0229fafa66c56f05b3ae688c6ec` completes successfully.
- Install/sign the unsigned IPA with FlareStore and test local notifications on a physical iPhone while foregrounded, backgrounded, and terminated; CI/unit tests cannot establish real iOS delivery behavior.


## 2026-11-24 — prevent late forecast safety alerts from firing on app launch

### Findings
- Physical iPhone test confirmed the local test notification is delivered while the app is backgrounded.
- The user observed a frost forecast notification with the same 11:56 timestamp as opening Regnvakt. Notification history showed no remaining pending weather alerts.
- The forecast scheduler promoted any safety-critical forecast whose configured lead-time trigger had passed into an immediate notification. This could make an upcoming forecast frost/ice alert appear only when a fresh forecast was fetched on app launch.

### Changes
- Forecast-derived frost/ice alerts whose lead-time point has passed are now scheduled for the forecast event time, not emitted immediately at app launch.
- Explicitly detected current-frost alerts retain their immediate path.
- Updated the unit test to assert that a future safety-critical forecast event is not promoted to an immediate alert.

### Files
- `VADER/WeatherNotificationScheduler.swift`
- `VADER/WeatherNotificationBudget.swift`
- `Tests/WeatherNotificationBudgetTests.swift`
- `DEVELOPMENT_LOG.md`

### Verification
- Source and test changes committed; GitHub Actions validation is pending.
- Physical iPhone verification of this revised scheduling behavior is pending.
- The successful background test proves iOS local-notification delivery, not that forecast refreshes execute reliably while the app is closed.

### Git
- Branch: `feature/frost-notification-audit`
- Scheduler commit: `aa6f596e9ec4abc22c09018e80a70fba529f6374`
- Policy commit: `822c3527eb4c43e33464f46891d56bef6f8e5fe8`
- Test commit: `028659774ad09d9efd03a5735e9e9f45660f9a5a`

### Remaining
- Confirm CI passes all tests and Release build.
- Install the new IPA and verify that upcoming frost/ice events are pending before the event and are not delivered merely on app launch.
- Verify explicit current-frost alerts still deliver promptly.


## 2026-11-24 — clarify safety forecast eligibility semantics

### Findings
- A follow-up audit found that `WeatherWatchRules.canScheduleForecastEvent` still used the local name and documentation “immediate safety alert” for a safety-critical forecast whose lead-time point had passed.
- That helper only decides whether a forecast event may claim the first-alert slot; it does not create or schedule the notification. Actual delivery timing is handled in `WeatherNotificationScheduler`.

### Changes
- Renamed the internal decision flag to `safetyEventPastLeadTime`.
- Updated documentation to state that the event may claim the alert slot after lead time, while the scheduler arms it for the forecast event time.
- Renamed the corresponding XCTest to describe slot eligibility during quiet hours, not immediate delivery.

### Files
- `VADER/WeatherWatchRules.swift`
- `Tests/WeatherNotificationBudgetTests.swift`
- `DEVELOPMENT_LOG.md`

### Verification
- Source/test changes committed. CI validation is pending.
- No new physical-device test has been performed for this clarification; the prior IPA's physical-device result remains the user's reported background delivery of the test notification only.

### Git
- Branch: `feature/frost-notification-audit`
- Rules commit: `75c3d02fbc5ffcb6059ab86c3584347eb71045eb`
- Test commit: `4631fe8fb6b7553051f1c166603b1c03b075cf26`


## 2026-11-24 — background refresh diagnostics

### Changes
- Added persisted timestamps and status for BGAppRefreshTask submission, start, completion and expiration.
- The notification settings screen now shows the latest background refresh status, last start/completion, and the earliest requested run time.
- The UI explicitly explains that iOS controls actual execution and the requested time is not a guarantee.
- Submission errors are recorded instead of being silently swallowed.

### Files
- `VADER/VADERApp.swift`
- `VADER/NotificationSettingsView.swift`
- `DEVELOPMENT_LOG.md`

### Verification
- Source changes committed; GitHub Actions XCTest and Release build pending.
- This diagnostic records task lifecycle when iOS invokes the task. It does not force iOS to run background refreshes or guarantee a cadence.
- Physical iPhone verification of the new diagnostic UI and actual BGAppRefreshTask invocation remains pending.

### Git
- Branch: `feature/frost-notification-audit`
- App delegate commit: `d1121c77d2e194ffae6b3594f8a05e690fe9c38e`
- Settings UI commit: `c74355a31718074ba15e304bf07646e2ed06dc40`


## 2026-11-25 — expand notification look-ahead and report the live iOS queue

### Findings
- The Open-Meteo request already retrieves 48 hourly forecast entries, but the notification scheduler only considered the next 8 hours.
- The app's notification settings screen displayed a persisted count from the last scheduler reconciliation. It did not query UserNotifications when the screen appeared, so the displayed count could be stale after iOS delivered an alert.
- The dashboard risk horizon remains 8 hours; only the local notification planning horizon is extended.

### Changes
- Extended `WeatherWatchRules.notificationHorizonHours` from 8 to 24 hours. The scheduler can now arm the first eligible alert of each enabled risk type further ahead, using the existing lead-time, quiet-hour, safety-priority, deduplication, and global pending-budget rules.
- Added an XCTest asserting that the notification horizon is 24 hours while the dashboard forecast horizon remains 8 hours.
- Updated notification settings to query iOS pending notification requests when the screen loads, replace the persisted count with the live Regnvakt-owned pending count, and display up to five upcoming trigger times and titles.

### Files
- `VADER/WeatherWatchRules.swift`
- `Tests/WeatherNotificationBudgetTests.swift`
- `VADER/NotificationSettingsView.swift`
- `DEVELOPMENT_LOG.md`

### Verification
- Changes committed to `feature/frost-notification-audit`.
- CI/XCTest and Release device build have not yet been checked for these commits.
- The updated queue display has not been verified on a physical iPhone.
- The 24-hour horizon increases planning lead time; it does not guarantee background forecast refreshes or delivery of alerts when a forecast is stale.

### Git
- Branch: `feature/frost-notification-audit`
- Rules commit: `6b806fa79a9fea8ddb0dcf2647b3caa1574fed6b`
- Tests commit: `29d2a4fbde8cb5969d33f4d4e60534940a37aea8`
- Settings commit: `f787cf976e6c6f6d324ed351159c165181d9ceb5`

### Remaining
- Confirm GitHub Actions tests and Release build.
- Verify the live pending count and upcoming notification list on the user's iPhone.
- Confirm that 24-hour scheduling yields useful advance alerts without duplicates or excessive notifications.


## 2026-11-25 — notification queue visibility and planning horizon

### Changes on `feature/frost-notification-audit`
- Extended `WeatherWatchRules.notificationHorizonHours` to 24 hours. The dashboard's `forecastHorizonHours` remains 8 hours.
- Added an XCTest asserting the separate 8-hour dashboard and 24-hour notification horizons.
- Notification Settings now queries `UNUserNotificationCenter.pendingNotificationRequests()` on view task, filters Regnvakt-owned identifiers, calculates actual next trigger dates and displays up to five upcoming alerts.
- Follow-up correction: mark the async UI refresh method `@MainActor` and use actual newline separators in the upcoming-alert list.

### Files
- `VADER/WeatherWatchRules.swift`
- `Tests/WeatherNotificationBudgetTests.swift`
- `VADER/NotificationSettingsView.swift`

### Verification
- Source files were fetched again from the development branch after the earlier commit/branch discrepancy. The 24-hour constant, horizon test, and live pending-queue implementation are present on the branch.
- The line-break and actor-isolation correction is committed as `c96627aba7137e02d6f180fef9c592f61f2a2117`.
- No GitHub Actions run has yet been confirmed for the latest commit.
- No new IPA has been built or tested on a physical iPhone.
- The live queue display refreshes when Notification Settings' SwiftUI task runs; it is not a background observer.

### Next
- Confirm workflow execution and XCTest/Release build.
- Verify the live pending queue on device.
- Evaluate whether a 24-hour horizon produces useful future alerts under existing thresholds and budget.


## 2026-11-25 — verify independent future risk notifications after delivery

### Findings
- The global selector excludes identifiers already present in iOS delivered notifications, but selection is identifier-specific. A delivered current-frost alert must not suppress distinct future ice, rain, or snow alerts.
- The scheduler selects at most the first schedulable event per risk type and monitored location. Different risk types and different locations can coexist in the global candidate pool.

### Changes
- Added a test proving that a delivered current-frost identifier does not block later ice and rain candidates for the same location.
- Added an end-to-end pure selection/reconciliation test covering safety-priority ice, ordinary rain, snow at another location, removal of stale Regnvakt requests, and preservation of foreign SMHI requests.

### Files
- `Tests/WeatherNotificationBudgetTests.swift`
- `DEVELOPMENT_LOG.md`

### Verification
- Tests are committed to the development branch. GitHub Actions XCTest and Release build have not yet been confirmed for this commit.
- The tests exercise the pure selection and reconciliation policies; they do not simulate the iOS notification daemon or prove physical-device delivery.
- No new IPA has been built or distributed.

### Git
- Branch: `feature/frost-notification-audit`
- Test commit: `e2ce9a776e66eb5e420661ab78e2f5990acd2afc`
- Documentation commit: pending

### Remaining
- Confirm the push-triggered GitHub Actions workflow runs and passes the complete XCTest suite and Release device build.
- If CI passes, install the resulting unsigned IPA through the user's normal FlareStore workflow and verify multiple future alerts on the physical iPhone.
- Keep PR #1 open; do not merge without approval.



## 2026-11-25 — CI compile correction for notification settings

### Findings
- GitHub Actions run #928 (push) and run #929 (pull request) both failed before XCTest execution.
- The compiler error was exact and reproducible in `VADER/NotificationSettingsView.swift:271`: duplicate global actor annotation, `@MainActor` applied twice to `refreshPendingWeatherNotifications()`.
- This was a Swift compile failure, not a failure of the newly added multi-risk regression assertions. XCTest was cancelled because the app target did not compile.

### Changes
- Removed the duplicate `@MainActor` annotation while retaining the method's required actor isolation.

### Files
- `VADER/NotificationSettingsView.swift`
- `DEVELOPMENT_LOG.md`

### Verification
- The correction is committed. A fresh GitHub Actions run is required to verify compilation, XCTest, Release build and IPA packaging.
- The failed runs did not reach XCTest, Release build or IPA packaging.
- No new IPA has been built or distributed.

### Git
- Branch: `feature/frost-notification-audit`
- Fix commit: `36d844a24e194105ea3de59056843939b7b14b2b`
- Documentation commit: pending

### Remaining
- Verify the fresh push and PR workflow runs.
- If all steps pass, inspect the IPA artifact before distribution.
- Keep PR #1 open; do not merge without approval.



## 2026-11-25 — correct pending notification trigger date lookup

### Findings
- The next CI run exposed a second compile error in the live pending-notification list: `UNNotificationTrigger` does not declare `nextTriggerDate()`.
- The API is available on concrete calendar and time-interval trigger subclasses, not on the base trigger type.
- The compiler reached Swift compilation of the app target; XCTest execution was cancelled because this compile error stopped the build.

### Changes
- Updated the pending weather queue reader to branch on `UNCalendarNotificationTrigger` and `UNTimeIntervalNotificationTrigger`, calling each concrete type's `nextTriggerDate()` implementation.
- Unknown trigger types are safely omitted from the upcoming-date list rather than causing a compile-time API misuse.

### Files
- `VADER/NotificationSettingsView.swift`
- `DEVELOPMENT_LOG.md`

### Verification
- Source correction committed; a new GitHub Actions run must verify the API usage, full XCTest suite, Release device build and IPA packaging.
- No IPA was produced by the failed runs. No physical-device verification has been performed for this correction.

### Git
- Branch: `feature/frost-notification-audit`
- Code fix: `03b1962e54fc45ab84f4f249f964722daf6d5173`
- Documentation commit: pending

### Remaining
- Check the new push and PR runs and inspect any failing step logs.
- Only distribute an IPA after the complete workflow passes and the artifact is confirmed.
- Keep PR #1 open; do not merge without approval.
