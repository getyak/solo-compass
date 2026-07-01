import XCTest
import SwiftData
@testable import SoloCompass

/// Tests for the four new @Model tables that ship in schema v1.9:
/// VisitRecord, TasteProfile, TimeCapsule, AgentMemorySnapshot (P1.0 #101-#104).
///
/// Each model is exercised against an in-memory SwiftData container so the
/// tests stay hermetic and don't touch the on-disk store. The shared helper
/// `inMemoryContext()` rebuilds a fresh container per test to prevent cross-
/// test bleed.
final class V1_9SchemaRecordsTests: XCTestCase {

    // MARK: - Container helper

    /// Build a fresh in-memory ModelContainer holding exactly the v1.9 models.
    /// Using a narrow container (not the full SoloCompass set) keeps each test
    /// isolated and faster to construct.
    @MainActor
    private func inMemoryContext() throws -> ModelContext {
        let config = ModelConfiguration("V1_9Tests", isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: VisitRecord.self,
                TasteProfile.self,
                TimeCapsule.self,
                AgentMemorySnapshot.self,
            configurations: config
        )
        return ModelContext(container)
    }

    // MARK: - VisitRecord

    @MainActor
    func testVisitRecordInsertsAndQueriesByExperienceId() throws {
        let ctx = try inMemoryContext()
        let coords = VisitRecord.encodeCoords([100.5018, 13.7563]) // Bangkok lon/lat
        let visit = VisitRecord(
            experienceId: "exp_test_001",
            visitedAt: Date(timeIntervalSince1970: 1_780_000_000),
            dwellSeconds: 1_800,
            weatherCode: "clear",
            coordSnapBlob: coords
        )
        ctx.insert(visit)
        try ctx.save()

        let predicate = #Predicate<VisitRecord> { $0.experienceId == "exp_test_001" }
        let fetched = try ctx.fetch(FetchDescriptor<VisitRecord>(predicate: predicate))

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.dwellSeconds, 1_800)
        XCTAssertEqual(fetched.first?.weatherCode, "clear")
        XCTAssertEqual(fetched.first?.coords, [100.5018, 13.7563])
    }

    @MainActor
    func testVisitRecordAllowsMultipleVisitsToSameExperience() throws {
        let ctx = try inMemoryContext()
        let v1 = VisitRecord(experienceId: "exp_test_002", dwellSeconds: 600)
        let v2 = VisitRecord(experienceId: "exp_test_002", dwellSeconds: 1_200)
        ctx.insert(v1)
        ctx.insert(v2)
        try ctx.save()

        let predicate = #Predicate<VisitRecord> { $0.experienceId == "exp_test_002" }
        let fetched = try ctx.fetch(FetchDescriptor<VisitRecord>(predicate: predicate))
        XCTAssertEqual(fetched.count, 2, "experienceId is indexed but not unique — revisits must coexist")
    }

    func testVisitRecordCoordsRoundTrip() {
        let coords = VisitRecord.encodeCoords([100.5, 13.7])
        let v = VisitRecord(experienceId: "x", dwellSeconds: 300, coordSnapBlob: coords)
        XCTAssertEqual(v.coords, [100.5, 13.7])
    }

    func testVisitRecordCoordsRejectsMalformedInput() {
        XCTAssertNil(VisitRecord.encodeCoords(nil))
        XCTAssertNil(VisitRecord.encodeCoords([]))
        XCTAssertNil(VisitRecord.encodeCoords([100.0])) // only 1 coord
        XCTAssertNil(VisitRecord.encodeCoords([100.0, 13.0, 50.0])) // 3 coords
    }

    func testVisitRecordCoordsReturnsNilForCorruptBlob() {
        let v = VisitRecord(
            experienceId: "x",
            dwellSeconds: 300,
            coordSnapBlob: Data([0x01, 0x02, 0x03]) // wrong byte length
        )
        XCTAssertNil(v.coords, "corrupt blob must surface as nil, not crash")
    }

    // MARK: - TasteProfile

    @MainActor
    func testTasteProfileRoundTripsEmbeddingAndDescriptors() throws {
        let ctx = try inMemoryContext()
        let embedding = TasteProfile.encodeEmbedding([0.1, -0.2, 0.85, -0.04])
        let descriptors = try TasteProfile.encodeDescriptors(["arty", "quiet", "sunlit"])
        let profile = TasteProfile(
            embedding: embedding,
            descriptorsBlob: descriptors,
            confidence: 0.45
        )
        ctx.insert(profile)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<TasteProfile>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.embeddingVector, [0.1, -0.2, 0.85, -0.04])
        XCTAssertEqual(fetched.first?.descriptors, ["arty", "quiet", "sunlit"])
        XCTAssertEqual(try XCTUnwrap(fetched.first).confidence, 0.45, accuracy: 0.001)
    }

    func testTasteProfileEmbeddingDegradesGracefullyOnCorruptBlob() {
        let profile = TasteProfile(
            embedding: Data([0x01, 0x02, 0x03]), // 3 bytes — not divisible by 4 (Float)
            descriptorsBlob: Data(),
            confidence: 0.5
        )
        XCTAssertEqual(profile.embeddingVector, [], "corrupt embedding must degrade to empty, not crash")
    }

    func testTasteProfileSourcePhotosRoundTrip() throws {
        let photos = ["ph_local_id_001", "ph_local_id_002", "ph_local_id_003"]
        let blob = try JSONEncoder().encode(photos)
        let profile = TasteProfile(
            embedding: TasteProfile.encodeEmbedding([0.1]),
            descriptorsBlob: try TasteProfile.encodeDescriptors([]),
            confidence: 0.3,
            sourceVibePhotosBlob: blob
        )
        XCTAssertEqual(profile.sourceVibePhotos, photos)
    }

    func testTasteProfileSourcePhotosNilWhenAbsent() throws {
        let profile = TasteProfile(
            embedding: Data(),
            descriptorsBlob: try TasteProfile.encodeDescriptors([]),
            confidence: 0.0
        )
        XCTAssertNil(profile.sourceVibePhotos, "absent blob must surface as nil, not []")
    }

    // MARK: - TimeCapsule

    @MainActor
    func testTimeCapsuleInsertsWithDefaultUnopenedState() throws {
        let ctx = try inMemoryContext()
        let capsule = TimeCapsule(
            experienceId: "exp_test_003",
            createdAt: Date(timeIntervalSince1970: 1_780_000_000),
            scheduledFor: Date(timeIntervalSince1970: 1_811_536_000), // ~1 year later
            contentType: TimeCapsule.ContentType.text,
            contentBlob: Data("Today I sat here for an hour.".utf8)
        )
        ctx.insert(capsule)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<TimeCapsule>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.opened, false, "default opened state must be false")
        XCTAssertEqual(fetched.first?.contentType, "text")
    }

    @MainActor
    func testTimeCapsulePredicateFindsRipeUnopened() throws {
        let ctx = try inMemoryContext()
        let pastRipe = TimeCapsule(
            experienceId: "ripe",
            scheduledFor: Date(timeIntervalSinceNow: -3_600), // 1h ago — ripe
            contentType: "text",
            contentBlob: Data()
        )
        let futureNotRipe = TimeCapsule(
            experienceId: "future",
            scheduledFor: Date(timeIntervalSinceNow: 3_600), // 1h ahead — not ripe
            contentType: "text",
            contentBlob: Data()
        )
        let alreadyOpened = TimeCapsule(
            experienceId: "opened",
            scheduledFor: Date(timeIntervalSinceNow: -7_200),
            contentType: "text",
            contentBlob: Data(),
            opened: true
        )
        ctx.insert(pastRipe)
        ctx.insert(futureNotRipe)
        ctx.insert(alreadyOpened)
        try ctx.save()

        let now = Date()
        let predicate = #Predicate<TimeCapsule> { !$0.opened && $0.scheduledFor <= now }
        let ripe = try ctx.fetch(FetchDescriptor<TimeCapsule>(predicate: predicate))
        XCTAssertEqual(ripe.count, 1)
        XCTAssertEqual(ripe.first?.experienceId, "ripe")
    }

    func testCapsuleContextEncodesNilWhenAllFieldsEmpty() throws {
        let empty = CapsuleContext()
        XCTAssertNil(try empty.encoded(), "empty context must return nil blob, not empty Data")
    }

    func testCapsuleContextRoundTrip() throws {
        let original = CapsuleContext(
            weatherCode: "rain",
            tasteDescriptors: ["quiet", "warm"],
            moodEmoji: "🌧"
        )
        let blob = try original.encoded()
        XCTAssertNotNil(blob)
        let decoded = CapsuleContext.decode(from: blob)
        XCTAssertEqual(decoded?.weatherCode, "rain")
        XCTAssertEqual(decoded?.tasteDescriptors, ["quiet", "warm"])
        XCTAssertEqual(decoded?.moodEmoji, "🌧")
    }

    func testCapsuleContextDecodeReturnsNilForGarbageBlob() {
        XCTAssertNil(CapsuleContext.decode(from: nil))
        XCTAssertNil(CapsuleContext.decode(from: Data([0xFF, 0xFE, 0xFD])))
    }

    // MARK: - AgentMemorySnapshot

    @MainActor
    func testAgentMemorySnapshotPersistsAllFields() throws {
        let ctx = try inMemoryContext()
        let snap = AgentMemorySnapshot(
            summary: "Solo traveler exploring quiet cafes in Bangkok",
            lastTripCity: "Bangkok",
            recentChatDigest: "Asked about quiet cafes 3 times this week",
            updatedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
        ctx.insert(snap)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<AgentMemorySnapshot>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.summary, "Solo traveler exploring quiet cafes in Bangkok")
        XCTAssertEqual(fetched.first?.lastTripCity, "Bangkok")
        XCTAssertEqual(fetched.first?.recentChatDigest, "Asked about quiet cafes 3 times this week")
    }

    func testAgentMemorySnapshotSystemPromptBlockSkipsEmptyFields() {
        let coldStart = AgentMemorySnapshot()
        XCTAssertEqual(coldStart.systemPromptBlock(), "", "cold-start snapshot must produce no noise in the prompt")
    }

    func testAgentMemorySnapshotSystemPromptBlockJoinsPopulatedFields() {
        let snap = AgentMemorySnapshot(
            summary: "Solo traveler",
            lastTripCity: "Tokyo",
            recentChatDigest: "Wants quiet spots"
        )
        let block = snap.systemPromptBlock()
        XCTAssertTrue(block.contains("About this user: Solo traveler"))
        XCTAssertTrue(block.contains("Last/current trip: Tokyo"))
        XCTAssertTrue(block.contains("Recent chats: Wants quiet spots"))
    }

    func testAgentMemorySnapshotSystemPromptBlockSkipsEmptyOptionalCity() {
        let snap = AgentMemorySnapshot(
            summary: "Solo traveler",
            lastTripCity: nil,
            recentChatDigest: "Wants quiet spots"
        )
        let block = snap.systemPromptBlock()
        XCTAssertFalse(block.contains("Last/current trip"), "nil city must not appear in prompt")
    }
}
