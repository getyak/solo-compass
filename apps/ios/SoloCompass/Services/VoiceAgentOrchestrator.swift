import AVFoundation
import CoreLocation
import Foundation
import Observation

/// Drives one VoiceAgentSession through the think → tool_execute → repeat loop.
///
/// US-VA-06: owns the tight loop logic that was deliberately left out of
/// VoiceAgentSession (the session is pure model, no I/O). Create one per
/// ConversationSheet presentation; discard when the sheet closes.
@MainActor
@Observable
public final class VoiceAgentOrchestrator: Identifiable {

    // MARK: - Dependencies

    public let session = VoiceAgentSession()
    private let aiService: AIService
    private let voiceService: VoiceService
    private let toolRouter: VoiceAgentToolRouter
    private weak var mapViewModel: MapViewModel?

    // MARK: - State

    public let id = UUID()
    public private(set) var isRunning = false
    public private(set) var errorMessage: String?

    /// Streaming text being assembled word-by-word; cleared when the final
    /// assistant message is committed to the session.
    public private(set) var streamingContent: String = ""

    /// Human-readable label for the current thinking/tool step shown in the overlay.
    public private(set) var thinkingStep: String = ""

    /// True while a tool is executing.
    public private(set) var isExecutingTool: Bool = false

    private var turnTask: Task<Void, Never>?
    private let synthesizer = AVSpeechSynthesizer()

    public init(
        aiService: AIService,
        voiceService: VoiceService,
        mapViewModel: MapViewModel,
        preferences: UserPreferences
    ) {
        self.aiService = aiService
        self.voiceService = voiceService
        self.mapViewModel = mapViewModel
        self.toolRouter = VoiceAgentToolRouter(
            mapViewModel: mapViewModel,
            preferences: preferences
        )
    }

    // MARK: - Public API

    /// Seed with system prompt and begin listening immediately.
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        errorMessage = nil
        session.seedSystem(systemPrompt)
        session.beginListening()
        thinkingStep = NSLocalizedString("agent.step.listening", comment: "Listening…")
    }

    /// Called when the user submits a text message (not voice).
    public func handleTextInput(_ text: String) {
        guard isRunning, !session.isEnded else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        runTurn(transcript: trimmed)
    }

    /// Called when voice transcription completes.
    public func handleTranscript(_ transcript: String) {
        guard isRunning else { return }
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        session.beginTranscribing()
        runTurn(transcript: trimmed)
    }

    /// Terminate the session.
    public func stop() {
        turnTask?.cancel()
        turnTask = nil
        isRunning = false
        streamingContent = ""
        thinkingStep = ""
        isExecutingTool = false
        synthesizer.stopSpeaking(at: .immediate)
        if !session.isEnded {
            session.end(reason: .userClose)
        }
    }

    /// Speak the agent's final text response via AVSpeechSynthesizer.
    public func speakResponse(_ text: String) {
        guard !text.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.05
        synthesizer.speak(utterance)
    }

    // MARK: - Turn loop

    private func runTurn(transcript: String) {
        session.beginUserTurn(transcript: transcript)
        thinkingStep = NSLocalizedString("agent.step.thinking", comment: "Thinking…")
        streamingContent = ""

        turnTask = Task {
            let turnStart = Date()
            var shouldContinue = true

            while shouldContinue, !Task.isCancelled, !session.isEnded {
                if session.hasExceededRecursionBudget {
                    await sendForceText(prompt: "You are out of tool-call budget. Summarize what you know and give a direct answer in one or two sentences.")
                    return
                }

                guard await sendToAIStreaming() else { return }

                if case .toolExecuting = session.state {
                    await executePendingTools()
                    session.resumeThinkingAfterTools()
                    thinkingStep = NSLocalizedString("agent.step.thinking", comment: "Thinking…")
                    streamingContent = ""
                    shouldContinue = true
                } else {
                    let finalText = streamingContent
                    session.finishSpeakingTurn()
                    thinkingStep = ""
                    shouldContinue = false
                    speakResponse(finalText)
                }

                if Date().timeIntervalSince(turnStart) > VoiceAgentSession.turnTimeoutSeconds {
                    session.end(reason: .timeout)
                    thinkingStep = ""
                    return
                }
            }
        }
    }

    /// Stream one AI turn, updating streamingContent and thinkingStep progressively.
    /// Returns false on unrecoverable error.
    private func sendToAIStreaming() async -> Bool {
        streamingContent = ""
        var accumulatedContent = ""
        var pendingToolCalls: [(id: String, name: String, args: String)] = []

        do {
            let stream = aiService.sendAgentMessageStreaming(
                messages: session.messages,
                tools: VoiceAgentToolRouter.allTools
            )
            for try await event in stream {
                guard !Task.isCancelled else { return false }
                switch event {
                case .contentDelta(let delta):
                    accumulatedContent += delta
                    streamingContent = accumulatedContent
                case .toolCall(let id, let name, let args):
                    pendingToolCalls.append((id: id, name: name, args: args))
                    thinkingStep = thinkingStepLabel(for: name)
                case .done:
                    break
                }
            }

            let sessionCalls = pendingToolCalls.map {
                VoiceAgentSession.ToolCall(id: $0.id, name: $0.name, argumentsJSON: $0.args)
            }
            let content = accumulatedContent.isEmpty ? nil : accumulatedContent
            session.appendAssistantTurn(content: content, toolCalls: sessionCalls)
            if sessionCalls.isEmpty {
                streamingContent = ""
            }
            return true

        } catch {
            // Streaming failed — fall back to non-streaming path.
            return await sendToAIFallback()
        }
    }

    /// Non-streaming fallback for servers that don't support SSE.
    private func sendToAIFallback() async -> Bool {
        do {
            let response = try await aiService.sendAgentMessage(
                messages: session.messages,
                tools: VoiceAgentToolRouter.allTools
            )
            session.appendAssistantTurn(
                content: response.content,
                toolCalls: response.toolCalls
            )
            if let content = response.content {
                streamingContent = content
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            session.end(reason: .error)
            thinkingStep = ""
            return false
        }
    }

    /// Execute all tool calls from the last assistant turn and feed results
    /// back into the session so the next AI call sees them.
    private func executePendingTools() async {
        guard let lastMsg = session.messages.last, lastMsg.role == .assistant else { return }
        isExecutingTool = true
        for call in lastMsg.toolCalls {
            thinkingStep = thinkingStepLabel(for: call.name)
            let resultJSON = await toolRouter.execute(call)
            session.appendToolResult(
                toolCallId: call.id,
                name: call.name,
                resultJSON: resultJSON
            )
        }
        isExecutingTool = false
    }

    /// Force one more non-tool response from the model (budget overflow path).
    private func sendForceText(prompt: String) async {
        session.appendSystemContinuation(prompt)
        _ = await sendToAIFallback()
        let finalText = streamingContent
        session.finishSpeakingTurn()
        thinkingStep = ""
        speakResponse(finalText)
    }

    // MARK: - UI helpers

    private func thinkingStepLabel(for toolName: String) -> String {
        switch toolName {
        case "explore_nearby":
            return NSLocalizedString("agent.step.exploreNearby", comment: "🔍 Searching nearby…")
        case "filter_by_category":
            return NSLocalizedString("agent.step.filter", comment: "🗂 Filtering map…")
        case "show_details":
            return NSLocalizedString("agent.step.showDetails", comment: "📍 Opening details…")
        case "save_to_favorites":
            return NSLocalizedString("agent.step.save", comment: "❤️ Saving to favorites…")
        case "dismiss_recommendation":
            return NSLocalizedString("agent.step.dismiss", comment: "✕ Dismissing…")
        case "search_places":
            return NSLocalizedString("agent.step.search", comment: "🔍 Searching places…")
        case "navigate_to":
            return NSLocalizedString("agent.step.navigate", comment: "🗺 Opening navigation…")
        default:
            return NSLocalizedString("agent.step.executing", comment: "⚙️ Executing…")
        }
    }

    // MARK: - System prompt

    private var systemPrompt: String {
        let visible = mapViewModel?.visibleExperiences.prefix(VoiceAgentSession.visibleExperiencesInjected) ?? []
        let visibleSummary = visible.isEmpty
            ? "No experiences currently visible on the map."
            : visible.map {
                "  [\($0.id)] \($0.title) — \($0.category.rawValue) — score \(String(format: "%.1f", $0.soloScore.overall))/10"
              }.joined(separator: "\n")

        let coord = mapViewModel?.exploreAnchorCoordinate ?? MapViewModel.defaultCenter

        return """
        You are Solo Compass, a warm and knowledgeable travel companion for solo travelers.
        The user is at approximately (\(String(format: "%.4f", coord.latitude)), \(String(format: "%.4f", coord.longitude))).

        CURRENT VISIBLE EXPERIENCES (use ONLY these IDs when calling tools):
        \(visibleSummary)

        TOOLS AVAILABLE:
        1. explore_nearby(latitude, longitude, radius_meters) — Fetch real OSM POIs near a coordinate and enrich with AI. Use when the user wants new places or is in an unfamiliar area.
        2. filter_by_category(category) — Filter the map to one category. Values: culture|nature|food|coffee|work|wellness|nightlife|hidden
        3. show_details(experience_id) — Open the detail sheet for one experience. MUST use an ID from CURRENT VISIBLE EXPERIENCES.
        4. save_to_favorites(experience_id) — Toggle favorite status for an experience.
        5. dismiss_recommendation(experience_id) — Hide an experience from the current view. Ephemeral — it can return after refresh.
        6. search_places(query, latitude, longitude, radius_meters) — Search for a specific type or named place (e.g. "ramen", "7-Eleven", "rooftop bar"). Returns newly discovered experiences.
        7. navigate_to(experience_id) — Open the user's preferred map app with walking directions to an experience.

        CONVERSATION RULES:
        - Be warm, concise, and conversational. You are a companion, not a database.
        - Keep replies under 2 sentences unless the user asks for detail.
        - When recommending a place, call show_details on your top pick so the user sees it immediately.
        - When the user wants somewhere specific, use filter_by_category or search_places first.
        - If the user asks to go somewhere or get directions, call navigate_to.
        - NEVER invent experience IDs — only use IDs from CURRENT VISIBLE EXPERIENCES or from explore_nearby/search_places results.
        - Detect the user's language from their input and reply in the same language.
        - If the user's request is unclear, ask exactly ONE clarifying question.
        """
    }
}
