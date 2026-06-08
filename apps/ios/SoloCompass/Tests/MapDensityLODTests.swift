import XCTest
import CoreLocation
@testable import SoloCompass

/// Zoom-adaptive map density (Level-of-Detail). The map shows few prominent
/// pins when zoomed out and progressively more as you zoom in — like Apple /
/// Google Maps. Three pure pieces drive it and are pinned here:
///   1. `spanToLimit(_:)`   — camera span → max pin count (3 bands)
///   2. `prominenceScore(for:)` — which pins survive when space is scarce
///   3. `displayedExperiences`  — the derived, capped set the map renders
@MainActor
final class MapDensityLODTests: XCTestCase {

    // MARK: - Fixtures

    /// Builds an experience whose prominence inputs are fully controllable:
    /// `soloOverall` (0–10), `confidenceLevel` (0–5), `gpsHits` (footprint).
    /// `bestTimes` is left empty so `isBestNow()` stays false and the score is
    /// deterministic (no wall-clock dependency in the ranking assertions).
    private func makeExperience(
        id: String,
        soloOverall: Double,
        confidenceLevel: Int,
        gpsHits: Int = 0,
        lon: Double = 98.99,
        lat: Double = 18.79
    ) -> Experience {
        let now = Date()
        return Experience(
            id: id,
            title: "Fixture \(id)",
            oneLiner: "Fixture \(id)",
            whyItMatters: "LOD fixture",
            category: .food,
            location: ExperienceLocation(coordinates: [lon, lat], cityCode: "cmi"),
            bestTimes: [],
            durationMinutes: .init(min: 30, max: 60),
            howTo: [],
            realInconveniences: [],
            soloScore: SoloScore(
                overall: soloOverall,
                breakdown: .init(
                    seatingFriendly: 7, soloPatronRatio: 7, staffPressure: 7,
                    soloPortioning: 7, ambianceFit: 7, safety: 7
                ),
                basedOnCount: 1
            ),
            sources: [InformationSource(type: .user, attribution: "test", verifiedAt: now)],
            confidence: Confidence(
                level: confidenceLevel,
                lastVerifiedAt: now,
                reason: "Test fixture",
                signals: .init(
                    aiScrapeAgeDays: 1,
                    passiveGpsHits30d: gpsHits,
                    activeReports30d: 0,
                    trustedVerifications: 0
                )
            ),
            nearbyExperienceIds: [],
            stats: .init(completionCount: 0, averageRating: 0),
            status: .active,
            createdAt: now,
            updatedAt: now
        )
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "map.lod.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeViewModel(seed: [Experience]) -> MapViewModel {
        let prefs = UserPreferences(defaults: makeIsolatedDefaults())
        prefs.lastSelectedCity = "cmi"
        return MapViewModel(
            locationService: LocationService(),
            experienceService: ExperienceService(seed: seed),
            aiService: AIService(),
            preferences: prefs
        )
    }

    // MARK: - 1. spanToLimit bands

    func testSpanToLimitCityBandShowsFew() {
        // At or above the city-band threshold → the curated dozen.
        XCTAssertEqual(MapViewModel.spanToLimit(MapViewModel.cityBandSpan), MapViewModel.cityBandLimit)
        XCTAssertEqual(MapViewModel.spanToLimit(0.5), MapViewModel.cityBandLimit)
    }

    func testSpanToLimitDistrictBandShowsMore() {
        // Between district and city thresholds → the ~30 mid band.
        XCTAssertEqual(MapViewModel.spanToLimit(MapViewModel.districtBandSpan), MapViewModel.districtBandLimit)
        XCTAssertEqual(MapViewModel.spanToLimit(0.05), MapViewModel.districtBandLimit)
    }

    func testSpanToLimitStreetBandUncapped() {
        // Below the district threshold (street / walking scale) → everything.
        XCTAssertEqual(MapViewModel.spanToLimit(0.01), Int.max)
        XCTAssertEqual(MapViewModel.spanToLimit(0.0), Int.max)
    }

    func testSpanBandsAreMonotonic() {
        // Zooming in never shows *fewer* pins than zooming out.
        XCTAssertLessThanOrEqual(
            MapViewModel.spanToLimit(0.5),
            MapViewModel.spanToLimit(0.05)
        )
        XCTAssertLessThanOrEqual(
            MapViewModel.spanToLimit(0.05),
            MapViewModel.spanToLimit(0.005)
        )
    }

    // MARK: - 2. prominenceScore ranking

    func testProminenceFavorsHigherSoloScore() {
        let strong = makeExperience(id: "strong", soloOverall: 9, confidenceLevel: 3)
        let weak = makeExperience(id: "weak", soloOverall: 2, confidenceLevel: 3)
        XCTAssertGreaterThan(
            MapViewModel.prominenceScore(for: strong),
            MapViewModel.prominenceScore(for: weak)
        )
    }

    func testProminenceFavorsHigherConfidence() {
        let trusted = makeExperience(id: "trusted", soloOverall: 5, confidenceLevel: 5)
        let shaky = makeExperience(id: "shaky", soloOverall: 5, confidenceLevel: 0)
        XCTAssertGreaterThan(
            MapViewModel.prominenceScore(for: trusted),
            MapViewModel.prominenceScore(for: shaky)
        )
    }

    func testRankedByProminenceOrdersHighFirst() {
        let seed = [
            makeExperience(id: "lo", soloOverall: 1, confidenceLevel: 0),
            makeExperience(id: "hi", soloOverall: 9, confidenceLevel: 5),
            makeExperience(id: "mid", soloOverall: 5, confidenceLevel: 2)
        ]
        let ranked = MapViewModel.rankedByProminence(seed)
        XCTAssertEqual(ranked.map { $0.id }, ["hi", "mid", "lo"])
    }

    func testRankedByProminenceKeepsIncomingOrderOnTie() {
        // Equal prominence → original (distance) order is preserved.
        let a = makeExperience(id: "a", soloOverall: 5, confidenceLevel: 3)
        let b = makeExperience(id: "b", soloOverall: 5, confidenceLevel: 3)
        let c = makeExperience(id: "c", soloOverall: 5, confidenceLevel: 3)
        let ranked = MapViewModel.rankedByProminence([a, b, c])
        XCTAssertEqual(ranked.map { $0.id }, ["a", "b", "c"])
    }

    // MARK: - 3. displayedExperiences capping

    func testDisplayedExperiencesCapsAtCityBand() {
        // 20 experiences, zoomed out to city band → only the top dozen render.
        let seed = (0..<20).map {
            makeExperience(id: "e\($0)", soloOverall: Double($0 % 10), confidenceLevel: 3)
        }
        let vm = makeViewModel(seed: seed)
        vm.loadNearbyExperiences()
        vm.currentSpanLatitudeDelta = MapViewModel.cityBandSpan
        XCTAssertEqual(vm.visibleExperiences.count, 20, "full set stays intact")
        XCTAssertEqual(vm.displayedExperiences.count, MapViewModel.cityBandLimit, "map is capped")
    }

    func testDisplayedExperiencesUncappedWhenZoomedIn() {
        let seed = (0..<20).map {
            makeExperience(id: "e\($0)", soloOverall: Double($0 % 10), confidenceLevel: 3)
        }
        let vm = makeViewModel(seed: seed)
        vm.loadNearbyExperiences()
        vm.currentSpanLatitudeDelta = 0.005 // street level
        XCTAssertEqual(vm.displayedExperiences.count, vm.visibleExperiences.count)
    }

    func testDisplayedExperiencesNoCapWhenBelowLimit() {
        // Fewer pins than the cap → all shown, no work, no reorder surprises.
        let seed = (0..<5).map {
            makeExperience(id: "e\($0)", soloOverall: 5, confidenceLevel: 3)
        }
        let vm = makeViewModel(seed: seed)
        vm.loadNearbyExperiences()
        vm.currentSpanLatitudeDelta = MapViewModel.cityBandSpan
        XCTAssertEqual(vm.displayedExperiences.count, 5)
    }
}
