import XCTest
@testable import SoloCompass

/// Heuristic-only tests for `TurnPlanner.heuristicClassify` — the fast path
/// that decides in Swift whether a turn even deserves a planning API call.
///
/// This suite is deterministic (no network), so it runs on every CI + local
/// build. The LLM-planning fallback is exercised separately in the live
/// integration suite.
///
/// The point of these tests: lock in that the vast majority of real user
/// turns short-circuit to `.single` with zero API overhead. Every regression
/// on this file directly costs money and latency.
final class TurnPlannerHeuristicTests: XCTestCase {

    // MARK: - Single (fast path — MUST stay cheap)

    func testShortAffirmationIsSingle() {
        XCTAssertEqual(TurnPlanner.heuristicClassify(transcript: "yes"), .single)
        XCTAssertEqual(TurnPlanner.heuristicClassify(transcript: "the second one"), .single)
        XCTAssertEqual(TurnPlanner.heuristicClassify(transcript: "closer"), .single)
        XCTAssertEqual(TurnPlanner.heuristicClassify(transcript: "试试第二个"), .single)
    }

    func testSingleActionAskIsSingle() {
        XCTAssertEqual(TurnPlanner.heuristicClassify(transcript: "Find me a coffee shop nearby"), .single)
        XCTAssertEqual(TurnPlanner.heuristicClassify(transcript: "附近有什么好吃的"), .single)
        XCTAssertEqual(TurnPlanner.heuristicClassify(transcript: "Show me the museum"), .single)
    }

    func testDetailFollowUpIsSingle() {
        XCTAssertEqual(TurnPlanner.heuristicClassify(transcript: "tell me more about that place"), .single)
    }

    // MARK: - Compound (justifies an extra API round-trip)

    func testJoinCueMakesItCompound() {
        if case .suspectCompound = TurnPlanner.heuristicClassify(transcript: "plan a walk through Futian for me") {
            // ok
        } else {
            XCTFail("plan-a-walk should trip the join cue")
        }
        if case .suspectCompound = TurnPlanner.heuristicClassify(transcript: "把这几个地方串起来") {
            // ok
        } else {
            XCTFail("串起来 should trip the CJK join cue")
        }
    }

    func testMultiCategoryTimeSpanIsCompound() {
        if case .suspectCompound(let sig) = TurnPlanner.heuristicClassify(
            transcript: "Find me coffee and lunch for tomorrow morning"
        ) {
            XCTAssertTrue(sig.hasTimeSpan)
            XCTAssertGreaterThanOrEqual(sig.categoryHits.count, 2)
        } else {
            XCTFail("multi-category + time span should be compound")
        }
    }

    func testChineseCompoundAsk() {
        if case .suspectCompound = TurnPlanner.heuristicClassify(
            transcript: "帮我规划一下明天早上的深圳,先喝咖啡再去博物馆"
        ) {
            // ok
        } else {
            XCTFail("多动词+早上+先..再.. 应判 compound")
        }
    }

    func testSequencingCuePlusVerbIsCompound() {
        if case .suspectCompound = TurnPlanner.heuristicClassify(
            transcript: "First find a cafe, then check the park"
        ) {
            // ok
        } else {
            XCTFail("first…then… + 2 verbs should be compound")
        }
    }

    // MARK: - Clarify (short + vague, cost-avoiding)

    func testShortVagueAskIsClarify() {
        if case .clarify(let q) = TurnPlanner.heuristicClassify(transcript: "推荐一下") {
            XCTAssertFalse(q.isEmpty, "clarify must carry a question")
        } else {
            XCTFail("bare '推荐一下' should clarify")
        }
    }

    func testVagueButLongerFallsThroughToSingle() {
        XCTAssertEqual(
            TurnPlanner.heuristicClassify(transcript: "推荐一下附近的咖啡"),
            .single,
            "adding a category should shift clarify → single"
        )
    }

    // MARK: - Regression guardrails

    func testEmptyTranscriptIsSingle() {
        XCTAssertEqual(TurnPlanner.heuristicClassify(transcript: "   "), .single,
                       "whitespace should never trigger a planning API call")
    }

    func testAllPlannerConstructorsRoundTripEncoding() throws {
        let plans: [TurnPlan] = [
            .single(rationale: "heuristic:single"),
            .clarify(question: "What are you in the mood for?", rationale: "heuristic:clarify"),
            .compound(steps: [
                PlannedStep(goal: "Find a cafe", expectedTool: "search_places", reflectAfter: false),
                PlannedStep(goal: "Filter by rating", expectedTool: "filter_visible", reflectAfter: true),
            ], rationale: "llm:compound"),
        ]
        let enc = JSONEncoder()
        let dec = JSONDecoder()
        for original in plans {
            let data = try enc.encode(original)
            let decoded = try dec.decode(TurnPlan.self, from: data)
            XCTAssertEqual(decoded, original, "TurnPlan round-trip lost fidelity: \(original)")
        }
    }

    func testCompoundConstructorCapsAt5Steps() {
        let bigSteps = (0..<10).map {
            PlannedStep(goal: "step \($0)", expectedTool: nil, reflectAfter: false)
        }
        let plan = TurnPlan.compound(steps: bigSteps, rationale: "test")
        XCTAssertEqual(plan.steps.count, 5, "TurnPlan.compound must cap at 5 steps")
    }
}
