import Foundation
import SwiftData
import Observation
import UIKit

/// Outbox sync (Epic E US-031). Local mutations enqueue
/// `PendingSyncRecord` rows; this service drains them to Supabase
/// every 30 seconds while in foreground and on willEnterForeground.
///
/// Inbound pull: on each flush cycle we also GET rows from Supabase
/// where `updated_at > lastPulledAt` and merge them into SwiftData
/// using last-write-wins (compare `updated_at`; ties broken by lex
/// `device_id` so both devices converge to the same winner).
///
/// Design choices:
/// - The outbox is the single source of truth for "what needs to
///   reach the server." Direct sync calls aren't allowed; everything
///   goes through `enqueue(...)`. This makes the sync layer fully
///   resumable across app kills.
/// - When `FF_BACKEND_SYNC` is off, `enqueue` still records rows
///   (cheap; lets us flip the flag on later without losing pre-flag
///   activity) but `flush`/`pull` are no-ops.
/// - Failures bump retryCount; we never throw out a row from the
///   outbox in v1.0 (dead-letter handling is post-launch).
@MainActor
@Observable
public final class SyncService {
    public static let shared = SyncService()

    public private(set) var isFlushing: Bool = false
    public private(set) var lastFlushAt: Date?
    public private(set) var pendingCount: Int = 0

    /// #87: dead-letter threshold for PendingSyncRecord. Rows that fail
    /// more than this many times are dropped + Sentry-reported. Prevents
    /// a single broken payload (bad schema, deleted FK, banned table)
    /// from blocking the head of the outbox forever and burning a round
    /// trip on every flush. 10 retries × exponential foreground backoff
    /// (~minutes) gives genuine transient failures plenty of room before
    /// we give up; the metric is "tries", not "wall-clock minutes".
    private static let retryCeiling = 10

    nonisolated(unsafe) private var foregroundTimer: Timer?
    nonisolated(unsafe) private var foregroundObserver: NSObjectProtocol?

    // MARK: - lastPulledAt (UserDefaults, keyed per-table)

    private static func lastPulledAtKey(for table: String) -> String {
        "sc.sync.lastPulledAt.\(table)"
    }

    static func lastPulledAt(for table: String) -> Date? {
        let ts = UserDefaults.standard.double(forKey: lastPulledAtKey(for: table))
        guard ts > 0 else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    static func setLastPulledAt(_ date: Date, for table: String) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastPulledAtKey(for: table))
    }

    // MARK: - Dependency injection (production uses singletons; tests inject mocks)

    // The client and device-id supplier are injectable so unit tests
    // can replace them without touching any singleton.
    var supabaseClient: any SupabaseClientProtocol = SupabaseClient.shared
    var deviceID: () -> String = { DeviceIdentityService.shared.deviceID }

    // Error reporter is injectable so tests can assert that encode/save
    // failures are surfaced instead of being silently swallowed (US-002).
    var reporter: any SyncErrorReporting = LiveSyncErrorReporter()

    /// Beta-P0-C: replacement for `try? context.save()` throughout the
    /// sync layer. SwiftData save failures used to drop completions,
    /// favorites, and itinerary merges silently — a write that vanishes
    /// is the worst class of bug because the user trusts the spinner.
    /// We now surface every save failure to Sentry tagged by the op so
    /// the on-call can see *what* was lost, not just *that* something
    /// was lost.
    fileprivate func saveOrReport(_ context: ModelContext, op: String) {
        do {
            try context.save()
        } catch {
            reporter.capture(error, context: "SyncService.\(op).save", payload: nil)
        }
    }

    init() {}

    deinit {
        foregroundTimer?.invalidate()
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Wire up the 30-second timer + foreground observer. Idempotent.
    /// Called once from `SoloCompassApp.onAppear`.
    public func start() {
        guard foregroundTimer == nil else { return }
        foregroundTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor [weak self] in await self?.flushAndPull() }
        }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor [weak self] in await self?.flushAndPull() }
        }
    }

    // MARK: - Enqueue

    /// Enqueue a payload for `tableName`. Caller is responsible for
    /// constructing a body the PostgREST endpoint understands. The
    /// payload is stored verbatim (no re-serialization on flush).
    public func enqueue(
        tableName: String,
        operation: String,
        payload: any Encodable,
        context: ModelContext
    ) {
        // Encoding or persisting the outbox row must never fail silently — a
        // dropped row means a user's completion / favorite / route-join request
        // vanishes. Report to Sentry instead of swallowing via `try?`.
        let data: Data
        do {
            data = try JSONEncoder.iso8601Encoder.encode(AnyEncodable(payload))
        } catch {
            reporter.capture(error, context: "SyncService.enqueue", payload: tableName)
            return
        }
        context.insert(
            PendingSyncRecord(tableName: tableName, operation: operation, payloadJSON: data)
        )
        do {
            try context.save()
        } catch {
            reporter.capture(error, context: "SyncService.enqueue", payload: tableName)
        }
        refreshCount(context: context)
    }

    // MARK: - Flush + Pull (combined cycle)

    /// Drain the outbox then pull inbound changes. No-op when
    /// `FF_BACKEND_SYNC` is off.
    public func flushAndPull(context override: ModelContext? = nil) async {
        let ctx = override ?? ModelContext(SoloCompassModelContainer.shared)
        await flush(context: ctx)
        await pull(context: ctx)
    }

    // MARK: - Flush (outbound)

    /// Drain the outbox. Returns the number of rows successfully
    /// sent + deleted. No-op when `FF_BACKEND_SYNC` is off.
    @discardableResult
    public func flush(context override: ModelContext? = nil) async -> Int {
        guard FeatureFlags.backendSync else { return 0 }
        guard !isFlushing else { return 0 }
        isFlushing = true
        defer { isFlushing = false; lastFlushAt = Date() }

        let context = override ?? ModelContext(SoloCompassModelContainer.shared)
        let descriptor = FetchDescriptor<PendingSyncRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        guard let rows = try? context.fetch(descriptor), !rows.isEmpty else {
            refreshCount(context: context)
            return 0
        }

        var sent = 0
        for row in rows {
            let result: Result<Data, SupabaseClient.SupabaseError>
            switch row.operation {
            case "upsert":
                result = await supabaseClient.post(table: row.tableName, body: row.payloadJSON)
            default:
                row.retryCount += 1
                // #87: unrecognized op should also hit the dead-letter
                // ceiling so a corrupt row doesn't block forever.
                if row.retryCount > Self.retryCeiling { context.delete(row) }
                continue
            }
            switch result {
            case .success:
                context.delete(row)
                sent += 1
            case .failure:
                row.retryCount += 1
                // #87: dead-letter rows that have failed too many times so
                // the queue can actually drain. A single broken payload
                // (bad schema, deleted FK, etc) used to sit at the head
                // forever, wasting a network round-trip on every flush and
                // starving legitimate pending rows. Surface to Sentry so a
                // systematic schema drift is visible, not a silent loss.
                if row.retryCount > Self.retryCeiling {
                    SentryService.capture(
                        message: "PendingSyncRecord dead-lettered after \(row.retryCount) retries",
                        level: .warning,
                        context: [
                            "table": row.tableName,
                            "operation": row.operation,
                            "retry_count": row.retryCount
                        ]
                    )
                    context.delete(row)
                }
            }
        }
        saveOrReport(context, op: "flush")
        refreshCount(context: context)
        return sent
    }

    // MARK: - Itinerary sync payload (US-007)

    /// Outbound payload for the `itineraries` table. Mirrors the Supabase
    /// column set defined in `0003_companion.sql`. `is_deleted` acts as a
    /// soft-delete tombstone so the row can be pulled back on other devices.
    public struct SyncItineraryPayload: Encodable {
        public let id: String
        public let user_id: String
        public let owner_id: String
        public let title: String
        public let city_code: String
        public let start_date: String
        public let end_date: String
        public let experience_ids: [String]
        public let note: String?
        public let open_to_companions: Bool
        public let is_deleted: Bool
        public let device_id: String
        public let created_at: String
        public let updated_at: String
    }

    // MARK: - Pull (inbound)

    /// Pull rows updated since `lastPulledAt` from Supabase and merge
    /// them into SwiftData with last-write-wins semantics. No-op when
    /// `FF_BACKEND_SYNC` is off.
    ///
    /// LWW rule: keep the row whose `updated_at` is later. On ties,
    /// the row whose `device_id` sorts lexicographically later wins
    /// — both devices apply the same deterministic rule so they converge.
    ///
    /// US-035: also pulls `aggregated_solo_score` + `signal_count` from
    /// `synthesized_experiences` for any experiences currently in the local
    /// store and merges the values into `ExperienceRecord` so
    /// `ExperienceRepository.aggregatedSoloScore()` can prefer server data.
    public func pull(context: ModelContext? = nil) async {
        guard FeatureFlags.backendSync else { return }
        let ctx = context ?? ModelContext(SoloCompassModelContainer.shared)
        let myDeviceID = deviceID()

        await pullTable(
            "user_completions",
            context: ctx,
            deviceID: myDeviceID,
            merge: mergeCompletion
        )
        await pullTable(
            "user_favorites",
            context: ctx,
            deviceID: myDeviceID,
            merge: mergeFavorite
        )
        if FeatureFlags.companion {
            await pullTable(
                "itineraries",
                context: ctx,
                deviceID: myDeviceID,
                merge: mergeItinerary
            )
        }
        await pullAggregatedSoloScores(context: ctx)
    }

    // MARK: - Internals

    private func pullTable(
        _ table: String,
        context: ModelContext,
        deviceID: String,
        merge: (Data, ModelContext, String) async -> Void
    ) async {
        let since = Self.lastPulledAt(for: table)
        var query = [URLQueryItem(name: "select", value: "*")]
        if let since {
            // PostgREST filter: updated_at > since (ISO8601 string)
            let iso = ISO8601DateFormatter().string(from: since)
            query.append(URLQueryItem(name: "updated_at", value: "gt.\(iso)"))
        }

        let result = await supabaseClient.get(table: table, query: query)
        guard case .success(let data) = result, !data.isEmpty else { return }

        await merge(data, context, deviceID)

        // Advance the cursor to now so next pull only fetches deltas.
        Self.setLastPulledAt(Date(), for: table)
    }

    /// Decode a `Decodable` array off the main actor. `SyncService` is
    /// `@MainActor`, so a plain `JSONDecoder().decode(...)` in a merge helper ran
    /// on the main thread; a large pull (hundreds of rows) then decoded on the
    /// same thread that drives the UI, right as the app returned to foreground.
    /// The decoded rows are value types (`Sendable`), so the decode has no
    /// business touching the main actor — hop it to a detached task.
    nonisolated static func decodeRows<T: Decodable & Sendable>(
        _ type: [T].Type,
        from data: Data
    ) async -> [T]? {
        await Task.detached(priority: .userInitiated) {
            try? JSONDecoder().decode(type, from: data)
        }.value
    }

    // MARK: - LWW merge helpers

    private func mergeCompletion(_ data: Data, _ context: ModelContext, _ myDeviceID: String) async {
        guard let rows = await Self.decodeRows([RemoteCompletion].self, from: data) else {
            reporter.capture(
                SyncDecodeError.completions,
                context: "SyncService.mergeCompletion",
                payload: "user_completions"
            )
            return
        }
        let formatter = ISO8601DateFormatter()

        // Batch-fetch every local completion ONCE, key it by (experienceId,
        // completedAt), and diff the remote rows against that set in memory.
        // The previous code ran a `#Predicate` fetch per row — a SQLite round
        // trip on the main thread for each of potentially hundreds of pulled
        // rows. Completions are immutable once written, so "does this key
        // already exist?" is the only question, and one fetch answers it for
        // the whole batch.
        let allLocal = (try? context.fetch(FetchDescriptor<UserCompletionRecord>())) ?? []
        var seen = Set(allLocal.map { CompletionKey(experienceId: $0.experienceId, completedAt: $0.completedAt) })

        var didInsert = false
        for row in rows {
            guard let completedAt = formatter.date(from: row.completed_at) else { continue }
            let key = CompletionKey(experienceId: row.experience_id, completedAt: completedAt)
            // De-dupe against both existing rows AND earlier rows in this same
            // batch, so a remote payload with duplicates inserts at most once.
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            // No local record — remote wins by default (LWW: remote is newer
            // than lastPulledAt by definition of the query filter).
            context.insert(
                UserCompletionRecord(experienceId: row.experience_id, completedAt: completedAt)
            )
            didInsert = true
        }
        _ = myDeviceID  // completions are immutable; no per-row LWW / device tiebreak.
        if didInsert {
            saveOrReport(context, op: "mergeCompletion")
        }
    }

    /// Identity key for a completion row — completions are unique by
    /// (experienceId, completedAt), so this is the natural de-dupe key.
    private struct CompletionKey: Hashable {
        let experienceId: String
        let completedAt: Date
    }

    private func mergeFavorite(_ data: Data, _ context: ModelContext, _ myDeviceID: String) async {
        guard let rows = await Self.decodeRows([RemoteFavorite].self, from: data) else {
            reporter.capture(
                SyncDecodeError.favorites,
                context: "SyncService.mergeFavorite",
                payload: "user_favorites"
            )
            return
        }
        let formatter = ISO8601DateFormatter()

        // Batch-fetch every local favorite ONCE and index it by experienceId
        // so the per-row LWW below is a dictionary lookup, not a `#Predicate`
        // SQLite round trip per remote row (the old cost, on the main thread).
        let allLocal = (try? context.fetch(FetchDescriptor<UserFavoriteRecord>())) ?? []
        var localByExp = Dictionary(
            allLocal.map { ($0.experienceId, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for row in rows {
            guard let updatedAt = formatter.date(from: row.updated_at) else { continue }

            let remoteIsFavorited = row.favorited_at != nil
            let remoteDeviceID = row.device_id ?? ""

            if let local = localByExp[row.experience_id] {
                // LWW: compare updated_at. On tie, lex device_id decides.
                let localUpdatedAt = local.favoritedAt  // best proxy for local write time
                let remoteWins: Bool
                if updatedAt > localUpdatedAt {
                    remoteWins = true
                } else if updatedAt == localUpdatedAt {
                    remoteWins = remoteDeviceID > myDeviceID
                } else {
                    remoteWins = false
                }

                if remoteWins {
                    if remoteIsFavorited {
                        if let favAt = row.favorited_at {
                            local.favoritedAt = formatter.date(from: favAt) ?? local.favoritedAt
                        }
                    } else {
                        context.delete(local)
                        localByExp[row.experience_id] = nil
                    }
                }
            } else if remoteIsFavorited {
                // No local record and remote says it's favorited — insert.
                let favoritedAt = row.favorited_at.flatMap { formatter.date(from: $0) } ?? updatedAt
                let record = UserFavoriteRecord(experienceId: row.experience_id, favoritedAt: favoritedAt)
                context.insert(record)
                // Keep the index consistent so a later remote row for the same
                // experience in this batch hits the LWW branch, not re-insert.
                localByExp[row.experience_id] = record
            }
            // Remote says unfavorited and we have no local row — already in sync.
        }
        saveOrReport(context, op: "mergeFavorite")
    }

    // MARK: - Itinerary LWW merge (US-007)

    private func mergeItinerary(_ data: Data, _ context: ModelContext, _ myDeviceID: String) async {
        guard let rows = await Self.decodeRows([RemoteItinerary].self, from: data) else {
            reporter.capture(
                SyncDecodeError.itineraries,
                context: "SyncService.mergeItinerary",
                payload: "itineraries"
            )
            return
        }
        let formatter = ISO8601DateFormatter()

        // Batch-fetch every local itinerary ONCE, keyed by id, so the per-row
        // LWW below is a dictionary lookup instead of a `#Predicate` SQLite
        // round trip per remote row on the main thread.
        let allLocal = (try? context.fetch(FetchDescriptor<ItineraryRecord>())) ?? []
        var localById = Dictionary(
            allLocal.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for row in rows {
            guard let remoteUpdatedAt = formatter.date(from: row.updated_at) else { continue }
            let remoteDeviceID = row.device_id ?? ""

            if let local = localById[row.id] {
                // LWW: compare updated_at. On tie, lex device_id decides.
                guard let localUpdatedAt = formatter.date(from: local.updatedAt) else { continue }
                let remoteWins: Bool
                if remoteUpdatedAt > localUpdatedAt {
                    remoteWins = true
                } else if remoteUpdatedAt == localUpdatedAt {
                    remoteWins = remoteDeviceID > myDeviceID
                } else {
                    remoteWins = false
                }

                if remoteWins {
                    if row.is_deleted {
                        context.delete(local)
                        localById[row.id] = nil
                    } else {
                        local.title = row.title
                        local.cityCode = row.city_code
                        local.startDate = row.start_date
                        local.endDate = row.end_date
                        local.experienceIdsBlob = encodeExperienceIDs(row.experience_ids)
                            ?? local.experienceIdsBlob
                        local.note = row.note
                        local.openToCompanions = row.open_to_companions
                        local.updatedAt = row.updated_at
                    }
                }
            } else if !row.is_deleted {
                // No local record and remote is not a tombstone — insert.
                let blob = encodeExperienceIDs(row.experience_ids) ?? Data()
                let record = ItineraryRecord(
                    id: row.id,
                    ownerId: row.owner_id,
                    title: row.title,
                    cityCode: row.city_code,
                    startDate: row.start_date,
                    endDate: row.end_date,
                    experienceIdsBlob: blob,
                    note: row.note,
                    openToCompanions: row.open_to_companions,
                    createdAt: row.created_at,
                    updatedAt: row.updated_at
                )
                context.insert(record)
                localById[row.id] = record
            }
        }
        saveOrReport(context, op: "mergeItinerary")
    }

    // MARK: - US-035: Pull aggregated Solo Scores

    /// Fetch `aggregated_solo_score` and `signal_count` from
    /// `synthesized_experiences` for every experience currently in the local
    /// store. Merges the values into `ExperienceRecord` so the repository's
    /// `aggregatedSoloScore()` can prefer authoritative community data over
    /// local-only survey blends when `signal_count >= 3`.
    ///
    /// We pull all IDs in one GET (select=id,aggregated_solo_score,signal_count)
    /// rather than a per-experience call to keep network overhead low.
    private func pullAggregatedSoloScores(context: ModelContext) async {
        let descriptor = FetchDescriptor<ExperienceRecord>()
        guard let records = try? context.fetch(descriptor), !records.isEmpty else { return }

        let query: [URLQueryItem] = [
            URLQueryItem(name: "select", value: "id,aggregated_solo_score,signal_count"),
        ]
        let result = await supabaseClient.get(table: "synthesized_experiences", query: query)
        guard case .success(let data) = result, !data.isEmpty else { return }

        struct AggRow: Decodable {
            let id: String
            let aggregated_solo_score: Double?
            let signal_count: Int?
        }
        let rows: [AggRow]
        do {
            rows = try JSONDecoder().decode([AggRow].self, from: data)
        } catch {
            reporter.capture(error, context: "SyncService.pullAggregatedSoloScores", payload: "synthesized_experiences")
            return
        }

        let lookup = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        var changed = false
        for record in records {
            guard let row = lookup[record.id],
                  let score = row.aggregated_solo_score,
                  let count = row.signal_count else { continue }
            if record.serverAggregatedSoloScore != score || record.serverSignalCount != count {
                record.serverAggregatedSoloScore = score
                record.serverSignalCount = count
                changed = true
            }
        }
        if changed { saveOrReport(context, op: "pullAggregatedSoloScores") }
    }

    /// Encode an experience-id list to a blob, reporting (rather than swallowing)
    /// any encoding failure. Returns nil on failure so callers can fall back.
    private func encodeExperienceIDs(_ ids: [String]) -> Data? {
        do {
            return try JSONEncoder().encode(ids)
        } catch {
            reporter.capture(error, context: "SyncService.encodeExperienceIDs", payload: nil)
            return nil
        }
    }

    private func refreshCount(context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<PendingSyncRecord>())) ?? 0
        self.pendingCount = count
    }
}

// MARK: - AnyEncodable wrapper for heterogeneous payloads

private struct AnyEncodable: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

// MARK: - Remote row shapes (file-scope so they're Sendable across the
// off-actor decode). Field names mirror the PostgREST snake_case columns.

struct RemoteCompletion: Decodable, Sendable {
    let experience_id: String
    let completed_at: String      // ISO8601
    let updated_at: String        // ISO8601
    let device_id: String?
}

struct RemoteFavorite: Decodable, Sendable {
    let experience_id: String
    let favorited_at: String?     // nil means unfavorited (tombstone)
    let updated_at: String        // ISO8601
    let device_id: String?
}

struct RemoteItinerary: Decodable, Sendable {
    let id: String
    let owner_id: String
    let title: String
    let city_code: String
    let start_date: String
    let end_date: String
    let experience_ids: [String]
    let note: String?
    let open_to_companions: Bool
    let is_deleted: Bool
    let device_id: String?
    let created_at: String
    let updated_at: String
}

/// The off-actor decode helper returns nil on failure (it can't carry the
/// thrown error across the actor hop cheaply), so we report a typed marker
/// instead — enough for Sentry to see *which* table's payload failed to decode.
enum SyncDecodeError: Error {
    case completions
    case favorites
    case itineraries
}
