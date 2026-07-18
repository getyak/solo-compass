import XCTest
import CoreLocation
import SwiftData
@testable import SoloCompass

/// "Saved" map filter (the heart pill next to All): `MapViewModel.isFavoriteFilter`
/// keeps only favourited experiences, and is mutually exclusive with the
/// category / custom-tag / Now filters. The favourite *data* already existed
/// end-to-end; these tests pin the new map-filter entry point.
@MainActor
final class FavoriteFilterTests: XCTestCase {

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "favorite.filter.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeExperience(id: String, cityCode: String, lon: Double, lat: Double) -> Experience {
        let now = Date()
        return Experience(
            id: id,
            title: "Fixture \(id)",
            oneLiner: "Fixture \(id)",
            whyItMatters: "Favorite filter fixture",
            category: .food,
            location: ExperienceLocation(coordinates: [lon, lat], cityCode: cityCode),
            bestTimes: [],
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
                level: 3,
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

    /// Build a view model whose seed has three Chiang-Mai experiences, with one
    /// of them favourited. Starts on the `cmi` city so all three are nearby.
    private func makeViewModel(favoriting favoriteId: String?) -> MapViewModel {
        let prefs = UserPreferences(defaults: makeIsolatedDefaults())
        prefs.lastSelectedCity = "cmi"
        if let favoriteId {
            prefs.toggleFavorite(favoriteId)
        }
        let seed = [
            makeExperience(id: "cmi_1", cityCode: "cmi", lon: 98.9938, lat: 18.7877),
            makeExperience(id: "cmi_2", cityCode: "cmi", lon: 98.9940, lat: 18.7880),
            makeExperience(id: "cmi_3", cityCode: "cmi", lon: 98.9942, lat: 18.7882)
        ]
        let service = ExperienceService(seed: seed)
        return MapViewModel(
            locationService: LocationService(),
            experienceService: service,
            aiService: AIService(),
            preferences: prefs
        )
    }

    // MARK: - Filtering

    func testFavoriteFilterKeepsOnlyFavorited() {
        let vm = makeViewModel(favoriting: "cmi_2")
        XCTAssertFalse(vm.isFavoriteFilter, "starts inactive")
        XCTAssertGreaterThan(vm.visibleExperiences.count, 1, "all nearby visible before filtering")

        vm.selectFavoriteFilter()

        XCTAssertTrue(vm.isFavoriteFilter, "filter is active after selecting")
        XCTAssertEqual(vm.visibleExperiences.map(\.id), ["cmi_2"],
                       "only the favourited experience remains visible")
    }

    func testFavoriteFilterTogglesOff() {
        let vm = makeViewModel(favoriting: "cmi_2")
        let baseline = vm.visibleExperiences.count

        vm.selectFavoriteFilter()
        XCTAssertTrue(vm.isFavoriteFilter)

        // Tapping the active pill again clears it back to All.
        vm.selectFavoriteFilter()
        XCTAssertFalse(vm.isFavoriteFilter, "re-tap toggles the filter off")
        XCTAssertEqual(vm.visibleExperiences.count, baseline,
                       "clearing the filter restores the full nearby list")
    }

    // MARK: - Mutual exclusivity

    func testSelectingFavoriteClearsOtherFilters() {
        let vm = makeViewModel(favoriting: "cmi_2")
        vm.selectNowFilter()
        vm.selectCategory(.food)              // now category is active
        XCTAssertNotNil(vm.selectedCategory)

        vm.selectFavoriteFilter()

        XCTAssertTrue(vm.isFavoriteFilter)
        XCTAssertNil(vm.selectedCategory, "category cleared when Saved activates")
        XCTAssertNil(vm.selectedCustomTag, "custom tag cleared when Saved activates")
        XCTAssertFalse(vm.isNowFilter, "Now cleared when Saved activates")
    }

    func testSelectingOtherFilterClearsFavorite() {
        let vm = makeViewModel(favoriting: "cmi_2")
        vm.selectFavoriteFilter()
        XCTAssertTrue(vm.isFavoriteFilter)

        vm.selectNowFilter()
        XCTAssertFalse(vm.isFavoriteFilter, "Now clears the Saved filter")

        vm.selectFavoriteFilter()
        XCTAssertTrue(vm.isFavoriteFilter)
        vm.selectCategory(.food)
        XCTAssertFalse(vm.isFavoriteFilter, "category clears the Saved filter")

        vm.selectFavoriteFilter()
        XCTAssertTrue(vm.isFavoriteFilter)
        vm.clearFilters()
        XCTAssertFalse(vm.isFavoriteFilter, "clearFilters clears the Saved filter")
    }
}

/// Regression guards for the create-route candidate pool (UX audit 2026-07-16:
/// "選擇地點 list empty + AI button dead").
///
/// Root cause: the create-route sheet was fed `viewModel.visibleExperiences`,
/// but its entry cards live in the Now section — so the pool arrived
/// pre-filtered by `isBestNow()` and was routinely empty. Both flows died at
/// once: a blank manual picker and a permanently `.disabled` ✨ button (which,
/// with explicit colors and `.plain` style, didn't even LOOK disabled).
/// `routeCandidates()` must ignore the transient map filters.
@MainActor
final class RouteCandidatesPoolTests: XCTestCase {

    private func makeExperience(id: String, cityCode: String, lon: Double, lat: Double) -> Experience {
        let now = Date()
        return Experience(
            id: id,
            title: "Fixture \(id)",
            oneLiner: "Fixture \(id)",
            whyItMatters: "Route candidates fixture",
            category: .food,
            location: ExperienceLocation(coordinates: [lon, lat], cityCode: cityCode),
            // No bestTimes → `isBestNow()` is false → the Now filter drops
            // every fixture, reproducing the audit's empty-pool scenario.
            bestTimes: [],
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
                level: 3,
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

    private func makeViewModel() -> MapViewModel {
        let suite = "route.candidates.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let prefs = UserPreferences(defaults: defaults)
        prefs.lastSelectedCity = "cmi"
        let seed = [
            makeExperience(id: "cmi_1", cityCode: "cmi", lon: 98.9938, lat: 18.7877),
            makeExperience(id: "cmi_2", cityCode: "cmi", lon: 98.9940, lat: 18.7880),
            makeExperience(id: "cmi_3", cityCode: "cmi", lon: 98.9942, lat: 18.7882)
        ]
        return MapViewModel(
            locationService: LocationService(),
            experienceService: ExperienceService(seed: seed),
            aiService: AIService(),
            preferences: prefs
        )
    }

    /// The audit scenario: Now filter active, zero visible experiences — the
    /// route builder must still see the full nearby pool.
    func testRouteCandidatesIgnoreNowFilter() {
        let vm = makeViewModel()
        vm.selectNowFilter()
        XCTAssertTrue(vm.visibleExperiences.isEmpty,
                      "precondition: fixtures have no bestTimes, so Now filters everything out")
        XCTAssertEqual(vm.routeCandidates().count, 3,
                       "routeCandidates must ignore the transient Now filter — an empty pool kills both the manual picker and the AI button")
    }

    func testRouteCandidatesIgnoreCategoryFilter() {
        let vm = makeViewModel()
        vm.selectCategory(.culture) // fixtures are .food → visible = 0
        XCTAssertEqual(vm.routeCandidates().count, 3,
                       "routeCandidates must ignore the transient category filter")
    }

    /// Structural pin on the CompassMapView wiring: the create sheet must be
    /// fed `routeCandidates()`, and the Now placeholder (whose copy promises
    /// "Solo picks 3 stops") must open with `autoGenerate: true`.
    func testCreateRouteSheetWiring() throws {
        let here = URL(fileURLWithPath: #filePath)
        let url = here
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // SoloCompass/
            .appendingPathComponent("Views/Map/CompassMapView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(source.contains("candidates: viewModel.visibleExperiences"),
                       "CreateRouteView must not be fed the Now-filtered visibleExperiences (empty-pool dead end)")
        XCTAssertTrue(source.contains("candidates: viewModel.routeCandidates()"),
                      "CreateRouteView must draw from the unfiltered routeCandidates() pool")
        XCTAssertTrue(source.contains(".create(autoGenerate: true)"),
                      "the Now placeholder promises Solo picks the stops — it must open with autoGenerate: true")
    }
}
