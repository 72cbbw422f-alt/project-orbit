import XCTest

final class SMHIWarningNotificationPolicyTests: XCTestCase {
    func testSMHIInboxFingerprintUsesWarningIdentityAndStartNotMutableCopy() {
        let first = SMHIWarningNotificationPolicy.smhiEventFingerprint(
            warningID: "warning-42-area-7", start: "2026-11-22T08:00:00Z"
        )
        let changedSeveritySameWarning = SMHIWarningNotificationPolicy.smhiEventFingerprint(
            warningID: "warning-42-area-7", start: "2026-11-22T08:00:00Z"
        )
        let separateArea = SMHIWarningNotificationPolicy.smhiEventFingerprint(
            warningID: "warning-42-area-8", start: "2026-11-22T08:00:00Z"
        )
        let separateEpisode = SMHIWarningNotificationPolicy.smhiEventFingerprint(
            warningID: "warning-42-area-7", start: "2026-11-22T10:00:00Z"
        )

        XCTAssertEqual(first, changedSeveritySameWarning)
        XCTAssertNotEqual(first, separateArea)
        XCTAssertNotEqual(first, separateEpisode)
    }

    func testSeverityOrWordingChangeDoesNotCreateNewWarningEpisode() {
        // The mutable presentation fields are deliberately excluded from the
        // event fingerprint, so a severity/title update remains the same episode.
        let beforeUpdate = SMHIWarningNotificationPolicy.smhiEventFingerprint(
            warningID: "warning-42-area-7", start: "2026-11-22T08:00:00Z"
        )!
        let afterUpdate = SMHIWarningNotificationPolicy.smhiEventFingerprint(
            warningID: "warning-42-area-7", start: "2026-11-22T08:00:00Z"
        )!
        let transition = SMHIWarningNotificationPolicy.activeWarningTransition(
            current: [afterUpdate], previous: [beforeUpdate], hasBaseline: true
        )

        XCTAssertTrue(transition.newlyActive.isEmpty)
        XCTAssertEqual(transition.retainedBaseline, [beforeUpdate])
    }

    func testNationalBaselineMigrationDoesNotMarkExistingWarningsAsNew() {
        let legacy = Set(["warning-1|Gul|Kraftigt regn", "warning-2|Orange|Hård vind"])
        let current = Set(["smhi|warning-1|2026-11-22T08:00:00Z", "smhi|warning-2|2026-11-22T09:00:00Z"])
        let legacyCurrent = Set(["warning-1|Gul|Kraftigt regn", "warning-2|Orange|Hård vind"])

        XCTAssertFalse(SMHIWarningNotificationPolicy.hasNewNationalWarnings(
            current: current, previous: legacy, legacyCurrent: legacyCurrent, hasBaseline: true
        ))
    }

    func testNationalBaselineMigrationStillDetectsActuallyNewWarning() {
        let legacy = Set(["warning-1|Gul|Kraftigt regn"])
        let current = Set(["smhi|warning-1|2026-11-22T08:00:00Z", "smhi|warning-2|2026-11-22T09:00:00Z"])
        let legacyCurrent = Set(["warning-1|Gul|Kraftigt regn", "warning-2|Orange|Hård vind"])

        XCTAssertTrue(SMHIWarningNotificationPolicy.hasNewNationalWarnings(
            current: current, previous: legacy, legacyCurrent: legacyCurrent, hasBaseline: true
        ))
    }

    func testFirstNationalBaselineDoesNotMarkExistingWarningsAsNew() {
        XCTAssertFalse(SMHIWarningNotificationPolicy.hasNewNationalWarnings(
            current: ["smhi|warning-1|2026-11-22T08:00:00Z"], previous: [],
            legacyCurrent: ["warning-1|Gul|Kraftigt regn"], hasBaseline: false
        ))
    }

    func testStableNationalBaselineDetectsNewEpisode() {
        XCTAssertTrue(SMHIWarningNotificationPolicy.hasNewNationalWarnings(
            current: ["smhi|warning-1|2026-11-22T08:00:00Z", "smhi|warning-2|2026-11-22T09:00:00Z"],
            previous: ["smhi|warning-1|2026-11-22T08:00:00Z"],
            legacyCurrent: [], hasBaseline: true
        ))
    }

    func testSMHIInboxFingerprintRejectsMissingIdentity() {
        XCTAssertNil(SMHIWarningNotificationPolicy.smhiEventFingerprint(warningID: nil, start: "2026-11-22T08:00:00Z"))
        XCTAssertNil(SMHIWarningNotificationPolicy.smhiEventFingerprint(warningID: "warning-42", start: nil))
    }

    func testInboxLoadGenerationRejectsOlderRefresh() {
        let older = UUID()
        let newer = UUID()
        XCTAssertFalse(SMHIWarningNotificationPolicy.isCurrentInboxLoad(older, currentGeneration: newer))
        XCTAssertTrue(SMHIWarningNotificationPolicy.isCurrentInboxLoad(newer, currentGeneration: newer))
    }

    func testEndedWarningReleasesItsInMemoryNotificationClaim() {
        let scheduled: Set<String> = ["still-active", "ended"]
        let current: Set<String> = ["still-active"]

        let retained = SMHIWarningNotificationPolicy.retainedScheduledSignatures(
            scheduled: scheduled,
            current: current
        )

        XCTAssertEqual(retained, ["still-active"])
        XCTAssertFalse(retained.contains("ended"))

        // If the same warning later reappears, it is no longer blocked by
        // an in-memory claim from its previous active episode.
        let reappeared = SMHIWarningNotificationPolicy.retainedScheduledSignatures(
            scheduled: retained,
            current: ["still-active", "ended"]
        )
        XCTAssertFalse(reappeared.contains("ended"))
    }

    func testFirstObservationEstablishesBaselineWithoutNotifyingExistingWarnings() {
        XCTAssertTrue(SMHIWarningNotificationPolicy.newlyActiveSignatures(current: ["a", "b"], previous: [], hasBaseline: false).isEmpty)
    }

    func testOnlyNewOrChangedActiveSignaturesAreSelected() {
        XCTAssertEqual(SMHIWarningNotificationPolicy.newlyActiveSignatures(current: ["a", "b-new"], previous: ["a", "b"], hasBaseline: true), ["b-new"])
    }

    func testPreviouslyEndedWarningCanNotifyIfItBecomesActiveAgain() {
        XCTAssertEqual(SMHIWarningNotificationPolicy.newlyActiveSignatures(current: ["a"], previous: [], hasBaseline: true), ["a"])
    }

    func testNoNewWarningsProducesEmptySelection() {
        XCTAssertTrue(SMHIWarningNotificationPolicy.newlyActiveSignatures(current: ["a"], previous: ["a"], hasBaseline: true).isEmpty)
    }

    func testActiveWarningTransitionDropsEndedWarningsFromBaseline() {
        let transition = SMHIWarningNotificationPolicy.activeWarningTransition(
            current: ["still-active"],
            previous: ["still-active", "ended"],
            hasBaseline: true
        )
        XCTAssertTrue(transition.newlyActive.isEmpty)
        XCTAssertEqual(transition.retainedBaseline, ["still-active"])
    }

    func testReappearingWarningIsNewAfterItWasRemovedFromBaseline() {
        let ended = SMHIWarningNotificationPolicy.activeWarningTransition(
            current: [],
            previous: ["warning-a"],
            hasBaseline: true
        )
        XCTAssertTrue(ended.retainedBaseline.isEmpty)

        let reappeared = SMHIWarningNotificationPolicy.activeWarningTransition(
            current: ["warning-a"],
            previous: ended.retainedBaseline,
            hasBaseline: true
        )
        XCTAssertEqual(reappeared.newlyActive, ["warning-a"])
        XCTAssertTrue(reappeared.retainedBaseline.isEmpty)
    }

    func testUnscheduledNewWarningRemainsEligibleUntilAccepted() {
        let firstCheck = SMHIWarningNotificationPolicy.activeWarningTransition(
            current: ["already-known", "new-warning"],
            previous: ["already-known"],
            hasBaseline: true
        )
        XCTAssertEqual(firstCheck.newlyActive, ["new-warning"])
        XCTAssertEqual(firstCheck.retainedBaseline, ["already-known"])

        // Simulate iOS accepting the request: runtime then records the signature.
        let afterAccepted = firstCheck.retainedBaseline.union(firstCheck.newlyActive)
        let nextCheck = SMHIWarningNotificationPolicy.activeWarningTransition(
            current: ["already-known", "new-warning"],
            previous: afterAccepted,
            hasBaseline: true
        )
        XCTAssertTrue(nextCheck.newlyActive.isEmpty)
    }

    func testFirstActiveWarningObservationCreatesBaselineWithoutNotification() {
        let transition = SMHIWarningNotificationPolicy.activeWarningTransition(
            current: ["warning-a", "warning-b"],
            previous: [],
            hasBaseline: false
        )
        XCTAssertTrue(transition.newlyActive.isEmpty)
        XCTAssertEqual(transition.retainedBaseline, ["warning-a", "warning-b"])
    }

    func testParsesISO8601WithFractionalSeconds() {
        XCTAssertNotNil(SMHIWarningNotificationPolicy.parseDate("2026-11-21T10:15:30.123Z"))
    }

    func testParsesISO8601WithoutFractionalSeconds() {
        XCTAssertNotNil(SMHIWarningNotificationPolicy.parseDate("2026-11-21T10:15:30Z"))
    }

    func testParsesTimezoneLessTimestampAsSwedishLocalTime() {
        let value = "2026-01-15T12:30:00"
        let parsed = SMHIWarningNotificationPolicy.parseDate(value)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.timeZone = TimeZone(identifier: "Europe/Stockholm")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        XCTAssertEqual(parsed, formatter.date(from: value))
    }

    func testRejectsMalformedTimestamp() {
        XCTAssertNil(SMHIWarningNotificationPolicy.parseDate("not-a-date"))
    }

    func testSMHICheckGenerationRejectsSupersededResponses() {
        XCTAssertFalse(SMHIWarningNotificationPolicy.isCurrentCheck("older", storedGeneration: "newer"))
        XCTAssertTrue(SMHIWarningNotificationPolicy.isCurrentCheck("current", storedGeneration: "current"))
        XCTAssertFalse(SMHIWarningNotificationPolicy.isCurrentCheck("current", storedGeneration: nil))
    }

    func testForegroundPolicyAcceptsFreshActiveSwedishLocalWarning() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(SMHIWarningNotificationPolicy.shouldPresentInForeground(
            level: "Gul", scheduledAt: now.timeIntervalSince1970 - 30,
            start: "2026-01-01T10:00:00", end: "", now: now
        ))
    }

    func testForegroundPolicyRejectsUnknownLevel() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(SMHIWarningNotificationPolicy.shouldPresentInForeground(
            level: "Meddelande", scheduledAt: now.timeIntervalSince1970,
            start: "2026-01-01T10:00:00", end: "", now: now
        ))
    }

    func testForegroundPolicyRejectsStaleFutureAndExpiredRequests() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fresh = now.timeIntervalSince1970 - 30
        XCTAssertFalse(SMHIWarningNotificationPolicy.shouldPresentInForeground(level: "Orange", scheduledAt: fresh - 700, start: "2026-01-01T10:00:00", end: "", now: now))
        XCTAssertFalse(SMHIWarningNotificationPolicy.shouldPresentInForeground(level: "Röd", scheduledAt: fresh, start: "2027-02-01T10:00:00", end: "", now: now))
        XCTAssertFalse(SMHIWarningNotificationPolicy.shouldPresentInForeground(level: "Gul", scheduledAt: fresh, start: "2026-01-01T10:00:00", end: "2026-01-01T11:00:00", now: now))
    }

    func testForegroundPolicyRejectsMalformedStartAndEnd() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(SMHIWarningNotificationPolicy.shouldPresentInForeground(level: "Gul", scheduledAt: now.timeIntervalSince1970, start: "bad", end: "", now: now))
        XCTAssertFalse(SMHIWarningNotificationPolicy.shouldPresentInForeground(level: "Gul", scheduledAt: now.timeIntervalSince1970, start: "2026-01-01T10:00:00", end: "bad", now: now))
    }
}