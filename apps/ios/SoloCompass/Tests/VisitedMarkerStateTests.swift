import XCTest
@testable import SoloCompass

/// Tests for the gold-halo `.footprinted` state surfaced by the new
/// passive `VisitRecord` channel (P1.1 #112).
///
/// The map view already renders `.footprinted` with a gold halo, so the only
/// thing we need to verify is that `MapViewModel.markerState` flips to
/// `.footprinted` when a passive visit is on file — and that higher-priority
/// states (completed / favorited / bestNow / upcoming) still win.
@MainActor
final class VisitedMarkerStateTests: XCTestCase {

    // MARK: - Helpers

    private func makeViewModel(prefsSuite: String) -> (MapViewModel, UserPreferences) {
        let defaults = UserDefaults(suiteName: prefsSuite)!
        defaults.removePersistentDomain(forName: prefsSuite)
        let prefs = UserPreferences(defaults: defaults)
        let vm = MapViewModel(
            locationService: LocationService(),
            experienceService: ExperienceService(seed: ExperienceService.hardcodedSeed),
            aiService: AIService(),
            preferences: prefs
        )
        return (vm, prefs)
    }

    /// Build a clean Experience: passiveGpsHits30d=0 and bestTimes=[] so the
    /// *only* signal that can flip `markerState` is the `visitedExperienceIds`
    /// set we attach in tests. Skeleton on its own ships with a 9-21 bestTime
    /// window, which would mask our assertions via .bestNow / .upcoming.
    private func seedExperience() throws -> Experience {
        let poi = OverpassService.POI(
            osmId: 9_999_001,
            name: "Visited Test Place",
            nameEn: nil,
            lat: 0,
            lon: 0,
            tags: ["amenity": "cafe"]
        )
        let raw = AIService.skeletonExperience(from: poi, cityCode: "osm_0.0_0.0")
        return Experience(
            id: raw.id,
            title: raw.title,
            oneLiner: raw.oneLiner,
            whyItMatters: raw.whyItMatters,
            category: raw.category,
            location: raw.location,
            bestTimes: [], // ← key strip: no bestTime → no .bestNow / .upcoming
            durationMinutes: raw.durationMinutes,
            howTo: raw.howTo,
            realInconveniences: raw.realInconveniences,
            soloScore: raw.soloScore,
            sources: raw.sources,
            confidence: raw.confidence,
            nearbyExperienceIds: raw.nearbyExperienceIds,
            stats: raw.stats,
            status: raw.status,
            createdAt: raw.createdAt,
            updatedAt: raw.updatedAt,
            userTags: raw.userTags,
            categoryHighlights: raw.categoryHighlights
        )
    }

    // MARK: - Default → footprinted via VisitRecord

    func testAttachingVisitedIdsFlipsMarkerToFootprinted() throws {
        let (vm, _) = makeViewModel(prefsSuite: "visited.flip.\(UUID().uuidString)")
        let exp = try seedExperience()

        // Pin a "now" outside any best-time window so we don't accidentally
        // collide with .bestNow or .upcoming — use an instant exactly between
        // two large windows. The default marker state for an arbitrary
        // mid-afternoon date with no best-time hit is .default.
        let neutralNow = Date(timeIntervalSince1970: 0)

        XCTAssertEqual(vm.markerState(for: exp, now: neutralNow), .default,
                       "baseline must be .default before any visit is attached")

        vm.attachVisitedExperienceIds([exp.id])
        XCTAssertEqual(vm.markerState(for: exp, now: neutralNow), .footprinted,
                       "after attaching a visit id, the marker must read .footprinted")
    }

    func testAttachingEmptySetClearsTheHalo() throws {
        let (vm, _) = makeViewModel(prefsSuite: "visited.clear.\(UUID().uuidString)")
        let exp = try seedExperience()
        let neutralNow = Date(timeIntervalSince1970: 0)

        vm.attachVisitedExperienceIds([exp.id])
        XCTAssertEqual(vm.markerState(for: exp, now: neutralNow), .footprinted)

        vm.attachVisitedExperienceIds([])
        XCTAssertEqual(vm.markerState(for: exp, now: neutralNow), .default,
                       "clearing the attached set must drop the halo back to default")
    }

    // MARK: - Higher-priority states still win

    func testCompletedBeatsVisitedFootprint() throws {
        let (vm, prefs) = makeViewModel(prefsSuite: "visited.completed.\(UUID().uuidString)")
        let exp = try seedExperience()
        let neutralNow = Date(timeIntervalSince1970: 0)

        prefs.markCompleted(exp.id)
        vm.attachVisitedExperienceIds([exp.id])

        XCTAssertEqual(vm.markerState(for: exp, now: neutralNow), .completed,
                       ".completed must dominate even if the experience is also marked visited")
    }

    func testFavoritedBeatsVisitedFootprint() throws {
        let (vm, prefs) = makeViewModel(prefsSuite: "visited.favorited.\(UUID().uuidString)")
        let exp = try seedExperience()
        let neutralNow = Date(timeIntervalSince1970: 0)

        prefs.toggleFavorite(exp.id)
        vm.attachVisitedExperienceIds([exp.id])

        XCTAssertEqual(vm.markerState(for: exp, now: neutralNow), .favorited,
                       ".favorited must dominate even if the experience is also marked visited")
    }

    // MARK: - Visited id for an unknown experience is a no-op

    func testUnknownVisitedIdDoesNotAffectOtherExperiences() throws {
        let (vm, _) = makeViewModel(prefsSuite: "visited.unknown.\(UUID().uuidString)")
        let exp = try seedExperience()
        let neutralNow = Date(timeIntervalSince1970: 0)

        vm.attachVisitedExperienceIds(["exp_does_not_exist_xyz"])
        XCTAssertEqual(vm.markerState(for: exp, now: neutralNow), .default,
                       "an unrelated visited id must not flip another experience's marker")
    }

    // MARK: - VisitedIds is publicly observable

    func testVisitedExperienceIdsIsExposedForViewLayer() {
        let (vm, _) = makeViewModel(prefsSuite: "visited.expose.\(UUID().uuidString)")
        XCTAssertTrue(vm.visitedExperienceIds.isEmpty, "fresh vm must start with no visited ids")
        vm.attachVisitedExperienceIds(["a", "b", "c"])
        XCTAssertEqual(vm.visitedExperienceIds, Set(["a", "b", "c"]))
    }
}
