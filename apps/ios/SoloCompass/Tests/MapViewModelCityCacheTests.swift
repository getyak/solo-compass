import XCTest
import MapKit
import SwiftData
@testable import SoloCompass

/// US-017: `availableCities` is O(n) over `allExperiences` (+ discovered
/// cities), so it is memoized in `_cachedCities`. The cache must:
///  - compute & store on the first read,
///  - serve the stored value on subsequent reads (no recompute), and
///  - drop when the underlying inputs change (`allExperiences` via the
///    refresh path, or `selectedCity`).
@MainActor
final class MapViewModelCityCacheTests: XCTestCase {

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "mapvm.citycache.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// Minimal valid `Experience` at a given coordinate / city code.
    private func makeExperience(id: String, cityCode: String, lon: Double, lat: Double) -> Experience {
        let now = Date()
        return Experience(
            id: id,
            title: "City Cache Fixture \(id)",
            oneLiner: "Fixture \(id)",
            whyItMatters: "City cache fixture",
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

    private func makeViewModel(seed: [Experience]) -> (MapViewModel, ExperienceService) {
        let prefs = UserPreferences(defaults: makeIsolatedDefaults())
        // Use a private in-memory repo and write the seed THROUGH it, so that
        // a later `appendGenerated` + `reload()` (the refresh path) sees both
        // the seed and the appended rows. The `seed:` arg keeps the initial
        // @Observable mirror aligned without round-tripping the store.
        let repo = ExperienceRepository(
            context: ModelContext(SoloCompassModelContainer.makeInMemory()),
            preferences: nil
        )
        _ = repo.appendGenerated(seed)
        let service = ExperienceService(seed: seed, repository: repo)
        let vm = MapViewModel(
            locationService: LocationService(),
            experienceService: service,
            aiService: AIService(),
            preferences: prefs
        )
        return (vm, service)
    }

    /// Fresh path: the first read computes the list and includes the seed city.
    func testFreshReadComputesAndStores() {
        let (vm, _) = makeViewModel(seed: [
            makeExperience(id: "cmi_1", cityCode: "cmi", lon: 98.99, lat: 18.79),
        ])

        let codes = vm.availableCities.map(\.code)
        XCTAssertTrue(codes.contains("cmi"), "fresh read must derive the seed city")
    }

    /// Second read hits the cache: mutate `allExperiences` after the first read
    /// (without going through a refresh) and confirm the second read returns the
    /// SAME (stale) value, proving it did not re-traverse `allExperiences`.
    func testSecondReadHitsCache() {
        let (vm, service) = makeViewModel(seed: [
            makeExperience(id: "cmi_1", cityCode: "cmi", lon: 98.99, lat: 18.79),
        ])

        // First read computes & caches.
        let first = vm.availableCities.map(\.code).sorted()
        XCTAssertEqual(first, ["cmi"])

        // Snapshot the underlying experience count, then grow it underneath the
        // cache without invalidating (no refresh call).
        let countBefore = service.allExperiences.count
        let added = service.appendGenerated([
            makeExperience(id: "bkk_1", cityCode: "bkk", lon: 100.50, lat: 13.75),
        ])
        XCTAssertEqual(added, 1, "fixture must actually append a new experience")
        XCTAssertGreaterThan(
            service.allExperiences.count, countBefore,
            "allExperiences must have grown for this test to be meaningful"
        )

        // Second read serves the cached value — the new "bkk" city is absent.
        let second = vm.availableCities.map(\.code).sorted()
        XCTAssertEqual(second, first, "second read must return the cached (stale) list")
        XCTAssertFalse(second.contains("bkk"), "cache hit must not reflect the post-cache mutation")
    }

    /// Invalidation: after `allExperiences` changes AND the refresh path runs,
    /// the next read recomputes and reflects the new city.
    func testInvalidationAfterExperiencesChange() {
        let (vm, service) = makeViewModel(seed: [
            makeExperience(id: "cmi_1", cityCode: "cmi", lon: 98.99, lat: 18.79),
        ])

        _ = vm.availableCities  // prime the cache

        _ = service.appendGenerated([
            makeExperience(id: "bkk_1", cityCode: "bkk", lon: 100.50, lat: 13.75),
        ])
        vm.loadNearbyExperiences()  // refresh path invalidates the cache

        let codes = vm.availableCities.map(\.code).sorted()
        XCTAssertEqual(codes, ["bkk", "cmi"], "recompute must include the newly added city")
    }

    /// Changing `selectedCity` invalidates the cache (per acceptance criteria),
    /// so a subsequent read reflects any intervening data changes.
    func testInvalidationAfterSelectedCityChange() {
        let (vm, service) = makeViewModel(seed: [
            makeExperience(id: "cmi_1", cityCode: "cmi", lon: 98.99, lat: 18.79),
        ])

        _ = vm.availableCities  // prime the cache

        _ = service.appendGenerated([
            makeExperience(id: "bkk_1", cityCode: "bkk", lon: 100.50, lat: 13.75),
        ])
        vm.selectedCity = "cmi"  // change invalidates the cache via didSet

        let codes = vm.availableCities.map(\.code).sorted()
        XCTAssertTrue(codes.contains("bkk"), "selectedCity change must drop the stale cache")
    }
}
