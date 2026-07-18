import Foundation
import SwiftData
import os

/// One-tap "Export my data" — the read-side twin of `ForgetMeService`.
///
/// The four highest-stickiness user assets (visit history, time capsules,
/// traveler notes, taste profile) live in on-device SwiftData with **no cloud
/// sync**. That is a deliberate privacy stance (PRIVACY.md on-device
/// commitment), but until this exporter existed it had a fatal side effect:
/// a user who accrued a year of location history and buried capsules lost all
/// of it on device migration. `MarkdownExporter` only ever exported a single
/// `Experience` card — never the user's own accumulated assets.
///
/// This service closes the data-sovereignty loop: `ForgetMeService` lets the
/// user *erase* those four tables; `PersonalDataExporter` lets them *take the
/// data with them*. It scopes to exactly the same tables so the two are
/// symmetric (what you can wipe, you can also carry out).
///
/// Format per asset — chosen for the asset's real consumer, not uniformity:
/// - `VisitRecord`         → CSV  (tabular; opens in Excel / hands to an accountant)
/// - `TimeCapsule`         → Markdown (text capsules inline; voice/photo noted as binary)
/// - `TravelerNoteRecord`  → Markdown (only `isMine` notes — seeded demo notes are
///                            NOT the user's asset and are excluded)
/// - `TasteProfile`        → Markdown (human-readable descriptors + confidence;
///                            the raw embedding vector is an internal representation,
///                            not a user-legible asset, so it is omitted)
///
/// Design mirrors `ForgetMeService`: a `ModelContainer` injected once at
/// bootstrap, all reads through `ModelContext(container)`, never throws (a
/// Settings button must never hang), and returns a `Result` so the UI can
/// report exactly what was written rather than a silent success.
@MainActor
public final class PersonalDataExporter {

    public static let shared = PersonalDataExporter()

    private static let log = OSLog(subsystem: "com.solocompass.app", category: "PersonalDataExport")

    private var modelContainer: ModelContainer?

    private init() {}

    /// Injected once at app bootstrap (mirrors `ForgetMeService.setModelContainer`).
    public func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }

    /// Test-only overload: bind a specific container without the shared singleton.
    /// Test-only overload. `nil` binds no container, exercising the
    /// missing-container guard exactly as production hits it when bootstrap
    /// hasn't run yet.
    #if DEBUG
    public convenience init(modelContainer: ModelContainer?) {
        self.init()
        self.modelContainer = modelContainer
    }
    #endif

    // MARK: - Result

    /// One exported file: a suggested filename + its UTF-8 text payload. The
    /// caller (a Settings share sheet) writes these to temp URLs and hands them
    /// to `UIActivityViewController`.
    public struct File: Equatable, Sendable {
        public let filename: String
        public let contents: String

        public init(filename: String, contents: String) {
            self.filename = filename
            self.contents = contents
        }
    }

    /// What the export produced, so the UI reports counts (not a silent success)
    /// and a `forgetEverything()`-style caller can assert on the numbers.
    public struct Result: Equatable, Sendable {
        public var files: [File]
        public var visitRecordsExported: Int
        public var timeCapsulesExported: Int
        public var travelerNotesExported: Int
        public var tasteProfileExported: Bool

        public var totalAssets: Int {
            visitRecordsExported + timeCapsulesExported +
            travelerNotesExported + (tasteProfileExported ? 1 : 0)
        }

        public var isEmpty: Bool { totalAssets == 0 }
    }

    // MARK: - Export

    /// Read all four personal-asset tables and render each to its file format.
    ///
    /// - Parameter now: injected clock so the export header timestamp is
    ///   deterministic in tests. Defaults to `Date()`.
    /// - Returns: the rendered files + per-table counts. When the
    ///   `ModelContainer` is missing, returns an empty result and logs — never
    ///   throws, so a Settings button never hangs on an alert.
    @discardableResult
    public func exportEverything(now: Date = Date()) -> Result {
        guard let container = modelContainer else {
            os_log("PersonalDataExport skipped — no ModelContainer bound",
                   log: Self.log, type: .error)
            return Result(files: [], visitRecordsExported: 0,
                          timeCapsulesExported: 0, travelerNotesExported: 0,
                          tasteProfileExported: false)
        }
        let context = ModelContext(container)

        // A single id→title lookup shared by every renderer, so we hit the
        // Experience table once instead of once per visit/capsule/note. A
        // visit whose experience has been pruned still exports — it just shows
        // the raw id rather than a name (never drop a user's own row).
        let titles = experienceTitleLookup(in: context)

        let (visitFile, visitCount) = exportVisits(in: context, titles: titles, now: now)
        let (capsuleFile, capsuleCount) = exportCapsules(in: context, titles: titles, now: now)
        let (noteFile, noteCount) = exportTravelerNotes(in: context, titles: titles, now: now)
        let (tasteFile, hasTaste) = exportTasteProfile(in: context, now: now)

        var files: [File] = []
        if let visitFile { files.append(visitFile) }
        if let capsuleFile { files.append(capsuleFile) }
        if let noteFile { files.append(noteFile) }
        if let tasteFile { files.append(tasteFile) }

        os_log("PersonalDataExport v=%d c=%d n=%d taste=%{public}@ files=%d",
               log: Self.log, type: .info, visitCount, capsuleCount, noteCount,
               hasTaste ? "true" : "false", files.count)

        return Result(
            files: files,
            visitRecordsExported: visitCount,
            timeCapsulesExported: capsuleCount,
            travelerNotesExported: noteCount,
            tasteProfileExported: hasTaste
        )
    }

    // MARK: - Experience title lookup

    /// Build `experienceId → title` once. Missing rows simply aren't in the
    /// map, and renderers fall back to the raw id — a pruned Experience must
    /// never cause the user's visit/capsule/note to be dropped from the export.
    private func experienceTitleLookup(in context: ModelContext) -> [String: String] {
        let rows = (try? context.fetch(FetchDescriptor<ExperienceRecord>())) ?? []
        return Dictionary(rows.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
    }

    private func placeName(for experienceId: String, titles: [String: String]) -> String {
        titles[experienceId] ?? experienceId
    }

    // MARK: - Visits → CSV

    private func exportVisits(
        in context: ModelContext,
        titles: [String: String],
        now: Date
    ) -> (File?, Int) {
        let descriptor = FetchDescriptor<VisitRecord>(
            sortBy: [SortDescriptor(\.visitedAt, order: .forward)]
        )
        guard let rows = try? context.fetch(descriptor), !rows.isEmpty else {
            return (nil, 0)
        }

        let iso = ISO8601DateFormatter()
        var lines = ["visited_at,place,experience_id,dwell_minutes,longitude,latitude,weather"]
        for row in rows {
            let place = placeName(for: row.experienceId, titles: titles)
            let dwellMinutes = String(format: "%.1f", Double(row.dwellSeconds) / 60.0)
            let coords = row.coords
            let lon = coords.map { String($0[0]) } ?? ""
            let lat = coords.map { String($0[1]) } ?? ""
            let cells = [
                iso.string(from: row.visitedAt),
                place,
                row.experienceId,
                dwellMinutes,
                lon,
                lat,
                row.weatherCode ?? "",
            ].map(Self.csvEscape)
            lines.append(cells.joined(separator: ","))
        }

        let filename = "solo-compass-visits-\(Self.dateStamp(now)).csv"
        return (File(filename: filename, contents: lines.joined(separator: "\n") + "\n"), rows.count)
    }

    // MARK: - Capsules → Markdown

    private func exportCapsules(
        in context: ModelContext,
        titles: [String: String],
        now: Date
    ) -> (File?, Int) {
        let descriptor = FetchDescriptor<TimeCapsule>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        guard let rows = try? context.fetch(descriptor), !rows.isEmpty else {
            return (nil, 0)
        }

        let iso = ISO8601DateFormatter()
        var body = "# Solo Compass — Time Capsules\n\n"
        body += "Exported \(iso.string(from: now)) · \(rows.count) capsule(s)\n\n"

        for row in rows {
            let place = placeName(for: row.experienceId, titles: titles)
            body += "## \(place)\n\n"
            body += "- Buried: \(iso.string(from: row.createdAt))\n"
            body += "- Opens: \(iso.string(from: row.scheduledFor))\n"
            body += "- Status: \(row.opened ? "opened" : "sealed")\n"

            switch row.contentType {
            case TimeCapsule.ContentType.text:
                let message = String(data: row.contentBlob, encoding: .utf8) ?? "(unreadable text)"
                body += "\n\(message)\n"
            case TimeCapsule.ContentType.voice:
                body += "\n_Voice note — \(row.contentBlob.count) bytes of audio, not inlined._\n"
            case TimeCapsule.ContentType.photo:
                body += "\n_Photo — \(row.contentBlob.count) bytes of image, not inlined._\n"
            default:
                body += "\n_\(row.contentType) content — \(row.contentBlob.count) bytes, not inlined._\n"
            }

            if let ctx = CapsuleContext.decode(from: row.contextBlob) {
                var bits: [String] = []
                if let mood = ctx.moodEmoji { bits.append("mood \(mood)") }
                if let weather = ctx.weatherCode { bits.append("weather \(weather)") }
                if let desc = ctx.tasteDescriptors, !desc.isEmpty {
                    bits.append("vibe " + desc.joined(separator: "/"))
                }
                if !bits.isEmpty {
                    body += "\n> _\(bits.joined(separator: " · "))_\n"
                }
            }
            body += "\n---\n\n"
        }

        let filename = "solo-compass-capsules-\(Self.dateStamp(now)).md"
        return (File(filename: filename, contents: body), rows.count)
    }

    // MARK: - Traveler notes → Markdown (only the user's own)

    private func exportTravelerNotes(
        in context: ModelContext,
        titles: [String: String],
        now: Date
    ) -> (File?, Int) {
        // Only `isMine` notes are the user's asset. Seeded demo notes
        // (`seedBank` in TravelerNoteStore) belong to the content layer, not
        // the user, and must not leak into a "your data" export.
        let descriptor = FetchDescriptor<TravelerNoteRecord>(
            predicate: #Predicate { $0.isMine == true },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        guard let rows = try? context.fetch(descriptor), !rows.isEmpty else {
            return (nil, 0)
        }

        let iso = ISO8601DateFormatter()
        var body = "# Solo Compass — My Traveler Notes\n\n"
        body += "Exported \(iso.string(from: now)) · \(rows.count) note(s)\n\n"

        for row in rows {
            let place = placeName(for: row.experienceId, titles: titles)
            let kind = row.kind == TravelerNote.Kind.correction.rawValue ? "correction" : "note"
            body += "## \(place)\n\n"
            body += "- \(kind) · \(row.createdAt)"
            if row.confirms > 0 { body += " · \(row.confirms) confirmed" }
            if row.aiAdopted { body += " · adopted by AI" }
            body += "\n\n\(row.text)\n\n---\n\n"
        }

        let filename = "solo-compass-notes-\(Self.dateStamp(now)).md"
        return (File(filename: filename, contents: body), rows.count)
    }

    // MARK: - Taste profile → Markdown

    private func exportTasteProfile(in context: ModelContext, now: Date) -> (File?, Bool) {
        // Singleton table — 0 or 1 row. The raw embedding vector is an internal
        // model representation, not a user-legible asset, so we export only the
        // human-readable descriptors + calibrated confidence.
        guard let row = try? context.fetch(FetchDescriptor<TasteProfile>()).first else {
            return (nil, false)
        }

        let iso = ISO8601DateFormatter()
        var body = "# Solo Compass — My Taste Profile\n\n"
        body += "Exported \(iso.string(from: now))\n\n"
        body += "- Last updated: \(iso.string(from: row.updatedAt))\n"
        body += "- Confidence: \(String(format: "%.0f%%", row.confidence * 100))\n\n"

        let descriptors = row.descriptors
        if descriptors.isEmpty {
            body += "_No descriptors recorded yet._\n"
        } else {
            body += "## Vibe\n\n"
            for d in descriptors { body += "- \(d)\n" }
            body += "\n"
        }

        let filename = "solo-compass-taste-\(Self.dateStamp(now)).md"
        return (File(filename: filename, contents: body), true)
    }

    // MARK: - Helpers

    /// RFC 4180 CSV escaping: wrap in double quotes and double any embedded
    /// quote whenever the cell contains a comma, quote, or newline. A place
    /// name like `Café "Central", Lisbon` must not shift columns.
    static func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// `yyyy-MM-dd` stamp for filenames, in the device's local calendar. Uses a
    /// fixed-format `DateFormatter` (not ISO8601) so the filename has no colons,
    /// which some file systems and share targets dislike.
    static func dateStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
