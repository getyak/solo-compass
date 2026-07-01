import XCTest
import SwiftData
@testable import SoloCompass

/// P2.0 #202 tests: `MemoryDigestService` — deterministic summariser,
/// recent-chat roll-up, singleton upsert, and the P2.0 #204 forget-me wipe.
///
/// These tests never touch the LLM slot; the service defaults to
/// `useLLM = false`. That keeps them hermetic + fast even when no API
/// key is present.
@MainActor
final class MemoryDigestServiceTests: XCTestCase {

    private var container: ModelContainer!

    override func setUp() async throws {
        // In-memory SwiftData container using the same models the production
        // schema V1_9 registers. Matches VisitTrackingServiceTests /
        // TasteUpdateServiceTests pattern.
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: AgentMemorySnapshot.self, TasteProfile.self, VisitRecord.self,
            configurations: config
        )
    }

    override func tearDown() async throws {
        container = nil
    }

    // MARK: - rollUpRecentChats

    func test_rollUpRecentChats_emptyMessages_returnsEmpty() {
        XCTAssertEqual(MemoryDigestService.rollUpRecentChats(from: []), "")
    }

    func test_rollUpRecentChats_onlySystemMessages_returnsEmpty() {
        let msgs: [VoiceAgentSession.Message] = [
            .init(role: .system, content: "seed prompt"),
            .init(role: .assistant, content: "hi, welcome"),
        ]
        XCTAssertEqual(MemoryDigestService.rollUpRecentChats(from: msgs), "")
    }

    func test_rollUpRecentChats_picksUserTurnsInChronologicalOrder() {
        let msgs: [VoiceAgentSession.Message] = [
            .init(role: .system, content: "seed"),
            .init(role: .user, content: "any quiet cafes near me"),
            .init(role: .assistant, content: "sure — check…"),
            .init(role: .user, content: "how about tomorrow morning"),
        ]
        let out = MemoryDigestService.rollUpRecentChats(from: msgs)
        XCTAssertEqual(out, "any quiet cafes near me; how about tomorrow morning")
    }

    func test_rollUpRecentChats_dropsOldestWhenExceedingCap() {
        // Build 5 user turns of ~80 chars each — well over the 300 cap.
        let filler = String(repeating: "a", count: 80)
        let msgs: [VoiceAgentSession.Message] = (0..<5).map { i in
            .init(role: .user, content: "\(i)-\(filler)")
        }
        let out = MemoryDigestService.rollUpRecentChats(from: msgs)
        XCTAssertLessThanOrEqual(out.count, MemoryDigestService.recentDigestCharCap)
        // Must retain the LATEST turn (index 4).
        XCTAssertTrue(out.contains("4-"))
        // Must have dropped the OLDEST (index 0).
        XCTAssertFalse(out.contains("0-"))
    }

    func test_rollUpRecentChats_normalisesNewlines() {
        let msgs: [VoiceAgentSession.Message] = [
            .init(role: .user, content: "hello\nthere"),
        ]
        let out = MemoryDigestService.rollUpRecentChats(from: msgs)
        XCTAssertEqual(out, "hello there")
    }

    func test_rollUpRecentChats_skipsNilContent() {
        let msgs: [VoiceAgentSession.Message] = [
            .init(role: .user, content: nil),
            .init(role: .user, content: "real turn"),
        ]
        XCTAssertEqual(MemoryDigestService.rollUpRecentChats(from: msgs), "real turn")
    }

    // MARK: - deterministicSummary

    func test_deterministicSummary_bothEmpty_returnsEmpty() {
        XCTAssertEqual(MemoryDigestService.deterministicSummary(prior: "", recent: ""), "")
    }

    func test_deterministicSummary_onlyPrior_returnsPriorTruncated() {
        let long = String(repeating: "x", count: 800)
        let out = MemoryDigestService.deterministicSummary(prior: long, recent: "")
        XCTAssertEqual(out.count, MemoryDigestService.summaryCharCap)
    }

    func test_deterministicSummary_onlyRecent_returnsRecent() {
        let out = MemoryDigestService.deterministicSummary(prior: "", recent: "loves quiet cafes")
        XCTAssertEqual(out, "loves quiet cafes")
    }

    func test_deterministicSummary_bothPresent_blendsPriorAndRecentUnderCap() {
        let out = MemoryDigestService.deterministicSummary(
            prior: "Solo traveler; obsessed with sunlit cafes",
            recent: "asked about ramen twice"
        )
        XCTAssertEqual(out, "Solo traveler; obsessed with sunlit cafes Recently: asked about ramen twice")
        XCTAssertLessThanOrEqual(out.count, MemoryDigestService.summaryCharCap)
    }

    // MARK: - digestConversation + persist

    func test_digestConversation_insertsSingletonWhenAbsent() async throws {
        let svc = MemoryDigestService(aiService: AIService(), modelContainer: container)
        let msgs: [VoiceAgentSession.Message] = [
            .init(role: .user, content: "quiet mornings in Chiang Mai"),
        ]
        await svc.digestConversation(msgs, cityCode: "cmi")

        let ctx = ModelContext(container)
        let rows = try ctx.fetch(FetchDescriptor<AgentMemorySnapshot>())
        XCTAssertEqual(rows.count, 1, "must insert exactly one snapshot row")
        XCTAssertEqual(rows.first?.lastTripCity, "cmi")
        XCTAssertTrue(rows.first?.recentChatDigest.contains("Chiang Mai") ?? false)
    }

    func test_digestConversation_upsertsSingletonWhenPresent() async throws {
        let svc = MemoryDigestService(aiService: AIService(), modelContainer: container)
        await svc.digestConversation([
            .init(role: .user, content: "first visit"),
        ], cityCode: "cmi")
        await svc.digestConversation([
            .init(role: .user, content: "second visit"),
        ], cityCode: nil)

        let ctx = ModelContext(container)
        let rows = try ctx.fetch(FetchDescriptor<AgentMemorySnapshot>())
        XCTAssertEqual(rows.count, 1, "must upsert, not append")
        // Prior city preserved because 2nd call passed nil cityCode.
        XCTAssertEqual(rows.first?.lastTripCity, "cmi")
        // Recent digest reflects the most recent turn (LLM off, deterministic).
        XCTAssertTrue(rows.first?.recentChatDigest.contains("second") ?? false)
    }

    func test_digestConversation_withoutContainer_noOps() async {
        let svc = MemoryDigestService(aiService: AIService(), modelContainer: nil)
        await svc.digestConversation([
            .init(role: .user, content: "hi"),
        ])
        XCTAssertNil(svc.currentSnapshot())
    }

    // MARK: - currentSnapshot

    func test_currentSnapshot_returnsNilWhenAbsent() {
        let svc = MemoryDigestService(aiService: AIService(), modelContainer: container)
        XCTAssertNil(svc.currentSnapshot())
    }

    func test_currentSnapshot_returnsRowAfterDigest() async {
        let svc = MemoryDigestService(aiService: AIService(), modelContainer: container)
        await svc.digestConversation([
            .init(role: .user, content: "morning walks"),
        ])
        XCTAssertNotNil(svc.currentSnapshot())
    }

    // MARK: - forgetMe (P2.0 #204)

    func test_forgetMe_wipesAgentMemoryAndTasteProfile() async throws {
        // Seed one snapshot + one taste profile.
        let svc = MemoryDigestService(aiService: AIService(), modelContainer: container)
        await svc.digestConversation([
            .init(role: .user, content: "hello"),
        ])
        let ctx = ModelContext(container)
        ctx.insert(TasteProfile(
            embedding: Data(),
            descriptorsBlob: Data(),
            confidence: 0.5
        ))
        try ctx.save()

        // Sanity check — both rows exist before wipe.
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<AgentMemorySnapshot>()).count, 1)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<TasteProfile>()).count, 1)

        XCTAssertTrue(svc.forgetMe())

        // Fresh context because forgetMe uses its own; poll for effect.
        let ctxAfter = ModelContext(container)
        XCTAssertEqual(try ctxAfter.fetch(FetchDescriptor<AgentMemorySnapshot>()).count, 0)
        XCTAssertEqual(try ctxAfter.fetch(FetchDescriptor<TasteProfile>()).count, 0)
    }

    func test_forgetMe_withoutContainer_returnsFalse() {
        let svc = MemoryDigestService(aiService: AIService(), modelContainer: nil)
        XCTAssertFalse(svc.forgetMe())
    }
}
