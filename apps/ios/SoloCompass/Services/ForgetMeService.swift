import Foundation
import SwiftData
import os

/// One-tap "Forget me" — atomically clears every on-device table that carries
/// personal signal (Phase 2 P2.0 #204).
///
/// Scope by table:
/// - `VisitRecord`         — passive geofence archive
/// - `TasteProfile`        — vibe embedding + descriptors
/// - `TimeCapsule`         — buried notes/voice/photos
/// - `AgentMemorySnapshot` — chat memory summary
///
/// Not scoped:
/// - Experience seed/pool (public content)
/// - Chat sessions/messages (kept — deleting mid-turn breaks in-flight UI)
///   → users clear chat via ChatHistoryStore's per-session delete
/// - Favorites (users would want a separate confirm — a different button)
///
/// This service does NOT touch iCloud/Supabase — the four tables above never
/// leave the device (PRIVACY.md #X30 on-device commitment). Nothing to unsync.
@MainActor
public final class ForgetMeService {

    public static let shared = ForgetMeService()

    private static let log = OSLog(subsystem: "com.solocompass.app", category: "ForgetMe")

    private var modelContainer: ModelContainer?

    private init() {}

    /// Injected once at app bootstrap (mirrors `VisitTrackingService.setModelContainer`).
    public func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }

    /// Test-only overload: bind a specific container without the shared singleton.
    /// Enables hermetic in-memory ModelContainer per test case.
    #if DEBUG
    public convenience init(modelContainer: ModelContainer) {
        self.init()
        self.modelContainer = modelContainer
    }
    #endif

    /// Result of a `forgetEverything()` call, so a settings screen can report
    /// exactly what was wiped and any failures rather than a silent success.
    public struct Result: Equatable, Sendable {
        public var visitRecordsDeleted: Int
        public var tasteProfilesDeleted: Int
        public var timeCapsulesDeleted: Int
        public var agentMemorySnapshotsDeleted: Int
        public var didSave: Bool

        public var totalDeleted: Int {
            visitRecordsDeleted + tasteProfilesDeleted +
            timeCapsulesDeleted + agentMemorySnapshotsDeleted
        }
    }

    /// Delete every row from the four personal-signal tables and save.
    ///
    /// - Returns: per-table row counts + whether the save succeeded. When the
    ///   ModelContainer is missing, returns all-zero result with `didSave=false`
    ///   and logs — never throws, so a Settings button never hangs on an alert.
    @discardableResult
    public func forgetEverything() -> Result {
        guard let container = modelContainer else {
            os_log("ForgetMe skipped — no ModelContainer bound",
                   log: Self.log, type: .error)
            return Result(visitRecordsDeleted: 0, tasteProfilesDeleted: 0,
                          timeCapsulesDeleted: 0, agentMemorySnapshotsDeleted: 0,
                          didSave: false)
        }
        let context = ModelContext(container)
        let visits    = deleteAll(VisitRecord.self,         in: context)
        let tastes    = deleteAll(TasteProfile.self,        in: context)
        let capsules  = deleteAll(TimeCapsule.self,         in: context)
        let memories  = deleteAll(AgentMemorySnapshot.self, in: context)

        var saved = true
        do {
            try context.save()
        } catch {
            saved = false
            os_log("ForgetMe save failed: %{public}@",
                   log: Self.log, type: .error, String(describing: error))
        }
        os_log("ForgetMe cleared v=%d t=%d c=%d m=%d saved=%{public}@",
               log: Self.log, type: .info, visits, tastes, capsules, memories,
               saved ? "true" : "false")
        return Result(
            visitRecordsDeleted:         visits,
            tasteProfilesDeleted:        tastes,
            timeCapsulesDeleted:         capsules,
            agentMemorySnapshotsDeleted: memories,
            didSave:                     saved
        )
    }

    private func deleteAll<T: PersistentModel>(
        _ type: T.Type,
        in context: ModelContext
    ) -> Int {
        do {
            let rows = try context.fetch(FetchDescriptor<T>())
            for row in rows { context.delete(row) }
            return rows.count
        } catch {
            os_log("ForgetMe fetch(%{public}@) failed: %{public}@",
                   log: Self.log, type: .error,
                   String(describing: T.self), String(describing: error))
            return 0
        }
    }
}
