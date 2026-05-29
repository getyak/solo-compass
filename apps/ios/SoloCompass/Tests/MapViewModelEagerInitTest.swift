import XCTest
import SwiftUI
@testable import SoloCompass

/// US-021: `CompassMapContentView` must build its `MapViewModel` *eagerly* in
/// `init`, so the app-launch path can read view-model state the instant the
/// view exists — before any `onAppear` fires. The old `@State viewModel:
/// MapViewModel?` was created lazily inside `onAppear`, so writes between launch
/// and the first appear silently dropped against `nil`. This test proves the
/// view model is live and readable at construction time, with no window install
/// and no run-loop pumping (i.e. `onAppear` has not run).
@MainActor
final class MapViewModelEagerInitTest: XCTestCase {

    /// Mirrors the launch path: the public `CompassMapView` reads the
    /// environment and constructs `CompassMapContentView(...)` with the same
    /// dependencies. We build the content view directly so we can read its
    /// eager view model without installing it in a SwiftUI graph.
    private func makeContentView() -> CompassMapContentView {
        CompassMapContentView(
            locationService: LocationService(),
            experienceService: ExperienceService(),
            aiService: AIService(),
            preferences: UserPreferences(),
            notificationService: NotificationService.shared,
            subscriptionService: SubscriptionService(),
            themeService: ThemeService.shared,
            companionService: CompanionService(),
            presenceService: PresenceService()
        )
    }

    /// The view model exists and `allExperiences` is readable immediately —
    /// no `onAppear`, no layout pass, no run-loop pump.
    func testViewModelIsReadableBeforeOnAppear() {
        let view = makeContentView()

        // Reading `allExperiences` would trap if `viewModel` were nil/lazy.
        // Seed data is loaded synchronously by ExperienceService, so the
        // launch path sees a populated set up-front.
        let experiences = view.debugViewModel.allExperiences
        XCTAssertFalse(
            experiences.isEmpty,
            "Eager view model must expose seed experiences at construction time, "
                + "before any onAppear runs"
        )
    }

    /// A write performed in the launch→onAppear window lands on the live
    /// instance instead of dropping against `nil` (the bug US-021 fixes).
    func testWritesBetweenLaunchAndOnAppearArePersisted() {
        let view = makeContentView()
        let vm = view.debugViewModel

        // Simulate an early write (e.g. a filter selection) before onAppear.
        vm.selectCategory(.coffee)

        XCTAssertEqual(
            vm.selectedCategory,
            .coffee,
            "A write before onAppear must persist on the eagerly-created view model"
        )
    }
}
