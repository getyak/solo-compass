import XCTest
import CoreLocation
@testable import SoloCompass

/// End-to-end router tests for the ② tool structured errors refactor.
///
/// The point of this suite: prove that every error path a real handler can
/// throw shows up on the wire in the new `ToolOutcome` envelope shape the
/// model was taught in the system prompt — otherwise the model can't self-
/// repair, even if the router does its own bookkeeping correctly.
///
/// Complements `ToolOutcomeTests`, which pins the envelope shape in isolation.
/// This suite runs the actual `VoiceAgentToolRouter.execute(_:)` dispatcher
/// against a real `MapViewModel` fixture and asserts what lands in the JSON.
@MainActor
final class ToolRouterOutcomeTests: XCTestCase {

    // MARK: - Fixtures

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "tool.router.outcome.\(UUID().uuidString)"
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
            whyItMatters: "Router outcome fixture",
            category: .food,
            location: ExperienceLocation(coordinates: [98.9938, 18.7877], cityCode: "cmi"),
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

    /// Fixture bag — the router only holds `MapViewModel` weakly (so a live
    /// sheet dismissal frees the map), so we hand back the strong owner too.
    /// Every test binds `let f = makeRouter()` and passes `f.router` around;
    /// `f` itself keeps `vm` alive for the duration of the test.
    private final class Fixture {
        let router: VoiceAgentToolRouter
        let vm: MapViewModel
        let prefs: UserPreferences
        init(router: VoiceAgentToolRouter, vm: MapViewModel, prefs: UserPreferences) {
            self.router = router; self.vm = vm; self.prefs = prefs
        }
    }

    private func makeRouter(seed: [Experience] = []) -> Fixture {
        let prefs = UserPreferences(defaults: makeIsolatedDefaults())
        prefs.lastSelectedCity = "cmi"
        let service = ExperienceService(seed: seed.isEmpty ? [makeExperience(id: "cmi_1")] : seed)
        let vm = MapViewModel(
            locationService: LocationService(),
            experienceService: service,
            aiService: AIService(),
            preferences: prefs
        )
        let router = VoiceAgentToolRouter(mapViewModel: vm, preferences: prefs, aiService: nil)
        return Fixture(router: router, vm: vm, prefs: prefs)
    }

    private func call(_ name: String, args: String = "{}") -> VoiceAgentSession.ToolCall {
        VoiceAgentSession.ToolCall(id: "test-\(UUID().uuidString.prefix(8))", name: name, argumentsJSON: args)
    }

    /// Parse a router JSON envelope. Returns nil (with a diagnostic) if it's
    /// not a top-level dictionary — the router should NEVER emit anything else.
    private func parse(_ json: String, file: StaticString = #file, line: UInt = #line) -> [String: Any]? {
        guard let data = json.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            XCTFail("Router did not emit a top-level JSON object: \(json)", file: file, line: line)
            return nil
        }
        return dict
    }

    // MARK: - Unknown tool → fatal.unknownTool

    func testUnknownToolIsFatalWithHint() async throws {
        let f = makeRouter()
        let json = await f.router.execute(call("does_not_exist"))
        let dict = try XCTUnwrap(parse(json))

        XCTAssertEqual(dict["ok"] as? Bool, false)
        XCTAssertEqual(dict["outcome"] as? String, "fatal")
        XCTAssertEqual(dict["reason"] as? String, "unknown_tool")
        let hint = try XCTUnwrap(dict["hint"] as? String)
        XCTAssertTrue(hint.contains("does_not_exist"), "hint should name the offending tool: \(hint)")
        XCTAssertTrue(hint.lowercased().contains("do not retry") || hint.lowercased().contains("not a known"),
                      "hint should discourage retry: \(hint)")
    }

    // MARK: - Bad arguments → retryable.invalidArgs, then fatal after budget

    func testInvalidArgsRetryableWithSchemaHint() async throws {
        let f = makeRouter()
        // filter_by_category requires `category` — omit it entirely.
        let json = await f.router.execute(call("filter_by_category", args: "{}"))
        let dict = try XCTUnwrap(parse(json))

        XCTAssertEqual(dict["outcome"] as? String, "retryable")
        XCTAssertEqual(dict["reason"] as? String, "invalid_args")
        let hint = try XCTUnwrap(dict["hint"] as? String)
        XCTAssertTrue(hint.contains("filter_by_category"), "hint names the tool: \(hint)")
        XCTAssertTrue(hint.lowercased().contains("schema") || hint.lowercased().contains("fix"),
                      "hint suggests recovery: \(hint)")
    }

    func testInvalidArgsBudgetEscalatesToFatal() async throws {
        let f = makeRouter()
        // 3 attempts with the same bad-args shape → 4th call must escalate to
        // fatal.retry_budget_exhausted so the model stops looping.
        for _ in 0..<3 {
            _ = await f.router.execute(call("filter_by_category", args: "{}"))
        }
        let json = await f.router.execute(call("filter_by_category", args: "{}"))
        let dict = try XCTUnwrap(parse(json))

        XCTAssertEqual(dict["outcome"] as? String, "fatal")
        XCTAssertEqual(dict["reason"] as? String, "retry_budget_exhausted")
        let hint = try XCTUnwrap(dict["hint"] as? String)
        XCTAssertTrue(hint.contains("filter_by_category"),
                      "budget-exhausted hint should still name the offending tool: \(hint)")
    }

    func testRetryLedgerResetsPerTurnAllowsFreshRetries() async throws {
        let f = makeRouter()
        for _ in 0..<3 {
            _ = await f.router.execute(call("filter_by_category", args: "{}"))
        }
        XCTAssertTrue(f.router.retryLedger.isExhausted(tool: "filter_by_category", reason: "invalid_args"),
                      "budget exhausted after 3 same-reason retries")

        f.router.retryLedger.resetForNewTurn()
        let json = await f.router.execute(call("filter_by_category", args: "{}"))
        let dict = try XCTUnwrap(parse(json))
        XCTAssertEqual(dict["outcome"] as? String, "retryable",
                       "after resetForNewTurn(), same call should be retryable again — the new user turn deserves a fresh chance")
    }

    // MARK: - Not found → retryable.notFound with visibleHint

    func testExperienceNotFoundCarriesVisibleIDHint() async throws {
        let f = makeRouter(seed: [makeExperience(id: "cmi_1"), makeExperience(id: "cmi_2")])
        let json = await f.router.execute(call("show_details", args: #"{"experience_id":"not_a_real_id"}"#))
        let dict = try XCTUnwrap(parse(json))

        XCTAssertEqual(dict["outcome"] as? String, "retryable")
        XCTAssertEqual(dict["reason"] as? String, "not_found")
        let hint = try XCTUnwrap(dict["hint"] as? String)
        XCTAssertTrue(hint.contains("not_a_real_id"),
                      "hint echoes the offending id: \(hint)")
        // Highest-leverage nudge: the hint should list at least one valid id
        // the model can retry with.
        XCTAssertTrue(hint.contains("cmi_1") || hint.contains("cmi_2"),
                      "hint should list a valid visible id so the model can self-repair: \(hint)")
    }

    // MARK: - OK path — a real handler still produces a parseable envelope

    func testFilterByCategoryOKEnvelope() async throws {
        // NB: filter_by_category is a pure map-side op — no network. Success
        // path currently still uses the legacy successJSON, so this test
        // documents that behavior and pins it as intentional until we migrate
        // handlers one by one to native `ToolOutcome.ok(...)`.
        let f = makeRouter()
        let json = await f.router.execute(call("filter_by_category", args: #"{"category":"food"}"#))
        let dict = try XCTUnwrap(parse(json))
        XCTAssertEqual(dict["ok"] as? Bool, true,
                       "success envelope keeps the legacy ok:true so old chat transcripts still parse")
    }
}
