import XCTest
import CoreLocation
@testable import SoloCompass

// MARK: - US-035: FilterBar "Now" mode ↔ Map bestNow highlight sync

/// Verifies that toggling the FilterBar's "Now" mode changes the visual style
/// of `bestNow` markers on the map, so the two UIs read as one connected
/// gesture (US-035).
///
/// `MarkerIconView` exposes the highlight through two testable hooks:
///   - `showsNowSyncRing` — the pure predicate that drives the extra CT.accent
///     ring (true only for a high-confidence best-now pin while Now is active);
///   - `accessibilityIdentifier` — gains a `.nowsync` suffix when the ring is
///     shown, giving us a stable, render-free way to assert the style differs.
///
/// We assert both the marker view in isolation and the end-to-end path:
/// `MapViewModel.selectNowFilter()` flips `isNowFilter`, which the map passes to
/// `MarkerIconView(nowFilterActive:)`.
///
/// Run with:
///   xcodebuild test -only-testing:SoloCompassTests/FilterNowMapSyncTest
final class FilterNowMapSyncTest: XCTestCase {

    // MARK: - Marker view: style changes with the Now flag

    /// A best-now marker must look different when the Now filter is active vs.
    /// not — the whole point of the sync. We assert via both the predicate and
    /// the identifier suffix.
    func testBestNowMarkerStyleChangesWhenNowFilterToggles() {
        let off = MarkerIconView(category: .coffee, state: .bestNow, confidenceLevel: 4, nowFilterActive: false)
        let on  = MarkerIconView(category: .coffee, state: .bestNow, confidenceLevel: 4, nowFilterActive: true)

        XCTAssertFalse(off.showsNowSyncRing, "Now filter off → no sync ring")
        XCTAssertTrue(on.showsNowSyncRing, "Now filter on → best-now pin gains the sync ring")

        XCTAssertNotEqual(
            off.accessibilityIdentifier,
            on.accessibilityIdentifier,
            "Marker identifier must differ between Now-off and Now-on so the style change is observable"
        )
        XCTAssertFalse(
            off.accessibilityIdentifier.hasSuffix(".nowsync"),
            "Now-off marker must not carry '.nowsync', got: \(off.accessibilityIdentifier)"
        )
        XCTAssertTrue(
            on.accessibilityIdentifier.hasSuffix(".nowsync"),
            "Now-on best-now marker should end with '.nowsync', got: \(on.accessibilityIdentifier)"
        )
    }

    /// The highlight is scoped to best-now pins. A non-best-now marker should
    /// look identical regardless of the Now flag.
    func testNonBestNowMarkerUnaffectedByNowFilter() {
        let off = MarkerIconView(category: .food, state: .default, confidenceLevel: 4, nowFilterActive: false)
        let on  = MarkerIconView(category: .food, state: .default, confidenceLevel: 4, nowFilterActive: true)

        XCTAssertFalse(off.showsNowSyncRing)
        XCTAssertFalse(on.showsNowSyncRing, "Default-state markers never gain the Now sync ring")
        XCTAssertEqual(
            off.accessibilityIdentifier,
            on.accessibilityIdentifier,
            "Non-best-now markers must be unchanged by the Now filter"
        )
    }

    /// Low-confidence (AI-guessed) best-now pins don't earn the highlight, just
    /// like the existing gold pulse-ring suppression.
    func testLowConfidenceBestNowMarkerHasNoNowSyncRing() {
        let on = MarkerIconView(category: .coffee, state: .bestNow, confidenceLevel: 1, nowFilterActive: true)
        XCTAssertFalse(
            on.showsNowSyncRing,
            "Low-confidence best-now pins must not show the Now sync ring"
        )
        XCTAssertFalse(on.accessibilityIdentifier.hasSuffix(".nowsync"))
    }

    /// `nowFilterActive` must default to false for source compatibility with
    /// every existing call site.
    func testNowFilterActiveDefaultsToFalse() {
        let marker = MarkerIconView(category: .coffee, state: .bestNow, confidenceLevel: 4)
        XCTAssertFalse(marker.showsNowSyncRing, "nowFilterActive must default to false")
    }

    // MARK: - End-to-end: ViewModel flag drives the marker style

    /// Toggling the Now filter on the view model must flip the styling input
    /// that the map feeds into `MarkerIconView`. This is the wiring the map
    /// performs in `mapLayer`: `nowFilterActive: viewModel.isNowFilter`.
    @MainActor
    func testSelectNowFilterFlipsMarkerStyleEndToEnd() {
        let bestNow = makeBestNowExperience()
        let vm = makeViewModel(with: [bestNow])

        // Baseline: Now filter off → marker carries no sync ring.
        XCTAssertFalse(vm.isNowFilter)
        let before = MarkerIconView(
            category: bestNow.category,
            state: vm.markerState(for: bestNow),
            confidenceLevel: bestNow.confidence.level,
            nowFilterActive: vm.isNowFilter
        )
        XCTAssertEqual(vm.markerState(for: bestNow), .bestNow, "fixture must read as best-now")
        XCTAssertFalse(before.showsNowSyncRing)

        // Toggle Now on → the same marker now lights up.
        vm.selectNowFilter()
        XCTAssertTrue(vm.isNowFilter)
        let after = MarkerIconView(
            category: bestNow.category,
            state: vm.markerState(for: bestNow),
            confidenceLevel: bestNow.confidence.level,
            nowFilterActive: vm.isNowFilter
        )
        XCTAssertTrue(after.showsNowSyncRing, "selectNowFilter() must light up best-now markers")
        XCTAssertNotEqual(
            before.accessibilityIdentifier,
            after.accessibilityIdentifier,
            "Toggling Now must visibly change the best-now marker style"
        )

        // Clearing the filter turns it back off — the sync is bidirectional.
        vm.clearFilters()
        XCTAssertFalse(vm.isNowFilter)
        let cleared = MarkerIconView(
            category: bestNow.category,
            state: vm.markerState(for: bestNow),
            confidenceLevel: bestNow.confidence.level,
            nowFilterActive: vm.isNowFilter
        )
        XCTAssertFalse(cleared.showsNowSyncRing, "Clearing the filter must remove the sync ring")
    }

    // MARK: - Fixtures

    @MainActor
    private func makeViewModel(with experiences: [Experience]) -> MapViewModel {
        MapViewModel(
            locationService: LocationService(),
            experienceService: ExperienceService(seed: experiences),
            aiService: AIService(),
            preferences: UserPreferences()
        )
    }

    /// A high-confidence experience whose `bestTimes` window covers the current
    /// hour, so `isBestNow()` returns true and `markerState` is `.bestNow`.
    /// Mirrors the minimal fixture shape used by `NowCountCacheTests`.
    private func makeBestNowExperience() -> Experience {
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        return Experience(
            id: "now_sync_fixture",
            title: "Always-Open Café",
            oneLiner: "Now-sync fixture",
            whyItMatters: "Best-now highlight fixture",
            category: .coffee,
            location: ExperienceLocation(coordinates: [98.99, 18.79], cityCode: "cmi"),
            bestTimes: [TimeWindow(startHour: hour, endHour: (hour + 1) % 24)],
            durationMinutes: .init(min: 30, max: 60),
            howTo: [],
            realInconveniences: [],
            soloScore: SoloScore(
                overall: 5,
                breakdown: .init(
                    seatingFriendly: 7, soloPatronRatio: 7, staffPressure: 7,
                    soloPortioning: 7, ambianceFit: 7, safety: 7
                ),
                basedOnCount: 1
            ),
            sources: [InformationSource(type: .user, attribution: "test", verifiedAt: now)],
            confidence: Confidence(
                level: 4,
                lastVerifiedAt: now,
                reason: "Test fixture",
                signals: .init(aiScrapeAgeDays: 1, passiveGpsHits30d: 0, activeReports30d: 0, trustedVerifications: 0)
            ),
            nearbyExperienceIds: [],
            stats: .init(completionCount: 0, averageRating: 0),
            status: .active,
            createdAt: now,
            updatedAt: now
        )
    }
}
