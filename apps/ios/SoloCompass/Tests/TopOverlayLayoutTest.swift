import XCTest
import SwiftUI
@testable import SoloCompass

/// US-022: the city pill and the filter bar must occupy vertically separate
/// bands in the top overlay so the two capsules never overlap or hit-test
/// interfere.
///
/// The production layout (`MapOverlayView.body`) is driven entirely by the
/// constants in `MapOverlayMetrics`, so this test reconstructs the two rects
/// from the same source of truth and asserts they do not intersect. The
/// modelled width matches the iPhone 17 Pro logical point width (402pt) so the
/// assertion is anchored to the device size called out in the story.
@MainActor
final class TopOverlayLayoutTest: XCTestCase {

    /// iPhone 17 Pro logical width in points (portrait).
    private let iPhone17ProWidth: CGFloat = 402

    /// City pill rect and filter bar rect must not intersect at the
    /// iPhone 17 Pro size — they live in separate vertical bands.
    func testCityPillAndFilterBarDoNotIntersect() {
        let cityPill = MapOverlayMetrics.cityPillRowRect(width: iPhone17ProWidth)
        let filterBar = MapOverlayMetrics.filterBarRect(width: iPhone17ProWidth)

        XCTAssertFalse(
            cityPill.intersects(filterBar),
            "city pill rect \(cityPill) must not intersect filter bar rect \(filterBar)"
        )
    }

    /// There must be a real, non-zero gap between the bottom of the city-pill
    /// band and the top of the filter bar — not merely touching edges.
    func testGapBetweenBandsIsPositive() {
        let cityPill = MapOverlayMetrics.cityPillRowRect(width: iPhone17ProWidth)
        let filterBar = MapOverlayMetrics.filterBarRect(width: iPhone17ProWidth)

        let gap = filterBar.minY - cityPill.maxY
        XCTAssertGreaterThan(
            gap,
            0,
            "expected a positive vertical gap between the city pill and the filter bar, got \(gap)"
        )
        XCTAssertEqual(
            gap,
            MapOverlayMetrics.cityPillToFilterBarGap,
            accuracy: 0.001,
            "the gap should equal the configured cityPillToFilterBarGap"
        )
    }

    /// The filter bar must start strictly below the city pill band — VoiceOver
    /// traversal order (city pill → filter bar → map) mirrors this top-to-bottom
    /// vertical ordering in the overlay's view hierarchy.
    func testFilterBarStartsBelowCityPill() {
        let cityPill = MapOverlayMetrics.cityPillRowRect(width: iPhone17ProWidth)
        let filterBar = MapOverlayMetrics.filterBarRect(width: iPhone17ProWidth)

        XCTAssertGreaterThanOrEqual(
            filterBar.minY,
            cityPill.maxY,
            "filter bar must begin at or below the bottom of the city pill band"
        )
    }

    /// The city-pill band height is pinned to the 44pt HIG hit target so it can
    /// never grow into the gap regardless of the pill's intrinsic visual size.
    func testCityPillRowHeightMatchesHitTarget() {
        XCTAssertEqual(
            MapOverlayMetrics.cityPillRowHeight,
            MapOverlayMetrics.cityPillHitTarget,
            accuracy: 0.001,
            "the city-pill row should reserve exactly the 44pt hit-target height"
        )
    }
}
