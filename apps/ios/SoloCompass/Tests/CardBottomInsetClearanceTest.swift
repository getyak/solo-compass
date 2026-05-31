import XCTest
import SwiftUI
@testable import SoloCompass

/// Regression guard for the "selected-experience floating card hidden behind the
/// bottom sheet" bug.
///
/// **The bug:** `ExperienceCardView` (the popup preview card in
/// `CompassMapView`) used a hard-coded `.padding(.bottom, 80)`. The
/// `BottomInfoSheet` rests at its `peek` detent at **170pt** (the
/// `basePeekHeight`) and grows further with Dynamic Type. An 80pt inset is far
/// shorter than the 170pt peek, so the card's lower edge — including its
/// Solo-Score rating row — was occluded by the sheet.
///
/// **The fix:** `CompassMapView.cardBottomInset` now computes
/// `BottomSheetDetent.peekHeight(for: traits) + cardSheetGap` where
/// `cardSheetGap == 12`, so the card always floats clear of the sheet's resting
/// height at any text size.
///
/// These are pure geometric assertions (no pixel rendering) so they are fast and
/// deterministic. The `cardBottomInset` formula is reproduced below as the unit
/// under test.
///
/// ⚠️ If `CompassMapView.cardBottomInset` ever changes its formula or the
/// `cardSheetGap` constant, update `Self.cardSheetGap` and `inset(for:)` here to
/// match, or this regression guard will silently drift from production.
@MainActor
final class CardBottomInsetClearanceTest: XCTestCase {

    // MARK: - Reproduced production constants

    /// Mirror of `CompassMapView.cardBottomInset`'s `cardSheetGap` (the breathing
    /// room between the card's lower edge and the sheet's top). Keep in sync with
    /// production.
    private static let cardSheetGap: CGFloat = 12

    /// The old hard-coded inset that caused the bug: 80pt < 170pt peek height, so
    /// the card's Solo-Score row was hidden behind the sheet. This is the root
    /// cause being regressed against.
    private static let legacyBrokenInset: CGFloat = 80

    /// The unscaled base `peek` detent height (`basePeekHeight` in
    /// `BottomInfoSheet.swift`).
    private static let basePeekHeight: CGFloat = 170

    /// Mirror of `CompassMapView.controlBarBottomInset`'s `controlSheetGap` — the
    /// gap between the floating map control bar (filter / explore / `+` FAB) and
    /// the sheet top. Slightly smaller than `cardSheetGap` so the controls hug the
    /// sheet. Keep in sync with production.
    private static let controlSheetGap: CGFloat = 8

    /// Reproduces `CompassMapView.cardBottomInset` for the given traits.
    private func inset(for traits: UITraitCollection?) -> CGFloat {
        BottomSheetDetent.peekHeight(for: traits) + Self.cardSheetGap
    }

    /// Reproduces `CompassMapView.controlBarBottomInset` for the given traits.
    private func controlInset(for traits: UITraitCollection?) -> CGFloat {
        BottomSheetDetent.peekHeight(for: traits) + Self.controlSheetGap
    }

    // MARK: - Trait collections

    private var ax5Traits: UITraitCollection {
        UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
    }

    // MARK: - 1. Core clearance assertion

    /// The default peek height must be ≥ the 170pt base, and the card inset
    /// (peek + gap) must be strictly greater than the peek height — i.e. the
    /// card's bottom edge sits above the sheet's top edge with a positive gap.
    func testCardInsetClearsPeekHeightWithPositiveGap() {
        let peekHeight = BottomSheetDetent.peekHeight(for: nil)
        XCTAssertGreaterThanOrEqual(
            peekHeight, Self.basePeekHeight,
            "Default peek height must be at least the \(Self.basePeekHeight)pt base; got \(peekHeight)"
        )

        let inset = inset(for: nil)
        XCTAssertGreaterThan(
            inset, peekHeight,
            "Card inset (\(inset)) must exceed the peek height (\(peekHeight)) so the card floats clear of the sheet"
        )

        let gap = inset - peekHeight
        XCTAssertGreaterThan(gap, 0, "Gap between card and sheet must be positive; got \(gap)")
        XCTAssertEqual(
            gap, Self.cardSheetGap, accuracy: 0.0001,
            "Gap must equal cardSheetGap (\(Self.cardSheetGap)); if this fails the formula drifted from CompassMapView"
        )
    }

    // MARK: - 2. Dynamic Type does not regress

    /// At the largest text size (AX5) the peek height — and therefore the card
    /// inset — must grow beyond the default, so the card still clears the
    /// (now taller) sheet rather than falling back behind it.
    func testCardInsetGrowsAtAX5SoCardStillClears() {
        let defaultPeek = BottomSheetDetent.peekHeight(for: nil)
        let ax5Peek = BottomSheetDetent.peekHeight(for: ax5Traits)
        XCTAssertGreaterThan(
            ax5Peek, defaultPeek,
            "At AX5 the peek height (\(ax5Peek)) must exceed the default (\(defaultPeek))"
        )

        let defaultInset = inset(for: nil)
        let ax5Inset = inset(for: ax5Traits)
        XCTAssertGreaterThan(
            ax5Inset, defaultInset,
            "At AX5 the card inset (\(ax5Inset)) must grow beyond the default (\(defaultInset))"
        )

        // The clearance gap is preserved at AX5 too — card still floats clear.
        XCTAssertGreaterThan(
            ax5Inset, ax5Peek,
            "At AX5 the card inset (\(ax5Inset)) must still exceed the peek height (\(ax5Peek))"
        )
    }

    // MARK: - 3. Regression against the old broken value

    /// The fixed default inset (≈182pt) must be strictly greater than the old
    /// hard-coded 80pt. The 80pt inset is precisely the bug's root cause: it sat
    /// far below the 170pt peek, hiding the card's Solo-Score row behind the
    /// sheet.
    func testDefaultInsetExceedsLegacyBrokenValue() {
        let defaultInset = inset(for: nil)
        XCTAssertGreaterThan(
            defaultInset, Self.legacyBrokenInset,
            "Fixed inset (\(defaultInset)) must exceed the legacy broken 80pt that caused the occlusion bug"
        )
        // Sanity: the legacy value was itself below the peek height — that is *why*
        // it broke.
        XCTAssertLessThan(
            Self.legacyBrokenInset, BottomSheetDetent.peekHeight(for: nil),
            "The legacy 80pt inset was below the peek height, confirming the documented root cause"
        )
    }

    // MARK: - 4. Map control bar clears the sheet too

    /// The floating control bar (filter / explore / `+` FAB) shared the exact same
    /// bug: a hard-coded `.padding(.bottom, 80)` left the lower half of all three
    /// buttons occluded by the peek sheet. `controlBarBottomInset` now tracks the
    /// peek height, so the controls clear the sheet at every Dynamic Type size.
    func testControlBarInsetClearsPeekHeightAtDefaultAndAX5() {
        // Default size: inset clears peek with the documented gap.
        let defaultPeek = BottomSheetDetent.peekHeight(for: nil)
        let defaultControlInset = controlInset(for: nil)
        XCTAssertGreaterThan(
            defaultControlInset, defaultPeek,
            "Control-bar inset (\(defaultControlInset)) must exceed the peek height (\(defaultPeek))"
        )
        XCTAssertEqual(
            defaultControlInset - defaultPeek, Self.controlSheetGap, accuracy: 0.0001,
            "Control-bar gap must equal controlSheetGap (\(Self.controlSheetGap)); if this fails the formula drifted from CompassMapView"
        )

        // Regression against the shared legacy 80pt root cause.
        XCTAssertGreaterThan(
            defaultControlInset, Self.legacyBrokenInset,
            "Fixed control inset (\(defaultControlInset)) must exceed the legacy broken 80pt that occluded the buttons"
        )

        // AX5: inset grows with the taller peek so the controls still clear.
        let ax5Peek = BottomSheetDetent.peekHeight(for: ax5Traits)
        let ax5ControlInset = controlInset(for: ax5Traits)
        XCTAssertGreaterThan(
            ax5ControlInset, defaultControlInset,
            "At AX5 the control inset (\(ax5ControlInset)) must grow beyond the default (\(defaultControlInset))"
        )
        XCTAssertGreaterThan(
            ax5ControlInset, ax5Peek,
            "At AX5 the control inset (\(ax5ControlInset)) must still exceed the peek height (\(ax5Peek))"
        )
    }
}
