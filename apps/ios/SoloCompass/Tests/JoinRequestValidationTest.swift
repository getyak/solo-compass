import XCTest
@testable import SoloCompass

/// US-031: JoinRouteRequestSheet inline error feedback.
///
/// Asserts the pure `JoinRequestValidation` logic that drives the sheet's
/// inline hints and submit-enabled state: a missing pace or empty message each
/// surface their hint (`join.error.<field>.missing`); filling both clears the
/// hints and enables submit.
final class JoinRequestValidationTest: XCTestCase {

    // MARK: - Pace hint appears / disappears

    func testPaceHintAppearsWhenNoPaceChosen() {
        XCTAssertTrue(
            JoinRequestValidation.isPaceMissing(nil),
            "With no pace chosen the pace field must show its missing hint"
        )
    }

    func testPaceHintDisappearsWhenPaceChosen() {
        for pace in PaceMatch.allCases {
            XCTAssertFalse(
                JoinRequestValidation.isPaceMissing(pace),
                "Choosing a pace (\(pace)) must clear the pace hint"
            )
        }
    }

    // MARK: - Message hint appears / disappears

    func testMessageHintAppearsWhenEmpty() {
        XCTAssertTrue(
            JoinRequestValidation.isMessageMissing(""),
            "An empty message must show its missing hint"
        )
    }

    func testMessageHintAppearsWhenOnlyWhitespace() {
        XCTAssertTrue(
            JoinRequestValidation.isMessageMissing("   \n\t "),
            "A whitespace-only message must still show its missing hint"
        )
    }

    func testMessageHintDisappearsWhenFilled() {
        XCTAssertFalse(
            JoinRequestValidation.isMessageMissing("Hi there!"),
            "A non-empty message must clear the message hint"
        )
    }

    // MARK: - Submit gating

    func testSubmitDisabledWhenPaceMissing() {
        XCTAssertFalse(
            JoinRequestValidation.canSubmit(pace: nil, message: "A long enough intro message"),
            "Submit must stay disabled while the pace is unchosen"
        )
    }

    func testSubmitDisabledWhenMessageMissing() {
        XCTAssertFalse(
            JoinRequestValidation.canSubmit(pace: .matching, message: ""),
            "Submit must stay disabled while the message is empty"
        )
    }

    func testSubmitDisabledWhenMessageTooShort() {
        XCTAssertFalse(
            JoinRequestValidation.canSubmit(pace: .matching, message: "short"),
            "Submit must stay disabled while the message is under the minimum length"
        )
    }

    func testSubmitEnabledWhenBothFieldsValid() {
        XCTAssertTrue(
            JoinRequestValidation.canSubmit(pace: .faster, message: "Excited to join this walk!"),
            "Filling both fields must enable submit"
        )
    }

    // MARK: - Localized hint strings resolve

    func testFieldHintsResolveToLocalizedStrings() {
        for field in [JoinRequestField.pace, JoinRequestField.message] {
            let hint = field.missingHint
            XCTAssertFalse(hint.isEmpty, "\(field.rawValue) hint must be non-empty")
            XCTAssertNotEqual(
                hint, "join.error.\(field.rawValue).missing",
                "\(field.rawValue) hint must resolve to a localized value, not the raw key"
            )
        }
    }
}
