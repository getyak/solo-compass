import XCTest
import CoreLocation
import MapKit
import SwiftData
@testable import SoloCompass

/// US-018: `nowCount` (count of visible experiences at their best time right
/// now) is O(n) over `visibleExperiences`, so it is cached in `_nowCount` and
/// exposed read-only through `nowCount`. The cache must:
///  - start at 0 before any load,
///  - recompute at the documented checkpoints
///    (`loadNearbyExperiences`, `refreshForLocation`, `updateBottomInfo`), and
///  - NOT recompute on an out-of-band `visibleExperiences` mutation (proving
///    `BottomInfoSheet` / `FilterBarView` renders don't trigger an O(n) scan).
@MainActor
final class NowCountCacheTests: XCTestCase {

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "mapvm.nowcount.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// A `TimeWindow` that contains the current hour, so `isBestNow()` is true
    /// regardless of when the test runs. Handles the hour-23 wrap.
    private func windowCoveringNow() -> TimeWindow {
        let hour = Calendar.current.component(.hour, from: Date())
        return TimeWindow(startHour: hour, endHour: (hour + 1) % 24)
    }

    /// Minimal valid `Experience`. When `bestNow` is true it carries a window
    /// covering the current hour; otherwise it has no best times.
    private func makeExperience(id: String, cityCode: String, lon: Double, lat: Double, bestNow: Bool) -> Experience {
        let now = Date()
        return Experience(
            id: id,
            title: "Now Count Fixture \(id)",
            oneLiner: "Fixture \(id)",
            whyItMatters: "Now count fixture",
            category: .food,
            location: ExperienceLocation(coordinates: [lon, lat], cityCode: cityCode),
            bestTimes: bestNow ? [windowCoveringNow()] : [],
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

    /// With no visible best-now experiences the cache is 0. The view model's
    /// `init` runs the documented `loadNearbyExperiences` checkpoint (V-004: a
    /// cold start must anchor on the selected city, not the simulator's default
    /// GPS), so we can't observe a "before any load" state. Instead we anchor on
    /// a city with no seeded experiences nearby (San Francisco, while the only
    /// fixture sits in Chiang Mai), so the load filters everything out and the
    /// now-best subset — hence the cached count — is genuinely 0.
    func testCountIsZeroWhenNoVisibleBestNow() {
        let (vm, _) = makeViewModel(seed: [
            makeExperience(id: "cmi_1", cityCode: "cmi", lon: 98.99, lat: 18.79, bestNow: true),
        ])
        vm.selectedCity = "san-francisco"
        vm.loadNearbyExperiences()

        XCTAssertTrue(
            vm.visibleExperiences.isEmpty,
            "the lone Chiang Mai fixture must be filtered out when anchored on San Francisco"
        )
        XCTAssertEqual(vm.nowCount, 0, "nowCount must be 0 when no visible experience is best now")
    }

    /// `loadNearbyExperiences` is a documented checkpoint: it recomputes the
    /// cache to reflect the now-best subset of the visible experiences.
    func testLoadNearbyRecomputes() {
        let (vm, _) = makeViewModel(seed: [
            makeExperience(id: "cmi_1", cityCode: "cmi", lon: 98.99, lat: 18.79, bestNow: true),
            makeExperience(id: "cmi_2", cityCode: "cmi", lon: 98.99, lat: 18.79, bestNow: true),
            makeExperience(id: "cmi_3", cityCode: "cmi", lon: 98.99, lat: 18.79, bestNow: false),
        ])
        vm.selectedCity = "cmi"
        vm.customCoordinates = CLLocationCoordinate2D(latitude: 18.79, longitude: 98.99)
        vm.loadNearbyExperiences()

        XCTAssertEqual(
            vm.nowCount,
            vm.visibleExperiences.filter { $0.isBestNow() }.count,
            "load must recompute nowCount to the now-best subset"
        )
        XCTAssertEqual(vm.nowCount, 2, "two of three fixtures are best now")
    }

    /// An out-of-band mutation of `visibleExperiences` (the shape a SwiftUI
    /// render does NOT cause, but which proves no recompute happens off the
    /// checkpoints) leaves the cached value stale until a checkpoint runs.
    func testMutationWithoutCheckpointDoesNotRecompute() {
        let (vm, _) = makeViewModel(seed: [
            makeExperience(id: "cmi_1", cityCode: "cmi", lon: 98.99, lat: 18.79, bestNow: true),
        ])
        vm.selectedCity = "cmi"
        vm.customCoordinates = CLLocationCoordinate2D(latitude: 18.79, longitude: 98.99)
        vm.loadNearbyExperiences()
        XCTAssertEqual(vm.nowCount, 1, "baseline after load")

        // Append a best-now experience straight onto the visible list, bypassing
        // every checkpoint. The cached count must NOT change.
        vm.visibleExperiences.append(
            makeExperience(id: "extra", cityCode: "cmi", lon: 98.99, lat: 18.79, bestNow: true)
        )
        XCTAssertEqual(vm.nowCount, 1, "nowCount must stay stale until a checkpoint recomputes it")

        // `updateBottomInfo` is a documented checkpoint — it recomputes now.
        vm.updateBottomInfo()
        XCTAssertEqual(vm.nowCount, 2, "updateBottomInfo checkpoint must pick up the appended now-best experience")
    }

    /// `refreshForLocation` is a documented checkpoint and recomputes the cache.
    func testRefreshForLocationRecomputes() {
        let coord = CLLocationCoordinate2D(latitude: 18.79, longitude: 98.99)
        let (vm, _) = makeViewModel(seed: [
            makeExperience(id: "cmi_1", cityCode: "cmi", lon: 98.99, lat: 18.79, bestNow: true),
            makeExperience(id: "cmi_2", cityCode: "cmi", lon: 98.99, lat: 18.79, bestNow: false),
        ])
        vm.selectedCity = "cmi"
        vm.refreshForLocation(coord)

        XCTAssertEqual(
            vm.nowCount,
            vm.visibleExperiences.filter { $0.isBestNow() }.count,
            "refreshForLocation must recompute nowCount"
        )
        XCTAssertEqual(vm.nowCount, 1, "one of two fixtures is best now")
    }
}
