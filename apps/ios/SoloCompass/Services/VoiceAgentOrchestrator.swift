import Foundation
import Observation
import CoreLocation

/// Drives one `VoiceAgentSession` through the thinking ↔ tool_executing
/// loop until the model produces final assistant content or one of the
/// budgets trips (recursion depth, wall-clock timeout, user cancellation).
///
/// US-VA-06: orchestration only — no UI, no HTTP construction. The
/// view-model owns one orchestrator per voice sheet presentation; the
/// view (`ConversationSheet`) reads `session` for state.
@MainActor
@Observable
public final class VoiceAgentOrchestrator {

    // MARK: - State

    public let session: VoiceAgentSession
    private let aiService: AIService
    private let router: VoiceAgentToolRouter

    /// Currently-running turn, retained so `cancel()` can cooperatively
    /// kill the in-flight think/tool loop.
    private var currentTurnTask: Task<Void, Never>?

    public init(
        session: VoiceAgentSession,
        aiService: AIService,
        router: VoiceAgentToolRouter
    ) {
        self.session = session
        self.aiService = aiService
        self.router = router
    }

    // MARK: - Public API

    /// Seed the session with a system prompt. Call once before the first
    /// user turn. The system prompt is the long bilingual block from
    /// PRD §6.1; the caller owns the exact text so it can be A/B tested
    /// without touching this file.
    public func start(systemPrompt: String) {
        guard session.messages.isEmpty else { return }
        session.seedSystem(systemPrompt)
    }

    /// Process one user turn end-to-end. Safe to await from the view;
    /// races against `cancel()` and the per-turn timeout.
    ///
    /// `visibleExperiences` and `userLocation` are injected into a
    /// per-turn system continuation so the model can resolve "the
    /// second one" without inventing ids (PRD §6.2).
    public func handleUserTurn(
        transcript: String,
        visibleExperiences: [Experience],
        userLocation: CLLocationCoordinate2D?
    ) async {
        guard !session.isEnded else { return }
        currentTurnTask?.cancel()
        let task = Task {
            await runTurn(
                transcript: transcript,
                visibleExperiences: visibleExperiences,
                userLocation: userLocation
            )
        }
        currentTurnTask = task
        await task.value
    }

    /// User pulled the rip-cord (× button, app backgrounded mid-turn).
    /// Cancels the current Task; the loop sees `Task.isCancelled` and
    /// stops without appending more rows.
    public func cancel() {
        currentTurnTask?.cancel()
        currentTurnTask = nil
        if !session.isEnded {
            session.end(reason: .userClose)
        }
    }

    // MARK: - Turn loop

    /// One end-to-end user turn: optionally inject context, then loop
    /// (DeepSeek → execute tool_calls → DeepSeek …) up to the recursion
    /// budget; wrapped in a wall-clock timeout (PRD §5.1).
    private func runTurn(
        transcript: String,
        visibleExperiences: [Experience],
        userLocation: CLLocationCoordinate2D?
    ) async {
        appendPerTurnSystemContext(
            visibleExperiences: visibleExperiences,
            userLocation: userLocation
        )
        session.beginUserTurn(transcript: transcript)

        let timeoutSeconds = VoiceAgentSession.turnTimeoutSeconds
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor [weak self] in
                    await self?.runThinkLoop()
                }
                group.addTask {
                    try await Task.sleep(
                        nanoseconds: UInt64(timeoutSeconds * 1_000_000_000)
                    )
                    throw VoiceAgentError.turnTimeout
                }
                // First branch to finish wins. If think finishes first
                // the timeout sleep gets cancelled when we cancelAll();
                // if the timeout fires it throws and we drop the loop.
                _ = try await group.next()
                group.cancelAll()
            }
        } catch is CancellationError {
            // user-initiated cancel — no-op; session already moved by cancel()
            return
        } catch VoiceAgentError.turnTimeout {
            session.end(reason: .timeout)
        } catch {
            session.end(reason: .error)
        }
    }

    /// `thinking → toolExecuting → thinking → …` loop. Stops on:
    /// - assistant content with no tool_calls (success: finishSpeakingTurn)
    /// - recursion budget exhausted (synthesise refusal results so the
    ///   model has a clean chance to wrap up on the next turn)
    /// - any network failure (ends the session as .error)
    /// - external cancellation (Task.isCancelled → bail silently)
    private func runThinkLoop() async {
        while !Task.isCancelled {
            do {
                let response = try await aiService.sendAgentMessage(
                    messages: session.messages,
                    tools: VoiceAgentToolRouter.allTools
                )
                if Task.isCancelled { return }

                if response.toolCalls.isEmpty {
                    session.appendAssistantTurn(
                        content: response.content,
                        toolCalls: []
                    )
                    session.finishSpeakingTurn()
                    return
                }

                // tool_calls path
                session.appendAssistantTurn(
                    content: response.content,
                    toolCalls: response.toolCalls
                )

                if session.hasExceededRecursionBudget {
                    // Force the next pass to be content-only by feeding
                    // synthetic refusals for every pending call.
                    for call in response.toolCalls {
                        session.appendToolResult(
                            toolCallId: call.id,
                            name: call.name,
                            resultJSON: #"{"ok":false,"error":"recursion_budget_exhausted"}"#
                        )
                    }
                    session.resumeThinkingAfterTools()
                    continue
                }

                await executeToolCallsInParallel(response.toolCalls)
                if Task.isCancelled { return }
                session.resumeThinkingAfterTools()
            } catch {
                if Task.isCancelled { return }
                if error is CancellationError { return }
                session.end(reason: .error)
                return
            }
        }
    }

    /// Fan tool calls out as a TaskGroup so independent tools (e.g.
    /// `filter_by_category` + `explore_nearby`) overlap. Results are
    /// appended back in the input order so the conversation reads naturally.
    private func executeToolCallsInParallel(
        _ calls: [VoiceAgentSession.ToolCall]
    ) async {
        var results: [String?] = Array(repeating: nil, count: calls.count)
        await withTaskGroup(of: (Int, String).self) { group in
            for (index, call) in calls.enumerated() {
                let router = self.router
                group.addTask { @MainActor in
                    let json = await router.execute(call)
                    return (index, json)
                }
            }
            for await (index, json) in group {
                results[index] = json
            }
        }
        for (index, call) in calls.enumerated() {
            let json = results[index] ?? #"{"ok":false,"error":"missing_result"}"#
            session.appendToolResult(
                toolCallId: call.id, name: call.name, resultJSON: json
            )
        }
    }

    // MARK: - Per-turn system context (PRD §6.2)

    /// Append a system continuation listing up to N visible experiences
    /// + the user's location. We append (not replace) so the AI sees a
    /// fresh snapshot each turn. The orchestrator never edits past msgs.
    private func appendPerTurnSystemContext(
        visibleExperiences: [Experience],
        userLocation: CLLocationCoordinate2D?
    ) {
        let summarised = visibleExperiences
            .prefix(VoiceAgentSession.visibleExperiencesInjected)
            .map { exp in
                "- \(exp.id): \"\(exp.title)\" [\(exp.category.rawValue)]"
            }
            .joined(separator: "\n")
        let locationLine: String
        if let coord = userLocation {
            locationLine = "USER_LOCATION: lat=\(String(format: "%.4f", coord.latitude)) lon=\(String(format: "%.4f", coord.longitude))"
        } else {
            locationLine = "USER_LOCATION: unknown"
        }
        let payload = """
        VISIBLE_EXPERIENCES (max \(VoiceAgentSession.visibleExperiencesInjected), ranked):
        \(summarised.isEmpty ? "(none on map yet — explore_nearby first)" : summarised)
        \(locationLine)
        """
        session.appendSystemContext(payload)
    }
}

// MARK: - Errors

enum VoiceAgentError: Error {
    case turnTimeout
}
