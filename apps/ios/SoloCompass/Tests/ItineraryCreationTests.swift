import XCTest
import SwiftData
@testable import SoloCompass

/// Focused coverage for the bounded itinerary-creation fixes:
/// cancel never pins, the exact created itinerary is surfaced (never a
/// `loadAll().first` guess), a failed save never fires the success callback,
/// and new-form defaults never overwrite existing edit data.
@MainActor
final class ItineraryCreationTests: XCTestCase {

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
        id: String,
        title: String = "Test Trip",
        cityCode: String = "TYO",
        experienceIds: [String] = [],
        openToCompanions: Bool = false,
        createdAt: String = "2026-01-01T00:00:00Z"
    ) -> Itinerary {
        Itinerary(
            id: ItineraryId(rawValue: id),
            ownerId: "user_test",
            title: title,
            cityCode: cityCode,
            startDate: "2026-06-01",
            endDate: "2026-06-10",
            experienceIds: experienceIds,
            note: nil,
            openToCompanions: openToCompanions,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    private func validDraft(cityCode: String, title: String) -> ItineraryCreationDraft {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return ItineraryCreationDraft(
            title: title,
            cityCode: cityCode,
            startDate: now,
            endDate: now,
            note: "",
            openToCompanions: false
        )
    }

    // MARK: - Cancel must never pin

    func testCancelCreationWritesNothing() throws {
        let existing = makeItinerary(id: "keep-existing", experienceIds: ["already-pinned"])
        try store.save(existing)
        let model = AddToItineraryModel(store: store)

        model.beginCreation()
        XCTAssertEqual(model.step, .creating)

        model.cancelCreation()

        XCTAssertEqual(model.step, .browsing)
        XCTAssertNil(model.addedToId, "Cancelling must not mark anything as added")
        XCTAssertEqual(store.loadAll().count, 1, "Cancelling must not create an itinerary")
        XCTAssertEqual(store.load(id: existing.id)?.experienceIds, ["already-pinned"],
                       "Cancelling must not pin the source into the previously newest itinerary")
    }

    func testCancellingFormWithPinnedExperiencePersistsNothing() {
        let formModel = ItineraryCreationFormModel(
            flow: ItineraryCreationFlow(store: store),
            editing: nil,
            pinnedExperienceIds: ["exp_source"],
            draft: validDraft(cityCode: "cmi", title: "Chiang Mai Trip")
        )

        formModel.cancel()

        XCTAssertTrue(store.loadAll().isEmpty, "Cancelling must never pin the source experience")
        XCTAssertEqual(formModel.draft, validDraft(cityCode: "cmi", title: "Chiang Mai Trip"))
    }

    // MARK: - Exact created itinerary / pinned experience

    func testPinnedExperienceLandsInTheExactCreatedItinerary() throws {
        // An unrelated, newer record exists first, so `loadAll().first` would
        // be this one — proving the surfaced value is the created itinerary.
        let unrelatedNewer = makeItinerary(
            id: "itin_unrelated",
            title: "Unrelated",
            createdAt: "2030-01-01T00:00:00Z"
        )
        try store.save(unrelatedNewer)

        let flow = ItineraryCreationFlow(store: store)
        let created = try flow.commit(
            draft: validDraft(cityCode: "cmi", title: "Chiang Mai Trip"),
            editing: nil,
            pinnedExperienceIds: ["exp_source"],
            now: Date(timeIntervalSince1970: 1_700_000_000),
            generatedId: "itin_created"
        )

        XCTAssertEqual(created.experienceIds, ["exp_source"])
        let persisted = try XCTUnwrap(store.load(id: created.id))
        XCTAssertEqual(persisted.experienceIds, ["exp_source"])

        let model = AddToItineraryModel(store: store)
        let surfaced = model.creationSucceeded(created)

        XCTAssertEqual(surfaced.id, ItineraryId(rawValue: "itin_created"))
        XCTAssertEqual(surfaced.experienceIds, ["exp_source"])
        XCTAssertEqual(model.addedToId, ItineraryId(rawValue: "itin_created"))
        XCTAssertNotEqual(surfaced.id, unrelatedNewer.id, "Must not resolve to loadAll().first")
        XCTAssertEqual(store.loadAll().first?.id, unrelatedNewer.id, "Sanity: newest-by-date is the unrelated record")
    }

    func testAddExistingPinsIntoTargetItineraryOnly() throws {
        let target = makeItinerary(id: "itin_target")
        let other = makeItinerary(id: "itin_other")
        try store.save(target)
        try store.save(other)

        let model = AddToItineraryModel(store: store)
        let updated = try XCTUnwrap(model.addExisting(experienceId: "exp_source", to: target.id))

        XCTAssertEqual(updated.id, target.id)
        XCTAssertEqual(updated.experienceIds, ["exp_source"])
        XCTAssertEqual(model.addedToId, target.id)
        XCTAssertEqual(try XCTUnwrap(store.load(id: target.id)).experienceIds, ["exp_source"])
        XCTAssertEqual(try XCTUnwrap(store.load(id: other.id)).experienceIds, [])
    }

    // MARK: - Persistence failure / success callback

    func testPersistenceFailureKeepsFormRecoverableAndSkipsSuccessCallback() {
        struct SaveFailure: Error {}

        var persistCalls = 0
        let flow = ItineraryCreationFlow(persist: { _, _ in
            persistCalls += 1
            throw SaveFailure()
        })
        let formModel = ItineraryCreationFormModel(
            flow: flow,
            editing: nil,
            pinnedExperienceIds: ["exp_source"],
            draft: validDraft(cityCode: "cmi", title: "Chiang Mai Trip")
        )

        var successCallbackCount = 0
        let saved = formModel.saveAndNotify { _ in
            successCallbackCount += 1
        }

        XCTAssertNil(saved, "A failed save must not return an itinerary")
        XCTAssertEqual(persistCalls, 1)
        XCTAssertEqual(successCallbackCount, 0, "The success callback must not run when persistence fails")
        XCTAssertNotNil(formModel.saveErrorMessage, "Failure must surface recoverable, localized feedback")
        XCTAssertTrue(formModel.isValid, "The draft is preserved so the form can be retried")
        XCTAssertEqual(formModel.isDirty, false, "A failed save does not mutate the draft")
    }

    func testSuccessfulSaveInvokesCallbackWithExactItinerary() throws {
        let flow = ItineraryCreationFlow(store: store)
        let formModel = ItineraryCreationFormModel(
            flow: flow,
            editing: nil,
            pinnedExperienceIds: ["exp_source"],
            draft: validDraft(cityCode: "cmi", title: "Chiang Mai Trip")
        )

        var notified: Itinerary?
        let saved = formModel.saveAndNotify(now: Date(timeIntervalSince1970: 1_700_000_000)) { itinerary in
            notified = itinerary
        }

        let savedItinerary = try XCTUnwrap(saved)
        XCTAssertEqual(notified?.id, savedItinerary.id)
        XCTAssertEqual(savedItinerary.experienceIds, ["exp_source"])
        XCTAssertNil(formModel.saveErrorMessage)
    }

    func testInvalidDraftDoesNotAttemptPersistence() {
        var persistCalls = 0
        let flow = ItineraryCreationFlow(persist: { _, _ in persistCalls += 1 })
        let formModel = ItineraryCreationFormModel(
            flow: flow,
            editing: nil,
            pinnedExperienceIds: [],
            draft: validDraft(cityCode: "", title: "No City")
        )

        XCTAssertNil(formModel.save())
        XCTAssertEqual(persistCalls, 0)
    }

    // MARK: - Prefilled defaults

    func testNewDraftPrefillsSourceCitySuggestedTitleAndCurrentDate() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let draft = ItineraryCreationRules.initialDraft(
            editing: nil,
            sourceCityCode: "cmi",
            now: now,
            suggestedTitle: "Suggested Title"
        )

        XCTAssertEqual(draft.title, "Suggested Title")
        XCTAssertEqual(draft.cityCode, "cmi")
        XCTAssertEqual(draft.startDate, now)
        XCTAssertEqual(draft.endDate, now)
        XCTAssertEqual(draft.note, "")
        XCTAssertFalse(draft.openToCompanions)
    }

    func testNewDraftWithoutKnownSourceCityDoesNotInventOne() {
        let draft = ItineraryCreationRules.initialDraft(
            editing: nil,
            sourceCityCode: nil,
            now: Date(timeIntervalSince1970: 1_700_000_000),
            suggestedTitle: "Suggested Title"
        )

        XCTAssertEqual(draft.cityCode, "", "Unknown source city must stay empty, not be invented")
    }

    func testSourceCityCodeResolvesFromLoadedExperiences() throws {
        let experiences = ExperienceService.hardcodedSeed
        let first = try XCTUnwrap(experiences.first)
        XCTAssertEqual(
            ItineraryCreationRules.sourceCityCode(experienceId: first.id, in: experiences),
            first.location.cityCode
        )
        XCTAssertNil(ItineraryCreationRules.sourceCityCode(experienceId: "exp_missing", in: experiences))
    }

    // MARK: - Edit preservation

    func testEditDraftPreservesSavedValuesAndIgnoresDefaults() {
        let editing = Itinerary.sample
        let draft = ItineraryCreationRules.initialDraft(
            editing: editing,
            sourceCityCode: "cmi",
            now: Date(),
            suggestedTitle: "Default That Must Not Apply"
        )

        XCTAssertEqual(draft.title, editing.title)
        XCTAssertEqual(draft.cityCode, editing.cityCode)
        XCTAssertEqual(draft.note, editing.note ?? "")
        XCTAssertEqual(draft.openToCompanions, editing.openToCompanions)
        XCTAssertEqual(ItineraryCreationRules.dateString(from: draft.startDate), editing.startDate)
        XCTAssertEqual(ItineraryCreationRules.dateString(from: draft.endDate), editing.endDate)
    }

    func testEditingDoesNotAppendPinnedExperienceOrChangeIdentity() throws {
        let editing = makeItinerary(
            id: "itin_edit",
            experienceIds: ["exp_old"],
            createdAt: "2021-05-05T00:00:00Z"
        )
        try store.save(editing)

        let flow = ItineraryCreationFlow(store: store)
        let saved = try flow.commit(
            draft: validDraft(cityCode: "OSA", title: "Updated"),
            editing: editing,
            pinnedExperienceIds: ["exp_new"],
            now: Date(timeIntervalSince1970: 1_700_000_000),
            generatedId: "should_be_ignored"
        )

        XCTAssertEqual(saved.id, editing.id)
        XCTAssertEqual(saved.ownerId, editing.ownerId)
        XCTAssertEqual(saved.createdAt, editing.createdAt)
        XCTAssertEqual(saved.experienceIds, ["exp_old"], "Editing must preserve existing pins")
        let reloaded = try XCTUnwrap(store.load(id: editing.id))
        XCTAssertEqual(reloaded.title, "Updated")
        XCTAssertEqual(reloaded.experienceIds, ["exp_old"])
    }

    // MARK: - Validation

    func testValidationRequiresTitleCityAndOrderedDates() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let base = ItineraryCreationDraft(
            title: "Trip",
            cityCode: "cmi",
            startDate: now,
            endDate: now,
            note: "",
            openToCompanions: false
        )
        XCTAssertTrue(ItineraryCreationRules.isValid(base))

        var blankTitle = base
        blankTitle.title = "   "
        XCTAssertFalse(ItineraryCreationRules.isValid(blankTitle))

        var blankCity = base
        blankCity.cityCode = ""
        XCTAssertFalse(ItineraryCreationRules.isValid(blankCity))

        var reversed = base
        reversed.endDate = now.addingTimeInterval(-86_400)
        XCTAssertFalse(ItineraryCreationRules.isValid(reversed))
    }
}
