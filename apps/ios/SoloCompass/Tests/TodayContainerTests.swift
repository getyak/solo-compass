import XCTest
import SwiftUI
@testable import SoloCompass

/// Nomad OS B1-a: `TodayContainer` is the app root and must route on
/// `FeatureFlags.todayHome`. The critical guarantee is the **rollback path**:
/// with the flag off (the shipping default), the root falls straight through
/// to `CompassMapView` with zero behavioural change. These tests install the
/// container in a real graph — both branches read `@Environment`, and the
/// flag-on branch embeds `CompassMapView` as its map layer — so every service
/// `CompassMapView` needs is injected regardless of branch.
@MainActor
final class TodayContainerTests: XCTestCase {

    private let flagKey = "FF_TODAY_HOME"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: flagKey)
        TodayContainer.debugRenderedBranch = .none
        super.tearDown()
    }

    /// Flag OFF (default) → root is the map, unchanged. This is the safety net.
    func testFlagOffRendersMapFallback() {
        UserDefaults.standard.set(false, forKey: flagKey)
        XCTAssertFalse(FeatureFlags.todayHome, "override should force flag off")

        installAndPump()

        XCTAssertEqual(
            TodayContainer.debugRenderedBranch, .mapFallback,
            "flag off must fall through to CompassMapView with no form change"
        )
    }

    /// Flag ON → root is the Today home scaffold, not the bare map.
    func testFlagOnRendersTodayHome() {
        UserDefaults.standard.set(true, forKey: flagKey)
        XCTAssertTrue(FeatureFlags.todayHome, "override should force flag on")

        installAndPump()

        XCTAssertEqual(
            TodayContainer.debugRenderedBranch, .todayHome,
            "flag on must render the Today home scaffold"
        )
    }

    // MARK: Helper

    private func installAndPump() {
        TodayContainer.debugRenderedBranch = .none

        let root = TodayContainer()
            .environment(LocationService())
            .environment(ExperienceService())
            .environment(AIService())
            .environment(UserPreferences())
            .environment(NotificationService.shared)
            .environment(SubscriptionService())
            .environment(CompanionService())
            .environment(PresenceService())
            .environment(BestNowClock.shared)

        let host = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    }
}
