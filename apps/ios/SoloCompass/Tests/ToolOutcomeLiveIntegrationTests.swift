import XCTest
@testable import SoloCompass

/// Live LLM integration for the ② tool structured errors refactor.
///
/// The unit + router e2e suites prove the wire format is correct. This suite
/// proves the model actually *reads* it and self-repairs. Without this test
/// the whole ② refactor is unfalsifiable — hints could be gibberish and
/// pass every offline check.
///
/// Skipped when `DEEPSEEK_API_KEY` is not baked into `GeneratedSecrets` so
/// CI stays deterministic; runs locally + on TestFlight builds where the key
/// is present.
@MainActor
final class ToolOutcomeLiveIntegrationTests: XCTestCase {

    private func skipIfNoKey() throws {
        try XCTSkipIf(
            Secrets.resolvedDeepSeekApiKey.isEmpty,
            "DEEPSEEK_API_KEY not configured — skipping live AI self-repair test"
        )
    }

    /// Given a chat where the model just called `explore_nearby(radius=800)`
    /// and got back a `retryable/empty_result` with a `retryable_with:
    /// {radius_meters: 3000}` hint, does the next model turn:
    ///  1. Call the same tool again (not give up), AND
    ///  2. Widen `radius_meters` to ≥3000 (obey the hint)?
    ///
    /// If yes, the hint format is doing its job. If not, either the system
    /// prompt's TOOL OUTCOMES section is unclear, the hint text is bad, or
    /// the model is ignoring structured JSON — all actionable.
    func testModelRespondsToRetryableHintByAdjustingArgs() async throws {
        try skipIfNoKey()

        // Reproduce a real orchestrator turn state: system prompt (with the
        // TOOL OUTCOMES contract), user asks for coffee, assistant already
        // called explore_nearby with a small radius, tool returned a
        // retryable envelope pointing at radius 3000.
        let system = """
        You are Solo Compass, a warm travel companion. When a tool returns
        outcome:"retryable", read the hint, adjust the offending argument
        (retryable_with fields suggest concrete values), and try the SAME tool
        one more time. NEVER retry with identical args. NEVER give up after one
        empty result — the hint tells you exactly how to widen the search.

        TOOL OUTCOMES:
        - "ok" → use payload.
        - "retryable" → adjust args per hint / retryable_with, call SAME tool ONCE more.
        - "fatal" → do not retry, explain briefly to the user.
        - "needs_confirmation" → ask the user the question.
        """

        let toolResultJSON = """
        {"ok":false,"outcome":"retryable","reason":"empty_result","hint":"No coffee shops within 800m of your location. Widen the radius (try 3000m) or drop the category filter and I can look again.","retryable_with":{"radius_meters":3000}}
        """

        let priorToolCallId = "call_live_test_001"
        let messages: [VoiceAgentSession.Message] = [
            .init(role: .system, content: system),
            .init(role: .user, content: "Find me a coffee spot nearby"),
            .init(
                role: .assistant,
                content: nil,
                toolCalls: [VoiceAgentSession.ToolCall(
                    id: priorToolCallId,
                    name: "explore_nearby",
                    argumentsJSON: #"{"latitude":22.5431,"longitude":114.0579,"radius_meters":800,"categories":["coffee"]}"#
                )]
            ),
            .init(
                role: .tool,
                content: toolResultJSON,
                toolCallId: priorToolCallId
            ),
        ]

        // Only offer explore_nearby so the model has one obvious repair path.
        let tools = VoiceAgentToolRouter.allTools.filter { $0.name == "explore_nearby" }

        let ai = AIService()
        let response = try await ai.sendAgentMessage(messages: messages, tools: tools)

        // Diagnostic dump — always visible in test log so a failure shows the
        // actual model output, not just an assertion message.
        print("=== Live model response (retryable) ===")
        print("content: \(response.content ?? "<nil>")")
        for call in response.toolCalls {
            print("tool_call: \(call.name)(\(call.argumentsJSON))")
        }
        print("========================================")

        // 1. Model must call a tool, not surrender with prose.
        XCTAssertFalse(response.toolCalls.isEmpty,
                       "Model gave up with prose instead of retrying: \(response.content ?? "<nil>")")

        // 2. It must be explore_nearby (the same tool, per the hint).
        let call = try XCTUnwrap(response.toolCalls.first, "expected at least one tool call")
        XCTAssertEqual(call.name, "explore_nearby",
                       "Model should retry the SAME tool per hint, not switch tools mid-repair")

        // 3. radius_meters must widen. Parse the args and check the field.
        struct RetryArgs: Decodable {
            let radius_meters: Int?
            let latitude: Double?
            let longitude: Double?
        }
        let data = try XCTUnwrap(call.argumentsJSON.data(using: .utf8))
        let args = try JSONDecoder().decode(RetryArgs.self, from: data)

        let newRadius = args.radius_meters ?? 0
        XCTAssertGreaterThanOrEqual(newRadius, 3000,
            "Model ignored the retryable_with hint. Expected radius_meters ≥ 3000, got \(newRadius). Full args: \(call.argumentsJSON)")
    }

    /// Given a `fatal` outcome, the model must NOT retry the tool. It should
    /// either surrender to prose or (accepted) call a different tool. This is
    /// the counterpart safety test: if the model retries a fatal, the retry
    /// budget is ineffective and we're back in the death-spiral pattern the
    /// ② refactor exists to prevent.
    func testModelDoesNotRetryFatalOutcome() async throws {
        try skipIfNoKey()

        let system = """
        You are Solo Compass. TOOL OUTCOMES:
        - "fatal" → do not call the same tool again. Explain briefly to the user or, if genuinely useful, call a different tool.
        """
        let fatalJSON = """
        {"ok":false,"outcome":"fatal","reason":"map_unavailable","hint":"The map session isn't active. Ask the user to reopen the map before this tool can run."}
        """

        let priorToolCallId = "call_live_test_002"
        let messages: [VoiceAgentSession.Message] = [
            .init(role: .system, content: system),
            .init(role: .user, content: "Show me coffee nearby"),
            .init(
                role: .assistant,
                content: nil,
                toolCalls: [VoiceAgentSession.ToolCall(
                    id: priorToolCallId,
                    name: "explore_nearby",
                    argumentsJSON: #"{"latitude":22.5,"longitude":114.0}"#
                )]
            ),
            .init(role: .tool, content: fatalJSON, toolCallId: priorToolCallId),
        ]

        let tools = VoiceAgentToolRouter.allTools.filter { $0.name == "explore_nearby" }
        let ai = AIService()
        let response = try await ai.sendAgentMessage(messages: messages, tools: tools)

        print("=== Fatal-outcome model response ===")
        print("content: \(response.content ?? "<nil>")")
        for call in response.toolCalls {
            print("tool_call: \(call.name)(\(call.argumentsJSON))")
        }
        print("====================================")

        // No retry of the same tool.
        let retriedSame = response.toolCalls.contains { $0.name == "explore_nearby" }
        XCTAssertFalse(retriedSame,
                       "Model retried explore_nearby AFTER a fatal outcome — the retry-budget is not being respected. Full response: \(response.content ?? "<nil>")")
    }
}
