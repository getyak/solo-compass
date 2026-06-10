import Foundation
import SwiftData

/// ISO 8601 UTC timestamp for "now". File-level (non-isolated) so the nested
/// seed descriptors can call it synchronously under strict concurrency.
private func travelerNoteNowISO() -> String {
    ISO8601DateFormatter().string(from: Date())
}

/// ISO 8601 UTC timestamp `days` in the past — gives seeded notes believable
/// relative times ("3 天前") without absolute dates baked into source.
private func travelerNoteISODaysAgo(_ days: Int) -> String {
    let date = Date().addingTimeInterval(TimeInterval(-days) * 86_400)
    return ISO8601DateFormatter().string(from: date)
}

/// SwiftData-backed persistence for the traveler co-build layer: per-experience
/// notes (`TravelerNoteRecord`) and pending field corrections
/// (`PlaceCorrectionRecord`). Mirrors `ChatHistoryStore`: `@MainActor` (the
/// `ModelContext` is single-actor), a `didChange` notification after mutations,
/// and a `convenience init()` over the shared container plus a DI `init(context:)`
/// for tests.
///
/// On first run it seeds a small set of demonstration notes/corrections for the
/// known seed POIs so the section isn't empty out of the box; seeding is marked
/// per-experience-id idempotent so it runs at most once per place.
@Observable
@MainActor
public final class TravelerNoteStore {
    /// Posted after any successful mutation so views can refresh without holding
    /// a strong reference to the store.
    @ObservationIgnored
    public static let didChange = Notification.Name("SoloCompass.TravelerNoteStore.didChange")

    @ObservationIgnored
    let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Convenience init using the shared on-disk container.
    public convenience init() {
        self.init(context: ModelContext(SoloCompassModelContainer.shared))
    }

    // MARK: - Notes: fetch

    /// Notes for an experience, AI-adopted and most-confirmed first, then newest.
    /// `SortDescriptor` can't sort on a `Bool` key path, so the AI-adopted
    /// priority is applied in Swift after the store-side confirm/date sort.
    public func notes(for experienceId: String) -> [TravelerNote] {
        seedIfNeeded(for: experienceId)
        let descriptor = FetchDescriptor<TravelerNoteRecord>(
            predicate: #Predicate { $0.experienceId == experienceId },
            sortBy: [
                SortDescriptor(\.confirms, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse),
            ]
        )
        let records = (try? context.fetch(descriptor)) ?? []
        // Stable partition: AI-adopted first, each group keeping the store's
        // confirm/date order (Swift's `sorted` isn't guaranteed stable).
        let adopted = records.filter { $0.aiAdopted }
        let rest = records.filter { !$0.aiAdopted }
        return (adopted + rest).map(\.asValue)
    }

    // MARK: - Notes: mutate

    /// Insert a new note authored by the current user ("你"). Returns the value
    /// that was stored so the caller can optimistically prepend it.
    @discardableResult
    public func addNote(
        experienceId: String,
        text: String,
        kind: TravelerNote.Kind = .experience
    ) -> TravelerNote? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let note = TravelerNote(
            id: "nu_\(UUID().uuidString)",
            experienceId: experienceId,
            authorInitial: NSLocalizedString("notes.author.you", comment: "Current-user author initial"),
            authorColor: nil,            // nil → accent disc
            text: trimmed,
            kind: kind,
            createdAt: travelerNoteNowISO(),
            confirms: 0,
            aiAdopted: false,
            isMine: true
        )
        context.insert(TravelerNoteRecord(from: note))
        save()
        return note
    }

    /// Increment a note's confirm count by one. No-op if the note is missing.
    public func confirmNote(id: String) {
        guard let record = noteRecord(id) else { return }
        record.confirms += 1
        save()
    }

    // MARK: - Corrections

    /// Pending corrections for an experience (resolved ones are filtered out).
    public func corrections(for experienceId: String) -> [PlaceCorrection] {
        seedIfNeeded(for: experienceId)
        let pending = PlaceCorrection.Status.pending.rawValue
        let descriptor = FetchDescriptor<PlaceCorrectionRecord>(
            predicate: #Predicate { $0.experienceId == experienceId && $0.status == pending },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor))?.map(\.asValue) ?? []
    }

    /// Mark a correction accepted (folds into the record) — persisted so it stays
    /// resolved across launches.
    public func acceptCorrection(id: String) {
        setCorrectionStatus(id: id, status: .accepted)
    }

    /// Mark a correction dismissed ("不准确").
    public func dismissCorrection(id: String) {
        setCorrectionStatus(id: id, status: .dismissed)
    }

    // MARK: - Private

    private func setCorrectionStatus(id: String, status: PlaceCorrection.Status) {
        guard let record = correctionRecord(id) else { return }
        record.status = status.rawValue
        save()
    }

    private func noteRecord(_ id: String) -> TravelerNoteRecord? {
        let descriptor = FetchDescriptor<TravelerNoteRecord>(
            predicate: #Predicate { $0.id == id }
        )
        return (try? context.fetch(descriptor))?.first
    }

    private func correctionRecord(_ id: String) -> PlaceCorrectionRecord? {
        let descriptor = FetchDescriptor<PlaceCorrectionRecord>(
            predicate: #Predicate { $0.id == id }
        )
        return (try? context.fetch(descriptor))?.first
    }

    private func save() {
        do {
            try context.save()
        } catch {
            assertionFailure("TravelerNoteStore.save failed: \(error)")
            return
        }
        NotificationCenter.default.post(name: TravelerNoteStore.didChange, object: self)
    }

    // MARK: - Seeding

    /// True once any record for `experienceId` exists — used as the idempotency
    /// marker so demo content seeds at most once per place.
    private func hasAnyRecords(for experienceId: String) -> Bool {
        var noteDesc = FetchDescriptor<TravelerNoteRecord>(
            predicate: #Predicate { $0.experienceId == experienceId }
        )
        noteDesc.fetchLimit = 1
        if let count = try? context.fetchCount(noteDesc), count > 0 { return true }
        var corrDesc = FetchDescriptor<PlaceCorrectionRecord>(
            predicate: #Predicate { $0.experienceId == experienceId }
        )
        corrDesc.fetchLimit = 1
        if let count = try? context.fetchCount(corrDesc), count > 0 { return true }
        return false
    }

    /// Seed demonstration notes + corrections for a known POI the first time it's
    /// opened. Content is lifted from the design handoff's NOTES_BANK /
    /// PENDING_CORRECTIONS. No-op for unknown ids or already-seeded places.
    private func seedIfNeeded(for experienceId: String) {
        guard let seed = Self.seedBank[experienceId] else { return }
        guard !hasAnyRecords(for: experienceId) else { return }

        for note in seed.notes {
            context.insert(TravelerNoteRecord(from: note.materialize(experienceId: experienceId)))
        }
        for corr in seed.corrections {
            context.insert(PlaceCorrectionRecord(from: corr.materialize(experienceId: experienceId)))
        }
        try? context.save()
    }

    /// Lightweight seed descriptors — `daysAgo` is resolved to an ISO timestamp
    /// at seed time so we don't bake absolute dates into the source.
    private struct SeedNote {
        let id: String
        let initial: String
        let color: String?
        let text: String
        let daysAgo: Int
        let kind: TravelerNote.Kind
        let confirms: Int
        let aiAdopted: Bool

        func materialize(experienceId: String) -> TravelerNote {
            TravelerNote(
                id: "seed_\(experienceId)_\(id)",
                experienceId: experienceId,
                authorInitial: initial,
                authorColor: color,
                text: text,
                kind: kind,
                createdAt: travelerNoteISODaysAgo(daysAgo),
                confirms: confirms,
                aiAdopted: aiAdopted,
                isMine: false
            )
        }
    }

    private struct SeedCorrection {
        let id: String
        let field: String
        let oldVal: String
        let newVal: String
        let sourceNote: String
        let daysAgo: Int

        func materialize(experienceId: String) -> PlaceCorrection {
            PlaceCorrection(
                id: "seed_\(experienceId)_\(id)",
                experienceId: experienceId,
                field: field,
                oldVal: oldVal,
                newVal: newVal,
                sourceNote: sourceNote,
                status: .pending,
                createdAt: travelerNoteISODaysAgo(daysAgo)
            )
        }
    }

    private struct SeedBundle {
        let notes: [SeedNote]
        let corrections: [SeedCorrection]
    }

    /// Demo content keyed by experience id. Mirrors the design handoff
    /// (sheet.jsx NOTES_BANK / PENDING_CORRECTIONS). Only known seed POIs appear;
    /// everything else opens with an empty, addable feed.
    private static let seedBank: [String: SeedBundle] = [
        "x10kup": SeedBundle(
            notes: [
                SeedNote(id: "n1", initial: "J", color: "#9B6A3A",
                         text: "週二下午兩點過去，二樓大窗位空著，待了 3 小時沒人理我。咖啡 30,000 ₭。",
                         daysAgo: 2, kind: .experience, confirms: 12, aiAdopted: true),
                SeedNote(id: "n2", initial: "M", color: "#2F7DD1",
                         text: "WiFi 偶爾會斷，大約 5 分鐘自動重連一次。需要連續工作的人留意。",
                         daysAgo: 7, kind: .correction, confirms: 1, aiAdopted: false),
                SeedNote(id: "n3", initial: "A", color: "#E89530",
                         text: "老闆會說一點英語，點單沒問題，可以指菜單。",
                         daysAgo: 21, kind: .experience, confirms: 5, aiAdopted: true),
                SeedNote(id: "n4", initial: "R", color: "#2FA46A",
                         text: "巷子有點難找，跟著地圖走最後 100 米要看門牌。",
                         daysAgo: 30, kind: .experience, confirms: 8, aiAdopted: true),
            ],
            corrections: [
                SeedCorrection(id: "pc1", field: NSLocalizedString("notes.field.hours", comment: "Opening hours field"),
                               oldVal: "09:00 – 21:00", newVal: "09:30 – 21:00",
                               sourceNote: NSLocalizedString("notes.correction.source.demo", comment: "Seed correction source"),
                               daysAgo: 4),
            ]
        ),
        "sunset-vp": SeedBundle(
            notes: [
                SeedNote(id: "n1", initial: "K", color: "#2FA46A",
                         text: "雨季傍晚經常陰天，看不到正經日落，建議查天氣再去。",
                         daysAgo: 5, kind: .correction, confirms: 7, aiAdopted: true),
                SeedNote(id: "n2", initial: "L", color: "#7A5BCC",
                         text: "河邊有蚊子，記得帶驅蚊液。日落後 30 分鐘最舒服。",
                         daysAgo: 7, kind: .experience, confirms: 4, aiAdopted: false),
            ],
            corrections: []
        ),
    ]
}
