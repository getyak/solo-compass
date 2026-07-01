import Foundation
import Observation
import SwiftData
import os

/// P2.4 #243: CRUD + region-matching wrapper around the `TimeCapsule` @Model.
///
/// Responsibilities:
/// 1. **Bury** a new capsule from the compose flow (P2.4 #241).
/// 2. **Fetch ripe capsules** on app launch + region enter — i.e. rows
///    where `!opened && scheduledFor <= now`. The predicate lives here so
///    the query text stays consistent across LiveActivity trigger
///    (P2.2 #223), ArchiveView "my capsules" section (P2.4 #245), and
///    year-end proactive nudge (P2.4 #244).
/// 3. **Mark opened** after `CapsuleOpenView` finishes the unwrap
///    animation (P2.4 #242) so the capsule doesn't re-surface next launch.
/// 4. **Answer queries** grouped by state ({buried unripe, ripe unopened,
///    opened}) so the Archive tab can render three sections cleanly.
///
/// Failure semantics: every method is best-effort. Missing container is
/// os_log'd + returns `[]` / `false`. SwiftData throws are logged and
/// swallowed — the caller sees the pre-throw state (empty / previous
/// value) instead of an error. This matches VisitTrackingService's
/// contract so the UI never has to show an error toast for capsule
/// persistence.
@MainActor
@Observable
public final class CapsuleStore {

    public static let shared = CapsuleStore(modelContainer: nil)

    private var modelContainer: ModelContainer?
    private let log = OSLog(subsystem: "com.solocompass.app", category: "CapsuleStore")

    public init(modelContainer: ModelContainer?) {
        self.modelContainer = modelContainer
    }

    /// Wire the SwiftData container after init — same pattern as
    /// `VisitTrackingService` / `TasteUpdateService` / `MemoryDigestService`.
    public func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }

    // MARK: - Bury

    /// Insert a new capsule. Returns the row's id on success, nil on any
    /// failure (missing container / encode error / save error — each
    /// logged).
    @discardableResult
    public func bury(
        experienceId: String,
        contentType: String,
        contentBlob: Data,
        context: CapsuleContext?,
        monthsFromNow: Int,
        now: Date = Date(),
        calendar: Calendar = Calendar.current
    ) -> UUID? {
        guard let container = modelContainer else {
            os_log("CapsuleStore: no modelContainer attached", log: log, type: .error)
            return nil
        }
        let ctx = ModelContext(container)

        guard let scheduledFor = calendar.date(byAdding: .month, value: monthsFromNow, to: now) else {
            os_log("CapsuleStore: could not schedule (%d months from now)", log: log, type: .error, monthsFromNow)
            return nil
        }

        let contextBlob: Data?
        do {
            contextBlob = try context?.encoded()
        } catch {
            os_log("CapsuleStore: context encode failed %{public}@", log: log, type: .error, String(describing: error))
            contextBlob = nil
        }

        let row = TimeCapsule(
            experienceId: experienceId,
            createdAt: now,
            scheduledFor: scheduledFor,
            contentType: contentType,
            contentBlob: contentBlob,
            contextBlob: contextBlob
        )
        ctx.insert(row)
        do {
            try ctx.save()
            return row.id
        } catch {
            os_log("CapsuleStore: bury save failed %{public}@", log: log, type: .error, String(describing: error))
            return nil
        }
    }

    // MARK: - Queries

    /// Ripe = unopened AND scheduledFor already passed. Fired every
    /// launch (P2.4 #243 acceptance) and on region enter.
    public func ripeCapsules(now: Date = Date()) -> [TimeCapsule] {
        guard let container = modelContainer else { return [] }
        let ctx = ModelContext(container)
        do {
            let descriptor = FetchDescriptor<TimeCapsule>(
                predicate: #Predicate { !$0.opened && $0.scheduledFor <= now }
            )
            return try ctx.fetch(descriptor)
        } catch {
            os_log("CapsuleStore: ripe fetch failed %{public}@", log: log, type: .error, String(describing: error))
            return []
        }
    }

    /// Ripe capsules whose experience matches the region the user just
    /// entered.
    public func ripeCapsules(atExperienceId experienceId: String, now: Date = Date()) -> [TimeCapsule] {
        ripeCapsules(now: now).filter { $0.experienceId == experienceId }
    }

    /// Buried but not yet ripe — surfaced in Archive "our secret" list.
    public func buriedUnripeCapsules(now: Date = Date()) -> [TimeCapsule] {
        guard let container = modelContainer else { return [] }
        let ctx = ModelContext(container)
        do {
            let descriptor = FetchDescriptor<TimeCapsule>(
                predicate: #Predicate { !$0.opened && $0.scheduledFor > now }
            )
            return try ctx.fetch(descriptor)
        } catch {
            os_log("CapsuleStore: buried fetch failed %{public}@", log: log, type: .error, String(describing: error))
            return []
        }
    }

    /// Opened history — the archive "already unwrapped" list.
    public func openedCapsules() -> [TimeCapsule] {
        guard let container = modelContainer else { return [] }
        let ctx = ModelContext(container)
        do {
            let descriptor = FetchDescriptor<TimeCapsule>(
                predicate: #Predicate { $0.opened }
            )
            return try ctx.fetch(descriptor)
        } catch {
            os_log("CapsuleStore: opened fetch failed %{public}@", log: log, type: .error, String(describing: error))
            return []
        }
    }

    /// Total row count — used by year-end review nudge ("you buried N capsules
    /// this year, X ripen next year").
    public func buriedCount(inYear year: Int, calendar: Calendar = Calendar.current) -> Int {
        guard let container = modelContainer else { return 0 }
        let ctx = ModelContext(container)
        do {
            let rows = try ctx.fetch(FetchDescriptor<TimeCapsule>())
            return rows.filter { calendar.component(.year, from: $0.createdAt) == year }.count
        } catch {
            os_log("CapsuleStore: buriedCount failed %{public}@", log: log, type: .error, String(describing: error))
            return 0
        }
    }

    // MARK: - Mutations

    /// Flip `opened = true` on the given capsule. Returns whether the row
    /// was found + updated.
    @discardableResult
    public func markOpened(_ id: UUID) -> Bool {
        guard let container = modelContainer else { return false }
        let ctx = ModelContext(container)
        do {
            let descriptor = FetchDescriptor<TimeCapsule>(
                predicate: #Predicate { $0.id == id }
            )
            guard let row = try ctx.fetch(descriptor).first else { return false }
            row.opened = true
            try ctx.save()
            return true
        } catch {
            os_log("CapsuleStore: markOpened failed %{public}@", log: log, type: .error, String(describing: error))
            return false
        }
    }
}
