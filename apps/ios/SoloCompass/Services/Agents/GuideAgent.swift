import Foundation

// MARK: - GuideAgent

/// Generates warm, streaming recommendation replies that incorporate context and
/// selected experiences. Uses Anthropic streaming (AsyncThrowingStream).
public final class GuideAgent: Agent, @unchecked Sendable {

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

    /// Produces a complete guide reply by collecting the full streamed response.
    public func handle(_ message: AgentMessage) async throws -> AgentResponse {
        var full = ""
        let stream = stream(message: message, contextSnapshot: nil, experienceSummaries: [])
        for try await token in stream {
            full += token
        }
        return AgentResponse(text: full)
    }

    // MARK: - Streaming

    /// Streams the guide response token by token.
    /// - Parameters:
    ///   - message: The user message with history.
    ///   - contextSnapshot: Optional JSON string of LLMContext snapshot (for caching).
    ///   - experienceSummaries: Short text descriptions of selected experiences.
    public func stream(
        message: AgentMessage,
        contextSnapshot: String?,
        experienceSummaries: [String]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let key = self.apiKey, let url = self.apiURL else {
                    continuation.yield(self.stubReply(for: message.text))
                    continuation.finish()
                    return
                }
                do {
                    try await self.streamFromAPI(
                        message: message,
                        contextSnapshot: contextSnapshot,
                        experienceSummaries: experienceSummaries,
                        key: key,
                        url: url,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Remote streaming

    private func streamFromAPI(
        message: AgentMessage,
        contextSnapshot: String?,
        experienceSummaries: [String],
        key: String,
        url: URL,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30

        // Build messages with optional cache_control on the context block.
        var systemContent: [[String: Any]] = []
        if let ctx = contextSnapshot, !ctx.isEmpty {
            systemContent.append([
                "type": "text",
                "text": "CONTEXT SNAPSHOT:\n\(ctx)",
                "cache_control": ["type": "ephemeral"]
            ])
        }
        systemContent.append([
            "type": "text",
            "text": guideSystemPrompt(experienceSummaries: experienceSummaries)
        ])

        var apiMessages: [[String: Any]] = message.history.map { turn in
            ["role": turn.role.rawValue, "content": turn.content]
        }
        apiMessages.append(["role": "user", "content": message.text])

        var body: [String: Any] = [
            "model": modelName,
            "max_tokens": 512,
            "temperature": 0.7,
            "stream": true,
            "messages": apiMessages
        ]
        if !systemContent.isEmpty {
            body["system"] = systemContent
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        _ = http

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" || payload.contains("\"type\":\"message_stop\"") { break }

            guard
                let data = payload.data(using: .utf8),
                let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            // Anthropic streaming: type = "content_block_delta"
            if let type_ = event["type"] as? String,
               type_ == "content_block_delta",
               let delta = event["delta"] as? [String: Any],
               let text = delta["text"] as? String,
               !text.isEmpty {
                continuation.yield(text)
            }
        }

        continuation.finish()
    }

    // MARK: - Helpers

    private func guideSystemPrompt(experienceSummaries: [String]) -> String {
        let expBlock = experienceSummaries.isEmpty
            ? ""
            : "\n\nSELECTED EXPERIENCES:\n" + experienceSummaries.map { "  - \($0)" }.joined(separator: "\n")
        return """
        You are Solo Compass, a warm travel companion for solo travelers. \
        Your role is to give friendly, concise recommendations and guidance.\(expBlock)

        RULES:
        - Be warm and conversational. 1-2 sentences unless asked for more.
        - Ground recommendations in the specific experiences provided.
        - Detect user language and reply in the same language.
        """
    }

    private func stubReply(for text: String) -> String {
        "Here are some great spots for solo travelers nearby! Let me show you what's available."
    }
}
