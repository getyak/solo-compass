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

    let context: ModelContext

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
    ///
    /// #81: The v1.7 active-route progress columns (activeStartedAt,
    /// currentStopIndex, completedStopIdsBlob) are NOT carried on the
    /// `Route` value type — they're per-device state, not part of the
    /// content schema. RouteRecord.fromValue therefore leaves them nil,
    /// which would silently wipe in-progress progress every time anyone
    /// re-saves the same route (companion change, AI re-generation, etc).
    /// We snapshot the three fields off the old record before deleting,
    /// then restore them onto the freshly-inserted one. Idempotent: when
    /// no record existed before, the three remain nil as expected.
    public func save(_ route: Route) {
        let prior = record(for: route.id.rawValue)
        let priorActiveStartedAt = prior?.activeStartedAt
        let priorCurrentStopIndex = prior?.currentStopIndex
        let priorCompletedBlob = prior?.completedStopIdsBlob

        deleteRecord(id: route.id.rawValue)
        let fresh = RouteRecord.fromValue(route)
        fresh.activeStartedAt = priorActiveStartedAt
        fresh.currentStopIndex = priorCurrentStopIndex
        fresh.completedStopIdsBlob = priorCompletedBlob
        context.insert(fresh)
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
    /// `limit` returns an empty array. Sorted by `title` so the Routes section
    /// shows a stable, deterministic order across app restarts (the fetch is
    /// otherwise unordered, which made the list shuffle on each cold start).
    public func nearby(cityCode: String, limit: Int) -> [Route] {
        guard limit > 0 else { return [] }
        let candidates = Self.cityCodeCandidates(for: cityCode)
        let descriptor = FetchDescriptor<RouteRecord>(
            sortBy: [SortDescriptor(\.title)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        let matched = all.filter { record in
            candidates.contains { $0.caseInsensitiveCompare(record.cityCode) == .orderedSame }
        }
        return Array(matched.prefix(limit)).map(\.asValue)
    }

    /// Mirrors `MapViewModel.cityCodeAliases` — kept local so the persistence
    /// layer doesn't depend on a view model. When the persisted
    /// `lastSelectedCity` is the human slug (`vientiane`) but seed routes are
    /// coded as `VTE`, the literal `==` predicate dropped every row; expanding
    /// the query into the alias-equivalent set keeps the Routes section
    /// populated on cold start.
    private static let cityCodeAliases: [String: String] = [
        "chiang-mai": "cmi",
        "vientiane": "VTE",
        "shenzhen": "cn-深圳市",
        "szx": "cn-深圳市",
    ]

    private static func cityCodeCandidates(for cityCode: String) -> [String] {
        var result: [String] = [cityCode]
        let lower = cityCode.lowercased()
        if let forward = cityCodeAliases[lower] {
            result.append(forward)
        }
        for (slug, seed) in cityCodeAliases
        where seed.caseInsensitiveCompare(cityCode) == .orderedSame {
            result.append(slug)
        }
        return result
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

    // MARK: - Atomic helpers (for multi-record saves in a single context.save())

    /// Stage a route insert without calling `context.save()`. Pair with
    /// `commitContext()` to flush multiple staged writes atomically.
    public func saveWithContext(_ route: Route) {
        deleteRecord(id: route.id.rawValue)
        context.insert(RouteRecord.fromValue(route))
    }

    /// Flush all staged inserts/deletes to disk. Throws on failure.
    public func commitContext() throws {
        try context.save()
        NotificationCenter.default.post(
            name: RouteStore.didChange,
            object: self,
            userInfo: nil
        )
    }

    // MARK: - Beta-P0-A: active-route progress
    //
    // The "in-progress route" used to live as @State on CompassMapView,
    // so closing the app or being killed in the background lost the
    // user's place in a half-day walk. We now persist three optional
    // RouteRecord columns (activeStartedAt, currentStopIndex,
    // completedStopIdsBlob) so a relaunch can resume exactly where the
    // user left off. We deliberately keep this iOS-local — there's no
    // upstream Route schema column for "in-progress", and the user
    // signal is per-device by definition.

    /// Mark the given route as started for the user. No-op if the
    /// route record can't be found. Resets currentStopIndex to 0 and
    /// the completedStopIds blob to an empty array so a re-start of a
    /// finished route gets a clean slate.
    public func startRoute(_ id: RouteId, at date: Date = Date()) {
        guard let rec = record(for: id.rawValue) else { return }
        rec.activeStartedAt = date
        rec.currentStopIndex = 0
        rec.completedStopIdsBlob = Data("[]".utf8)
        do {
            try context.save()
        } catch {
            assertionFailure("RouteStore.startRoute failed: \(error)")
        }
        postChange(routeId: id.rawValue)
    }

    /// Advance to the next stop in an active route. `completedExperienceId`
    /// is appended to the persisted completed list. No-op if the route is
    /// not currently active. Returns the new currentStopIndex (nil if
    /// nothing changed) so callers can chain UI updates.
    @discardableResult
    public func advanceStop(_ id: RouteId, completedExperienceId: String) -> Int? {
        guard let rec = record(for: id.rawValue),
              let current = rec.currentStopIndex else { return nil }
        var completed: [String] = []
        if let blob = rec.completedStopIdsBlob,
           let decoded = try? JSONDecoder().decode([String].self, from: blob) {
            completed = decoded
        }
        if !completed.contains(completedExperienceId) {
            completed.append(completedExperienceId)
        }
        rec.completedStopIdsBlob = (try? JSONEncoder().encode(completed)) ?? rec.completedStopIdsBlob
        let next = current + 1
        rec.currentStopIndex = next
        do {
            try context.save()
        } catch {
            assertionFailure("RouteStore.advanceStop failed: \(error)")
        }
        postChange(routeId: id.rawValue)
        return next
    }

    /// Skip the current stop without marking it completed. Same index advance
    /// as `advanceStop` but the experience id is NOT appended to the
    /// completed list — useful when the user wants to drop a stop ("下雨了，
    /// 跳过这家咖啡") without faking attendance. Returns the new
    /// currentStopIndex (nil if no-op).
    @discardableResult
    public func skipStop(_ id: RouteId) -> Int? {
        guard let rec = record(for: id.rawValue),
              let current = rec.currentStopIndex else { return nil }
        let next = current + 1
        rec.currentStopIndex = next
        do {
            try context.save()
        } catch {
            assertionFailure("RouteStore.skipStop failed: \(error)")
        }
        postChange(routeId: id.rawValue)
        return next
    }

    /// Pause an active route — keeps progress (`currentStopIndex` and
    /// `completedStopIdsBlob`) but clears `activeStartedAt` so
    /// `loadActiveRoute()` stops returning it. Allows the user to step
    /// away mid-route ("接个电话，先暂停") without losing their place.
    public func pauseRoute(_ id: RouteId) {
        guard let rec = record(for: id.rawValue) else { return }
        rec.activeStartedAt = nil
        do {
            try context.save()
        } catch {
            assertionFailure("RouteStore.pauseRoute failed: \(error)")
        }
        postChange(routeId: id.rawValue)
    }

    /// Resume a paused route — re-stamps `activeStartedAt` so the loader
    /// finds it again. `currentStopIndex` and completed list are preserved
    /// from before the pause.
    public func resumeRoute(_ id: RouteId, at date: Date = Date()) {
        guard let rec = record(for: id.rawValue) else { return }
        rec.activeStartedAt = date
        do {
            try context.save()
        } catch {
            assertionFailure("RouteStore.resumeRoute failed: \(error)")
        }
        postChange(routeId: id.rawValue)
    }

    /// Finish the route — clears active progress fields so subsequent
    /// queries no longer pick it up as the resume candidate. The route
    /// itself stays in the store for history.
    public func completeRoute(_ id: RouteId) {
        guard let rec = record(for: id.rawValue) else { return }
        rec.activeStartedAt = nil
        rec.currentStopIndex = nil
        rec.completedStopIdsBlob = nil
        do {
            try context.save()
        } catch {
            assertionFailure("RouteStore.completeRoute failed: \(error)")
        }
        postChange(routeId: id.rawValue)
    }

    /// Snapshot of any currently-active route, for cold-start recovery.
    /// Returns the route value, its current stop index, and the set of
    /// already-completed experience ids. When multiple routes are
    /// marked active (shouldn't happen normally, but defensive against
    /// orphan rows) the most-recently-started one wins.
    public func loadActiveRoute() -> (route: Route, stopIndex: Int, completedIds: Set<String>)? {
        let descriptor = FetchDescriptor<RouteRecord>(
            predicate: #Predicate { $0.activeStartedAt != nil }
        )
        guard let records = try? context.fetch(descriptor), !records.isEmpty else {
            return nil
        }
        let sorted = records.sorted { a, b in
            (a.activeStartedAt ?? .distantPast) > (b.activeStartedAt ?? .distantPast)
        }
        guard let rec = sorted.first,
              let index = rec.currentStopIndex else { return nil }
        var completed: Set<String> = []
        if let blob = rec.completedStopIdsBlob,
           let decoded = try? JSONDecoder().decode([String].self, from: blob) {
            completed = Set(decoded)
        }
        return (rec.asValue, index, completed)
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
