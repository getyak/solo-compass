import Foundation
import Observation

// MARK: - Persistence flow

/// Persists an `ItineraryCreationDraft`.
///
/// The persistence step is injected as a throwing closure so a failed save can
/// be exercised deterministically in tests (a real `ItineraryStore` rarely
/// fails on demand). The itinerary is returned only after the write succeeds.
@MainActor
public struct ItineraryCreationFlow {
    /// Persists an itinerary, choosing update vs. insert from the flag.
    public typealias Persist = @MainActor (_ itinerary: Itinerary, _ isEditing: Bool) throws -> Void

    private let persist: Persist

    /// Creates a flow backed by an injected persistence step.
    public init(persist: @escaping Persist) {
        self.persist = persist
    }

    /// Creates a flow backed by a real `ItineraryStore`.
    public init(store: ItineraryStore) {
        self.persist = { itinerary, isEditing in
            if isEditing {
                try store.update(itinerary)
            } else {
                try store.save(itinerary)
            }
        }
    }

    /// Builds and persists the itinerary. The returned value is the exact
    /// itinerary that was written; it is only returned after persistence
    /// succeeds, so callers must never treat a throw as saved.
    @discardableResult
    public func commit(
        draft: ItineraryCreationDraft,
        editing: Itinerary?,
        pinnedExperienceIds: [String],
        now: Date,
        generatedId: String
    ) throws -> Itinerary {
        let itinerary = ItineraryCreationRules.itinerary(
            from: draft,
            editing: editing,
            pinnedExperienceIds: pinnedExperienceIds,
            now: now,
            generatedId: generatedId
        )
        try persist(itinerary, editing != nil)
        return itinerary
    }
}

// MARK: - Form model

/// Observable form state for `ItineraryFormView`.
///
/// Owns the draft, validation, dirty tracking, and the single persistence
/// entry point. Keeping it outside the view lets tests prove that a failed save
/// never fires the success callback and that cancelling never writes anything.
@MainActor
@Observable
public final class ItineraryCreationFormModel {
    /// Current field values.
    public var draft: ItineraryCreationDraft
    /// Localized, recoverable message shown when persistence fails.
    public private(set) var saveErrorMessage: String?

    private let flow: ItineraryCreationFlow
    private let editing: Itinerary?
    private let pinnedExperienceIds: [String]
    private let initialDraft: ItineraryCreationDraft

    /// Creates the form model. Defaults must already be resolved into `draft`
    /// by `ItineraryCreationRules.initialDraft`.
    public init(
        flow: ItineraryCreationFlow,
        editing: Itinerary?,
        pinnedExperienceIds: [String],
        draft: ItineraryCreationDraft
    ) {
        self.flow = flow
        self.editing = editing
        self.pinnedExperienceIds = pinnedExperienceIds
        self.draft = draft
        self.initialDraft = draft
        self.saveErrorMessage = nil
    }

    /// Whether `draft` differs from the values the form opened with.
    public var isDirty: Bool { draft != initialDraft }

    /// Whether the draft has the fields required to save.
    public var isValid: Bool { ItineraryCreationRules.isValid(draft) }

    /// Whether the end date precedes the start date.
    public var endBeforeStart: Bool { draft.endDate < draft.startDate }

    /// Discards the in-progress draft. Never persists — cancelling must not pin
    /// the source experience into anything.
    public func cancel() {
        draft = initialDraft
        saveErrorMessage = nil
    }

    /// Persists the draft. Returns the exact saved itinerary, or nil (after
    /// setting `saveErrorMessage`) when invalid or when the save failed.
    @discardableResult
    public func save(now: Date = Date()) -> Itinerary? {
        guard isValid else { return nil }
        do {
            let saved = try flow.commit(
                draft: draft,
                editing: editing,
                pinnedExperienceIds: pinnedExperienceIds,
                now: now,
                generatedId: UUID().uuidString
            )
            saveErrorMessage = nil
            return saved
        } catch {
            saveErrorMessage = NSLocalizedString(
                "itinerary.form.save.error.message",
                comment: "Recoverable message shown when saving an itinerary fails"
            )
            return nil
        }
    }

    /// Saves and invokes `onSaved` only after persistence succeeds.
    @discardableResult
    public func saveAndNotify(
        now: Date = Date(),
        onSaved: (Itinerary) -> Void
    ) -> Itinerary? {
        guard let saved = save(now: now) else { return nil }
        onSaved(saved)
        return saved
    }

    /// Dismisses the recoverable save error.
    public func clearSaveError() {
        saveErrorMessage = nil
    }
}

// MARK: - Add-to-itinerary model

/// Observable state for `AddToItinerarySheet`.
///
/// Extracted so the "surface the exact itinerary the form created" and
/// "cancel writes nothing" contracts are unit-testable instead of living only
/// in view code that used to guess via `store.loadAll().first`.
@MainActor
@Observable
public final class AddToItineraryModel {
    /// Which step of the add-to-itinerary sheet is visible.
    public enum Step: Equatable {
        /// Choosing among existing itineraries.
        case browsing
        /// Filling in the create form.
        case creating
    }

    /// Stored itineraries, newest created first.
    public private(set) var itineraries: [Itinerary]
    /// The itinerary just updated, highlighted in the list.
    public private(set) var addedToId: ItineraryId?
    /// Localized, recoverable error message.
    public private(set) var errorMessage: String?
    /// Current sheet step; drives the navigation path.
    public private(set) var step: Step

    private let store: ItineraryStore

    /// Creates the model and loads existing itineraries.
    public init(store: ItineraryStore) {
        self.store = store
        self.itineraries = store.loadAll()
        self.step = .browsing
    }

    /// Re-reads itineraries from the store.
    public func reload() {
        itineraries = store.loadAll()
    }

    /// Shows the create form.
    public func beginCreation() {
        step = .creating
    }

    /// Leaves the create form without writing anything. Cancelling must never
    /// pin the source experience.
    public func cancelCreation() {
        step = .browsing
        errorMessage = nil
    }

    /// Records a form save that already persisted. Returns the exact created
    /// itinerary — never a freshly fetched `loadAll().first`, which could be an
    /// unrelated older record.
    @discardableResult
    public func creationSucceeded(_ created: Itinerary) -> Itinerary {
        step = .browsing
        addedToId = created.id
        reload()
        return created
    }

    /// Pins `experienceId` into an existing itinerary, returning the updated
    /// value. On failure keeps the list visible and sets a localized error.
    @discardableResult
    public func addExisting(experienceId: String, to itineraryId: ItineraryId) -> Itinerary? {
        do {
            guard let updated = try store.addExperience(experienceId, to: itineraryId) else {
                return nil
            }
            addedToId = updated.id
            reload()
            return updated
        } catch {
            errorMessage = NSLocalizedString(
                "itinerary.addTo.error.message",
                comment: "Recoverable message shown when adding an experience fails"
            )
            return nil
        }
    }

    /// Clears the recoverable error message.
    public func clearError() {
        errorMessage = nil
    }
}
