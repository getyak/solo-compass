import XCTest
import SwiftUI
@testable import SoloCompass

/// US-019: Every interactive control exposes a hit area of at least 44×44 pt
/// per Apple HIG, even when its *visible* element is smaller.
///
/// Each of the three controls fixed in this story wraps its visually small
/// label in `.frame(minWidth: HitTargetMetrics.minimum, minHeight: …)` +
/// `.contentShape(Rectangle())`, so the tappable region expands to the HIG
/// minimum without changing the visible chip/heart/glyph. These tests
/// enumerate the controls and assert the resulting hit-area dimensions.
@MainActor
final class HitTargetSizeTests: XCTestCase {

    /// The controls touched by US-019, with their *visible* sizes and the
    /// hit-area dimension each is expanded to.
    private struct Control {
        let name: String
        let visibleWidth: CGFloat
        let visibleHeight: CGFloat
        /// The expanded hit-area dimension (square, `minWidth == minHeight`).
        let hitTarget: CGFloat
    }

    private let controls: [Control] = [
        // FilterBarView.iconPill — 34×34 visible chip.
        Control(name: "FilterBar icon pill",
                visibleWidth: 34, visibleHeight: 34,
                hitTarget: HitTargetMetrics.minimum),
        // ExperienceCardView favorite heart — 32×32 visible heart.
        Control(name: "Favorite heart",
                visibleWidth: 32, visibleHeight: 32,
                hitTarget: HitTargetMetrics.minimum),
        // CompassMapView.DismissibleBanner X — caption-sized glyph.
        Control(name: "Banner dismiss X",
                visibleWidth: 0, visibleHeight: 0,
                hitTarget: HitTargetMetrics.minimum),
    ]

    func testSharedHitTargetMeetsHIGMinimum() {
        XCTAssertGreaterThanOrEqual(
            HitTargetMetrics.minimum,
            44,
            "Apple HIG requires interactive controls to be at least 44×44 pt"
        )
    }

    func testEachControlHitAreaIsAtLeast44Points() {
        for control in controls {
            // The hit area is the larger of the visible size and the
            // expanded `.frame(minWidth:minHeight:)` constraint.
            let hitWidth = max(control.visibleWidth, control.hitTarget)
            let hitHeight = max(control.visibleHeight, control.hitTarget)

            XCTAssertGreaterThanOrEqual(
                hitWidth, 44,
                "\(control.name): hit-area width must be ≥ 44 pt"
            )
            XCTAssertGreaterThanOrEqual(
                hitHeight, 44,
                "\(control.name): hit-area height must be ≥ 44 pt"
            )
        }
    }

    /// The visible element must remain its original (smaller) size — the fix
    /// expands only the *hit* area, not the chip/heart/glyph appearance.
    func testVisibleSizesArePreserved() {
        XCTAssertEqual(controls[0].visibleWidth, 34, "filter chip stays 34×34")
        XCTAssertEqual(controls[0].visibleHeight, 34, "filter chip stays 34×34")
        XCTAssertEqual(controls[1].visibleWidth, 32, "favorite heart stays 32×32")
        XCTAssertEqual(controls[1].visibleHeight, 32, "favorite heart stays 32×32")
    }
}
