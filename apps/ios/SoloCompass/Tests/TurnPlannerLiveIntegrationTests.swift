import XCTest
@testable import SoloCompass

/// Live LLM integration for the ① Plan-Execute-Reflect layer.
///
/// The heuristic suite proves the fast path never wastes an API call. This
/// suite proves the slow path — the LLM planner + compound execution — works
/// end-to-end and produces plans the main agent turn can actually use.
///
/// Skipped when `DEEPSEEK_API_KEY` isn't baked into `GeneratedSecrets`.
@MainActor
final class TurnPlannerLiveIntegrationTests: XCTestCase {

    private func skipIfNoKey() throws {
        try XCTSkipIf(
            Secrets.resolvedDeepSeekApiKey.isEmpty,
            "DEEPSEEK_API_KEY not configured — skipping live planner test"
        )
    }

    /// A recognisably compound Shenzhen morning ask must round-trip:
    ///  1. Heuristic flags it `.suspectCompound` (not `.single`).
    ///  2. LLM produces a valid strict-JSON plan (`intent="compound"`).
    ///  3. The plan has ≥ 2 steps, every `expected_tool` is real.
    ///  4. At least one step names a Solo Compass tool actually catalogued
    ///     in `VoiceAgentToolRouter.allTools`.
    func testCompoundShenzhenMorningReturnsUsablePlan() async throws {
        try skipIfNoKey()

        let transcript = "帮我规划一下明天早上的深圳一日:先喝咖啡,再去博物馆,最后串成一条路线"

        // Step 1: heuristic gate.
        guard case .suspectCompound = TurnPlanner.heuristicClassify(transcript: transcript) else {
            XCTFail("Heuristic should flag a multi-verb, multi-category, sequencing-cue Chinese transcript as compound")
            return
        }

        // Step 2-4: run the LLM planner.
        let planner = TurnPlanner(aiService: AIService())
        let plan = await planner.plan(transcript: transcript)

        print("=== TurnPlan (live) ===")
        print("intent: \(plan.intent.rawValue)")
        print("rationale: \(plan.rationale)")
        for (i, step) in plan.steps.enumerated() {
            print("  [\(i + 1)] \(step.goal) — tool=\(step.expectedTool ?? "nil") reflect=\(step.reflectAfter)")
        }
        print("========================")

        XCTAssertEqual(plan.intent, .compound,
                       "LLM should confirm compound intent on this transcript")
        XCTAssertGreaterThanOrEqual(plan.steps.count, 2, "Compound plan must produce ≥2 steps")
        XCTAssertLessThanOrEqual(plan.steps.count, 5, "TurnPlan.compound caps at 5 steps")

        // Every expectedTool must be a real tool name or nil. We don't require
        // that the LLM commit upfront — nil is a legitimate "exploratory step"
        // signal.
        let toolNames = Set(VoiceAgentToolRouter.allTools.map(\.name))
        for step in plan.steps {
            if let name = step.expectedTool {
                XCTAssertTrue(toolNames.contains(name),
                              "Step names unknown tool '\(name)'. Real tools: \(toolNames.sorted())")
            }
            XCTAssertFalse(step.goal.trimmingCharacters(in: .whitespaces).isEmpty,
                           "Step goal must not be empty")
        }

        // At least ONE step must commit to a real tool so the main turn has
        // something concrete to execute. All-nil plans defeat the point.
        let committedSteps = plan.steps.compactMap { $0.expectedTool }
        XCTAssertFalse(committedSteps.isEmpty,
                       "Compound plan should commit to at least one concrete tool. Steps: \(plan.steps)")
    }

    /// A simple ask must fall through the heuristic to `.single` — zero API
    /// round-trip for planning. This is the cost-invariant every product turn
    /// depends on.
    func testSingleAskDoesNotHitPlannerAPI() async {
        // Explicitly does NOT skip on missing key — the fast path never talks
        // to the LLM, so this test doubles as a check that the planner never
        // touches Secrets on the hot path.
        let planner = TurnPlanner(aiService: AIService())
        let plan = await planner.plan(transcript: "Show me the second one")

        XCTAssertEqual(plan.intent, .single,
                       "A trivial follow-up MUST stay on the fast path")
        XCTAssertTrue(plan.rationale.hasPrefix("heuristic:single"),
                      "A short follow-up should be caught by the heuristic (no API roundtrip). rationale=\(plan.rationale)")
    }
}
