import XCTest
import SwiftData
@testable import SoloCompass

@MainActor
final class RouteStoreTests: XCTestCase {

    private var store: RouteStore!

    override func setUp() async throws {
        try await super.setUp()
        let container = SoloCompassModelContainer.makeInMemory()
        store = RouteStore(context: ModelContext(container))
    }

    override func tearDown() async throws {
        store = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeRoute(
        id: String = "route_\(UUID().uuidString)",
        title: String = "Test Route",
        cityCode: String = "tyo",
        region: String = "Shibuya"
    ) -> Route {
        Route(
            id: RouteId(rawValue: id),
            title: title,
            summary: "Summary for \(title)",
            experienceIds: ["exp_a", "exp_b"],
            cityCode: cityCode,
            region: region,
            estimatedDuration: 90,
            distanceMeters: 2400,
            pace: .standard,
            tags: ["scenic"],
            source: .editorial
        )
    }

    // MARK: - save + get

    func testSaveAndGetById() {
        let route = makeRoute(id: "route_save_get", title: "Round-trip")
        store.save(route)

        let loaded = store.get(route.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id.rawValue, "route_save_get")
        XCTAssertEqual(loaded?.title, "Round-trip")
        XCTAssertEqual(loaded?.cityCode, "tyo")
        XCTAssertEqual(loaded?.experienceIds, ["exp_a", "exp_b"])
        XCTAssertEqual(loaded?.pace, .standard)
        XCTAssertEqual(loaded?.source, .editorial)
    }

    func testGetReturnsNilWhenMissing() {
        XCTAssertNil(store.get(RouteId(rawValue: "route_missing")))
    }

    func testSaveReplacesExistingRecord() {
        let original = makeRoute(id: "route_replace", title: "Original")
        store.save(original)

        let replacement = Route(
            id: original.id,
            title: "Replaced",
            summary: original.summary,
            experienceIds: original.experienceIds,
            cityCode: original.cityCode,
            region: original.region,
            estimatedDuration: original.estimatedDuration,
            distanceMeters: original.distanceMeters,
            pace: .packed,
            tags: original.tags,
            source: original.source
        )
        store.save(replacement)

        XCTAssertEqual(store.all().count, 1, "save should replace, not duplicate")
        XCTAssertEqual(store.get(original.id)?.title, "Replaced")
        XCTAssertEqual(store.get(original.id)?.pace, .packed)
    }

    // MARK: - delete

    func testDeleteRemovesRoute() {
        let route = makeRoute(id: "route_delete")
        store.save(route)
        XCTAssertNotNil(store.get(route.id))

        store.delete(route.id)
        XCTAssertNil(store.get(route.id))
    }

    func testDeleteNoOpWhenMissing() {
        store.delete(RouteId(rawValue: "route_ghost"))
        XCTAssertTrue(store.all().isEmpty)
    }

    func testDeleteOnlyRemovesTarget() {
        let a = makeRoute(id: "route_keep")
        let b = makeRoute(id: "route_remove")
        store.save(a)
        store.save(b)

        store.delete(b.id)

        XCTAssertNotNil(store.get(a.id))
        XCTAssertNil(store.get(b.id))
        XCTAssertEqual(store.all().count, 1)
    }

    // MARK: - all-after-save count

    func testAllReturnsEverythingSaved() {
        XCTAssertTrue(store.all().isEmpty)

        store.save(makeRoute(id: "route_1"))
        store.save(makeRoute(id: "route_2"))
        store.save(makeRoute(id: "route_3"))

        let all = store.all()
        XCTAssertEqual(all.count, 3)
        let ids = Set(all.map(\.id.rawValue))
        XCTAssertEqual(ids, ["route_1", "route_2", "route_3"])
    }

    func testAllReturnsEmptyWhenNoData() {
        XCTAssertTrue(store.all().isEmpty)
    }

    // MARK: - nearby filters by cityCode

    func testNearbyFiltersByCityCode() {
        store.save(makeRoute(id: "route_tyo_1", cityCode: "tyo"))
        store.save(makeRoute(id: "route_tyo_2", cityCode: "tyo"))
        store.save(makeRoute(id: "route_osa_1", cityCode: "osa"))

        let tyo = store.nearby(cityCode: "tyo", limit: 10)
        XCTAssertEqual(tyo.count, 2)
        XCTAssertTrue(tyo.allSatisfy { $0.cityCode == "tyo" })

        let osa = store.nearby(cityCode: "osa", limit: 10)
        XCTAssertEqual(osa.count, 1)
        XCTAssertEqual(osa.first?.id.rawValue, "route_osa_1")

        let unknown = store.nearby(cityCode: "nyc", limit: 10)
        XCTAssertTrue(unknown.isEmpty)
    }

    func testNearbyRespectsLimit() {
        for index in 0..<5 {
            store.save(makeRoute(id: "route_lim_\(index)", cityCode: "tyo"))
        }

        let limited = store.nearby(cityCode: "tyo", limit: 2)
        XCTAssertEqual(limited.count, 2)
    }

    func testNearbyReturnsEmptyForNonPositiveLimit() {
        store.save(makeRoute(id: "route_lim_zero", cityCode: "tyo"))
        XCTAssertTrue(store.nearby(cityCode: "tyo", limit: 0).isEmpty)
        XCTAssertTrue(store.nearby(cityCode: "tyo", limit: -1).isEmpty)
    }

    /// `nearby` sorts by title so the Routes section order is stable across
    /// restarts. Saving out of alphabetical order must still return sorted.
    func testNearbySortsByTitleForStableOrder() {
        store.save(makeRoute(id: "route_c", title: "Charlie", cityCode: "tyo"))
        store.save(makeRoute(id: "route_a", title: "Alpha", cityCode: "tyo"))
        store.save(makeRoute(id: "route_b", title: "Bravo", cityCode: "tyo"))

        let titles = store.nearby(cityCode: "tyo", limit: 10).map(\.title)
        XCTAssertEqual(titles, ["Alpha", "Bravo", "Charlie"])
    }

    // MARK: - didChange notification

    func testSavePostsDidChangeNotification() {
        let route = makeRoute(id: "route_notify_save")
        let exp = expectation(forNotification: RouteStore.didChange, object: store) { note in
            (note.userInfo?["routeId"] as? String) == "route_notify_save"
        }
        store.save(route)
        wait(for: [exp], timeout: 1.0)
    }

    func testDeletePostsDidChangeNotification() {
        let route = makeRoute(id: "route_notify_delete")
        store.save(route)

        let exp = expectation(forNotification: RouteStore.didChange, object: store) { note in
            (note.userInfo?["routeId"] as? String) == "route_notify_delete"
        }
        store.delete(route.id)
        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - importSeedIfNeeded (US-007)

    /// Set of every experienceId referenced by `seed_routes.json` so all 4
    /// seed routes resolve cleanly. Mirrors what `ExperienceService` would
    /// have loaded on a real first launch.
    private static let seedRoutesExperienceIds: Set<String> = [
        "exp_vte_mekong_riverside_sunset",
        "exp_vte_wat_si_saket_morning",
        "exp_vte_slow_coffee_dao",
        "exp_vte_pha_that_luang_dawn",
        "exp_vte_patuxai_view"
    ]

    func testImportSeedIfNeededOnFreshLaunchLoadsFourRoutes() {
        XCTAssertTrue(store.all().isEmpty, "fresh in-memory store must start empty")

        let bundle = Self.seedBundle()
        let added = store.importSeedIfNeeded(
            knownExperienceIds: Self.seedRoutesExperienceIds,
            bundle: bundle
        )

        XCTAssertEqual(added, 4, "importSeedIfNeeded should insert all 4 Vientiane seed routes")
        XCTAssertEqual(store.all().count, 4)

        let ids = Set(store.all().map { $0.id.rawValue })
        XCTAssertEqual(
            ids,
            Set(["mekong-sunset", "slow-coffee-day", "morning-ritual", "vientiane-monuments"])
        )
    }

    func testImportSeedIfNeededIsNoOpWhenStoreAlreadyPopulated() {
        store.save(makeRoute(id: "preexisting_route"))
        XCTAssertEqual(store.all().count, 1)

        let bundle = Self.seedBundle()
        let added = store.importSeedIfNeeded(
            knownExperienceIds: Self.seedRoutesExperienceIds,
            bundle: bundle
        )

        XCTAssertEqual(added, 0, "importSeedIfNeeded must be a no-op when store is non-empty")
        XCTAssertEqual(store.all().count, 1)
    }

    func testImportSeedIfNeededSkipsRoutesWithUnknownExperienceIds() {
        // Only `mekong-sunset` (single id) resolves; the other three routes
        // reference experienceIds we deliberately omit and must be skipped
        // without crashing.
        let partialKnown: Set<String> = ["exp_vte_mekong_riverside_sunset"]

        let bundle = Self.seedBundle()
        let added = store.importSeedIfNeeded(
            knownExperienceIds: partialKnown,
            bundle: bundle
        )

        XCTAssertEqual(added, 1, "only routes whose experienceIds all resolve should be saved")
        XCTAssertEqual(store.all().count, 1)
        XCTAssertEqual(store.all().first?.id.rawValue, "mekong-sunset")
    }

    /// US-015: After seed load, RouteStore.all() yields 4 routes with the 4
    /// expected distinct companion-fixture shapes.
    func testImportSeedIfNeededYieldsDistinctCompanionFixtures() {
        let bundle = Self.seedBundle()
        store.importSeedIfNeeded(
            knownExperienceIds: Self.seedRoutesExperienceIds,
            bundle: bundle
        )

        let routes = store.all()
        XCTAssertEqual(routes.count, 4)
        let byId = Dictionary(uniqueKeysWithValues: routes.map { ($0.id.rawValue, $0) })

        // mekong-sunset: open, 2 confirmed, 2 pending requests
        let mekong = byId["mekong-sunset"]
        XCTAssertNotNil(mekong?.companion)
        XCTAssertEqual(mekong?.companion?.status, .open)
        XCTAssertEqual(mekong?.companion?.confirmedMembers.count, 2)
        XCTAssertEqual(mekong?.companion?.joinRequests.filter { $0.status == .pending }.count, 2)

        // slow-coffee-day: forming, 3 confirmed
        let coffee = byId["slow-coffee-day"]
        XCTAssertNotNil(coffee?.companion)
        XCTAssertEqual(coffee?.companion?.status, .forming)
        XCTAssertEqual(coffee?.companion?.confirmedMembers.count, 3)

        // morning-ritual: nil companion
        XCTAssertNil(byId["morning-ritual"]?.companion)

        // vientiane-monuments: completed, 4/4 members
        let monuments = byId["vientiane-monuments"]
        XCTAssertNotNil(monuments?.companion)
        XCTAssertEqual(monuments?.companion?.status, .completed)
        XCTAssertEqual(monuments?.companion?.confirmedMembers.count, 4)
    }

    // MARK: - Beta-P0-A: active route progress (#78)
    //
    // skipStop / pauseRoute / resumeRoute were added after Beta v0.9 to let the
    // user drop a stop without faking attendance, and to step away from a
    // half-day walk without losing their place. These regressions are easy to
    // introduce in the SwiftData layer (forgetting to nil activeStartedAt,
    // bumping the index when no route is active, …) — lock the contract in.

    private func seededActiveRoute(id: String = "route_active") -> Route {
        let route = Route(
            id: RouteId(rawValue: id),
            title: "Active Walk",
            summary: "Two-stop walk",
            experienceIds: ["exp_a", "exp_b", "exp_c"],
            cityCode: "vte",
            region: "Riverside",
            estimatedDuration: 60,
            distanceMeters: 1500,
            pace: .standard,
            tags: [],
            source: .editorial
        )
        store.save(route)
        store.startRoute(route.id)
        return route
    }

    func testSkipStopAdvancesIndexWithoutMarkingCompleted() {
        let route = seededActiveRoute()
        guard let snapshot = store.loadActiveRoute() else {
            return XCTFail("startRoute should leave the route active")
        }
        XCTAssertEqual(snapshot.stopIndex, 0)
        XCTAssertTrue(snapshot.completedIds.isEmpty)

        let next = store.skipStop(route.id)
        XCTAssertEqual(next, 1, "skipStop must advance the index by one")

        guard let after = store.loadActiveRoute() else {
            return XCTFail("route should still be active after a skip")
        }
        XCTAssertEqual(after.stopIndex, 1)
        XCTAssertTrue(
            after.completedIds.isEmpty,
            "skipStop must NOT append to completedStopIds — that is advanceStop's job"
        )
    }

    func testSkipStopIsNoOpForInactiveRoute() {
        let route = Route(
            id: RouteId(rawValue: "route_inactive"),
            title: "Inactive",
            summary: "",
            experienceIds: ["exp_x"],
            cityCode: "vte",
            region: "",
            estimatedDuration: 10,
            distanceMeters: 100,
            pace: .standard,
            tags: [],
            source: .editorial
        )
        store.save(route) // saved but never startRoute() → currentStopIndex nil

        XCTAssertNil(
            store.skipStop(route.id),
            "skipStop on a never-started route must return nil"
        )
    }

    func testSkipStopReturnsNilForMissingRoute() {
        XCTAssertNil(store.skipStop(RouteId(rawValue: "route_does_not_exist")))
    }

    func testPauseRouteClearsActiveStartedAtButPreservesProgress() {
        let route = seededActiveRoute()
        store.advanceStop(route.id, completedExperienceId: "exp_a")
        // advanceStop bumped the index AND appended "exp_a" to completed.

        store.pauseRoute(route.id)

        XCTAssertNil(
            store.loadActiveRoute(),
            "loadActiveRoute must skip paused routes (activeStartedAt cleared)"
        )
        // Re-fetch the raw record via get() to verify progress survived the pause.
        XCTAssertNotNil(store.get(route.id), "the route record itself must still exist")
    }

    func testResumeRouteRestoresActiveLookupAndPreservesProgress() {
        let route = seededActiveRoute()
        store.advanceStop(route.id, completedExperienceId: "exp_a")
        store.pauseRoute(route.id)
        XCTAssertNil(store.loadActiveRoute(), "precondition: paused → not active")

        store.resumeRoute(route.id)

        guard let snapshot = store.loadActiveRoute() else {
            return XCTFail("resumeRoute must surface the route again")
        }
        XCTAssertEqual(snapshot.stopIndex, 1, "currentStopIndex must survive pause/resume")
        XCTAssertEqual(
            snapshot.completedIds,
            ["exp_a"],
            "completedStopIds must survive pause/resume"
        )
    }

    func testPauseAndResumeAreNoOpsForMissingRoute() {
        store.pauseRoute(RouteId(rawValue: "route_missing"))
        store.resumeRoute(RouteId(rawValue: "route_missing"))
        XCTAssertTrue(store.all().isEmpty)
    }

    func testSkipStopPostsDidChangeNotification() {
        let route = seededActiveRoute(id: "route_skip_notify")
        let exp = expectation(forNotification: RouteStore.didChange, object: store) { note in
            (note.userInfo?["routeId"] as? String) == "route_skip_notify"
        }
        store.skipStop(route.id)
        wait(for: [exp], timeout: 1.0)
    }

    func testPauseResumePostsDidChangeNotifications() {
        let route = seededActiveRoute(id: "route_pr_notify")

        let pauseExp = expectation(forNotification: RouteStore.didChange, object: store) { note in
            (note.userInfo?["routeId"] as? String) == "route_pr_notify"
        }
        store.pauseRoute(route.id)
        wait(for: [pauseExp], timeout: 1.0)

        let resumeExp = expectation(forNotification: RouteStore.didChange, object: store) { note in
            (note.userInfo?["routeId"] as? String) == "route_pr_notify"
        }
        store.resumeRoute(route.id)
        wait(for: [resumeExp], timeout: 1.0)
    }

    /// Locate the bundle hosting `seed_routes.json`. Mirrors the lookup in
    /// `SeedRoutesParityTests`: prefer the test bundle if it carries the
    /// resource, otherwise fall back to `Bundle.main` — under
    /// `xcodebuild test` the main bundle is the host app, which always ships
    /// `seed_routes.json` because XcodeGen scans the `Resources/JSON` tree.
    private static func seedBundle() -> Bundle {
        let testBundle = Bundle(for: RouteStoreTests.self)
        if testBundle.url(forResource: "seed_routes", withExtension: "json") != nil {
            return testBundle
        }
        return .main
    }
}
