import XCTest
import SwiftUI
@testable import SoloCompass

/// US-024: VoiceOver users must hear all six SoloScore dimensions read out from
/// the radar chart. `SoloScoreRadarChart` exposes a combined accessibility
/// element whose label names every dimension with its value and whose value
/// announces the overall score.
///
/// We assert against the raw label/value strings the view builds (which back the
/// `.accessibilityLabel` / `.accessibilityValue` modifiers), since SwiftUI's
/// resolved `Text` is otherwise opaque.
@MainActor
final class SoloScoreRadarA11yTest: XCTestCase {

    private func makeChart() -> SoloScoreRadarChart {
        let score = SoloScore(
            overall: 7.8,
            breakdown: .init(
                seatingFriendly: 9,
                soloPatronRatio: 3,
                staffPressure: 8,
                soloPortioning: 7,
                ambianceFit: 6,
                safety: 9
            ),
            hint: "Great seating and safety, but few solo patrons.",
            basedOnCount: 22
        )
        return SoloScoreRadarChart(score: score)
    }

    func testAccessibilityLabelIsNonEmpty() {
        let label = makeChart().radarAccessibilityLabelString
        XCTAssertFalse(
            label.isEmpty,
            "Radar chart accessibility label must not be empty"
        )
    }

    func testAccessibilityLabelContainsAllSixDimensions() {
        let label = makeChart().radarAccessibilityLabelString
        for key in ["solo.seating", "solo.staff", "solo.patrons",
                    "solo.ambiance", "solo.safety", "solo.portioning"] {
            let name = NSLocalizedString(key, comment: "")
            XCTAssertTrue(
                label.contains(name),
                "Accessibility label must name the \(name) dimension; got: \(label)"
            )
        }
    }

    func testAccessibilityLabelContainsDimensionValues() {
        let label = makeChart().radarAccessibilityLabelString
        // Each dimension is rendered as "<name> <value> of 10".
        XCTAssertTrue(
            label.contains("of 10"),
            "Accessibility label must read each dimension value out of 10; got: \(label)"
        )
    }

    func testAccessibilityValueAnnouncesOverallScore() {
        let value = makeChart().radarAccessibilityValueString
        XCTAssertFalse(value.isEmpty, "Accessibility value must not be empty")
        XCTAssertTrue(
            value.contains("7.8"),
            "Accessibility value must announce the overall score 7.8; got: \(value)"
        )
    }
}
