import XCTest
import SwiftUI
@testable import SoloCompass

/// Regression for the bottom-left settings FAB (`slider.horizontal.3`).
///
/// The button's action sets `viewModel.isShowingSettings = true`, which is only
/// meaningful if some `.sheet(isPresented: settingsSheetBinding)` modifier is
/// wired into `CompassMapView`'s tree to observe it. Commit 6655422 (the US-025
/// Routes-section change) accidentally deleted that modifier line, so the flag
/// flipped but nothing presented — the FAB looked dead. The `settingsSheetBinding`
/// and `settingsSheetContent` properties still existed (unused private members
/// compile without warning), so the build stayed green and the regression slipped
/// through.
///
/// We can't introspect SwiftUI's structural tree directly, so we reuse the
/// `CompassMapViewLayerToggleTests` pattern: install the view in a real window
/// graph, force `isShowingSettings` on via the DEBUG-only
/// `debugForceShowSettings` hook, pump the run loop, and read
/// `debugSettingsSheetRendered` — which only flips when `settingsSheetContent`
/// is actually evaluated (i.e. the sheet presented).
@MainActor
final class SettingsSheetPresentationTests: XCTestCase {

    override func tearDown() {
        CompassMapView.debugForceShowSettings = false
        CompassMapView.debugSettingsSheetRendered = false
        super.tearDown()
    }

    /// Forcing `isShowingSettings` true must present the settings sheet. This
    /// fails (hook stays false) if the `.sheet(isPresented: settingsSheetBinding)`
    /// modifier is missing from the tree — exactly the 6655422 regression.
    func testSettingsSheetPresentsWhenFlagIsTrue() {
        CompassMapView.debugForceShowSettings = true
        CompassMapView.debugSettingsSheetRendered = false

        installAndPump()

        XCTAssertTrue(
            CompassMapView.debugSettingsSheetRendered,
            "Settings sheet must present when isShowingSettings is true — the "
                + ".sheet(isPresented: settingsSheetBinding) modifier must be "
                + "wired into CompassMapView (regression of commit 6655422)."
        )
    }

    /// Control: with the flag off, the sheet must NOT present. Proves the hook
    /// tracks real presentation rather than always firing.
    func testSettingsSheetAbsentWhenFlagIsFalse() {
        CompassMapView.debugForceShowSettings = false
        CompassMapView.debugSettingsSheetRendered = false

        installAndPump()

        XCTAssertFalse(
            CompassMapView.debugSettingsSheetRendered,
            "Settings sheet must stay closed when isShowingSettings is false."
        )
    }

    // MARK: - Helpers

    /// Installs `CompassMapView` in a real window graph with every required
    /// service injected and pumps the run loop so `onAppear` (and any resulting
    /// sheet presentation) fires.
    private func installAndPump() {
        // SettingsView (the sheet content) reads LanguageService and a SwiftData
        // modelContext from the environment in addition to the services the map
        // needs. Inject the full set so the presented sheet renders instead of
        // tripping SwiftUI's "no value for environment key" assertion.
        let rootView = CompassMapView()
            .environment(LocationService())
            .environment(ExperienceService())
            .environment(AIService())
            .environment(UserPreferences())
            .environment(NotificationService.shared)
            .environment(SubscriptionService())
            .environment(CompanionService())
            .environment(PresenceService())
            .environment(BestNowClock.shared)
            .environment(LanguageService())
            .modelContainer(SoloCompassModelContainer.shared)

        let host = UIHostingController(rootView: rootView)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        // Sheet presentation is async; give the run loop enough time to both fire
        // onAppear and mount the presented sheet's content.
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
    }
}
