import Foundation
import CoreLocation
import CryptoKit
import Observation
import SwiftData

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
    /// Set when the daily AI quota cap fires (Epic B US-015). The map
    /// view shows a banner derived from this.
    public private(set) var quotaExceededAt: Date?

    /// Set by MapViewModel (or tests) to reflect the current subscription
    /// tier. Defaults to `true` so previews and tests without a
    /// SubscriptionService still get Pro-tier quotas.
    /// Free tier: synthesis 0 / explanation 0 (second line of defense
    /// after the paywall gate in MapViewModel).
    public var isProTier: Bool = true

    private let session: URLSession
    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")
    private let modelContext: ModelContext?

    /// Synthesis cache TTL — 30 days.
    public static let synthesisCacheTTLSeconds: TimeInterval = 30 * 86_400

    /// Default model routing. Sonnet 4.6 for generative tasks (synthesis,
    /// voice intent, ranking); Haiku 4.5 for lighter explanations. The
    /// `AI_FORCE_OPUS=1` env var routes everything to Opus for golden-set
    /// runs. `Secrets.plist` keys (`ANTHROPIC_MODEL_SYNTHESIS`,
    /// `ANTHROPIC_MODEL_EXPLANATION`, `ANTHROPIC_MODEL_VOICE`) override
    /// the defaults per build.
    public enum ModelKind {
        case synthesis, explanation, voice
    }

    public init(session: URLSession = .shared, modelContext: ModelContext? = nil) {
        self.session = session
        self.modelContext = modelContext
    }

    /// Initialise with an `ExperienceRepository`; the repository's context
    /// is reused so synthesis cache I/O shares the same actor-bound store.
    public convenience init(session: URLSession = .shared, repository: ExperienceRepository?) {
        self.init(session: session, modelContext: repository?.modelContext)
    }

    /// Convenience that uses the shared SwiftData container's main
    /// context for caching.
    public convenience init(session: URLSession = .shared, useSharedCache: Bool) {
        let ctx: ModelContext? = useSharedCache
            ? ModelContext(SoloCompassModelContainer.shared)
            : nil
        self.init(session: session, modelContext: ctx)
    }

    // MARK: - Model name resolution

    /// Resolve which model to use for a given call kind. Order:
    /// 1. `AI_FORCE_OPUS=1` env var → opus everywhere (debug only)
    /// 2. `Secrets.plist` override key
    /// 3. Hard-coded default
    static func modelName(for kind: ModelKind) -> String {
        if ProcessInfo.processInfo.environment["AI_FORCE_OPUS"] == "1" {
            return "claude-opus-4-7"
        }
        let plistKey: String
        let defaultName: String
        switch kind {
        case .synthesis:
            plistKey = "ANTHROPIC_MODEL_SYNTHESIS"
            defaultName = "claude-sonnet-4-6"
        case .explanation:
            plistKey = "ANTHROPIC_MODEL_EXPLANATION"
            defaultName = "claude-haiku-4-5-20251001"
        case .voice:
            plistKey = "ANTHROPIC_MODEL_VOICE"
            defaultName = "claude-sonnet-4-6"
        }
        return resolveSecretsOverride(plistKey) ?? defaultName
    }

    private static func resolveSecretsOverride(_ key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let value = plist[key] as? String,
              !value.isEmpty
        else { return nil }
        return value
    }

    // MARK: - Public

    public func recommendExperiences(
        from candidates: [Experience],
        context: UserContext
    ) async throws -> [String] {
        let prompt = Self.recommendationPrompt(candidates: candidates, context: context)
        do {
            let raw = try await sendMessage(prompt: prompt, kind: .synthesis)
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
            return try await sendMessage(prompt: prompt, kind: .explanation)
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
            let raw = try await sendMessage(prompt: prompt, kind: .voice)
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

    private func sendMessage(prompt: String, kind: ModelKind = .synthesis) async throws -> String {
        guard let key = Self.resolveAPIKey() else { throw AIError.missingAPIKey }
        guard let apiURL else { throw AIError.requestFailed(status: 0, body: "bad URL") }

        await MainActor.run { self.isProcessing = true }
        defer { Task { @MainActor [weak self] in self?.isProcessing = false } }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": Self.modelName(for: kind),
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

    // US-034: ANTHROPIC_API_KEY is no longer read from Secrets.plist.
    // The synthesis path now routes through the Supabase Edge Function
    // when FF_ROUTE_AI_THROUGH_EDGE is on. Only the env-var path is
    // kept so local QA runs (explanation/voice) and CI can still inject
    // a key without bundling it in the app.
    private static func resolveAPIKey() -> String? {
        guard let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !env.isEmpty else {
            return nil
        }
        return env
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

    // MARK: - Synthesize from OSM POIs (Explore Here)

    /// Maximum POIs sent to the model in one call. Keeps prompt size and cost
    /// predictable, and matches the product cap of 15 generated experiences.
    public static let synthesisLimit = 15

    /// Convert a batch of OSM POIs into Experiences. The hot path:
    /// 1. Cache hit (SHA256 of inputs + model name + 30-day TTL) →
    ///    return persisted Experiences without HTTP.
    /// 2. Quota check (Pro: 30 synthesis/day) → if exceeded, fall back
    ///    to skeleton mode and set `quotaExceededAt`.
    /// 3. Real Claude call → on success, persist + return; on failure,
    ///    skeleton fallback (no cache write).
    public func synthesizeExperiences(
        from pois: [OverpassService.POI],
        cityCode: String,
        locale: Locale = .current
    ) async throws -> [Experience] {
        let capped = Array(pois.prefix(Self.synthesisLimit))
        guard !capped.isEmpty else { return [] }

        let modelName = Self.modelName(for: .synthesis)
        let cacheKey = Self.synthesisCacheKey(
            pois: capped, cityCode: cityCode, locale: locale, modelName: modelName
        )

        if let cached = await loadCachedSynthesis(cacheKey: cacheKey) {
            return cached
        }

        // US-015 quota check: cache hits don't count, network calls do.
        // checkAndIncrementQuota atomically checks and, if under limit,
        // increments. Returns true = limit already hit (degrade now).
        let quotaHit = await checkAndIncrementQuota(kind: .synthesis)
        if quotaHit {
            await setQuotaExceeded()
            return capped.map { Self.skeletonExperience(from: $0, cityCode: cityCode) }
        }

        // Epic E US-031: route through Supabase Edge Function instead
        // of direct Anthropic when the flag is on. This is the path
        // that lets us remove ANTHROPIC_API_KEY from the iOS bundle.
        if FeatureFlags.routeAIThroughEdge && FeatureFlags.backendSync {
            do {
                let experiences = try await synthesizeViaEdge(
                    pois: capped, cityCode: cityCode, locale: locale, cacheKey: cacheKey
                )
                await writeCachedSynthesis(
                    cacheKey: cacheKey, experiences: experiences, modelName: modelName
                )
                return experiences
            } catch {
                // Edge Function failed — skeleton fallback (no cache write).
                return capped.map { Self.skeletonExperience(from: $0, cityCode: cityCode) }
            }
        }

        let prompt = Self.synthesisPrompt(pois: capped, cityCode: cityCode, locale: locale)
        do {
            let raw = try await sendMessage(prompt: prompt, kind: .synthesis)
            let experiences = try Self.parseSynthesizedExperiences(raw, pois: capped, cityCode: cityCode)
            await writeCachedSynthesis(
                cacheKey: cacheKey,
                experiences: experiences,
                modelName: modelName
            )
            return experiences
        } catch {
            // Skeleton fallback — never written to cache so a
            // transient network blip doesn't poison the cache for 30
            // days.
            return capped.map { Self.skeletonExperience(from: $0, cityCode: cityCode) }
        }
    }

    // MARK: - Edge Function path (Epic E US-031)

    private func synthesizeViaEdge(
        pois: [OverpassService.POI],
        cityCode: String,
        locale: Locale,
        cacheKey: String
    ) async throws -> [Experience] {
        struct EdgePOI: Encodable {
            let osmId: Int64
            let name: String
            let nameEn: String?
            let lat: Double
            let lon: Double
            let tags: [String: String]
        }
        struct EdgeRequest: Encodable {
            let pois: [EdgePOI]
            let cityCode: String
            let locale: String
            let cacheKey: String
        }
        let body = EdgeRequest(
            pois: pois.map { EdgePOI(osmId: $0.osmId, name: $0.name, nameEn: $0.nameEn,
                                     lat: $0.lat, lon: $0.lon, tags: $0.tags) },
            cityCode: cityCode,
            locale: locale.identifier,
            cacheKey: cacheKey
        )
        let bodyData = try JSONEncoder().encode(body)
        let result = await SupabaseClient.shared.invoke(function: "synthesize-experiences", body: bodyData)
        switch result {
        case .success(let data):
            // Edge response shape: {"experiences": [item, ...], "cached": bool}
            struct EdgeResponse: Decodable {
                let experiences: [EdgeItem]
                let cached: Bool?
            }
            struct EdgeItem: Decodable {
                let osmId: Int64
                let title: String
                let oneLiner: String
                let whyItMatters: String
                let category: String
                let bestStartHour: Int?
                let bestEndHour: Int?
                let durationMinMinutes: Int?
                let durationMaxMinutes: Int?
                let howTo: [String]?
                let soloHint: String?
                let soloOverall: Double?
            }
            let decoded = try JSONDecoder().decode(EdgeResponse.self, from: data)
            let poiById = Dictionary(uniqueKeysWithValues: pois.map { ($0.osmId, $0) })
            let now = Date()
            return decoded.experiences.compactMap { item -> Experience? in
                guard let poi = poiById[item.osmId] else { return nil }
                let category = ExperienceCategory(rawValue: item.category) ?? OverpassService.category(for: poi.tags)
                let startHour = item.bestStartHour.map { max(0, min(23, $0)) } ?? 9
                let endHour = item.bestEndHour.map { max(0, min(23, $0)) } ?? 21
                let dMin = item.durationMinMinutes ?? 30
                let dMax = max(dMin, item.durationMaxMinutes ?? 90)
                let overall = max(6.0, min(9.5, item.soloOverall ?? 7.0))
                let breakdown = SoloScore.Breakdown(
                    seatingFriendly: overall, soloPatronRatio: overall, staffPressure: overall,
                    soloPortioning: overall, ambianceFit: overall, safety: overall
                )
                let howTo = (item.howTo ?? []).enumerated().map { HowToStep(order: $0.offset + 1, text: $0.element) }
                return Experience(
                    id: "exp_osm_\(poi.osmId)",
                    title: item.title,
                    oneLiner: item.oneLiner,
                    whyItMatters: item.whyItMatters,
                    category: category,
                    location: ExperienceLocation(
                        coordinates: [poi.lon, poi.lat],
                        cityCode: cityCode,
                        addressHint: nil,
                        placeNameLocal: poi.name,
                        placeNameRomanized: poi.nameEn
                    ),
                    bestTimes: [TimeWindow(startHour: startHour, endHour: endHour)],
                    durationMinutes: .init(min: dMin, max: dMax),
                    howTo: howTo,
                    realInconveniences: [],
                    soloScore: SoloScore(overall: overall, breakdown: breakdown, hint: item.soloHint, basedOnCount: 0),
                    sources: [
                        InformationSource(
                            type: .user,
                            url: URL(string: "https://www.openstreetmap.org/node/\(poi.osmId)"),
                            attribution: "© OpenStreetMap contributors + AI",
                            verifiedAt: now
                        )
                    ],
                    confidence: Confidence(
                        level: 1,
                        lastVerifiedAt: now,
                        reason: "AI-synthesized via Edge Function, unverified",
                        signals: .init(aiScrapeAgeDays: 0, passiveGpsHits30d: 0, activeReports30d: 0, trustedVerifications: 0)
                    ),
                    nearbyExperienceIds: [],
                    stats: .init(completionCount: 0, averageRating: 0),
                    status: .candidate,
                    createdAt: now,
                    updatedAt: now
                )
            }
        case .failure(let err):
            throw err
        }
    }

    /// Public cache-clear; used by Settings → Storage.
    @MainActor
    public func clearSynthesisCache() {
        guard let context = modelContext else { return }
        try? context.delete(model: AISynthesisCacheRecord.self)
        try? context.save()
    }

    // MARK: - Synthesis cache key

    /// SHA256 of canonical input. Sorting osmIds ensures input order
    /// doesn't change the key. Model name is part of the key so a
    /// model bump invalidates old cache rows naturally.
    static func synthesisCacheKey(
        pois: [OverpassService.POI],
        cityCode: String,
        locale: Locale,
        modelName: String
    ) -> String {
        let sortedIds = pois.map { String($0.osmId) }.sorted()
        let canonical = sortedIds.joined(separator: "|")
            + "|" + cityCode
            + "|" + locale.identifier
            + "|" + modelName
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Synthesis cache I/O

    private func loadCachedSynthesis(cacheKey key: String) async -> [Experience]? {
        await MainActor.run { [weak self] in
            guard let self, let context = self.modelContext else { return nil }
            let descriptor = FetchDescriptor<AISynthesisCacheRecord>(
                predicate: #Predicate { $0.cacheKey == key }
            )
            guard let row = (try? context.fetch(descriptor))?.first else { return nil }
            let age = Date().timeIntervalSince(row.synthesizedAt)
            guard age < Self.synthesisCacheTTLSeconds else { return nil }
            return try? JSONDecoder.iso8601Decoder.decode([Experience].self, from: row.experiencesJSON)
        }
    }

    private func writeCachedSynthesis(
        cacheKey key: String,
        experiences: [Experience],
        modelName: String
    ) async {
        await MainActor.run { [weak self] in
            guard let self, let context = self.modelContext else { return }
            let descriptor = FetchDescriptor<AISynthesisCacheRecord>(
                predicate: #Predicate { $0.cacheKey == key }
            )
            if let existing = (try? context.fetch(descriptor))?.first {
                context.delete(existing)
            }
            guard let blob = try? JSONEncoder.iso8601Encoder.encode(experiences) else { return }
            context.insert(
                AISynthesisCacheRecord(
                    cacheKey: key,
                    experiencesJSON: blob,
                    synthesizedAt: Date(),
                    modelName: modelName
                )
            )
            try? context.save()
        }
    }

    // MARK: - Daily quota (US-015)

    /// Pro tier daily caps.
    public static let dailySynthesisQuota = 30
    public static let dailyExplanationQuota = 60

    /// Free tier daily caps: 0 for both (second line of defense after the
    /// paywall gate; entitlement is the primary barrier).
    public static let dailySynthesisQuotaFree = 0
    public static let dailyExplanationQuotaFree = 0

    /// Resolve the applicable daily cap for `kind` given the current tier.
    private func dailyLimit(for kind: ModelKind) -> Int {
        if isProTier {
            switch kind {
            case .synthesis, .voice: return Self.dailySynthesisQuota
            case .explanation: return Self.dailyExplanationQuota
            }
        } else {
            switch kind {
            case .synthesis, .voice: return Self.dailySynthesisQuotaFree
            case .explanation: return Self.dailyExplanationQuotaFree
            }
        }
    }

    /// Atomically checks whether today's quota for `kind` is already
    /// reached, and if not, increments the counter.
    ///
    /// Returns `true` when the limit was already hit (caller should degrade
    /// to skeleton mode). Returns `false` when the counter was incremented
    /// and the real API call should proceed.
    ///
    /// Cache hits must bypass this method entirely — only real network
    /// calls should call it.
    @discardableResult
    public func checkAndIncrementQuota(kind: ModelKind) async -> Bool {
        await MainActor.run { [weak self] in
            guard let self, let context = self.modelContext else { return false }
            let limit = dailyLimit(for: kind)
            let today = AIUsageRecord.todayUTC()
            let descriptor = FetchDescriptor<AIUsageRecord>(
                predicate: #Predicate { $0.date == today }
            )
            let row = (try? context.fetch(descriptor))?.first

            // Read current count.
            let current: Int
            switch kind {
            case .synthesis, .voice:
                current = row?.synthesisCalls ?? 0
            case .explanation:
                current = row?.explanationCalls ?? 0
            }

            if current >= limit {
                return true  // quota hit; do not increment
            }

            // Under limit — increment.
            let record = row ?? {
                let r = AIUsageRecord(date: today)
                context.insert(r)
                return r
            }()
            switch kind {
            case .synthesis, .voice:
                record.synthesisCalls += 1
            case .explanation:
                record.explanationCalls += 1
            }
            try? context.save()
            return false
        }
    }

    /// True if the per-day cap for `kind` is reached. Pure read; no
    /// mutation. Used internally to keep synthesizeExperiences readable.
    private func isQuotaExceeded(kind: ModelKind) async -> Bool {
        await MainActor.run { [weak self] in
            guard let self, let context = self.modelContext else { return false }
            let limit = dailyLimit(for: kind)
            let today = AIUsageRecord.todayUTC()
            let descriptor = FetchDescriptor<AIUsageRecord>(
                predicate: #Predicate { $0.date == today }
            )
            guard let row = (try? context.fetch(descriptor))?.first else {
                return limit == 0
            }
            switch kind {
            case .synthesis, .voice:
                return row.synthesisCalls >= limit
            case .explanation:
                return row.explanationCalls >= limit
            }
        }
    }

    /// Increment the counter for `kind`, creating today's row on first call.
    private func incrementQuota(kind: ModelKind) async {
        await MainActor.run { [weak self] in
            guard let self, let context = self.modelContext else { return }
            let today = AIUsageRecord.todayUTC()
            let descriptor = FetchDescriptor<AIUsageRecord>(
                predicate: #Predicate { $0.date == today }
            )
            let row = (try? context.fetch(descriptor))?.first
                ?? {
                    let r = AIUsageRecord(date: today)
                    context.insert(r)
                    return r
                }()
            switch kind {
            case .synthesis, .voice:
                row.synthesisCalls += 1
            case .explanation:
                row.explanationCalls += 1
            }
            try? context.save()
        }
    }

    @MainActor
    private func setQuotaExceeded() {
        self.quotaExceededAt = Date()
    }

    // MARK: - Synthesize helpers

    private static func synthesisPrompt(pois: [OverpassService.POI], cityCode: String, locale: Locale) -> String {
        let langTag = locale.language.languageCode?.identifier ?? "en"
        let lines = pois.map { poi -> String in
            let displayName = poi.nameEn ?? poi.name
            let tagSummary = poi.tags
                .filter { ["amenity", "tourism", "leisure", "natural", "shop", "cuisine", "opening_hours"].contains($0.key) }
                .map { "\($0.key)=\($0.value)" }
                .sorted()
                .joined(separator: ", ")
            return "- osmId=\(poi.osmId) name=\"\(poi.name)\" nameEn=\"\(displayName)\" lat=\(poi.lat) lon=\(poi.lon) tags=[\(tagSummary)]"
        }.joined(separator: "\n")

        return """
        You are writing solo-traveler-focused entries for real places sourced from OpenStreetMap.

        CRITICAL CONSTRAINTS — your output is read by users on the ground:
        - Use ONLY the provided OSM tags. Do NOT invent menu items, interior details, hours, prices, owner backstories, dish names, or specific seating positions.
        - If a field is not derivable from tags, write a generic safe value. Example: when no opening_hours tag is present, set bestStartHour to 9 and bestEndHour to 21 (a generic daytime window) rather than guessing a specific schedule.
        - howTo must contain navigation/orientation steps only. Do NOT write "order the X", "try the X", "ask for X", "sit at the bar/window/back".
        - Avoid the phrases: "menu", "specialty", "best seat", "the owner", "opens at", "closes at", "price", "order the", "try the".
        - Solo Score should be a conservative 7.0–8.5 unless tags clearly indicate something exceptional (e.g. tourism=viewpoint with a name → up to 9.0).

        Examples of GOOD output (tag-derived, generic):
        - title: "Sit with locals at a Hanoi café"
        - oneLiner: "A local cafe in the Old Quarter with sidewalk seating."
        - whyItMatters: "OpenStreetMap lists this as a café in a walkable neighbourhood. Solo travellers often find sidewalk-style cafés easier to enter alone than enclosed restaurants. Verify the vibe on arrival."
        - howTo: ["Find the entrance from the main street.", "Step inside; seating is usually self-service.", "Pay at the counter when you leave."]

        Examples of BAD output (hallucinated, do NOT do this):
        - title: "Eat the famous beef pho at Ms. Linh's"  ← invented owner + dish
        - oneLiner: "Try the lemongrass coffee, a hidden secret since 1972."  ← invented menu + history
        - howTo: ["Order the egg coffee", "Sit at the window seat"]  ← invented item + seat

        For each POI below, return ONE JSON object with these fields and nothing else:
        {
          "osmId": <int>,
          "title": "<action-oriented sensory line, less than 14 words>",
          "oneLiner": "<one concrete detail derivable from tags, less than 25 words>",
          "whyItMatters": "<2-3 sentences for someone alone, no specifics not in tags>",
          "category": "food|coffee|culture|nature|work|wellness|nightlife|hidden",
          "bestStartHour": <0-23>,
          "bestEndHour": <0-23>,
          "durationMinMinutes": <int>,
          "durationMaxMinutes": <int>,
          "howTo": ["navigation step 1", "navigation step 2", "navigation step 3"],
          "soloHint": "<one short hint for solo visitors>",
          "soloOverall": <number 6.0-9.5>
        }

        Output a JSON array containing one object per POI, in input order. No prose. No markdown fences.

        Output language: \(langTag).
        City code: \(cityCode).

        POIs:
        \(lines)
        """
    }

    private static func parseSynthesizedExperiences(
        _ raw: String,
        pois: [OverpassService.POI],
        cityCode: String
    ) throws -> [Experience] {
        guard
            let start = raw.firstIndex(of: "["),
            let end = raw.lastIndex(of: "]"),
            start <= end,
            let data = String(raw[start...end]).data(using: .utf8)
        else {
            throw AIError.decodingFailed("no JSON array in synthesis response")
        }

        struct Item: Decodable {
            let osmId: Int64
            let title: String
            let oneLiner: String
            let whyItMatters: String
            let category: String
            let bestStartHour: Int?
            let bestEndHour: Int?
            let durationMinMinutes: Int?
            let durationMaxMinutes: Int?
            let howTo: [String]?
            let soloHint: String?
            let soloOverall: Double?
        }
        let items = try JSONDecoder().decode([Item].self, from: data)
        let poiById = Dictionary(uniqueKeysWithValues: pois.map { ($0.osmId, $0) })
        let now = Date()

        return items.compactMap { item in
            guard let poi = poiById[item.osmId] else { return nil }
            let category = ExperienceCategory(rawValue: item.category) ?? OverpassService.category(for: poi.tags)
            let startHour = item.bestStartHour.map { max(0, min(23, $0)) } ?? 9
            let endHour = item.bestEndHour.map { max(0, min(23, $0)) } ?? 21
            let dMin = item.durationMinMinutes ?? 30
            let dMax = max(dMin, item.durationMaxMinutes ?? 90)
            let overall = max(6.0, min(9.5, item.soloOverall ?? 7.0))
            let breakdown = SoloScore.Breakdown(
                seatingFriendly: overall, soloPatronRatio: overall, staffPressure: overall,
                soloPortioning: overall, ambianceFit: overall, safety: overall
            )
            let howTo = (item.howTo ?? []).enumerated().map { HowToStep(order: $0.offset + 1, text: $0.element) }
            return Experience(
                id: "exp_osm_\(poi.osmId)",
                title: item.title,
                oneLiner: item.oneLiner,
                whyItMatters: item.whyItMatters,
                category: category,
                location: ExperienceLocation(
                    coordinates: [poi.lon, poi.lat],
                    cityCode: cityCode,
                    addressHint: nil,
                    placeNameLocal: poi.name,
                    placeNameRomanized: poi.nameEn
                ),
                bestTimes: [TimeWindow(startHour: startHour, endHour: endHour)],
                durationMinutes: .init(min: dMin, max: dMax),
                howTo: howTo,
                realInconveniences: [],
                soloScore: SoloScore(overall: overall, breakdown: breakdown, hint: item.soloHint, basedOnCount: 0),
                sources: [
                    InformationSource(
                        type: .user,
                        url: URL(string: "https://www.openstreetmap.org/node/\(poi.osmId)"),
                        attribution: "© OpenStreetMap contributors + AI",
                        verifiedAt: now
                    )
                ],
                confidence: Confidence(
                    level: 1,
                    lastVerifiedAt: now,
                    reason: "AI-synthesized from OpenStreetMap, unverified",
                    signals: .init(aiScrapeAgeDays: 0, passiveGpsHits30d: 0, activeReports30d: 0, trustedVerifications: 0)
                ),
                nearbyExperienceIds: [],
                stats: .init(completionCount: 0, averageRating: 0),
                status: .candidate,
                createdAt: now,
                updatedAt: now
            )
        }
    }

    /// Build a minimal Experience from raw OSM data, used when AI is unavailable.
    /// Preserves coordinate + name + category; everything else is conservative defaults.
    static func skeletonExperience(from poi: OverpassService.POI, cityCode: String) -> Experience {
        let now = Date()
        let category = OverpassService.category(for: poi.tags)
        let displayName = poi.nameEn ?? poi.name
        let breakdown = SoloScore.Breakdown(
            seatingFriendly: 7, soloPatronRatio: 7, staffPressure: 7,
            soloPortioning: 7, ambianceFit: 7, safety: 7
        )
        return Experience(
            id: "exp_osm_\(poi.osmId)",
            title: displayName,
            oneLiner: NSLocalizedString("explore.skeleton.oneLiner", comment: "Generic OSM POI tagline"),
            whyItMatters: NSLocalizedString("explore.skeleton.why", comment: "Generic OSM POI rationale"),
            category: category,
            location: ExperienceLocation(
                coordinates: [poi.lon, poi.lat],
                cityCode: cityCode,
                addressHint: nil,
                placeNameLocal: poi.name,
                placeNameRomanized: poi.nameEn
            ),
            bestTimes: [TimeWindow(startHour: 9, endHour: 21)],
            durationMinutes: .init(min: 30, max: 90),
            howTo: [],
            realInconveniences: [],
            soloScore: SoloScore(overall: 7.0, breakdown: breakdown, hint: nil, basedOnCount: 0),
            sources: [
                InformationSource(
                    type: .user,
                    url: URL(string: "https://www.openstreetmap.org/node/\(poi.osmId)"),
                    attribution: "© OpenStreetMap contributors",
                    verifiedAt: now
                )
            ],
            confidence: Confidence(
                level: 1,
                lastVerifiedAt: now,
                reason: "OpenStreetMap entry, no AI enrichment",
                signals: .init(aiScrapeAgeDays: 0, passiveGpsHits30d: 0, activeReports30d: 0, trustedVerifications: 0)
            ),
            nearbyExperienceIds: [],
            stats: .init(completionCount: 0, averageRating: 0),
            status: .candidate,
            createdAt: now,
            updatedAt: now
        )
    }
}
