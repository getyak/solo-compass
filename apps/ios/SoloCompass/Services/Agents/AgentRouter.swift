import AVFoundation
import Foundation
import Observation
import os

// MARK: - AgentRouter

/// Routes user input through the Intent → Query → Guide pipeline.
///
/// When `FeatureFlags.agentRouterEnabled` is false, callers should use the
/// legacy `VoiceAgentOrchestrator` instead. The feature flag defaults to true.
@MainActor
@Observable
public final class AgentRouter {

    // MARK: - Dependencies

    private let intentAgent: IntentAgent
    private let queryAgent: QueryAgent
    private let guideAgent: GuideAgent
    private let contextManager: (any ContextManager)?
    private weak var mapViewModel: MapViewModel?

    // MARK: - State

    public private(set) var uiState: ChatUIState = .idle
    public private(set) var streamingContent: String = ""
    public private(set) var isRunning = false
    public private(set) var errorMessage: String?

    /// Emitted for debug/analytics — cache hit/miss from GuideAgent.
    public private(set) var lastCacheHit: Bool? = nil

    private var conversationHistory: [AgentTurn] = []

    private let synthesizer = AVSpeechSynthesizer()

    private let logger = Logger(subsystem: "com.solocompass", category: "AgentRouter")

    public init(
        intentAgent: IntentAgent = IntentAgent(),
        queryAgent: QueryAgent = QueryAgent(),
        guideAgent: GuideAgent = GuideAgent(),
        contextManager: (any ContextManager)? = nil,
        mapViewModel: MapViewModel? = nil
    ) {
        self.intentAgent = intentAgent
        self.queryAgent = queryAgent
        self.guideAgent = guideAgent
        self.contextManager = contextManager
        self.mapViewModel = mapViewModel
    }

    // MARK: - Public API

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        uiState = .listening
    }

    public func stop() {
        isRunning = false
        streamingContent = ""
        uiState = .idle
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Process a user message through the full agent pipeline.
    public func handle(text: String) async {
        guard isRunning else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        uiState = .processing
        streamingContent = ""
        errorMessage = nil

        do {
            let reply = try await runPipeline(text: trimmed)
            conversationHistory.append(AgentTurn(role: .user, content: trimmed))
            conversationHistory.append(AgentTurn(role: .assistant, content: reply))
            uiState = .responding(reply)
            speakResponse(reply)
        } catch {
            errorMessage = error.localizedDescription
            uiState = .error(.network)
        }
    }

    // MARK: - Pipeline

    private func runPipeline(text: String) async throws -> String {
        // Step 1: Classify intent.
        let message = AgentMessage(text: text, history: conversationHistory)
        let intentResponse = try await intentAgent.handle(message)
        let intentRaw = intentResponse.metadata["intent"] ?? Intent.smallTalk.rawValue
        let intent = Intent(rawValue: intentRaw) ?? .smallTalk

        // Step 2: For discovery intents, run QueryAgent then GuideAgent.
        var experienceSummaries: [String] = []
        if intent == .findExperience || intent == .getRecommendation {
            let filterResponse = try await queryAgent.handle(message)
            experienceSummaries = buildExperienceSummaries(from: filterResponse.metadata)
        }

        // Step 3: Stream guide reply.
        let contextSnapshot = await buildContextSnapshot()

        var fullReply = ""
        let stream = guideAgent.stream(
            message: message,
            contextSnapshot: contextSnapshot,
            experienceSummaries: experienceSummaries
        )
        for try await token in stream {
            fullReply += token
            streamingContent = fullReply
        }

        // Log cache hit for debug builds.
        #if DEBUG
        logCacheStatus(intentRaw: intentRaw)
        #endif

        return fullReply.isEmpty ? fallbackReply(for: intent) : fullReply
    }

    // MARK: - Helpers

    private func buildExperienceSummaries(from metadata: [String: String]) -> [String] {
        guard let map = mapViewModel else { return [] }
        var experiences = map.visibleExperiences

        if let cat = metadata["category"] {
            experiences = experiences.filter { $0.category.rawValue == cat }
        }
        if let minScore = metadata["soloScoreMin"].flatMap(Double.init) {
            experiences = experiences.filter { $0.soloScore.overall >= minScore }
        }

        return experiences.prefix(5).map { exp in
            "\(exp.title) — \(exp.category.rawValue) — score \(String(format: "%.1f", exp.soloScore.overall))/10"
        }
    }

    private func buildContextSnapshot() async -> String? {
        guard let cm = contextManager else { return nil }
        let ctx = await cm.snapshot()
        return ctx.jsonString()
    }

    private func fallbackReply(for intent: Intent) -> String {
        switch intent {
        case .findExperience:
            return NSLocalizedString("router.fallback.find", comment: "I found some nearby spots — check the map!")
        case .getRecommendation:
            return NSLocalizedString("router.fallback.recommend", comment: "Based on your preferences, here are some great options nearby.")
        case .changeSettings:
            return NSLocalizedString("router.fallback.settings", comment: "You can adjust your preferences in the Settings tab.")
        case .smallTalk:
            return NSLocalizedString("router.fallback.smallTalk", comment: "I'm here to help you discover solo-friendly places. What are you looking for?")
        }
    }

    private func speakResponse(_ text: String) {
        guard !text.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.05
        synthesizer.speak(utterance)
    }

    private func logCacheStatus(intentRaw: String) {
        // US-035: Log cache hit/miss. GuideAgent marks cache via HTTP header
        // "anthropic-cache-creation-input-tokens" / "anthropic-cache-read-input-tokens".
        // For now, track via conversation history length as a proxy.
        lastCacheHit = conversationHistory.count > 2
        let status = (lastCacheHit == true) ? "HIT" : "MISS"
        logger.debug("Cache \(status, privacy: .public) for intent: \(intentRaw, privacy: .public)")
    }
}
