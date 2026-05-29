import XCTest
import SwiftUI
@testable import SoloCompass

// MARK: - US-043: Filter "Now" ↔ Map "bestNow" visual sync — smooth animation

/// US-043 refines US-035 by guaranteeing the Now-sync highlight glides between
/// states rather than snapping: toggling the Now pill fades the map ring in,
/// and deselecting Now fades it back out.
///
/// SwiftUI view modifiers aren't introspectable, so — like the rest of the
/// `MarkerIconView` test suite — we assert via render-free hooks:
///   - `MarkerIconView.nowSyncTransition` is the exact `.easeInOut(duration:0.2)`
///     animation applied to the body with `value: showsNowSyncRing`;
///   - `showsNowSyncRing` is the animated value, which must flip with the Now
///     filter so the transition has something to animate.
///
/// Run with:
///   xcodebuild test -only-testing:SoloCompassTests/FilterNowMapAnimationTest
final class FilterNowMapAnimationTest: XCTestCase {

    /// The transition animation must exist and match the spec'd easing/duration
    /// (`.easeInOut(duration: 0.2)`). We compare against a freshly constructed
    /// instance — `Animation` is `Equatable`, so this asserts both the curve and
    /// the duration without rendering.
    func testNowSyncTransitionIsEaseInOutPointTwo() {
        XCTAssertEqual(
            MarkerIconView.nowSyncTransition,
            .easeInOut(duration: 0.2),
            "US-043: the Now-sync highlight must animate with .easeInOut(duration: 0.2)"
        )
    }

    /// The transition must not be the default/snap — guard against a future edit
    /// silently dropping the easing back to an instant change.
    func testNowSyncTransitionIsNotInstant() {
        XCTAssertNotEqual(
            MarkerIconView.nowSyncTransition,
            .easeInOut(duration: 0),
            "US-043: the highlight must not snap between states"
        )
    }

    /// Selecting Now turns the highlight on; deselecting must turn it back off.
    /// This is the animated value (`showsNowSyncRing`) that the transition rides,
    /// so without this flip there would be nothing to animate — and US-043
    /// explicitly requires deselecting Now to remove the highlight.
    func testDeselectingNowRemovesHighlight() {
        let on = MarkerIconView(
            category: .coffee, state: .bestNow, confidenceLevel: 4, nowFilterActive: true
        )
        let off = MarkerIconView(
            category: .coffee, state: .bestNow, confidenceLevel: 4, nowFilterActive: false
        )

        XCTAssertTrue(on.showsNowSyncRing, "Now on → highlight shown")
        XCTAssertFalse(off.showsNowSyncRing, "Deselecting Now must remove the highlight")
    }
}
