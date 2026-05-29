import XCTest
import SwiftUI
@testable import SoloCompass

/// US-030: the BottomInfoSheet sort button must expose an `accessibilityValue`
/// that announces the current sort mode to VoiceOver (e.g. "Sorted by smart").
///
/// `SortMode.accessibilityValue` is keyed off the raw mode as
/// `sort.value.<mode>`, so the announced value must update when the active sort
/// mode changes. These assertions are locale-independent: rather than asserting
/// a specific localized phrase, they assert that (1) every mode yields a
/// non-empty value, (2) distinct modes yield distinct values, and (3) switching
/// the bound mode flips the announced value — which is the behavior VoiceOver
/// relies on.
final class SortButtonA11yValueTest: XCTestCase {

    func testEveryModeHasNonEmptyAccessibilityValue() {
        for mode in SortMode.allCases {
            XCTAssertFalse(
                mode.accessibilityValue.isEmpty,
                "\(mode) must expose a non-empty accessibilityValue"
            )
        }
    }

    func testEachModeAnnouncesADistinctValue() {
        let values = SortMode.allCases.map(\.accessibilityValue)
        let unique = Set(values)
        XCTAssertEqual(
            unique.count, SortMode.allCases.count,
            "Each sort mode must announce a distinct accessibilityValue; got \(values)"
        )
    }

    /// The accessibilityValue must track the active mode: as the bound sort mode
    /// changes, the value the button would announce changes with it.
    func testAccessibilityValueUpdatesWhenSortModeChanges() {
        var mode: SortMode = .smart
        let smartValue = mode.accessibilityValue

        mode = .distance
        let distanceValue = mode.accessibilityValue

        mode = .soloScore
        let soloValue = mode.accessibilityValue

        mode = .now
        let nowValue = mode.accessibilityValue

        XCTAssertNotEqual(smartValue, distanceValue,
            "Switching smart → distance must change the announced value")
        XCTAssertNotEqual(distanceValue, soloValue,
            "Switching distance → soloScore must change the announced value")
        XCTAssertNotEqual(soloValue, nowValue,
            "Switching soloScore → now must change the announced value")
    }

    /// When the localized strings resolve (test host bundle is found), the value
    /// for each mode must differ from its raw `sort.value.<mode>` key, proving the
    /// key is actually present in Localizable.strings and not falling back to the
    /// key itself.
    func testAccessibilityValueResolvesFromLocalizableStrings() throws {
        // Only meaningful when the strings table is available in the test host.
        let probe = NSLocalizedString("sheet.sort.button", comment: "")
        try XCTSkipIf(probe == "sheet.sort.button",
            "Localizable.strings not resolvable in this test host; skipping")

        for mode in SortMode.allCases {
            XCTAssertNotEqual(
                mode.accessibilityValue, "sort.value.\(mode.rawValue)",
                "sort.value.\(mode.rawValue) must be defined in Localizable.strings"
            )
        }
    }
}
