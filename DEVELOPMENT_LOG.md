# Development log — frost notification audit

## 2026-11-23

### Changes
- Updated `.github/workflows/build.yml` so pushes to `feature/frost-notification-audit` also run the iOS CI workflow; feature commits are no longer dependent on opening/updating a PR against `feature/wind-radar` to receive CI coverage.
- Added `testLatestDeliveredCurrentFrostDaysUsesNewestImmediateAlertPerRegisteredLocation` to `Tests/WeatherNotificationBudgetTests.swift`.
- The test covers the global delivered-alert recovery path: newest immediate frost day wins per registered location; non-immediate forecast frost, removed locations, foreign SMHI identifiers, and alerts without an alert day are ignored.

### Files
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
- Confirm the new push-triggered CI run on commit `dec59b78dd9f208da9f66ba771c97683e88e08aa` completes successfully.
- Install/sign the unsigned IPA with FlareStore and test local notifications on a physical iPhone while foregrounded, backgrounded, and terminated; CI/unit tests cannot establish real iOS delivery behavior.
