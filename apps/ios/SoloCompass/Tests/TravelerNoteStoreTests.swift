import XCTest
import SwiftData
@testable import SoloCompass

@MainActor
final class TravelerNoteStoreTests: XCTestCase {

    private var store: TravelerNoteStore!

    override func setUp() async throws {
        try await super.setUp()
        let container = SoloCompassModelContainer.makeInMemory()
        store = TravelerNoteStore(context: ModelContext(container))
    }

    override func tearDown() async throws {
        store = nil
        try await super.tearDown()
    }

    // MARK: - Add + fetch

    func testAddNotePersistsAndIsMine() {
        let added = store.addNote(experienceId: "exp_test", text: "Quiet corner upstairs")
        XCTAssertNotNil(added)
        XCTAssertTrue(added?.isMine == true)

        let notes = store.notes(for: "exp_test")
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.text, "Quiet corner upstairs")
        XCTAssertEqual(notes.first?.kind, .experience)
    }

    func testAddEmptyNoteIsRejected() {
        let added = store.addNote(experienceId: "exp_test", text: "   ")
        XCTAssertNil(added)
        XCTAssertTrue(store.notes(for: "exp_test").isEmpty)
    }

    func testNotesScopedByExperienceId() {
        store.addNote(experienceId: "exp_a", text: "Note A")
        store.addNote(experienceId: "exp_b", text: "Note B")

        XCTAssertEqual(store.notes(for: "exp_a").count, 1)
        XCTAssertEqual(store.notes(for: "exp_a").first?.text, "Note A")
        XCTAssertEqual(store.notes(for: "exp_b").count, 1)
    }

    // MARK: - Confirm

    func testConfirmNoteIncrementsCount() {
        guard let note = store.addNote(experienceId: "exp_c", text: "Reachable note") else {
            return XCTFail("addNote returned nil")
        }
        let before = store.notes(for: "exp_c").first { $0.id == note.id }?.confirms ?? -1
        store.confirmNote(id: note.id)
        let after = store.notes(for: "exp_c").first { $0.id == note.id }?.confirms ?? -1
        XCTAssertEqual(after, before + 1)
    }

    func testConfirmMissingNoteIsNoOp() {
        // Should not crash or create anything.
        store.confirmNote(id: "does_not_exist")
        XCTAssertTrue(store.notes(for: "exp_none").isEmpty)
    }

    // MARK: - AI-adopted ordering

    func testAiAdoptedNotesSortFirst() {
        // Seeded x10kup has AI-adopted notes; the first returned note is adopted.
        let notes = store.notes(for: "x10kup")
        XCTAssertGreaterThan(notes.count, 1)
        XCTAssertTrue(notes.first?.aiAdopted == true,
                      "AI-adopted notes should sort ahead of un-adopted ones")
    }

    // MARK: - Corrections

    func testSeededCorrectionAcceptRemovesIt() {
        let pending = store.corrections(for: "x10kup")
        XCTAssertEqual(pending.count, 1, "x10kup seeds one pending correction")
        guard let id = pending.first?.id else { return XCTFail("no correction id") }

        store.acceptCorrection(id: id)
        XCTAssertTrue(store.corrections(for: "x10kup").isEmpty,
                      "Accepted corrections drop out of the pending list")
    }

    func testSeededCorrectionDismissRemovesIt() {
        let pending = store.corrections(for: "x10kup")
        guard let id = pending.first?.id else { return XCTFail("no correction id") }

        store.dismissCorrection(id: id)
        XCTAssertTrue(store.corrections(for: "x10kup").isEmpty,
                      "Dismissed corrections drop out of the pending list")
    }

    // MARK: - Seeding idempotency

    func testSeedingRunsOnlyOncePerPlace() {
        let first = store.notes(for: "x10kup").count
        XCTAssertGreaterThan(first, 0, "x10kup should seed demo notes")
        // A second fetch must not duplicate the seed.
        let second = store.notes(for: "x10kup").count
        XCTAssertEqual(first, second, "Re-fetching must not re-seed")
    }

    func testUnknownPlaceSeedsNothing() {
        XCTAssertTrue(store.notes(for: "totally_unknown_poi").isEmpty)
        XCTAssertTrue(store.corrections(for: "totally_unknown_poi").isEmpty)
    }

    // MARK: - Mood presets

    func testMoodPresetsAreCategorySpecific() {
        let coffee = ExperienceDetailView.moodPresets(for: .coffee)
        let nature = ExperienceDetailView.moodPresets(for: .nature)
        XCTAssertFalse(coffee.isEmpty)
        XCTAssertFalse(nature.isEmpty)
        XCTAssertNotEqual(coffee, nature, "Mood chips should differ per category")
    }
}
