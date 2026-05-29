import XCTest
import CoreLocation
import MapKit
import SwiftData
@testable import SoloCompass

/// V-004 (US-033): cold start must show experiences for the selected city.
///
/// Root cause of the original empty state: on a fresh launch with a persisted
/// `lastSelectedCity` slug (e.g. `chiang-mai`), `loadNearbyExperiences` used
/// live GPS as the query origin (the simulator defaults to San Francisco,
/// ~12,000 km away) AND filtered by an exact `cityCode == selectedCity` match
/// — but the seed rows use the compact code `cmi`, not the `chiang-mai` slug.
/// Both effects independently emptied the map.
///
/// The fix makes `selectedCity` drive the nearby query origin from the city
/// center (for preset cities) and makes the cityCode filter alias-aware. These
/// tests pin both behaviours so the regression can't return.
@MainActor
final class ColdStartExperienceLoadTests: XCTestCase {

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "coldstart.load.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// A `LocationService` reporting a fixed coordinate, to emulate the
    /// simulator's San-Francisco GPS during a Chiang-Mai cold start.
    private let sanFrancisco = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)

    private func makeExperience(id: String, cityCode: String, lon: Double, lat: Double) -> Experience {
        let now = Date()
        return Experience(
            id: id,
            title: "Cold Start Fixture \(id)",
            oneLiner: "Fixture \(id)",
            whyItMatters: "Cold start fixture",
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

    /// Build a cold-start view model with the given seed and a persisted city
    /// selection — exactly the production launch path (`init` calls
    /// `loadNearbyExperiences`).
    private func makeColdStartViewModel(
        startingCity: String?,
        seed: [Experience]
    ) -> MapViewModel {
        let prefs = UserPreferences(defaults: makeIsolatedDefaults())
        prefs.lastSelectedCity = startingCity
        let service = ExperienceService(seed: seed)
        return MapViewModel(
            locationService: LocationService(),
            experienceService: service,
            aiService: AIService(),
            preferences: prefs
        )
    }

    // MARK: - Core acceptance: cold start with a slug yields a non-empty map

    /// The exact failure case: cold launch with `selectedCity = "chiang-mai"`
    /// (slug) against a seed that uses the `cmi` code must still surface pins.
    func testColdStartChiangMaiSlugShowsExperiences() {
        let vm = makeColdStartViewModel(
            startingCity: "chiang-mai",
            seed: [
                makeExperience(id: "cmi_1", cityCode: "cmi", lon: 98.9938, lat: 18.7877),
                makeExperience(id: "cmi_2", cityCode: "cmi", lon: 98.9692, lat: 18.7892),
            ]
        )
        XCTAssertEqual(vm.selectedCity, "chiang-mai")
        XCTAssertGreaterThan(
            vm.visibleExperiences.count, 0,
            "Cold start with the chiang-mai slug must show the cmi-coded seed experiences"
        )
    }

    /// The compact seed code itself must also work on cold start.
    func testColdStartCmiCodeShowsExperiences() {
        let vm = makeColdStartViewModel(
            startingCity: "cmi",
            seed: [makeExperience(id: "cmi_1", cityCode: "cmi", lon: 98.9938, lat: 18.7877)]
        )
        XCTAssertGreaterThan(vm.visibleExperiences.count, 0)
    }

    /// Production `ExperienceService()` (bundle seed → hardcoded fallback)
    /// always carries the Chiang Mai entries, so a real cold start is non-empty.
    func testProductionSeedColdStartChiangMaiNonEmpty() {
        let prefs = UserPreferences(defaults: makeIsolatedDefaults())
        prefs.lastSelectedCity = "chiang-mai"
        let vm = MapViewModel(
            locationService: LocationService(),
            experienceService: ExperienceService(),
            aiService: AIService(),
            preferences: prefs
        )
        XCTAssertGreaterThan(
            vm.visibleExperiences.count, 0,
            "Production seed cold start for Chiang Mai must not be empty"
        )
    }

    // MARK: - GPS far from the selected city must not empty the map

    /// Even when live GPS sits in San Francisco, selecting a preset city anchors
    /// the nearby query on the city center, so the city's seed still loads.
    func testSelectedCityOverridesFarAwayGPSOrigin() {
        let prefs = UserPreferences(defaults: makeIsolatedDefaults())
        prefs.lastSelectedCity = "chiang-mai"
        let service = ExperienceService(seed: [
            makeExperience(id: "cmi_1", cityCode: "cmi", lon: 98.9938, lat: 18.7877),
        ])
        let location = LocationService()
        location.simulate(location: CLLocation(
            latitude: sanFrancisco.latitude, longitude: sanFrancisco.longitude
        ))
        let vm = MapViewModel(
            locationService: location,
            experienceService: service,
            aiService: AIService(),
            preferences: prefs
        )
        vm.loadNearbyExperiences()
        XCTAssertGreaterThan(
            vm.visibleExperiences.count, 0,
            "A far-away GPS fix must not suppress the selected city's experiences"
        )
    }

    // MARK: - Each seed city resolves on cold start (5km and 25km)

    /// Drives every seed city (compact code + its slug alias) through a cold
    /// start at both the 5 km and 25 km radii. Each must be non-empty — the
    /// acceptance "each of N seed cities shows a non-zero nearby count".
    func testEachSeedCityNonEmptyAt5kmAnd25km() {
        // (selection, seedCode, center) for the cities the seed ships with,
        // exercised via both the compact code and the human-readable slug.
        let cities: [(selection: String, seedCode: String, lon: Double, lat: Double)] = [
            ("chiang-mai", "cmi", 98.9938, 18.7877),
            ("cmi", "cmi", 98.9938, 18.7877),
            ("vientiane", "VTE", 102.6000, 17.9667),
            ("VTE", "VTE", 102.6000, 17.9667),
        ]
        let seed = [
            makeExperience(id: "cmi_a", cityCode: "cmi", lon: 98.9938, lat: 18.7877),
            makeExperience(id: "cmi_b", cityCode: "cmi", lon: 98.9692, lat: 18.7892),
            makeExperience(id: "vte_a", cityCode: "VTE", lon: 102.6000, lat: 17.9667),
            makeExperience(id: "vte_b", cityCode: "VTE", lon: 102.6100, lat: 17.9700),
        ]
        for radiusKm in [5.0, 25.0] {
            for city in cities {
                let prefs = UserPreferences(defaults: makeIsolatedDefaults())
                prefs.lastSelectedCity = city.selection
                prefs.maxDistanceKm = radiusKm
                let vm = MapViewModel(
                    locationService: LocationService(),
                    experienceService: ExperienceService(seed: seed),
                    aiService: AIService(),
                    preferences: prefs
                )
                XCTAssertGreaterThan(
                    vm.visibleExperiences.count, 0,
                    "City \(city.selection) at \(radiusKm)km must show ≥1 experience"
                )
            }
        }
    }

    // MARK: - Alias matcher unit coverage

    func testCityCodeMatcherResolvesAliasesBothDirections() {
        XCTAssertTrue(MapViewModel.cityCodeMatches("cmi", selected: "chiang-mai"))
        XCTAssertTrue(MapViewModel.cityCodeMatches("chiang-mai", selected: "cmi"))
        XCTAssertTrue(MapViewModel.cityCodeMatches("cmi", selected: "cmi"))
        // Case-insensitive: upper-cased seed code vs lower-cased slug.
        XCTAssertTrue(MapViewModel.cityCodeMatches("VTE", selected: "vientiane"))
        XCTAssertTrue(MapViewModel.cityCodeMatches("vte", selected: "VTE"))
        XCTAssertFalse(MapViewModel.cityCodeMatches("cmi", selected: "san-francisco"))
    }
}
