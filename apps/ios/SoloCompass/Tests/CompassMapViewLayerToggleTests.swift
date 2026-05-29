import XCTest
@testable import SoloCompass

/// US-009 (decision A): the Companion-layer toggle must be hidden by default
/// so users never tap a dead control (the underlying discovery still returns
/// nil). The toggle is gated behind `FeatureFlags.companionLayerEnabled`,
/// which defaults to `false` and can be flipped in DEBUG via the
/// `FF_COMPANION_LAYER_ENABLED` UserDefaults key.
///
/// We can't introspect SwiftUI's structural tree directly, so we use the same
/// pattern as `CompassMapViewBodyTypeTests`: install the view in a real
/// `UIHostingController`/window graph and read the DEBUG-only
/// `debugCompanionLayerToggleRendered` hook, which the toggle branch flips to
/// `true` only when it is actually placed in the overlay. When the flag is
/// off the branch is structurally absent, so the hook stays `false` — i.e. the
/// toggle is not in the view hierarchy.
@MainActor
final class CompassMapViewLayerToggleTests: XCTestCase {

    private let flagKey = "FF_COMPANION_LAYER_ENABLED"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: flagKey)
        super.tearDown()
    }

    /// Cold launch with the flag at its default (off) → toggle absent.
    func testToggleHiddenWhenFlagIsFalse() {
        UserDefaults.standard.set(false, forKey: flagKey)
        XCTAssertFalse(
            FeatureFlags.companionLayerEnabled,
            "companionLayerEnabled must read false when the override is false"
        )

        installAndPump()

        XCTAssertFalse(
            CompassMapView.debugCompanionLayerToggleRendered,
            "Companion-layer toggle must NOT be in the view hierarchy when "
                + "FeatureFlags.companionLayerEnabled is false"
        )
    }

    /// Flag flipped on (DEBUG override) → toggle present.
    func testTogglePresentWhenFlagIsTrue() {
        UserDefaults.standard.set(true, forKey: flagKey)
        XCTAssertTrue(
            FeatureFlags.companionLayerEnabled,
            "companionLayerEnabled must read true when the override is true"
        )

        installAndPump()

        XCTAssertTrue(
            CompassMapView.debugCompanionLayerToggleRendered,
            "Companion-layer toggle MUST be in the view hierarchy when "
                + "FeatureFlags.companionLayerEnabled is true"
        )
    }

    // MARK: - Helpers

    /// Installs `CompassMapView` in a real window graph with every required
    /// service injected and pumps the run loop so `onAppear` fires.
    private func installAndPump() {
        CompassMapView.debugCompanionLayerToggleRendered = false

        let rootView = CompassMapView()
            .environment(LocationService())
            .environment(ExperienceService())
            .environment(AIService())
            .environment(UserPreferences())
            .environment(NotificationService.shared)
            .environment(SubscriptionService())
            .environment(CompanionService())
            .environment(PresenceService())

        let host = UIHostingController(rootView: rootView)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    }
}
