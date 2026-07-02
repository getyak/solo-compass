import XCTest
@testable import SoloCompass

/// ③ Memory三层 slice A: live LLM check that the model uses the
/// `recall_memory` payload naturally in its reply.
///
/// This is the highest-signal proof that the whole ③ layer is wired: the
/// model reads the payload we handed it, and the reply text reflects it.
/// Skipped when no DeepSeek key is baked in.
@MainActor
final class RecallMemoryLiveIntegrationTests: XCTestCase {

    private func skipIfNoKey() throws {
        try XCTSkipIf(
            Secrets.resolvedDeepSeekApiKey.isEmpty,
            "DEEPSEEK_API_KEY not configured — skipping live recall_memory test"
        )
    }

    func testModelUsesRecallPayloadInReply() async throws {
        try skipIfNoKey()

        let system = """
        You are Solo Compass, a warm travel companion. TOOL OUTCOMES:
        - `ok` → use payload; if a `hint` is present, follow it.
        - `retryable` → adjust and retry once.
        - `fatal` → do not retry.

        When the user references past context ("remember", "上次", "the last cafe"),
        call `recall_memory` first. When a `recall_memory` result comes back OK,
        WEAVE it into your reply — name the place, cite the mood, refer to when
        it happened. Never drop a raw dump; two short sentences that feel personal.
        """

        // Simulated router response — same shape as the real
        // executeRecallMemory would produce.
        let recallResultJSON = #"""
        {
          "ok": true,
          "outcome": "ok",
          "hint": "Cite the surfaced episodes with a natural aside — 'you mentioned X last time' — before your recommendation. Don't dump the full body verbatim.",
          "payload": {
            "queried": "the sunny corner cafe we tried before",
            "hits": [
              {
                "id": "11111111-2222-3333-4444-555555555555",
                "occurred_at": "2026-05-14T09:00:00Z",
                "city_code": "cmi",
                "title": "Ristr8to on Nimman Soi 3",
                "body": "Sunlit corner cafe near Nimman Soi 3 — spent the morning writing, said it felt like your quietest hour in Chiang Mai.",
                "tags": ["coffee", "quiet", "morning", "chiang_mai"],
                "score": 3.2
              }
            ]
          }
        }
        """#

        let toolCallId = "call_live_recall_001"
        let messages: [VoiceAgentSession.Message] = [
            .init(role: .system, content: system),
            .init(role: .user, content: "Take me back to that sunny corner cafe we tried before — where was it again?"),
            .init(
                role: .assistant,
                content: nil,
                toolCalls: [VoiceAgentSession.ToolCall(
                    id: toolCallId,
                    name: "recall_memory",
                    argumentsJSON: #"{"query":"the sunny corner cafe we tried before"}"#
                )]
            ),
            .init(role: .tool, content: recallResultJSON, toolCallId: toolCallId, name: "recall_memory"),
        ]

        // No tools this turn — we want the final natural-language reply.
        let ai = AIService()
        let response = try await ai.sendAgentMessage(messages: messages, tools: [])

        print("=== recall_memory live reply ===")
        print("content: \(response.content ?? "<nil>")")
        print("tool_calls: \(response.toolCalls.map { $0.name })")
        print("================================")

        // Prose reply present.
        let content = try XCTUnwrap(response.content?.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertFalse(content.isEmpty, "Model must reply with prose after recall_memory ok")

        // Grounded in the payload (place, neighborhood, or city).
        let lower = content.lowercased()
        let grounded =
            lower.contains("ristr8to") ||
            lower.contains("nimman") ||
            lower.contains("chiang mai")
        XCTAssertTrue(grounded,
            "Reply must ground itself in the recall payload (Ristr8to / Nimman / Chiang Mai). Got: \(content)")
    }
}
