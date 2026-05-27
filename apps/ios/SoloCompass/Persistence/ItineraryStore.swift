import Foundation
import SwiftData

/// SwiftData-backed CRUD for `Itinerary` values.
///
/// `@MainActor` because SwiftData `ModelContext` is single-actor and the
/// rest of the iOS code is main-thread-bound. Owns its `ModelContext`;
/// pass a context from `SoloCompassModelContainer.makeInMemory()` in tests.
///
/// US-007: every mutation enqueues an outbox row via `SyncService` when
/// `FF_COMPANION` is on. When the flag is off, the row is still written to
/// SwiftData but the outbox is skipped — flipping the flag later replays
/// nothing (itineraries are not event-sourced), but new mutations will sync
/// from that point forward.
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
        enqueueSync(itinerary, isDeleted: false)
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
        enqueueSync(itinerary, isDeleted: false)
    }

    /// Delete an itinerary by id. No-op if not found.
    public func delete(id: ItineraryId) throws {
        guard let rec = record(for: id.rawValue) else { return }
        let value = rec.asValue
        context.delete(rec)
        try context.save()
        // Enqueue a tombstone so the row is soft-deleted on the server.
        enqueueSync(value, isDeleted: true)
    }

    /// Append `experienceId` to the itinerary's list (idempotent — skips if already present).
    /// Returns the updated `Itinerary` value, or nil if the itinerary was not found.
    @discardableResult
    public func addExperience(_ experienceId: String, to itineraryId: ItineraryId) throws -> Itinerary? {
        guard let rec = record(for: itineraryId.rawValue) else { return nil }
        var ids = (try? JSONDecoder().decode([String].self, from: rec.experienceIdsBlob)) ?? []
        guard !ids.contains(experienceId) else { return rec.asValue }
        ids.append(experienceId)
        rec.experienceIdsBlob = (try? JSONEncoder().encode(ids)) ?? rec.experienceIdsBlob
        rec.updatedAt = ISO8601DateFormatter().string(from: Date())
        try context.save()
        let updated = rec.asValue
        enqueueSync(updated, isDeleted: false)
        return updated
    }

    /// Replace `experienceIds` with a reordered list. No-op if the itinerary is not found
    /// or the set of IDs differs from the current set (prevents accidental drops).
    public func reorderExperiences(_ orderedIds: [String], in itineraryId: ItineraryId) throws {
        guard let rec = record(for: itineraryId.rawValue) else { return }
        let current = Set((try? JSONDecoder().decode([String].self, from: rec.experienceIdsBlob)) ?? [])
        guard Set(orderedIds) == current else { return }
        rec.experienceIdsBlob = (try? JSONEncoder().encode(orderedIds)) ?? rec.experienceIdsBlob
        rec.updatedAt = ISO8601DateFormatter().string(from: Date())
        try context.save()
        enqueueSync(rec.asValue, isDeleted: false)
    }

    /// Import a set of favorited experience IDs into an itinerary, skipping duplicates.
    /// Returns the number of IDs actually added.
    @discardableResult
    public func importFavorites(_ favoriteIds: Set<String>, into itineraryId: ItineraryId) throws -> Int {
        guard let rec = record(for: itineraryId.rawValue) else { return 0 }
        var ids = (try? JSONDecoder().decode([String].self, from: rec.experienceIdsBlob)) ?? []
        let existing = Set(ids)
        let toAdd = favoriteIds.filter { !existing.contains($0) }.sorted()
        ids.append(contentsOf: toAdd)
        if !toAdd.isEmpty {
            rec.experienceIdsBlob = (try? JSONEncoder().encode(ids)) ?? rec.experienceIdsBlob
            rec.updatedAt = ISO8601DateFormatter().string(from: Date())
            try context.save()
            enqueueSync(rec.asValue, isDeleted: false)
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

    /// Enqueue an upsert (or soft-delete tombstone) to the SyncService outbox.
    /// No-op when `FF_COMPANION` is off or when no authenticated session exists.
    private func enqueueSync(_ itinerary: Itinerary, isDeleted: Bool) {
        guard FeatureFlags.companion else { return }
        guard let userId = SupabaseClient.shared.currentSession?.userId else { return }
        let payload = SyncService.SyncItineraryPayload(
            id: itinerary.id.rawValue,
            user_id: userId,
            owner_id: itinerary.ownerId,
            title: itinerary.title,
            city_code: itinerary.cityCode,
            start_date: itinerary.startDate,
            end_date: itinerary.endDate,
            experience_ids: itinerary.experienceIds,
            note: itinerary.note,
            open_to_companions: itinerary.openToCompanions,
            is_deleted: isDeleted,
            device_id: DeviceIdentityService.shared.deviceID,
            created_at: itinerary.createdAt,
            updated_at: itinerary.updatedAt
        )
        SyncService.shared.enqueue(
            tableName: "itineraries",
            operation: "upsert",
            payload: payload,
            context: context
        )
    }
}
