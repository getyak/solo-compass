import XCTest
import SwiftData
@testable import SoloCompass

/// Exercises `PersonalDataExporter` — the read-side twin of `ForgetMeService`.
/// Each test builds a fresh in-memory ModelContainer holding the five tables
/// the exporter touches, seeds rows, runs `exportEverything`, and asserts on
/// the rendered file contents + per-table counts.
@MainActor
final class PersonalDataExporterTests: XCTestCase {

    private let clock = Date(timeIntervalSince1970: 1_760_000_000)  // fixed for deterministic stamps

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration("PersonalDataExportTests", isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: VisitRecord.self, TimeCapsule.self, TravelerNoteRecord.self,
            TasteProfile.self, ExperienceRecord.self,
            configurations: config
        )
    }

    private func makeExporter(_ container: ModelContainer) -> PersonalDataExporter {
        PersonalDataExporter(modelContainer: container)
    }

    /// Minimal `ExperienceRecord` — the exporter only reads `id` + `title`, but
    /// the blob fields must hold *legal* JSON encodings (empty arrays / neutral
    /// values), not bare `Data()`. A bare empty blob makes the persistence codec
    /// log a `decode field … failed` error on every fetch, flooding test output.
    private func makeExperience(id: String, title: String) -> ExperienceRecord {
        let enc = JSONEncoder.iso8601Encoder
        let emptyArray = Data("[]".utf8)
        let soloScore = (try? enc.encode(ExperienceRecord.neutralSoloScore)) ?? Data("{}".utf8)
        let confidence = (try? enc.encode(ExperienceRecord.neutralConfidence)) ?? Data("{}".utf8)
        let stats = (try? enc.encode(ExperienceRecord.neutralStats)) ?? Data("{}".utf8)
        return ExperienceRecord(
            id: id, title: title, oneLiner: "", whyItMatters: "",
            category: "cafe", longitude: 0, latitude: 0, cityCode: "LIS",
            addressHint: nil, placeNameLocal: nil, placeNameRomanized: nil,
            durationMin: 30, durationMax: 60, status: "candidate",
            createdAt: clock, updatedAt: clock,
            bestTimesBlob: emptyArray, howToBlob: emptyArray,
            realInconveniencesBlob: emptyArray, sourcesBlob: emptyArray,
            soloScoreBlob: soloScore, confidenceBlob: confidence,
            statsBlob: stats, nearbyExperienceIdsBlob: emptyArray
        )
    }

    // MARK: - Empty / missing-container safety

    func testMissingModelContainerReturnsEmptyAndDoesNotCrash() {
        let exporter = PersonalDataExporter(modelContainer: nil)  // no container bound
        let result = exporter.exportEverything(now: clock)
        XCTAssertTrue(result.files.isEmpty)
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(result.totalAssets, 0)
    }

    func testEmptyDatabaseProducesNoFiles() throws {
        let container = try makeContainer()
        let result = makeExporter(container).exportEverything(now: clock)
        XCTAssertTrue(result.files.isEmpty)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Visits → CSV

    func testVisitsExportedAsCSVWithReadablePlaceName() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(makeExperience(id: "exp_1", title: "Hidden Café"))
        ctx.insert(VisitRecord(
            experienceId: "exp_1",
            visitedAt: Date(timeIntervalSince1970: 1_759_000_000),
            dwellSeconds: 1800,  // 30.0 min
            weatherCode: "rain",
            coordSnapBlob: VisitRecord.encodeCoords([-9.1393, 38.7223])
        ))
        try ctx.save()

        let result = makeExporter(container).exportEverything(now: clock)
        XCTAssertEqual(result.visitRecordsExported, 1)

        let csv = try XCTUnwrap(result.files.first { $0.filename.contains("visits") })
        XCTAssertTrue(csv.filename.hasSuffix(".csv"))
        XCTAssertTrue(csv.contents.contains("visited_at,place,experience_id,dwell_minutes"))
        XCTAssertTrue(csv.contents.contains("Hidden Café"))
        XCTAssertTrue(csv.contents.contains("30.0"))
        XCTAssertTrue(csv.contents.contains("-9.1393"))
        XCTAssertTrue(csv.contents.contains("rain"))
    }

    func testVisitWithCommaInPlaceNameIsCSVEscaped() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(makeExperience(id: "exp_2", title: "Café \"Central\", Lisbon"))
        ctx.insert(VisitRecord(experienceId: "exp_2", dwellSeconds: 600))
        try ctx.save()

        let csv = try XCTUnwrap(
            makeExporter(container).exportEverything(now: clock).files.first { $0.filename.contains("visits") }
        )
        // The comma-and-quote place name must be RFC4180-escaped so it stays one column.
        XCTAssertTrue(csv.contents.contains("\"Café \"\"Central\"\", Lisbon\""))
    }

    func testVisitWithPrunedExperienceFallsBackToRawId() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        // No ExperienceRecord for this id — the visit must still export.
        ctx.insert(VisitRecord(experienceId: "exp_gone", dwellSeconds: 300))
        try ctx.save()

        let result = makeExporter(container).exportEverything(now: clock)
        XCTAssertEqual(result.visitRecordsExported, 1)
        let csv = try XCTUnwrap(result.files.first { $0.filename.contains("visits") })
        XCTAssertTrue(csv.contents.contains("exp_gone"))
    }

    // MARK: - Capsules → Markdown

    func testTextCapsuleInlinesMessage() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(makeExperience(id: "exp_3", title: "Rooftop Bar"))
        ctx.insert(TimeCapsule(
            experienceId: "exp_3",
            scheduledFor: Date(timeIntervalSince1970: 1_800_000_000),
            contentType: TimeCapsule.ContentType.text,
            contentBlob: Data("Come back here in a year.".utf8)
        ))
        try ctx.save()

        let result = makeExporter(container).exportEverything(now: clock)
        XCTAssertEqual(result.timeCapsulesExported, 1)
        let md = try XCTUnwrap(result.files.first { $0.filename.contains("capsules") })
        XCTAssertTrue(md.contents.contains("Rooftop Bar"))
        XCTAssertTrue(md.contents.contains("Come back here in a year."))
        XCTAssertTrue(md.contents.contains("sealed"))
    }

    func testVoiceCapsuleNotedAsBinaryNotInlined() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(TimeCapsule(
            experienceId: "exp_4",
            scheduledFor: clock,
            contentType: TimeCapsule.ContentType.voice,
            contentBlob: Data(count: 4096)
        ))
        try ctx.save()

        let md = try XCTUnwrap(
            makeExporter(container).exportEverything(now: clock).files.first { $0.filename.contains("capsules") }
        )
        XCTAssertTrue(md.contents.contains("Voice note"))
        XCTAssertTrue(md.contents.contains("4096 bytes"))
    }

    // MARK: - Traveler notes → only isMine

    func testOnlyMyTravelerNotesAreExported() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(makeExperience(id: "exp_5", title: "Quiet Park"))
        // Seeded demo note — must NOT be exported.
        ctx.insert(TravelerNoteRecord(
            id: "seed_1", experienceId: "exp_5", authorInitial: "J", authorColor: nil,
            text: "Seeded demo note", kind: "experience",
            createdAt: "2026-06-01T00:00:00Z", confirms: 3, aiAdopted: false, isMine: false
        ))
        // The user's own note — must be exported.
        ctx.insert(TravelerNoteRecord(
            id: "mine_1", experienceId: "exp_5", authorInitial: "你", authorColor: nil,
            text: "Tuesday afternoon was dead quiet", kind: "experience",
            createdAt: "2026-06-10T00:00:00Z", confirms: 0, aiAdopted: false, isMine: true
        ))
        try ctx.save()

        let result = makeExporter(container).exportEverything(now: clock)
        XCTAssertEqual(result.travelerNotesExported, 1)
        let md = try XCTUnwrap(result.files.first { $0.filename.contains("notes") })
        XCTAssertTrue(md.contents.contains("Tuesday afternoon was dead quiet"))
        XCTAssertFalse(md.contents.contains("Seeded demo note"))
    }

    // MARK: - Taste profile → descriptors, no raw vector

    func testTasteProfileExportsDescriptorsNotEmbedding() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(TasteProfile(
            embedding: TasteProfile.encodeEmbedding([0.11, 0.22, 0.33]),
            descriptorsBlob: try TasteProfile.encodeDescriptors(["arty", "quiet", "sunlit"]),
            confidence: 0.85
        ))
        try ctx.save()

        let result = makeExporter(container).exportEverything(now: clock)
        XCTAssertTrue(result.tasteProfileExported)
        let md = try XCTUnwrap(result.files.first { $0.filename.contains("taste") })
        XCTAssertTrue(md.contents.contains("arty"))
        XCTAssertTrue(md.contents.contains("quiet"))
        XCTAssertTrue(md.contents.contains("85%"))
        // The raw embedding floats must never appear in a user-legible export.
        XCTAssertFalse(md.contents.contains("0.11"))
    }

    // MARK: - Full mixed export

    func testAllFourAssetTypesProduceFourFiles() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(VisitRecord(experienceId: "e", dwellSeconds: 600))
        ctx.insert(TimeCapsule(
            experienceId: "e", scheduledFor: clock,
            contentType: TimeCapsule.ContentType.text, contentBlob: Data("hi".utf8)
        ))
        ctx.insert(TravelerNoteRecord(
            id: "m", experienceId: "e", authorInitial: "你", authorColor: nil,
            text: "mine", kind: "experience", createdAt: "2026-06-10T00:00:00Z",
            confirms: 0, aiAdopted: false, isMine: true
        ))
        ctx.insert(TasteProfile(
            embedding: Data(), descriptorsBlob: try TasteProfile.encodeDescriptors(["arty"]),
            confidence: 0.5
        ))
        try ctx.save()

        let result = makeExporter(container).exportEverything(now: clock)
        XCTAssertEqual(result.files.count, 4)
        XCTAssertEqual(result.totalAssets, 4)
        XCTAssertFalse(result.isEmpty)
    }
}
