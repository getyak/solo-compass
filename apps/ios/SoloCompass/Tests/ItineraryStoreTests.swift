import XCTest
import SwiftData
@testable import SoloCompass

// MARK: - US-003: ItineraryStore CRUD tests

@MainActor
final class ItineraryStoreTests: XCTestCase {

    private var store: ItineraryStore!

    override func setUp() async throws {
        try await super.setUp()
        let container = SoloCompassModelContainer.makeInMemory()
        store = ItineraryStore(context: ModelContext(container))
    }

    override func tearDown() async throws {
        store = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeItinerary(
        id: String = "itin_test_\(UUID().uuidString)",
        title: String = "Test Trip",
        openToCompanions: Bool = false
    ) -> Itinerary {
        Itinerary(
            id: ItineraryId(rawValue: id),
            ownerId: "user_test",
            title: title,
            cityCode: "TYO",
            startDate: "2026-06-01",
            endDate: "2026-06-10",
            experienceIds: ["exp_1", "exp_2"],
            note: "Test note",
            openToCompanions: openToCompanions,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z"
        )
    }

    // MARK: - Create

    func testSaveAndLoadById() throws {
        let itinerary = makeItinerary(id: "itin_save_load")
        try store.save(itinerary)

        let loaded = try XCTUnwrap(store.load(id: itinerary.id))
        XCTAssertEqual(loaded.id, itinerary.id)
        XCTAssertEqual(loaded.title, "Test Trip")
        XCTAssertEqual(loaded.cityCode, "TYO")
        XCTAssertEqual(loaded.experienceIds, ["exp_1", "exp_2"])
        XCTAssertEqual(loaded.note, "Test note")
        XCTAssertFalse(loaded.openToCompanions, "openToCompanions must default to false")
    }

    func testDefaultOpenToCompanionsFalse() throws {
        let itinerary = makeItinerary(openToCompanions: false)
        try store.save(itinerary)
        let loaded = try XCTUnwrap(store.load(id: itinerary.id))
        XCTAssertFalse(loaded.openToCompanions)
    }

    // MARK: - Read

    func testLoadAllReturnsAllSaved() throws {
        let a = makeItinerary(id: "itin_a", title: "Alpha")
        let b = makeItinerary(id: "itin_b", title: "Beta")
        try store.save(a)
        try store.save(b)

        let all = store.loadAll()
        XCTAssertEqual(all.count, 2)
        let ids = Set(all.map(\.id.rawValue))
        XCTAssertTrue(ids.contains("itin_a"))
        XCTAssertTrue(ids.contains("itin_b"))
    }

    func testLoadByIdReturnsNilWhenMissing() {
        let result = store.load(id: ItineraryId(rawValue: "itin_nonexistent"))
        XCTAssertNil(result)
    }

    func testLoadAllReturnsEmptyWhenNoData() {
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    // MARK: - Update

    func testUpdateMutableFields() throws {
        var itinerary = makeItinerary(id: "itin_update")
        try store.save(itinerary)

        itinerary = Itinerary(
            id: itinerary.id,
            ownerId: itinerary.ownerId,
            title: "Updated Title",
            cityCode: "OSA",
            startDate: "2026-07-01",
            endDate: "2026-07-15",
            experienceIds: ["exp_3"],
            note: "Updated note",
            openToCompanions: true,
            createdAt: itinerary.createdAt,
            updatedAt: "2026-02-01T00:00:00Z"
        )
        try store.update(itinerary)

        let loaded = try XCTUnwrap(store.load(id: itinerary.id))
        XCTAssertEqual(loaded.title, "Updated Title")
        XCTAssertEqual(loaded.cityCode, "OSA")
        XCTAssertEqual(loaded.experienceIds, ["exp_3"])
        XCTAssertEqual(loaded.note, "Updated note")
        XCTAssertTrue(loaded.openToCompanions)
        XCTAssertEqual(loaded.updatedAt, "2026-02-01T00:00:00Z")
    }

    func testUpdateNoOpWhenIdMissing() throws {
        let itinerary = makeItinerary(id: "itin_ghost")
        // Not saved — update should be a no-op without throwing
        XCTAssertNoThrow(try store.update(itinerary))
        XCTAssertNil(store.load(id: itinerary.id))
    }

    // MARK: - Delete

    func testDeleteRemovesItinerary() throws {
        let itinerary = makeItinerary(id: "itin_delete")
        try store.save(itinerary)
        XCTAssertNotNil(store.load(id: itinerary.id))

        try store.delete(id: itinerary.id)
        XCTAssertNil(store.load(id: itinerary.id))
    }

    func testDeleteNoOpWhenIdMissing() {
        XCTAssertNoThrow(try store.delete(id: ItineraryId(rawValue: "itin_nonexistent")))
    }

    func testDeleteOnlyRemovesTargetItinerary() throws {
        let a = makeItinerary(id: "itin_keep")
        let b = makeItinerary(id: "itin_remove")
        try store.save(a)
        try store.save(b)

        try store.delete(id: b.id)

        XCTAssertNotNil(store.load(id: a.id))
        XCTAssertNil(store.load(id: b.id))
        XCTAssertEqual(store.loadAll().count, 1)
    }

    // MARK: - Idempotent save (replace)

    func testSaveReplacesExistingRecord() throws {
        let original = makeItinerary(id: "itin_replace", title: "Original")
        try store.save(original)

        let replacement = Itinerary(
            id: original.id,
            ownerId: original.ownerId,
            title: "Replaced",
            cityCode: original.cityCode,
            startDate: original.startDate,
            endDate: original.endDate,
            experienceIds: original.experienceIds,
            note: original.note,
            openToCompanions: original.openToCompanions,
            createdAt: original.createdAt,
            updatedAt: "2026-03-01T00:00:00Z"
        )
        try store.save(replacement)

        let all = store.loadAll()
        XCTAssertEqual(all.count, 1, "save should replace, not duplicate")
        XCTAssertEqual(all[0].title, "Replaced")
    }
}
