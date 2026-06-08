import XCTest
@testable import SoloCompass

/// Verifies the `CompassMapView.imminenceProgress(minutesUntil:windowMinutes:)` helper
/// used to fill the gold progress ring in the 'Now · upcoming' badge.
///
/// Run with:
///   xcodebuild test -only-testing:SoloCompassTests/ImminenceProgressTests
final class ImminenceProgressTests: XCTestCase {

    func testAtWindowBoundaryReturnsZero() {
        XCTAssertEqual(CompassMapView.imminenceProgress(minutesUntil: 120), 0.0, accuracy: 1e-9)
    }

    func testAtHalfwayReturnsFiftyPercent() {
        XCTAssertEqual(CompassMapView.imminenceProgress(minutesUntil: 60), 0.5, accuracy: 1e-9)
    }

    func testAtZeroMinutesReturnsFull() {
        XCTAssertEqual(CompassMapView.imminenceProgress(minutesUntil: 0), 1.0, accuracy: 1e-9)
    }

    func testBeyondWindowClampsToZero() {
        XCTAssertEqual(CompassMapView.imminenceProgress(minutesUntil: 200), 0.0, accuracy: 1e-9)
    }

    func testNegativeMinutesClampsToOne() {
        XCTAssertEqual(CompassMapView.imminenceProgress(minutesUntil: -5), 1.0, accuracy: 1e-9)
    }
}
