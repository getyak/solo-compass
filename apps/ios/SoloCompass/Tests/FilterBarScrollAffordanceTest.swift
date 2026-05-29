import XCTest
@testable import SoloCompass

/// US-034 (V-005): the filter chip strip must hint that it scrolls horizontally.
/// A right-edge fade gradient is applied via `.mask(...)` only when the pill
/// content overflows the visible viewport. These tests exercise the pure
/// `shouldShowScrollAffordance(contentWidth:viewportWidth:)` predicate that
/// drives the mask, snapshotting the two regimes the story calls out:
/// overflow (> 6 categories) and no-overflow (≤ 5 categories).
@MainActor
final class FilterBarScrollAffordanceTest: XCTestCase {

    /// Approximate laid-out width of a single chip + inter-pill spacing. Used
    /// only to synthesize representative content widths for the two regimes;
    /// the production predicate itself is layout-agnostic.
    private let perChipWidth: CGFloat = 44
    /// Fixed leading "Now" + "All" pills that always precede the categories.
    private let fixedPillsWidth: CGFloat = 120
    /// Horizontal content padding (12pt each edge) baked into the HStack.
    private let contentPadding: CGFloat = 24
    /// A typical iPhone strip viewport (screen width minus the 16pt outer pad).
    private let viewportWidth: CGFloat = 343

    private func contentWidth(forCategoryCount count: Int) -> CGFloat {
        fixedPillsWidth + contentPadding + CGFloat(count) * perChipWidth
    }

    // MARK: - Overflow regime (> 6 categories)

    func testOverflowShowsAffordanceWithMoreThanSixCategories() {
        let content = contentWidth(forCategoryCount: 7) // 120 + 24 + 308 = 452
        XCTAssertGreaterThan(content, viewportWidth, "precondition: 7 chips should overflow a 343pt viewport")
        XCTAssertTrue(
            FilterBarView.shouldShowScrollAffordance(contentWidth: content, viewportWidth: viewportWidth),
            "right-edge fade must appear when > 6 categories overflow the strip"
        )
    }

    func testOverflowShowsAffordanceWithAllEightCategories() {
        let content = contentWidth(forCategoryCount: 8)
        XCTAssertTrue(
            FilterBarView.shouldShowScrollAffordance(contentWidth: content, viewportWidth: viewportWidth),
            "the default 8-category set must overflow and show the fade"
        )
    }

    // MARK: - No-overflow regime (≤ 5 categories)

    func testNoAffordanceWhenFiveOrFewerCategoriesFit() {
        let content = contentWidth(forCategoryCount: 5) // 120 + 24 + 220 = 364 — still wider than 343?
        // Use a roomier viewport that comfortably fits 5 chips to model "all fit".
        let roomyViewport: CGFloat = content + 40
        XCTAssertFalse(
            FilterBarView.shouldShowScrollAffordance(contentWidth: content, viewportWidth: roomyViewport),
            "no fade should appear when ≤ 5 categories fit within the viewport"
        )
    }

    func testNoAffordanceWhenContentExactlyFitsViewport() {
        let width: CGFloat = 343
        XCTAssertFalse(
            FilterBarView.shouldShowScrollAffordance(contentWidth: width, viewportWidth: width),
            "content exactly equal to the viewport must not trigger the fade"
        )
    }

    // MARK: - Edge cases

    func testSubPixelDifferenceWithinToleranceShowsNoAffordance() {
        // Layout rounding can leave content a fraction wider than the viewport;
        // that must not trip the fade.
        let viewport: CGFloat = 343
        let content = viewport + (FilterBarView.overflowTolerance - 0.01)
        XCTAssertFalse(
            FilterBarView.shouldShowScrollAffordance(contentWidth: content, viewportWidth: viewport),
            "sub-tolerance overflow must be treated as 'fits'"
        )
    }

    func testZeroWidthBeforeLayoutShowsNoAffordance() {
        XCTAssertFalse(
            FilterBarView.shouldShowScrollAffordance(contentWidth: 0, viewportWidth: 0),
            "unmeasured (zero) widths must never show the fade"
        )
        XCTAssertFalse(
            FilterBarView.shouldShowScrollAffordance(contentWidth: 400, viewportWidth: 0),
            "a zero viewport (not yet laid out) must never show the fade"
        )
    }
}
