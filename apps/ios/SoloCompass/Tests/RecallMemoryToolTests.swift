import XCTest
import CoreLocation
@testable import SoloCompass

/// ③ Memory三层 slice A: end-to-end router tests for the `recall_memory` tool.
///
/// Combines with `MemoryEpisodeStoreTests` (storage layer) and the live
/// integration below (LLM contract). This suite pins the wire envelope +
/// error surface — same guarantees as `ToolRouterOutcomeTests` but for the
/// first tool built natively on the new `ToolOutcome` API.
@MainActor
final class RecallMemoryToolTests: XCTestCase {

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "recall.memory.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeExperience(id: String) -> Experience {
        let now = Date()
        return Experience(
            id: id,
            title: "Fixture \(id)",
            oneLiner: "Fixture \(id)",
            whyItMatters: "Recall memory fixture",
            category: .coffee,
            location: ExperienceLocation(coordinates: [114.05, 22.54], cityCode: "szx"),
            bestTimes: [],
            durationMinutes: .init(min: 30, max: 60),
            howTo: [],
            realInconveniences: [],
            soloScore: SoloScore(
                overall: 5,
                breakdown: .init(
                    seatingFriendly: 7, soloPatronRatio: 7, staffPressure: 7,
                    soloPortioning: 7, ambianceFit: 7, safety: 7
                ),
                basedOnCount: 1
            ),
            sources: [InformationSource(type: .user, attribution: "test", verifiedAt: now)],
            confidence: Confidence(
                level: 3,
                lastVerifiedAt: now,
                reason: "Test fixture",
                signals: .init(aiScrapeAgeDays: 1, passiveGpsHits30d: 0, activeReports30d: 0, trustedVerifications: 0)
            ),
            nearbyExperienceIds: [],
            stats: .init(completionCount: 0, averageRating: 0),
            status: .active,
            createdAt: now,
            updatedAt: now
        )
    }

    private final class Fixture {
        let router: VoiceAgentToolRouter
        let vm: MapViewModel
        let prefs: UserPreferences
        init(router: VoiceAgentToolRouter, vm: MapViewModel, prefs: UserPreferences) {
            self.router = router; self.vm = vm; self.prefs = prefs
        }
    }

    private func makeFixture(seed: [MemoryEpisodeStore.Episode] = []) -> Fixture {
        let prefs = UserPreferences(defaults: makeIsolatedDefaults())
        prefs.lastSelectedCity = "szx"
        let service = ExperienceService(seed: [makeExperience(id: "szx_1")])
        let vm = MapViewModel(
            locationService: LocationService(),
            experienceService: service,
            aiService: AIService(),
            preferences: prefs
        )
        let router = VoiceAgentToolRouter(mapViewModel: vm, preferences: prefs, aiService: nil)
        for ep in seed { router.memoryStore.insert(ep) }
        return Fixture(router: router, vm: vm, prefs: prefs)
    }

    private func call(_ name: String, args: String) -> VoiceAgentSession.ToolCall {
        VoiceAgentSession.ToolCall(id: "test-\(UUID().uuidString.prefix(8))", name: name, argumentsJSON: args)
    }

    private func parse(_ json: String) throws -> [String: Any] {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Empty store → retryable(emptyResult)

    func testEmptyStoreReturnsRetryableWithHint() async throws {
        let f = makeFixture()
        let json = await f.router.execute(call("recall_memory", args: #"{"query":"the sunny cafe"}"#))
        let dict = try parse(json)
        XCTAssertEqual(dict["outcome"] as? String, "retryable")
        XCTAssertEqual(dict["reason"] as? String, "empty_result")
        let hint = try XCTUnwrap(dict["hint"] as? String)
        XCTAssertTrue(hint.contains("the sunny cafe"), "hint should echo the query: \(hint)")
    }

    // MARK: - Match → ok(payload)

    func testMatchReturnsOKWithPayload() async throws {
        let f = makeFixture(seed: [
            .init(
                occurredAt: Date().addingTimeInterval(-86_400),
                cityCode: "szx",
                title: "Sunlit corner cafe in Futian",
                body: "Quiet coffee in the morning, wrote for two hours near Gangxia.",
                tags: ["coffee", "quiet"]
            ),
            .init(
                occurredAt: Date().addingTimeInterval(-172_800),
                cityCode: "szx",
                title: "Ramen at Coco Ichibanya",
                body: "Rainy night, spicy curry, felt good.",
                tags: ["food", "rainy"]
            ),
        ])
        let json = await f.router.execute(call("recall_memory", args: #"{"query":"quiet coffee morning cafe"}"#))
        let dict = try parse(json)
        XCTAssertEqual(dict["outcome"] as? String, "ok")

        let payload = try XCTUnwrap(dict["payload"] as? [String: Any])
        let hits = try XCTUnwrap(payload["hits"] as? [[String: Any]])
        XCTAssertFalse(hits.isEmpty)
        let first = try XCTUnwrap(hits.first)
        XCTAssertEqual(first["title"] as? String, "Sunlit corner cafe in Futian",
                       "coffee query should surface the coffee episode first")
        XCTAssertTrue((first["score"] as? Double ?? 0) > 0,
                      "score must be positive when there's a real match")
    }

    // MARK: - Bad args → retryable(invalidArgs)

    func testEmptyQueryReturnsRetryableInvalidArgs() async throws {
        let f = makeFixture()
        let json = await f.router.execute(call("recall_memory", args: #"{"query":""}"#))
        let dict = try parse(json)
        XCTAssertEqual(dict["outcome"] as? String, "retryable")
        XCTAssertEqual(dict["reason"] as? String, "invalid_args")
    }

    // MARK: - City filter → retryable with widen hint

    func testCityFilterEmptyResultOffersWidenHint() async throws {
        let f = makeFixture(seed: [
            .init(
                occurredAt: Date().addingTimeInterval(-86_400),
                cityCode: "cmi",
                title: "Chiang Mai morning coffee",
                body: "Quiet cafe near the wall.",
                tags: ["coffee"]
            )
        ])
        let json = await f.router.execute(call("recall_memory", args: #"{"query":"morning coffee","city_code":"szx"}"#))
        let dict = try parse(json)
        XCTAssertEqual(dict["outcome"] as? String, "retryable")
        let hint = try XCTUnwrap(dict["hint"] as? String)
        XCTAssertTrue(hint.contains("szx") || hint.contains("city_code"),
                      "hint should call out the city_code so the model knows to widen: \(hint)")
        let retryHint = dict["retryable_with"] as? [String: Any]
        XCTAssertNotNil(retryHint, "retryable_with should suggest dropping city_code")
    }
}
