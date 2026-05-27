import Foundation
import CoreLocation

// MARK: - ExperienceFilter

/// Structured filter extracted from natural language by QueryAgent.
///
/// Quality dimensions (US-017):
/// - ratingMin: minimum provider rating (0–10) from location.rating
/// - ambianceMin: minimum ambianceFit breakdown score (0–10)
/// - quietness: true = high seatingFriendly + low staffPressure
/// - soloFriendly: true = high soloPatronRatio + high soloPortioning
/// - priceMax: maximum price level (1–4)
public struct ExperienceFilter: Sendable, Equatable {
    public let category: String?
    public let maxDistanceMeters: Double?
    public let openNow: Bool
    public let soloScoreMin: Double?
    // US-017: quality and ambiance dimensions
    public let ratingMin: Double?
    public let ambianceMin: Double?
    public let quietness: Bool
    public let soloFriendly: Bool
    public let priceMax: Double?

    public init(
        category: String? = nil,
        maxDistanceMeters: Double? = nil,
        openNow: Bool = false,
        soloScoreMin: Double? = nil,
        ratingMin: Double? = nil,
        ambianceMin: Double? = nil,
        quietness: Bool = false,
        soloFriendly: Bool = false,
        priceMax: Double? = nil
    ) {
        self.category = category
        self.maxDistanceMeters = maxDistanceMeters
        self.openNow = openNow
        self.soloScoreMin = soloScoreMin
        self.ratingMin = ratingMin
        self.ambianceMin = ambianceMin
        self.quietness = quietness
        self.soloFriendly = soloFriendly
        self.priceMax = priceMax
    }

    // MARK: - Predicate (US-017)

    /// Returns true when `experience` satisfies all active filter dimensions.
    /// Dimensions with nil / false values are skipped (inactive).
    public func matches(_ experience: Experience) -> Bool {
        if let cat = category, !cat.isEmpty {
            guard experience.category.rawValue == cat else { return false }
        }
        if let rMin = ratingMin {
            guard let rating = experience.location.rating, rating >= rMin else { return false }
        }
        if let priceMax, let price = experience.location.priceLevel {
            guard price <= priceMax else { return false }
        }
        if let score = soloScoreMin {
            guard experience.soloScore.overall >= score else { return false }
        }
        if let ambMin = ambianceMin {
            guard experience.soloScore.breakdown.ambianceFit >= ambMin else { return false }
        }
        // quietness: seatingFriendly ≥ 7 AND staffPressure ≤ 3
        if quietness {
            let bd = experience.soloScore.breakdown
            guard bd.seatingFriendly >= 7.0 && bd.staffPressure <= 3.0 else { return false }
        }
        // soloFriendly: soloPatronRatio ≥ 7 AND soloPortioning ≥ 7
        if soloFriendly {
            let bd = experience.soloScore.breakdown
            guard bd.soloPatronRatio >= 7.0 && bd.soloPortioning >= 7.0 else { return false }
        }
        return true
    }
}

// MARK: - QueryAgent

/// Translates natural-language queries into structured ExperienceFilter using
/// Claude function-calling. Falls back to keyword matching when LLM is unavailable.
public final class QueryAgent: Agent, @unchecked Sendable {

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

    public func handle(_ message: AgentMessage) async throws -> AgentResponse {
        let filter = try await extractFilter(from: message.text)
        var meta: [String: String] = [:]
        if let cat = filter.category { meta["category"] = cat }
        if let dist = filter.maxDistanceMeters { meta["maxDistanceMeters"] = String(dist) }
        meta["openNow"] = filter.openNow ? "true" : "false"
        if let score = filter.soloScoreMin { meta["soloScoreMin"] = String(score) }
        if let rMin = filter.ratingMin { meta["ratingMin"] = String(rMin) }
        if let aMin = filter.ambianceMin { meta["ambianceMin"] = String(aMin) }
        if filter.quietness { meta["quietness"] = "true" }
        if filter.soloFriendly { meta["soloFriendly"] = "true" }
        if let pMax = filter.priceMax { meta["priceMax"] = String(pMax) }
        return AgentResponse(text: nil, metadata: meta)
    }

    // MARK: - Filter Extraction

    public func extractFilter(from text: String) async throws -> ExperienceFilter {
        guard let key = apiKey, let url = apiURL else {
            return keywordFilter(text)
        }
        do {
            return try await remoteExtract(text, key: key, url: url)
        } catch {
            return keywordFilter(text)
        }
    }

    // MARK: - Remote (Claude function-calling)

    private func remoteExtract(_ text: String, key: String, url: URL) async throws -> ExperienceFilter {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 15

        let tool: [String: Any] = [
            "name": "extract_experience_filter",
            "description": """
            Extract structured search filters from a natural language query about places or experiences.

            Extraction examples (US-018):
            - "quiet cafe to work" → category=coffee, quietness=true
            - "highly rated coffee shop" → category=coffee, rating_min=7.0
            - "solo-friendly restaurant" → category=food, solo_friendly=true
            - "cheap eats nearby" → category=food, price_max=2.0
            - "best ambiance bar tonight" → category=nightlife, ambiance_min=7.0, open_now=true
            - "peaceful nature spot with high solo score" → category=nature, quietness=true, solo_score_min=7.0
            """,
            "input_schema": [
                "type": "object",
                "properties": [
                    "category": [
                        "type": "string",
                        "enum": ["culture", "nature", "food", "coffee", "work", "wellness", "nightlife", "hidden"],
                        "description": "Category of place the user is looking for"
                    ],
                    "max_distance_m": [
                        "type": "number",
                        "description": "Maximum search radius in meters"
                    ],
                    "open_now": [
                        "type": "boolean",
                        "description": "Whether to filter for places open right now"
                    ],
                    "solo_score_min": [
                        "type": "number",
                        "description": "Minimum solo-traveler score (0-10). Set when user says best, top, highly-rated solo place."
                    ],
                    "rating_min": [
                        "type": "number",
                        "description": "Minimum provider rating (0-10). Set when user says highly rated, well reviewed, good reviews."
                    ],
                    "ambiance_min": [
                        "type": "number",
                        "description": "Minimum ambiance fit score (0-10). Set when user mentions ambiance, atmosphere, vibe."
                    ],
                    "quietness": [
                        "type": "boolean",
                        "description": "True when user says quiet, peaceful, calm, not noisy, low noise, easy to concentrate."
                    ],
                    "solo_friendly": [
                        "type": "boolean",
                        "description": "True when user says solo-friendly, good for solo travelers, solo dining, single portions."
                    ],
                    "price_max": [
                        "type": "number",
                        "description": "Maximum price level 1-4 (1=cheap, 4=expensive). Set when user says cheap, budget, affordable (→2), mid-range (→3)."
                    ]
                ]
            ] as [String: Any]
        ]

        let systemPrompt = """
        You extract structured search filters from natural language queries about places to visit.
        Map user adjectives to filter fields:
        - quiet/peaceful/calm → quietness=true
        - highly rated/well reviewed → rating_min=7.0
        - solo friendly/solo dining → solo_friendly=true
        - cheap/budget/affordable → price_max=2.0
        - great ambiance/nice atmosphere/good vibe → ambiance_min=7.0
        - best/top/excellent solo score → solo_score_min=7.0
        Only set a field when the query clearly implies it.
        """

        let body: [String: Any] = [
            "model": modelName,
            "max_tokens": 256,
            "temperature": 0,
            "system": systemPrompt,
            "tools": [tool],
            "tool_choice": ["type": "auto"],
            "messages": [["role": "user", "content": "Extract search filters from: \"\(text)\""]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return keywordFilter(text)
        }
        return parseToolResponse(data) ?? keywordFilter(text)
    }

    private func parseToolResponse(_ data: Data) -> ExperienceFilter? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let toolUse = content.first(where: { $0["type"] as? String == "tool_use" }),
            let input = toolUse["input"] as? [String: Any]
        else { return nil }

        return ExperienceFilter(
            category: input["category"] as? String,
            maxDistanceMeters: input["max_distance_m"] as? Double,
            openNow: (input["open_now"] as? Bool) ?? false,
            soloScoreMin: input["solo_score_min"] as? Double,
            ratingMin: input["rating_min"] as? Double,
            ambianceMin: input["ambiance_min"] as? Double,
            quietness: (input["quietness"] as? Bool) ?? false,
            soloFriendly: (input["solo_friendly"] as? Bool) ?? false,
            priceMax: input["price_max"] as? Double
        )
    }

    // MARK: - Keyword fallback

    private func keywordFilter(_ text: String) -> ExperienceFilter {
        let lower = text.lowercased()

        var category: String?
        let categoryMap: [(String, String)] = [
            ("cafe", "coffee"), ("coffee", "coffee"), ("work", "work"),
            ("food", "food"), ("eat", "food"), ("restaurant", "food"),
            ("culture", "culture"), ("museum", "culture"), ("temple", "culture"),
            ("nature", "nature"), ("park", "nature"), ("hike", "nature"),
            ("wellness", "wellness"), ("spa", "wellness"), ("yoga", "wellness"),
            ("nightlife", "nightlife"), ("bar", "nightlife"), ("club", "nightlife"),
            ("hidden", "hidden"), ("secret", "hidden")
        ]
        for (keyword, cat) in categoryMap {
            if lower.contains(keyword) { category = cat; break }
        }

        let openNow = lower.contains("open") || lower.contains("now") || lower.contains("right now")

        var maxDistance: Double?
        if lower.contains("nearby") || lower.contains("near me") || lower.contains("close") {
            maxDistance = 1000
        } else if lower.contains("within") {
            // Basic heuristic for "within X km/m"
            maxDistance = 2000
        }

        var soloScoreMin: Double?
        if lower.contains("best") || lower.contains("top") || lower.contains("great") {
            soloScoreMin = 7.0
        }

        var ratingMin: Double?
        if lower.contains("highly rated") || lower.contains("high rating") || lower.contains("well rated") {
            ratingMin = 7.0
        }

        let quietness = lower.contains("quiet") || lower.contains("peaceful") || lower.contains("calm")
        let soloFriendly = lower.contains("solo friendly") || lower.contains("solo-friendly")

        var priceMax: Double?
        if lower.contains("cheap") || lower.contains("budget") || lower.contains("affordable") {
            priceMax = 2.0
        }

        return ExperienceFilter(
            category: category,
            maxDistanceMeters: maxDistance,
            openNow: openNow,
            soloScoreMin: soloScoreMin,
            ratingMin: ratingMin,
            quietness: quietness,
            soloFriendly: soloFriendly,
            priceMax: priceMax
        )
    }
}
