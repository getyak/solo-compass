import Foundation
import SwiftData

/// SwiftData-backed CRUD for `Itinerary` values.
///
/// `@MainActor` because SwiftData `ModelContext` is single-actor and the
/// rest of the iOS code is main-thread-bound. Owns its `ModelContext`;
/// pass a context from `SoloCompassModelContainer.makeInMemory()` in tests.
@MainActor
public final class ItineraryStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Convenience init using the shared on-disk container.
    public convenience init() {
        self.init(context: ModelContext(SoloCompassModelContainer.shared))
    }

    // MARK: - CRUD

    /// Persist a new itinerary. Silently replaces an existing record with the
    /// same id (delete-then-insert to avoid SwiftData's implicit upsert gaps).
    public func save(_ itinerary: Itinerary) throws {
        deleteRecord(id: itinerary.id.rawValue)
        context.insert(ItineraryRecord(from: itinerary))
        try context.save()
    }

    /// All stored itineraries, ordered by `createdAt` descending.
    public func loadAll() -> [Itinerary] {
        var descriptor = FetchDescriptor<ItineraryRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.propertiesToFetch = nil
        return (try? context.fetch(descriptor))?.map(\.asValue) ?? []
    }

    /// Fetch a single itinerary by id. Returns nil if not found.
    public func load(id: ItineraryId) -> Itinerary? {
        record(for: id.rawValue)?.asValue
    }

    /// Update mutable fields of an existing itinerary. No-op if id not found.
    public func update(_ itinerary: Itinerary) throws {
        let rawId = itinerary.id.rawValue
        guard let existing = record(for: rawId) else { return }
        let fresh = ItineraryRecord(from: itinerary)
        existing.ownerId = fresh.ownerId
        existing.title = fresh.title
        existing.cityCode = fresh.cityCode
        existing.startDate = fresh.startDate
        existing.endDate = fresh.endDate
        existing.experienceIdsBlob = fresh.experienceIdsBlob
        existing.note = fresh.note
        existing.openToCompanions = fresh.openToCompanions
        existing.updatedAt = fresh.updatedAt
        try context.save()
    }

    /// Delete an itinerary by id. No-op if not found.
    public func delete(id: ItineraryId) throws {
        deleteRecord(id: id.rawValue)
        try context.save()
    }

    /// Append `experienceId` to the itinerary's list (idempotent — skips if already present).
    /// Returns the updated `Itinerary` value, or nil if the itinerary was not found.
    @discardableResult
    public func addExperience(_ experienceId: String, to itineraryId: ItineraryId) throws -> Itinerary? {
        guard let record = record(for: itineraryId.rawValue) else { return nil }
        var ids = (try? JSONDecoder().decode([String].self, from: record.experienceIdsBlob)) ?? []
        guard !ids.contains(experienceId) else {
            return record.asValue
        }
        ids.append(experienceId)
        record.experienceIdsBlob = (try? JSONEncoder().encode(ids)) ?? record.experienceIdsBlob
        record.updatedAt = ISO8601DateFormatter().string(from: Date())
        try context.save()
        return record.asValue
    }

    /// Replace `experienceIds` with a reordered list. No-op if the itinerary is not found
    /// or the set of IDs differs from the current set (prevents accidental drops).
    public func reorderExperiences(_ orderedIds: [String], in itineraryId: ItineraryId) throws {
        guard let record = record(for: itineraryId.rawValue) else { return }
        let current = Set((try? JSONDecoder().decode([String].self, from: record.experienceIdsBlob)) ?? [])
        guard Set(orderedIds) == current else { return }
        record.experienceIdsBlob = (try? JSONEncoder().encode(orderedIds)) ?? record.experienceIdsBlob
        record.updatedAt = ISO8601DateFormatter().string(from: Date())
        try context.save()
    }

    /// Import a set of favorited experience IDs into an itinerary, skipping duplicates.
    /// Returns the number of IDs actually added.
    @discardableResult
    public func importFavorites(_ favoriteIds: Set<String>, into itineraryId: ItineraryId) throws -> Int {
        guard let record = record(for: itineraryId.rawValue) else { return 0 }
        var ids = (try? JSONDecoder().decode([String].self, from: record.experienceIdsBlob)) ?? []
        let existing = Set(ids)
        let toAdd = favoriteIds.filter { !existing.contains($0) }.sorted()
        ids.append(contentsOf: toAdd)
        if !toAdd.isEmpty {
            record.experienceIdsBlob = (try? JSONEncoder().encode(ids)) ?? record.experienceIdsBlob
            record.updatedAt = ISO8601DateFormatter().string(from: Date())
            try context.save()
        }
        return toAdd.count
    }

    // MARK: - Private helpers

    private func record(for id: String) -> ItineraryRecord? {
        let descriptor = FetchDescriptor<ItineraryRecord>(
            predicate: #Predicate { $0.id == id }
        )
        return (try? context.fetch(descriptor))?.first
    }

    private func deleteRecord(id: String) {
        guard let existing = record(for: id) else { return }
        context.delete(existing)
    }
}
