import Foundation

// MARK: - Intent

/// Classified intent for a user utterance.
public enum Intent: String, Sendable, CaseIterable {
    case findExperience = "FindExperience"
    case changeSettings = "ChangeSettings"
    case getRecommendation = "GetRecommendation"
    case smallTalk = "SmallTalk"
}

// MARK: - IntentAgent

/// Classifies user input into one of four intents using a Claude prompt.
/// Confidence < 0.6 falls back to `.smallTalk`.
public final class IntentAgent: Agent, @unchecked Sendable {

    /// The classified intent for an utterance paired with the model's confidence.
    public struct ClassificationResult: Sendable {
        public let intent: Intent
        public let confidence: Double

        public init(intent: Intent, confidence: Double) {
            self.intent = intent
            self.confidence = confidence
        }
    }

    private let session: URLSession
    private let apiKey: String?
    private let apiURL: URL?
    private let modelName: String

    public init(
        session: URLSession = .shared,
        apiKey: String? = nil,
        apiURL: URL? = nil,
        modelName: String = "claude-opus-4-7"
    ) {
        self.session = session
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
        self.apiURL = apiURL ?? URL(string: "https://api.anthropic.com/v1/messages")
        self.modelName = modelName
    }

    // MARK: - Agent

    /// Classifies the message and returns the detected intent and confidence as response metadata.
    public func handle(_ message: AgentMessage) async throws -> AgentResponse {
        let result = try await classify(message.text)
        return AgentResponse(
            text: result.intent.rawValue,
            metadata: [
                "intent": result.intent.rawValue,
                "confidence": String(format: "%.2f", result.confidence)
            ]
        )
    }

    // MARK: - Classification

    /// Determines which of the four intents a user utterance expresses, falling back to keywords offline.
    public func classify(_ text: String) async throws -> ClassificationResult {
        guard let key = apiKey, let url = apiURL else {
            return fallbackClassify(text)
        }
        do {
            return try await remoteClassify(text, key: key, url: url)
        } catch {
            return fallbackClassify(text)
        }
    }

    // MARK: - Remote (Claude)

    private func remoteClassify(_ text: String, key: String, url: URL) async throws -> ClassificationResult {
        let prompt = classificationPrompt(for: text)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": modelName,
            "max_tokens": 64,
            "temperature": 0,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return fallbackClassify(text)
        }
        return parseClaudeResponse(data) ?? fallbackClassify(text)
    }

    private func classificationPrompt(for text: String) -> String {
        """
        Classify this user message into exactly one intent. Reply ONLY with JSON, no markdown.

        Intents:
        - FindExperience: user wants to find, discover, or locate a specific place or type of venue
        - ChangeSettings: user wants to adjust preferences, filters, or app settings
        - GetRecommendation: user wants a personalized suggestion or advice
        - SmallTalk: anything else — greetings, questions about the app, vague statements

        User message: "\(text)"

        Reply format: {"intent":"<one of the four>","confidence":<0.0-1.0>}
        """
    }

    private func parseClaudeResponse(_ data: Data) -> ClassificationResult? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = (json["content"] as? [[String: Any]])?.first,
            let text = content["text"] as? String,
            let payload = text.data(using: .utf8),
            let parsed = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
            let intentRaw = parsed["intent"] as? String,
            let intent = Intent(rawValue: intentRaw),
            let confidence = parsed["confidence"] as? Double
        else { return nil }

        if confidence < 0.6 { return ClassificationResult(intent: .smallTalk, confidence: confidence) }
        return ClassificationResult(intent: intent, confidence: confidence)
    }

    // MARK: - Local keyword fallback

    private func fallbackClassify(_ text: String) -> ClassificationResult {
        let lower = text.lowercased()
        if lower.contains("find") || lower.contains("where") || lower.contains("near") || lower.contains("cafe") || lower.contains("coffee") || lower.contains("restaurant") {
            return ClassificationResult(intent: .findExperience, confidence: 0.7)
        }
        if lower.contains("setting") || lower.contains("prefer") || lower.contains("filter") || lower.contains("change") {
            return ClassificationResult(intent: .changeSettings, confidence: 0.7)
        }
        if lower.contains("recommend") || lower.contains("suggest") || lower.contains("should i") || lower.contains("what's good") {
            return ClassificationResult(intent: .getRecommendation, confidence: 0.7)
        }
        return ClassificationResult(intent: .smallTalk, confidence: 0.8)
    }
}
