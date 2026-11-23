# Development log — frost notification audit

## 2026-11-23

### Changes
- Added `testLatestDeliveredCurrentFrostDaysUsesNewestImmediateAlertPerRegisteredLocation` to `Tests/WeatherNotificationBudgetTests.swift`.
- The test covers the global delivered-alert recovery path: newest immediate frost day wins per registered location; non-immediate forecast frost, removed locations, foreign SMHI identifiers, and alerts without an alert day are ignored.

### Files
- `Tests/WeatherNotificationBudgetTests.swift`

### Verification
- Reviewed the implementation in `VADER/WeatherNotificationBudget.swift` and its call site in `VADER/WeatherNotificationScheduler.swift`.
- The XCTest has been committed but has **not** yet been executed. No passing CI or release build is claimed.

### CI note
- `.github/workflows/build.yml` currently runs on pushes to `main`, pull requests targeting `feature/wind-radar`, and manual dispatch.
- A pull request targeting another base branch will not trigger this workflow as currently configured. Confirm the intended PR base or add the frost-audit branch to the workflow trigger before relying on CI for this work.

### Git
- Branch: `feature/frost-notification-audit`
- Commit: `afd55a44f8d2a30d46b54d48fda67673f0f3588d`

### Remaining
- Run the XCTest suite on a GitHub-hosted macOS runner.
- Verify the Release device build and unsigned IPA artifact.
- Test actual notification delivery on-device with the app foregrounded, backgrounded, and terminated; simulator/unit tests cannot prove OS delivery behavior.
