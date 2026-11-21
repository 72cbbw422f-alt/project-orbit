import XCTest

final class SMHIWarningNotificationPolicyTests: XCTestCase {
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