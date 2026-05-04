import Foundation
import CoreLocation
import Observation

/// Talks to Claude via the Anthropic Messages API. Reads the API key from
/// `Secrets.plist` (key `ANTHROPIC_API_KEY`) or the `ANTHROPIC_API_KEY` env var.
/// If neither is present, calls return a fallback that ranks by Solo Score.
///
/// We keep this surface minimal — three intents the rest of the app actually
/// needs. Adding more should require a real product reason.
@Observable
public final class AIService {
    public struct UserContext {
        public let location: CLLocationCoordinate2D?
        public let date: Date
        public let style: UserPreferences.SoloTravelStyle
        public let preferredCategories: [ExperienceCategory]
        public let dislikedCategories: [ExperienceCategory]

        public init(
            location: CLLocationCoordinate2D?,
            date: Date,
            style: UserPreferences.SoloTravelStyle,
            preferredCategories: [ExperienceCategory],
            dislikedCategories: [ExperienceCategory]
        ) {
            self.location = location
            self.date = date
            self.style = style
            self.preferredCategories = preferredCategories
            self.dislikedCategories = dislikedCategories
        }
    }

    public struct AIResponse: Codable, Hashable {
        public let recommendedIds: [String]
        public let explanation: String
        public let filterSuggestion: ExperienceCategory?

        public init(recommendedIds: [String], explanation: String, filterSuggestion: ExperienceCategory? = nil) {
            self.recommendedIds = recommendedIds
            self.explanation = explanation
            self.filterSuggestion = filterSuggestion
        }
    }

    public enum AIError: Error, LocalizedError {
        case missingAPIKey
        case requestFailed(status: Int, body: String)
        case decodingFailed(String)

        public var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return NSLocalizedString("ai.error.missingKey", comment: "Missing API key")
            case .requestFailed(let status, _):
                return String(format: NSLocalizedString("ai.error.request", comment: "Request failed status %d"), status)
            case .decodingFailed(let msg):
                return msg
            }
        }
    }

    public private(set) var isProcessing: Bool = false
    public private(set) var lastError: Error?

    private let session: URLSession
    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")
    private let model = "claude-opus-4-7"

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public

    public func recommendExperiences(
        from candidates: [Experience],
        context: UserContext
    ) async throws -> [String] {
        let prompt = Self.recommendationPrompt(candidates: candidates, context: context)
        do {
            let raw = try await sendMessage(prompt: prompt)
            return Self.parseIDList(raw, validIDs: Set(candidates.map(\.id)))
        } catch AIError.missingAPIKey {
            // Local fallback: rank by solo score, then by best-now boost.
            return candidates
                .sorted { lhs, rhs in
                    let lScore = lhs.soloScore.overall + (lhs.isBestNow(at: context.date) ? 2 : 0)
                    let rScore = rhs.soloScore.overall + (rhs.isBestNow(at: context.date) ? 2 : 0)
                    return lScore > rScore
                }
                .prefix(5)
                .map(\.id)
        }
    }

    public func explainRecommendation(for experienceId: String) async throws -> String {
        let prompt = """
        Explain in one warm, concrete sentence why a solo traveler would value the experience with id \"\(experienceId)\". \
        Avoid superlatives. Focus on a sensory detail.
        """
        do {
            return try await sendMessage(prompt: prompt)
        } catch AIError.missingAPIKey {
            return NSLocalizedString("ai.fallback.explanation", comment: "Default AI explanation")
        }
    }

    public func processVoiceIntent(transcript: String, near coordinate: CLLocationCoordinate2D) async throws -> AIResponse {
        let prompt = """
        A solo traveler said: \"\(transcript)\".
        Their current coordinates are \(coordinate.latitude), \(coordinate.longitude).
        Respond as JSON: {"recommendedIds":[],"explanation":"...","filterSuggestion":"culture|nature|food|coffee|work|wellness|nightlife|hidden|null"}
        """
        do {
            let raw = try await sendMessage(prompt: prompt)
            return try Self.parseAIResponse(raw)
        } catch AIError.missingAPIKey {
            return AIResponse(
                recommendedIds: [],
                explanation: NSLocalizedString("ai.fallback.voice", comment: "Voice fallback"),
                filterSuggestion: nil
            )
        }
    }

    // MARK: - HTTP

    private func sendMessage(prompt: String) async throws -> String {
        guard let key = Self.resolveAPIKey() else { throw AIError.missingAPIKey }
        guard let apiURL else { throw AIError.requestFailed(status: 0, body: "bad URL") }

        await MainActor.run { self.isProcessing = true }
        defer {
            Task { @MainActor [weak self] in self?.isProcessing = false }
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": [["role": "user", "content": prompt]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.requestFailed(status: 0, body: "no response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw AIError.requestFailed(status: http.statusCode, body: bodyText)
        }

        // Anthropic Messages API: content is an array of blocks; we want the
        // first text block.
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let first = content.first,
            let text = first["text"] as? String
        else {
            throw AIError.decodingFailed("Unexpected response shape")
        }
        return text
    }

    // MARK: - Helpers

    private static func resolveAPIKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !env.isEmpty {
            return env
        }
        if
            let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let key = plist["ANTHROPIC_API_KEY"] as? String,
            !key.isEmpty
        {
            return key
        }
        return nil
    }

    private static func recommendationPrompt(candidates: [Experience], context: UserContext) -> String {
        let candidateLines = candidates.map { exp in
            "- \(exp.id): \(exp.title) [\(exp.category.rawValue), solo=\(String(format: "%.1f", exp.soloScore.overall))]"
        }.joined(separator: "\n")
        let preferred = context.preferredCategories.map(\.rawValue).joined(separator: ",")
        let disliked = context.dislikedCategories.map(\.rawValue).joined(separator: ",")
        let coords = context.location.map { "\($0.latitude),\($0.longitude)" } ?? "unknown"
        return """
        You are ranking experiences for a solo traveler. Return up to 5 ids, one per line, in priority order. No prose.

        Time: \(context.date.ISO8601Format())
        Location: \(coords)
        Style: \(context.style.rawValue)
        Preferred: [\(preferred)]
        Disliked: [\(disliked)]

        Candidates:
        \(candidateLines)
        """
    }

    private static func parseIDList(_ raw: String, validIDs: Set<String>) -> [String] {
        raw.split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap { line -> String? in
                // Strip leading bullet/number/dash.
                let trimmed = line.drop(while: { !$0.isLetter })
                let candidate = String(trimmed)
                return candidate.isEmpty ? nil : candidate
            }
            .filter { validIDs.contains($0) }
    }

    private static func parseAIResponse(_ raw: String) throws -> AIResponse {
        // Find first {...} block.
        guard
            let start = raw.firstIndex(of: "{"),
            let end = raw.lastIndex(of: "}"),
            start <= end
        else { throw AIError.decodingFailed("no JSON in response") }
        let jsonText = String(raw[start...end])
        guard let data = jsonText.data(using: .utf8) else {
            throw AIError.decodingFailed("invalid utf8")
        }
        return try JSONDecoder().decode(AIResponse.self, from: data)
    }
}
