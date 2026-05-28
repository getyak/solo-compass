import Foundation
import SwiftData
import os.log

/// SwiftData-backed CRUD for `Route` values.
///
/// `@MainActor` because SwiftData `ModelContext` is single-actor and the rest
/// of the iOS code is main-thread-bound. Mirrors `ItineraryStore`: views and
/// view-models go through this service rather than touching `ModelContext`
/// directly so the persistence layer can evolve (sync, validation, telemetry)
/// without leaking through the UI.
///
/// Mutations post a `RouteStore.didChange` notification on the main thread so
/// `@Observable` view models / SwiftUI views can refresh without holding a
/// strong reference to the store instance.
@MainActor
public final class RouteStore {
    /// Posted on `NotificationCenter.default` after any successful mutation
    /// (save / delete). Userinfo carries the affected `RouteId.rawValue` under
    /// the `"routeId"` key when applicable.
    public static let didChange = Notification.Name("SoloCompass.RouteStore.didChange")

    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Convenience init using the shared on-disk container.
    public convenience init() {
        self.init(context: ModelContext(SoloCompassModelContainer.shared))
    }

    // MARK: - CRUD

    /// All stored routes. Order is unspecified — callers that need a stable
    /// ordering should sort the result.
    public func all() -> [Route] {
        let descriptor = FetchDescriptor<RouteRecord>()
        return (try? context.fetch(descriptor))?.map(\.asValue) ?? []
    }

    /// Fetch a single route by id. Returns nil if not found.
    public func get(_ id: RouteId) -> Route? {
        record(for: id.rawValue)?.asValue
    }

    /// Persist a route. If a record with the same id exists it is replaced
    /// (delete-then-insert) so callers can treat `save` as idempotent upsert.
    public func save(_ route: Route) {
        deleteRecord(id: route.id.rawValue)
        context.insert(RouteRecord.fromValue(route))
        do {
            try context.save()
        } catch {
            assertionFailure("RouteStore.save failed: \(error)")
        }
        postChange(routeId: route.id.rawValue)
    }

    /// Delete a route by id. No-op if not found.
    public func delete(_ id: RouteId) {
        guard let rec = record(for: id.rawValue) else { return }
        context.delete(rec)
        do {
            try context.save()
        } catch {
            assertionFailure("RouteStore.delete failed: \(error)")
        }
        postChange(routeId: id.rawValue)
    }

    /// Routes in a given city, capped at `limit` results. Non-positive
    /// `limit` returns an empty array. Order is unspecified beyond the city
    /// filter — sort at the call site if needed.
    public func nearby(cityCode: String, limit: Int) -> [Route] {
        guard limit > 0 else { return [] }
        var descriptor = FetchDescriptor<RouteRecord>(
            predicate: #Predicate { $0.cityCode == cityCode }
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor))?.map(\.asValue) ?? []
    }

    // MARK: - Private helpers

    private func record(for id: String) -> RouteRecord? {
        let descriptor = FetchDescriptor<RouteRecord>(
            predicate: #Predicate { $0.id == id }
        )
        return (try? context.fetch(descriptor))?.first
    }

    private func deleteRecord(id: String) {
        guard let existing = record(for: id) else { return }
        context.delete(existing)
    }

    private func postChange(routeId: String) {
        NotificationCenter.default.post(
            name: RouteStore.didChange,
            object: self,
            userInfo: ["routeId": routeId]
        )
    }

    // MARK: - Seed import

    private static let seedLog = OSLog(subsystem: "com.solocompass.app", category: "RouteStore")

    /// On first launch (when `all().isEmpty`), decode the bundled
    /// `seed_routes.json` and save each route. Routes referencing
    /// experienceIds not present in `knownExperienceIds` are skipped
    /// with a single `os_log` warning rather than crashing.
    ///
    /// Returns the number of routes inserted. Idempotent: if the store is
    /// already populated, this is a no-op and returns 0.
    @discardableResult
    public func importSeedIfNeeded(
        knownExperienceIds: Set<String>,
        bundle: Bundle = .main
    ) -> Int {
        guard all().isEmpty else { return 0 }

        guard let seed = Self.loadBundledSeed(bundle: bundle) else {
            return 0
        }

        var skipped: [(routeId: String, missingIds: [String])] = []
        var added = 0
        for route in seed {
            let missing = route.experienceIds.filter { !knownExperienceIds.contains($0) }
            if !missing.isEmpty {
                skipped.append((route.id.rawValue, missing))
                continue
            }
            save(route)
            added += 1
        }

        if !skipped.isEmpty {
            let summary = skipped
                .map { "\($0.routeId)→[\($0.missingIds.joined(separator: ","))]" }
                .joined(separator: " ")
            os_log(
                "RouteStore seed: skipped %d route(s) with unresolved experienceIds: %{public}@",
                log: Self.seedLog,
                type: .info,
                skipped.count,
                summary
            )
        }

        return added
    }

    private static func loadBundledSeed(bundle: Bundle) -> [Route]? {
        guard let url = bundle.url(forResource: "seed_routes", withExtension: "json") else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([Route].self, from: data)
        } catch {
            os_log(
                "RouteStore seed: decode failed: %{public}@",
                log: Self.seedLog,
                type: .error,
                String(describing: error)
            )
            return nil
        }
    }
}
