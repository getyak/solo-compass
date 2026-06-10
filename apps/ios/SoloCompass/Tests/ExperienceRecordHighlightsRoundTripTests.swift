import XCTest
@testable import SoloCompass

/// SchemaV1_5 round-trip coverage: `categoryHighlights` must survive
/// Experience → ExperienceRecord → Experience without loss, and rows from
/// before the field existed (nil blob) must decode cleanly as nil. The existing
/// round-trip tests use seed data with no highlights, so the populated-value
/// path was previously unasserted.
final class ExperienceRecordHighlightsRoundTripTests: XCTestCase {

    private func makeExperience(highlights: [CategoryHighlight]?) -> Experience {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return Experience(
            id: "exp_osm_42",
            title: "Test",
            oneLiner: "Line",
            whyItMatters: "Why",
            category: .coffee,
            location: ExperienceLocation(coordinates: [98.98, 18.79], cityCode: "CNX"),
            bestTimes: [],
            durationMinutes: .init(min: 30, max: 60),
            howTo: [],
            realInconveniences: [],
            soloScore: SoloScore(
                overall: 8,
                breakdown: .init(seatingFriendly: 8, soloPatronRatio: 8, staffPressure: 8,
                                 soloPortioning: 8, ambianceFit: 8, safety: 8),
                basedOnCount: 1
            ),
            sources: [],
            confidence: Confidence(level: 2, lastVerifiedAt: now, reason: "t",
                                   signals: .init(aiScrapeAgeDays: 0, passiveGpsHits30d: 0,
                                                  activeReports30d: 0, trustedVerifications: 0)),
            nearbyExperienceIds: [],
            stats: .init(completionCount: 0, averageRating: 0),
            status: .candidate,
            createdAt: now,
            updatedAt: now,
            categoryHighlights: highlights
        )
    }

    func testRoundTrip_preservesPopulatedHighlights() {
        let highlights = [
            CategoryHighlight(kind: .wifi, label: "Wi-Fi", value: "fast"),
            CategoryHighlight(kind: .power, label: "Power", value: "at seats"),
        ]
        let record = ExperienceRecord(from: makeExperience(highlights: highlights))
        let decoded = record.asValue
        XCTAssertEqual(decoded.highlights.count, 2)
        XCTAssertEqual(decoded.highlights.first?.kind, .wifi)
        XCTAssertEqual(decoded.highlights.first?.value, "fast")
        XCTAssertEqual(decoded.highlights.last?.kind, .power)
    }

    func testRoundTrip_nilHighlightsStayNil() {
        let record = ExperienceRecord(from: makeExperience(highlights: nil))
        XCTAssertNil(record.categoryHighlightsBlob, "nil highlights should not persist an empty blob")
        XCTAssertTrue(record.asValue.highlights.isEmpty)
    }

    func testRoundTrip_emptyHighlightsDoNotPersistBlob() {
        // encodedHighlights returns nil for an empty array — avoids writing `[]`.
        let record = ExperienceRecord(from: makeExperience(highlights: []))
        XCTAssertNil(record.categoryHighlightsBlob)
        XCTAssertTrue(record.asValue.highlights.isEmpty)
    }

    func testExperienceJSON_roundTripsHighlights() throws {
        let highlights = [CategoryHighlight(kind: .signature, label: "Signature", value: "Thai")]
        let original = makeExperience(highlights: highlights)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Experience.self, from: data)
        XCTAssertEqual(decoded.highlights.first?.kind, .signature)
        XCTAssertEqual(decoded.highlights.first?.value, "Thai")
    }

    func testExperienceJSON_absentHighlightsDecodeNil() throws {
        // A JSON payload from before the field existed must still decode.
        let json = """
        {"id":"exp_osm_1","title":"T","oneLiner":"O","whyItMatters":"W","category":"coffee",
         "location":{"coordinates":[98.98,18.79],"cityCode":"CNX"},"bestTimes":[],
         "durationMinutes":{"min":30,"max":60},"howTo":[],"realInconveniences":[],
         "soloScore":{"overall":8,"breakdown":{"seatingFriendly":8,"soloPatronRatio":8,"staffPressure":8,"soloPortioning":8,"ambianceFit":8,"safety":8},"basedOnCount":1},
         "sources":[],"confidence":{"level":2,"lastVerifiedAt":0,"reason":"t","signals":{"aiScrapeAgeDays":0,"passiveGpsHits30d":0,"activeReports30d":0,"trustedVerifications":0}},
         "nearbyExperienceIds":[],"stats":{"completionCount":0,"averageRating":0},
         "status":"candidate","createdAt":0,"updatedAt":0}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Experience.self, from: json)
        XCTAssertTrue(decoded.highlights.isEmpty)
    }
}
