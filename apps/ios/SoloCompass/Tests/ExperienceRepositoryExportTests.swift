import XCTest
import SwiftData
@testable import SoloCompass

/// `ExperienceRepository.exportAllUserData()` is the GDPR Article 15 (Subject
/// Access Request) endpoint. A regression here means users can't actually
/// retrieve their own data — a compliance failure, not just a bug. We pin the
/// envelope shape, the table set, and the field schema for each table so a
/// silently-renamed column (or a forgotten new table) is caught immediately.
@MainActor
final class ExperienceRepositoryExportTests: XCTestCase {

    private var repo: ExperienceRepository!

    override func setUp() async throws {
        try await super.setUp()
        let container = SoloCompassModelContainer.makeInMemory()
        repo = ExperienceRepository(context: ModelContext(container))
    }

    override func tearDown() async throws {
        repo = nil
        try await super.tearDown()
    }

    // MARK: - Envelope

    func testEmptyExportProducesWellFormedEnvelope() throws {
        let data = try XCTUnwrap(repo.exportAllUserData(), "export must succeed even with no data")
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            "top level must be a JSON object"
        )

        XCTAssertEqual(json["export_version"] as? Int, 1, "version pin: bump intentionally")
        XCTAssertNotNil(json["generated_at"] as? String, "generated_at must be present")
        XCTAssertNotNil(json["tables"] as? [String: Any], "tables wrapper must be present")
    }

    func testGeneratedAtIsISO8601() throws {
        let data = try XCTUnwrap(repo.exportAllUserData())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let generatedAt = try XCTUnwrap(json["generated_at"] as? String)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertNotNil(
            iso.date(from: generatedAt),
            "generated_at must round-trip through ISO8601 + fractional seconds — " +
            "downstream tooling (Privacy Manifest checker, EU regulator scripts) parses this"
        )
    }

    // MARK: - Favorites + completions roundtrip

    func testFavoritesAppearInExportAfterToggle() throws {
        _ = repo.toggleFavorite(experienceId: "exp_vte_riverside")

        let tables = try fetchTables()
        let favorites = try XCTUnwrap(tables["favorites"] as? [String])
        XCTAssertTrue(favorites.contains("exp_vte_riverside"))
    }

    func testCompletionsAppearInExportAfterRecord() throws {
        repo.recordCompletion(experienceId: "exp_vte_riverside")

        let tables = try fetchTables()
        let completions = try XCTUnwrap(tables["completions"] as? [String])
        XCTAssertTrue(completions.contains("exp_vte_riverside"))
    }

    // MARK: - Survey schema

    func testSurveyExportSchemaPinsAllFieldNames() throws {
        repo.recordSurvey(
            experienceId: "exp_vte_riverside",
            comfort: 4,
            pressure: 2,
            recommend: "5",
            anonDeviceId: "device_test"
        )

        let tables = try fetchTables()
        let surveys = try XCTUnwrap(tables["surveys"] as? [[String: Any]])
        let survey = try XCTUnwrap(surveys.first)

        // Field-name pin: rename a column → caller breaks → test fails.
        XCTAssertNotNil(survey["id"] as? String, "survey.id (UUID string) required")
        XCTAssertEqual(survey["experienceId"] as? String, "exp_vte_riverside")
        XCTAssertEqual(survey["comfort"] as? Int, 4)
        XCTAssertEqual(survey["pressure"] as? Int, 2)
        XCTAssertEqual(survey["recommend"] as? String, "5")
        XCTAssertNotNil(survey["submittedAt"] as? String, "submittedAt must be ISO string")
    }

    // MARK: - Tables set (catches "added a new @Model, forgot to export it")

    func testExportIncludesAllExpectedTables() throws {
        // Trigger at least one row in some user-mutable tables so the export
        // emits the corresponding keys. The in-memory store always fetches
        // successfully, so all known table keys should show up — even with
        // zero rows — because the export emits each key when its fetch
        // descriptor returns (even an empty array).
        _ = repo.toggleFavorite(experienceId: "exp_a")
        repo.recordCompletion(experienceId: "exp_a")
        repo.recordSurvey(experienceId: "exp_a", comfort: 3, pressure: 3, recommend: "3", anonDeviceId: "device_test")

        let tables = try fetchTables()
        let knownKeys: Set<String> = [
            "favorites", "completions", "surveys",
            "pending_checkins", "routes", "itineraries", "friendships",
            "friend_requests", "conversations", "chat_messages",
            "chat_sessions", "traveler_notes", "place_corrections",
            "pending_sync", "ai_usage"
        ]
        let exportedKeys = Set(tables.keys)
        for key in knownKeys {
            XCTAssertTrue(
                exportedKeys.contains(key),
                "export missing table key '\(key)' — likely forgot to wire " +
                "a new @Model into exportAllUserData()"
            )
        }
    }

    // MARK: - JSON shape sanity

    func testExportIsPrettyPrintedAndSortedKeys() throws {
        let data = try XCTUnwrap(repo.exportAllUserData())
        let raw = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(raw.contains("\n"), "export must be pretty-printed for human-readable SAR")
        if let v = raw.range(of: "\"export_version\""),
           let g = raw.range(of: "\"generated_at\"") {
            XCTAssertLessThan(
                v.lowerBound, g.lowerBound,
                "sortedKeys: export_version < generated_at alphabetically"
            )
        } else {
            XCTFail("expected both top-level keys to appear in raw output")
        }
    }

    // MARK: - Helpers

    private func fetchTables() throws -> [String: Any] {
        let data = try XCTUnwrap(repo.exportAllUserData())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(json["tables"] as? [String: Any])
    }
}
