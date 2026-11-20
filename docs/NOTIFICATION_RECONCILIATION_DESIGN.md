# Global notification reconciliation

Status: pure selector implemented; scheduler integration not implemented
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
