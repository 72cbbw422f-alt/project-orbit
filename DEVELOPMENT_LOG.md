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
