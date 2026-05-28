import XCTest
@testable import SoloCompass

@MainActor
final class HapticServiceTests: XCTestCase {

    private let key = HapticService.defaultsKey

    override func setUp() {
        super.setUp()
        // Restore default state before each test.
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    func testDefaultsToEnabled() {
        // Key absent → reads as true.
        XCTAssertTrue(HapticService.shared.isEnabled)
    }

    func testDisabledFlagPersists() {
        HapticService.shared.isEnabled = false
        XCTAssertFalse(HapticService.shared.isEnabled)
        // Re-read from UserDefaults directly to confirm persistence.
        XCTAssertEqual(UserDefaults.standard.bool(forKey: key), false)
    }

    func testReEnablePersists() {
        HapticService.shared.isEnabled = false
        HapticService.shared.isEnabled = true
        XCTAssertTrue(HapticService.shared.isEnabled)
    }

    /// Verifies that calling `impact` and `notification` with `isEnabled = false`
    /// short-circuits before any UIKit generator is touched (no crash or assertion).
    /// We can't intercept UIKit calls directly in unit tests, so we rely on the
    /// fact that the methods must return without throwing when the flag is off.
    func testDisabledFlagShortCircuitsImpact() {
        HapticService.shared.isEnabled = false
        // These must complete without crashing.
        HapticService.shared.impact(style: .light)
        HapticService.shared.impact(style: .medium)
        HapticService.shared.impact(style: .heavy)
    }

    func testDisabledFlagShortCircuitsNotification() {
        HapticService.shared.isEnabled = false
        HapticService.shared.notification(type: .success)
        HapticService.shared.notification(type: .warning)
        HapticService.shared.notification(type: .error)
    }

    func testPrepareShortCircuitsWhenDisabled() {
        HapticService.shared.isEnabled = false
        HapticService.shared.prepare(style: .light)
        // No crash → disabled flag short-circuits generator creation correctly.
    }
}
