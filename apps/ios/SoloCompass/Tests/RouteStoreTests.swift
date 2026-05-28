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
}
