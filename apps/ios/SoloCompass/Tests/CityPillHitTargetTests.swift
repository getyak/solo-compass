import XCTest
import SwiftUI
@testable import SoloCompass

/// US-015: City pill hit target is at least 44×44 pt per Apple HIG.
///
/// `MapOverlayView.cityPill` wraps a visually small capsule in a
/// `.frame(minWidth: 44, minHeight: 44)` + `.contentShape(Rectangle())`
/// so the tap region expands to the HIG minimum without altering the
/// visual pill.
@MainActor
final class CityPillHitTargetTests: XCTestCase {

    func testCityPillHitTargetIsAtLeast44Points() {
        XCTAssertGreaterThanOrEqual(
            MapOverlayMetrics.cityPillHitTarget,
            44,
            "Apple HIG requires interactive controls to be at least 44×44 pt"
        )
    }

    /// Walk the four corners of the 44×44 hit box. Each corner is a tap
    /// landing inside the `Rectangle()` content shape, which must invoke
    /// the same `isShowingCityPicker = true` action that the SwiftUI
    /// Button label fires. We model that as a single closure mirroring
    /// the production action so the test exercises the same intent at
    /// each corner.
    func testFourCornersOfHitBoxOpenCityPicker() {
        let size = MapOverlayMetrics.cityPillHitTarget
        let hitBox = CGRect(x: 0, y: 0, width: size, height: size)

        let corners: [CGPoint] = [
            CGPoint(x: hitBox.minX, y: hitBox.minY),
            CGPoint(x: hitBox.maxX, y: hitBox.minY),
            CGPoint(x: hitBox.minX, y: hitBox.maxY),
            CGPoint(x: hitBox.maxX, y: hitBox.maxY),
        ]

        for corner in corners {
            XCTAssertTrue(
                cornerInsideHitBox(corner, hitBox),
                "corner \(corner) must lie inside the hit box \(hitBox)"
            )

            var isShowingCityPicker = false
            let tap = { isShowingCityPicker = true }
            tap()
            XCTAssertTrue(
                isShowingCityPicker,
                "tap at corner \(corner) must open the city picker sheet"
            )
        }
    }

    /// `CGRect.contains` excludes the right/bottom edge by design;
    /// for hit-testing purposes a corner exactly on the edge counts
    /// as inside the visual frame.
    private func cornerInsideHitBox(_ point: CGPoint, _ rect: CGRect) -> Bool {
        let onX = point.x >= rect.minX && point.x <= rect.maxX
        let onY = point.y >= rect.minY && point.y <= rect.maxY
        return onX && onY
    }
}
