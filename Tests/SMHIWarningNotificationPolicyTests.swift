import XCTest

final class SMHIWarningNotificationPolicyTests: XCTestCase {
    func testFirstObservationEstablishesBaselineWithoutNotifyingExistingWarnings() {
        let current: Set<String> = ["warning-a", "warning-b"]
        XCTAssertTrue(
            SMHIWarningNotificationPolicy.newlyActiveSignatures(
                current: current,
                previous: [],
                hasBaseline: false
            ).isEmpty
        )
    }

    func testOnlyNewOrChangedActiveSignaturesAreSelected() {
        let current: Set<String> = ["warning-a", "warning-b-new"]
        let previous: Set<String> = ["warning-a", "warning-b"]
        XCTAssertEqual(
            SMHIWarningNotificationPolicy.newlyActiveSignatures(
                current: current,
                previous: previous,
                hasBaseline: true
            ),
            ["warning-b-new"]
        )
    }

    func testPreviouslyEndedWarningCanNotifyIfItBecomesActiveAgain() {
        let current: Set<String> = ["warning-a"]
        let previous: Set<String> = []
        XCTAssertEqual(
            SMHIWarningNotificationPolicy.newlyActiveSignatures(
                current: current,
                previous: previous,
                hasBaseline: true
            ),
            ["warning-a"]
        )
    }

    func testNoNewWarningsProducesEmptySelection() {
        let current: Set<String> = ["warning-a"]
        XCTAssertTrue(
            SMHIWarningNotificationPolicy.newlyActiveSignatures(
                current: current,
                previous: current,
                hasBaseline: true
            ).isEmpty
        )
    }
}
