import XCTest
import SwiftUI
@testable import SoloCompass

/// US-005: `CompassMapView.body` must return the `@ViewBuilder` result of
/// `mapContent` directly — no `AnyView(...)` wrapper. Type-erasing the root
/// of the app's heaviest view defeats SwiftUI's structural identity and
/// blocks incremental diffing, so we guard against it regressing.
///
/// `CompassMapView.body` reads `@Environment(LocationService.self)` (and other
/// `@Observable` services) the moment it is evaluated, so we cannot inspect
/// `type(of: instance.body)` on a bare instance — it would trap with a
/// "No Observable object" fatal error. Instead we install the view in a real
/// SwiftUI graph via `UIHostingController` with every required service
/// injected, drive a layout pass so `onAppear` fires, and read the
/// `body` type name that the view captured at that point.
@MainActor
final class CompassMapViewBodyTypeTests: XCTestCase {

    func testBodyIsNotAnyViewWrapped() {
        CompassMapView.debugBodyTypeName = ""

        let rootView = CompassMapView()
            .environment(LocationService())
            .environment(ExperienceService())
            .environment(AIService())
            .environment(UserPreferences())
            .environment(NotificationService.shared)
            .environment(SubscriptionService())
            .environment(CompanionService())
            .environment(PresenceService())
            // CompassMapView's subviews (ExperienceCardView / BottomInfoSheet) read
            // @Environment(BestNowClock.self); the app injects it at the root, so the
            // test must too — otherwise body evaluation traps with "No Observable
            // object of type BestNowClock", crashing and restarting the XCTest host.
            .environment(BestNowClock.shared)

        let host = UIHostingController(rootView: rootView)
        // `onAppear` only fires once the view is in a real window hierarchy,
        // so install the host on a key window before driving layout.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        // Pump the run loop so SwiftUI flushes the install/onAppear cycle.
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        let bodyTypeName = CompassMapView.debugBodyTypeName
        XCTAssertFalse(
            bodyTypeName.isEmpty,
            "onAppear did not fire — body type was never captured"
        )
        XCTAssertFalse(
            bodyTypeName.contains("AnyView"),
            "CompassMapView.body must return some View directly so SwiftUI can "
                + "diff the root incrementally; got type: \(bodyTypeName)"
        )
    }
}
