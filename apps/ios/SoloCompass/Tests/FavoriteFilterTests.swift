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
