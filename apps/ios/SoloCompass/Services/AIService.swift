import Foundation
import CoreLocation
import CryptoKit
import Observation
import os
import SwiftData

/// Talks to DeepSeek via the OpenAI-compatible chat completions API.
/// Resolves the API key via `Secrets.resolvedDeepSeekApiKey`
/// (UserDefaults override > GeneratedSecrets > env var). When no key is
/// available, calls return a fallback that ranks by Solo Score.
///
/// We keep this surface minimal — three intents the rest of the app actually
/// needs. Adding more should require a real product reason.
@Observable
public final class AIService {
    private static let logger = Logger(subsystem: "com.solocompass", category: "AIService")

    /// The solo traveler's current situation — where they are, when, and
    /// what they like — used to tailor experience recommendations.
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

    /// The AI's reply to a voice intent: which experiences to surface, a
    /// warm explanation for the traveler, and an optional category filter.
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

    /// Failure modes when talking to the AI backend — no key configured,
    /// the request failed, or the response couldn't be decoded.
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

    /// Provenance of the most recent synthesis result (US-003). The UI uses
    /// this to render a transparency badge so users can tell apart a real // anti-pattern-lint:allow transparency indicator for AI synthesis quality, not gamification
    /// AI-authored synthesis, a degraded skeleton fallback, and a cached hit.
    public enum AISynthesisQuality: Equatable {
        /// Synthesis succeeded through the model (direct or Edge Function).
        case real
        /// Network/model failed; we returned skeleton placeholders.
        case skeleton
        /// Served from the persisted synthesis cache without a network call.
        case cached
    }

    public private(set) var isProcessing: Bool = false
    public private(set) var lastError: Error?

    /// Set on every synthesis path: `.real` on success, `.skeleton` on
    /// fallback, `.cached` on a cache hit. Drives the transparency badge. // anti-pattern-lint:allow transparency indicator for AI synthesis quality, not gamification
    public private(set) var lastSynthesisQuality: AISynthesisQuality = .real
    /// Set when the daily AI quota cap fires (Epic B US-015). The map
    /// view shows a banner derived from this. Persisted across cold
    /// starts via UserDefaults — without persistence the user could
    /// trigger Explore 30 times, hit quota, restart, and silently get
    /// skeleton results on every call with no banner.
    /// `quotaResetIfPastMidnight()` clears it when the local day rolls.
    public private(set) var quotaExceededAt: Date? {
        didSet {
            if let date = quotaExceededAt {
                UserDefaults.standard.set(date, forKey: Self.quotaExceededAtUDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.quotaExceededAtUDKey)
            }
        }
    }

    /// UserDefaults key for the persisted quota-exceeded timestamp.
    private static let quotaExceededAtUDKey = "SoloCompass.AIService.quotaExceededAt"

    /// Set by MapViewModel (or tests) to reflect the current subscription
    /// tier. Defaults to `true` so previews and tests without a
    /// SubscriptionService still get Pro-tier quotas.
    /// Free tier: synthesis 0 / explanation 0 (second line of defense
    /// after the paywall gate in MapViewModel).
    public var isProTier: Bool = true

    private let session: URLSession
    private let modelContext: ModelContext?

    /// Resolve the DeepSeek `/chat/completions` endpoint from current Secrets.
    /// We strip only a single trailing "/" — `trimmingCharacters` is wrong
    /// here because it would also eat the leading "https://" slashes.
    private var apiURL: URL? {
        var base = Secrets.resolvedDeepSeekBaseURL
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + "/chat/completions")
    }

    /// Synthesis cache TTL — 7 days.
    ///
    /// #88: was 30 days. A traveler revisiting a neighbourhood 4 weeks later
    /// was served the original AI synthesis even after the model / prompt
    /// improved, with no in-UI signal that the content was stale. 7 days
    /// keeps the cache useful for a single trip but forces a re-synthesis
    /// on a return visit, so prompt + model improvements actually surface.
    /// The `.cached` badge is the user-visible signal that synthesis came
    /// from cache; this constant controls the upper bound on how old that
    /// cache can be before the entry is rejected.
    public static let synthesisCacheTTLSeconds: TimeInterval = 7 * 86_400

    /// Shared system prompt — identical across all call kinds to maximise
    /// DeepSeek's automatic prefix caching (same prefix → cached KV state).
    /// Keep this stable: every edit invalidates the cache fleet-wide.
    static let sharedSystemPrompt =
        "You are Solo Compass's AI engine for solo travelers. " +
        "Output exactly what the user prompt asks for. " +
        "When asked for JSON, return only a single valid JSON value with no markdown fences and no commentary."

    /// Model routing. DeepSeek currently exposes one general chat model
    /// (`deepseek-chat` / `deepseek-v4-pro`) via the OpenAI-compatible
    /// endpoint, so all three call kinds share the same model name resolved
    /// from `Secrets.resolvedDeepSeekModel`. The kind is still passed
    /// through so future per-kind tuning (max_tokens, temperature, model
    /// override env var) can land without changing call sites.
    public enum ModelKind: String, Sendable {
        case synthesis, explanation, voice
    }

    public init(session: URLSession = .shared, modelContext: ModelContext? = nil) {
        self.session = session
        self.modelContext = modelContext
        // Restore quota-exceeded from UserDefaults, but auto-clear if the
        // local day has rolled — daily caps reset at midnight per US-015.
        if let saved = UserDefaults.standard.object(forKey: Self.quotaExceededAtUDKey) as? Date {
            // #82: Compare the saved timestamp to "today" using the SAME UTC
            // calendar AIUsageRecord uses for its day-key. Earlier this was
            // Calendar.current.isDateInToday, which used the device's local
            // tz — on a UTC-8 device the local day rolls 8 hours AFTER the
            // UTC counter resets, leaving the banner stuck on "today's quota
            // exhausted" while the underlying counter was already empty.
            // Now: same UTC midnight → still today → keep banner; different
            // UTC day → counter has reset → clear banner.
            if AIUsageRecord.todayUTC(saved) == AIUsageRecord.todayUTC() {
                self.quotaExceededAt = saved
            } else {
                UserDefaults.standard.removeObject(forKey: Self.quotaExceededAtUDKey)
            }
        }
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

    /// Resolve which model to use for a given call kind. All kinds share the
    /// DeepSeek model from `Secrets.resolvedDeepSeekModel`. Per-kind env var
    /// overrides (`DEEPSEEK_MODEL_SYNTHESIS` etc.) take precedence so QA can
    /// pin a model per call kind without rebuilding.
    static func modelName(for kind: ModelKind) -> String {
        let envKey: String
        switch kind {
        case .synthesis:   envKey = "DEEPSEEK_MODEL_SYNTHESIS"
        case .explanation: envKey = "DEEPSEEK_MODEL_EXPLANATION"
        case .voice:       envKey = "DEEPSEEK_MODEL_VOICE"
        }
        if let override = ProcessInfo.processInfo.environment[envKey], !override.isEmpty {
            return override
        }
        return Secrets.resolvedDeepSeekModel
    }

    // MARK: - Public

    /// Rank candidate experiences for the traveler's current context,
    /// returning the top picks; falls back to Solo Score when AI is offline.
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

    // MARK: - Generate a route (AI "discover / build a walk")

    /// The model's route plan: an ordered subset of the candidate ids plus the
    /// editorial copy. Decoded from a single JSON object the model returns.
    private struct GeneratedRoutePlan: Codable {
        let orderedIds: [String]
        let title: String
        let summary: String
        let reasonNow: String?
        let tags: [String]?
    }

    /// Generate a single walkable route from nearby experiences. The model
    /// picks 3–5 stops, orders them into a sensible walk, and writes a title,
    /// summary, and an optional "why now" line. Falls back — when no key is
    /// configured or the response can't be parsed — to a local greedy
    /// nearest-neighbour walk over the top Solo-scored candidates, so the
    /// feature always produces a route.
    ///
    /// - Parameters:
    ///   - candidates: nearby experiences to choose stops from.
    ///   - cityCode: city the route belongs to (VTE/HAN/…).
    ///   - userCoordinate: the traveler's location, used as the walk's origin
    ///     in the local fallback ordering.
    ///   - now: current time, used for the best-now boost in the fallback.
    public func generateRoute(
        from candidates: [Experience],
        cityCode: String,
        userCoordinate: CLLocationCoordinate2D?,
        now: Date = Date()
    ) async throws -> Route {
        let routeId = RouteId(rawValue: "ai-\(UUID().uuidString.prefix(8))")
        let validIds = Set(candidates.map(\.id))

        // An AI-built route is composed for the CURRENT moment (the user asked
        // to "plan tonight" / "string these together now", and reasonNow speaks
        // to right now). Anchor its best-now window to the current hour so that,
        // once adopted, it immediately surfaces in the "此刻 / Now" section —
        // otherwise bestStartHour stays nil, isBestNow() is always false, and the
        // route the user just created never appears in Now. Same RouteStore, same
        // table; this is the field that gates Now visibility.
        let nowHour = Double(Calendar.current.component(.hour, from: now))

        do {
            let prompt = Self.routeGenerationPrompt(candidates: candidates, cityCode: cityCode)
            let raw = try await sendMessage(prompt: prompt, kind: .synthesis)
            let plan = try Self.parseRoutePlan(raw)
            // Keep only ids the model was actually given, in the order it chose,
            // capped to a walkable 3–6 stops; drop dupes.
            var seen = Set<String>()
            let chosen = plan.orderedIds
                .filter { validIds.contains($0) && seen.insert($0).inserted }
                .prefix(6)
            let ordered = chosen.compactMap { id in candidates.first { $0.id == id } }
            guard ordered.count >= 2 else { throw AIError.decodingFailed("route plan too short") }
            return RouteBuilder.makeRoute(
                id: routeId,
                title: plan.title.isEmpty ? Self.fallbackRouteTitle(ordered) : plan.title,
                summary: plan.summary,
                orderedExperiences: ordered,
                cityCode: cityCode,
                pace: .relaxed,
                tags: plan.tags ?? Self.tags(from: ordered),
                source: .aiGenerated,
                bestStartHour: nowHour,
                reasonNow: plan.reasonNow?.isEmpty == false ? plan.reasonNow : nil
            )
        } catch {
            // #66: Surface JSON parse failures to Sentry so we can spot the
            // model drifting away from the route-plan schema before the
            // fallback masks it forever. We capture metadata only — never the
            // raw body, which can contain user-adjacent place names from the
            // prompt; the error message + candidate count is enough to
            // diagnose a truncation or wrong-shape response. SentryService is
            // @MainActor, hop over fire-and-forget so the fallback isn't
            // blocked waiting for the report.
            let captureErr = error.localizedDescription
            let captureCount = candidates.count
            Task { @MainActor in
                SentryService.capture(
                    message: "AI JSON parse failed: generateRoute",
                    level: .warning,
                    context: [
                        "prompt_type": "route_generation",
                        "error": captureErr,
                        "candidate_count": captureCount
                    ]
                )
            }
            // Local fallback: top Solo-scored candidates, walked nearest-first.
            let top = candidates
                .sorted { lhs, rhs in
                    let l = lhs.soloScore.overall + (lhs.isBestNow(at: now) ? 2 : 0)
                    let r = rhs.soloScore.overall + (rhs.isBestNow(at: now) ? 2 : 0)
                    return l > r
                }
                .prefix(5)
            let ordered = RouteBuilder.nearestNeighbourOrder(Array(top), from: userCoordinate)
            guard !ordered.isEmpty else { throw AIError.decodingFailed("no candidates to build a route") }
            return RouteBuilder.makeRoute(
                id: routeId,
                title: Self.fallbackRouteTitle(ordered),
                summary: NSLocalizedString("route.generate.fallback.summary",
                                           comment: "Local fallback route summary"),
                orderedExperiences: ordered,
                cityCode: cityCode,
                pace: .relaxed,
                tags: Self.tags(from: ordered),
                source: .aiGenerated,
                bestStartHour: nowHour
            )
        }
    }

    /// Generate one warm, grounded sentence on why a solo traveler would
    /// value visiting this specific place.
    public func explainRecommendation(for experience: Experience) async throws -> String {
        // Feed the model the actual place — name, category, city, and
        // coordinate. Passing only the opaque id (the previous behaviour)
        // gave the model nothing to ground on, so it hallucinated
        // unrelated landmarks (e.g. describing a SF plaza as the Alhambra).
        let coord = experience.coordinate
        let coordText = coord.map { String(format: "%.4f, %.4f", $0.latitude, $0.longitude) } ?? "unknown"
        let prompt = """
        A real place from OpenStreetMap:
        - Name: \(experience.title)
        - Category: \(experience.category.rawValue)
        - City code: \(experience.location.cityCode)
        - Coordinate (lat, lon): \(coordText)

        Explain in one warm, concrete sentence why a solo traveler would value visiting THIS specific place. \
        Ground every detail in the name/category above — do NOT invent unrelated landmarks, history, or features. \
        If you cannot say anything specific, describe what a solo traveler typically does at a place of this category. \
        Avoid superlatives. Focus on a plausible sensory detail.
        """
        do {
            return try await sendMessage(prompt: prompt, kind: .explanation)
        } catch AIError.missingAPIKey {
            return NSLocalizedString("ai.fallback.explanation", comment: "Default AI explanation")
        }
    }

    /// Interpret what the traveler said aloud and turn it into experience
    /// recommendations plus a spoken-style reply.
    public func processVoiceIntent(
        transcript: String,
        near coordinate: CLLocationCoordinate2D,
        nearbyExperiences: [Experience] = []
    ) async throws -> AIResponse {
        let nearbyContext: String
        if nearbyExperiences.isEmpty {
            nearbyContext = "There are no curated experiences within 10km."
        } else {
            nearbyContext = nearbyExperiences.prefix(20).map { exp in
                "  [\(exp.id)] \(exp.title) — \(exp.category.rawValue) — \(String(format: "%.1f", exp.soloScore.overall))/10"
            }.joined(separator: "\n")
        }

        let prompt = """
        A solo traveler said: "\(transcript)".
        Their location: \(coordinate.latitude), \(coordinate.longitude).

        Nearby curated experiences (use these exact IDs to recommend):
        \(nearbyContext)

        Respond as JSON:
        {
          "recommendedIds": ["id1","id2"],
          "explanation": "A warm, one-sentence response to the user. If no matches, suggest what kind of place they might look for.",
          "filterSuggestion": "culture|nature|food|coffee|work|wellness|nightlife|hidden|null"
        }
        Only include IDs that match the user request. If nothing matches, use empty array and explain.
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

    // MARK: - Voice agent streaming (US-VA-08)

    /// Events emitted by `sendAgentMessageStreaming`. The orchestrator
    /// subscribes and updates the UI progressively.
    public enum StreamEvent: Sendable {
        /// The model is streaming its text content word-by-word (delta).
        case contentDelta(String)
        /// The model decided to call a tool. `args` is raw JSON.
        case toolCall(id: String, name: String, args: String)
        /// All content + tool calls have been emitted.
        case done
    }

    /// Stream one agent turn via SSE (`stream: true`). Emits `.toolCall`
    /// events as function-call chunks arrive, then `.contentDelta` events
    /// for plain-text tokens. Ends with `.done`. Falls back to the
    /// non-streaming path on servers that don't support SSE.
    public func sendAgentMessageStreaming(
        messages: [VoiceAgentSession.Message],
        tools: [AgentTool]
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await MainActor.run { self.isProcessing = true }
                do {
                    let body: [String: Any] = [
                        "model": Self.modelName(for: .voice),
                        "messages": Self.serializeAgentMessages(messages),
                        "tools": Self.serializeAgentTools(tools),
                        "tool_choice": "auto",
                        "stream": true,
                        "max_tokens": 512,
                        "temperature": 0.3,
                    ]
                    let request = try await buildChatRequest(
                        stream: true,
                        kind: .voice,
                        bodyDict: body,
                        timeout: 60
                    )

                    // Accumulate tool-call deltas keyed by index.
                    var toolCallAccum: [Int: (id: String, name: String, args: String)] = [:]
                    var contentAccum = ""

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw AIError.requestFailed(status: 0, body: "no response")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        throw AIError.requestFailed(status: http.statusCode, body: "streaming error")
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        guard
                            let data = payload.data(using: .utf8),
                            let chunk = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                            let choices = chunk["choices"] as? [[String: Any]],
                            let delta = choices.first?["delta"] as? [String: Any]
                        else { continue }

                        // Text content delta
                        if let text = delta["content"] as? String, !text.isEmpty {
                            contentAccum += text
                            continuation.yield(.contentDelta(text))
                        }

                        // Tool call deltas
                        if let rawCalls = delta["tool_calls"] as? [[String: Any]] {
                            for rawCall in rawCalls {
                                guard let idx = rawCall["index"] as? Int else { continue }
                                let id = rawCall["id"] as? String ?? ""
                                let fn = rawCall["function"] as? [String: Any]
                                let name = fn?["name"] as? String ?? ""
                                let argChunk = fn?["arguments"] as? String ?? ""
                                if var existing = toolCallAccum[idx] {
                                    existing.args += argChunk
                                    if !id.isEmpty { existing.id = id }
                                    if !name.isEmpty { existing.name = name }
                                    toolCallAccum[idx] = existing
                                } else {
                                    toolCallAccum[idx] = (id: id, name: name, args: argChunk)
                                }
                            }
                        }
                    }

                    // Emit accumulated tool calls in index order
                    for idx in toolCallAccum.keys.sorted() {
                        guard let call = toolCallAccum[idx] else { continue }
                        continuation.yield(.toolCall(id: call.id, name: call.name, args: call.args))
                    }

                    continuation.yield(.done)
                    continuation.finish()
                    await MainActor.run { self.isProcessing = false }
                } catch {
                    await MainActor.run { self.isProcessing = false }
                    continuation.finish(throwing: error)
                }
            }
        }
    }



    // MARK: - Voice agent (US-VA-02)

    /// Function-calling tool definition sent to DeepSeek. The `parameters`
    /// payload is the raw OpenAI-style JSON Schema for the tool's
    /// arguments — callers (the router in US-VA-03) own its shape.
    public struct AgentTool: Sendable {
        public let name: String
        public let description: String
        /// JSON Schema as a JSON string ready to drop into the
        /// `parameters` slot of `{"type":"function","function":{...}}`.
        public let parametersJSON: String

        public init(name: String, description: String, parametersJSON: String) {
            self.name = name
            self.description = description
            self.parametersJSON = parametersJSON
        }
    }

    /// What `sendAgentMessage` hands back. Mirrors the OpenAI shape:
    /// when the model decides to call tools, `content` is nil and
    /// `toolCalls` is populated; when it's done, `content` carries the
    /// final assistant text.
    public struct AgentResponse: Equatable, Sendable {
        public let content: String?
        public let toolCalls: [VoiceAgentSession.ToolCall]

        public init(content: String?, toolCalls: [VoiceAgentSession.ToolCall]) {
            self.content = content
            self.toolCalls = toolCalls
        }
    }

    /// POST a full message history + tool catalog to DeepSeek and return
    /// either tool calls or final content. Stateless — the caller (the
    /// voice agent orchestrator in US-VA-06) owns the conversation.
    ///
    /// Routes through `.voice` config for now (model + auth + quota);
    /// US-VA-07 may carve out a dedicated `.voiceAgent` kind once we
    /// have per-session quotas to enforce.
    public func sendAgentMessage(
        messages: [VoiceAgentSession.Message],
        tools: [AgentTool]
    ) async throws -> AgentResponse {
        await MainActor.run { self.isProcessing = true }
        defer { Task { @MainActor [weak self] in self?.isProcessing = false } }

        let body: [String: Any] = [
            "model": Self.modelName(for: .voice),
            "messages": Self.serializeAgentMessages(messages),
            "tools": Self.serializeAgentTools(tools),
            "tool_choice": "auto",
            "parallel_tool_calls": true,
            "max_tokens": 512,
            "temperature": 0.3,
        ]
        // tighter than synthesis: agent turn budget is 30s total
        let request = try await buildChatRequest(
            stream: false,
            kind: .voice,
            bodyDict: body,
            timeout: 30
        )

        let callStart = CFAbsoluteTimeGetCurrent()
        let (data, response) = try await session.data(for: request)
        let latencyMs = Int((CFAbsoluteTimeGetCurrent() - callStart) * 1000)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.requestFailed(status: 0, body: "no response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw AIError.requestFailed(status: http.statusCode, body: bodyText)
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let tokenUsage = AIObservability.extractUsage(
               from: json,
               model: Self.modelName(for: .voice),
               kind: ModelKind.voice.rawValue,
               latencyMs: latencyMs
           ) {
            await AIObservability.shared.record(tokenUsage)
        }

        return try Self.parseAgentResponse(data)
    }

    /// Serialise the conversation as the array DeepSeek wants. We map
    /// each Role / Message field by hand so the wire shape stays
    /// decoupled from the in-memory model.
    /// Wrap user content in `<user_input>` tags at API-serialization time so the
    /// model always treats it as untrusted input — WITHOUT polluting the stored
    /// message (which the chat UI renders verbatim). Session history keeps the
    /// raw text; only the bytes sent to the model carry the tags.
    static func wrapUserContentForAPI(_ content: String) -> String {
        "<user_input>\(content)</user_input>"
    }

    static func serializeAgentMessages(_ messages: [VoiceAgentSession.Message]) -> [[String: Any]] {
        messages.map { msg -> [String: Any] in
            var row: [String: Any] = ["role": msg.role.rawValue]
            if let content = msg.content {
                // User turns get wrapped here (not in the stored message) so the
                // <user_input> guard never leaks into the chat bubble.
                row["content"] = msg.role == .user ? wrapUserContentForAPI(content) : content
            } else {
                // OpenAI requires "content" key even when null on assistant
                // tool-call rows. NSNull renders as JSON null.
                row["content"] = NSNull()
            }
            if !msg.toolCalls.isEmpty {
                row["tool_calls"] = msg.toolCalls.map { call -> [String: Any] in
                    [
                        "id": call.id,
                        "type": "function",
                        "function": [
                            "name": call.name,
                            "arguments": call.argumentsJSON,
                        ],
                    ]
                }
            }
            if let toolCallId = msg.toolCallId {
                row["tool_call_id"] = toolCallId
            }
            if let name = msg.name {
                row["name"] = name
            }
            return row
        }
    }

    static func serializeAgentTools(_ tools: [AgentTool]) -> [[String: Any]] {
        tools.compactMap { tool -> [String: Any]? in
            guard
                let data = tool.parametersJSON.data(using: .utf8),
                let parametersDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return nil
            }
            return [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": parametersDict,
                ],
            ]
        }
    }

    static func parseAgentResponse(_ data: Data) throws -> AgentResponse {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any]
        else {
            throw AIError.decodingFailed("Unexpected agent response shape")
        }

        // tool_calls path
        if let rawCalls = message["tool_calls"] as? [[String: Any]], !rawCalls.isEmpty {
            let calls: [VoiceAgentSession.ToolCall] = rawCalls.compactMap { entry in
                guard
                    let id = entry["id"] as? String,
                    let fn = entry["function"] as? [String: Any],
                    let name = fn["name"] as? String
                else { return nil }
                let args = fn["arguments"] as? String ?? "{}"
                return VoiceAgentSession.ToolCall(id: id, name: name, argumentsJSON: args)
            }
            return AgentResponse(content: nil, toolCalls: calls)
        }

        // plain content path
        let content = message["content"] as? String
        return AgentResponse(content: content.map(Self.stripMarkdownFences), toolCalls: [])
    }

    // MARK: - HTTP

    /// POST a single user prompt to DeepSeek (`/chat/completions`) and return
    /// the assistant text content. Strips ``` fences defensively before
    /// returning so callers can `JSON.parse` the result without re-doing it.
    private func sendMessage(prompt: String, kind: ModelKind = .synthesis) async throws -> String {
        await MainActor.run { self.isProcessing = true }
        defer { Task { @MainActor [weak self] in self?.isProcessing = false } }

        let body: [String: Any] = [
            "model": Self.modelName(for: kind),
            "messages": [
                ["role": "system", "content": Self.sharedSystemPrompt],
                ["role": "user", "content": prompt],
            ],
            "max_tokens": kind == .synthesis ? 2048 : 1024,
            "temperature": 0.7,
        ]
        let request = try await buildChatRequest(
            stream: false,
            kind: kind,
            bodyDict: body,
            timeout: 60
        )

        let callStart = CFAbsoluteTimeGetCurrent()
        let (data, response) = try await session.data(for: request)
        let latencyMs = Int((CFAbsoluteTimeGetCurrent() - callStart) * 1000)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.requestFailed(status: 0, body: "no response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw AIError.requestFailed(status: http.statusCode, body: bodyText)
        }

        // OpenAI-compatible: choices[0].message.content
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw AIError.decodingFailed("Unexpected response shape")
        }

        if let tokenUsage = AIObservability.extractUsage(
            from: json,
            model: Self.modelName(for: kind),
            kind: kind.rawValue,
            latencyMs: latencyMs
        ) {
            await AIObservability.shared.record(tokenUsage)
        }

        return Self.stripMarkdownFences(content)
    }

    // MARK: - Request routing (Pro → Edge / direct DeepSeek)

    /// Pick between Supabase Edge proxy (Pro tier + flags) and direct
    /// DeepSeek. Returns a fully-built `URLRequest`. The `kind` parameter
    /// is stamped into the body when going via Edge so chat-proxy can
    /// pick the correct daily quota bucket.
    ///
    /// `bodyDict` is the OpenAI-compatible payload built by callers
    /// (messages / tools / stream / max_tokens / etc.). It is mutated to
    /// add `kind` only on the Edge path.
    private func buildChatRequest(
        stream: Bool,
        kind: ModelKind,
        bodyDict: [String: Any],
        timeout: TimeInterval
    ) async throws -> URLRequest {
        // Edge path: Pro user + flags on + Supabase session available.
        if FeatureFlags.routeAIThroughEdge
            && FeatureFlags.backendSync
            && isProTier
        {
            var edgeBody = bodyDict
            edgeBody["kind"] = Self.edgeKindString(for: kind)
            let bodyData = try JSONSerialization.data(withJSONObject: edgeBody)
            let accept = stream ? "text/event-stream" : "application/json"
            // SupabaseClient is @MainActor — hop over to it just for the
            // request build, then run the actual network call back here.
            let edgeRequest: URLRequest? = await MainActor.run {
                SupabaseClient.shared.makeFunctionRequest(
                    function: "chat-proxy",
                    body: bodyData,
                    accept: accept
                )
            }
            if var edgeRequest {
                edgeRequest.timeoutInterval = timeout
                return edgeRequest
            }
            // makeFunctionRequest returned nil — flag on but no session /
            // missing config. Fall through to the direct path; that
            // mirrors the legacy behaviour and is safer than failing the
            // whole request when the backend is momentarily unreachable.
        }

        // Direct DeepSeek path (legacy).
        guard let key = Self.resolveAPIKey() else { throw AIError.missingAPIKey }
        guard let apiURL else { throw AIError.requestFailed(status: 0, body: "bad URL") }
        let bodyData = try JSONSerialization.data(withJSONObject: bodyDict)
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        if stream {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        request.timeoutInterval = timeout
        request.httpBody = bodyData
        return request
    }

    private static func edgeKindString(for kind: ModelKind) -> String {
        switch kind {
        case .voice:       return "voice"
        case .explanation: return "explanation"
        case .synthesis:   return "synthesis"
        }
    }

    // MARK: - Helpers

    /// DeepSeek API key resolution. UserDefaults override > GeneratedSecrets >
    /// `DEEPSEEK_API_KEY` env var (used by tests + simulator runs).
    private static func resolveAPIKey() -> String? {
        let runtime = Secrets.resolvedDeepSeekApiKey
        if !runtime.isEmpty { return runtime }
        if let env = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !env.isEmpty {
            return env
        }
        return nil
    }

    /// DeepSeek occasionally wraps JSON in ```json … ``` fences despite the
    /// system prompt. Strip a single outer fence if present; leave plain
    /// content untouched.
    static func stripMarkdownFences(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("```") else { return s }
        // Drop opening fence line (```json or ```)
        if let firstNewline = s.firstIndex(of: "\n") {
            s = String(s[s.index(after: firstNewline)...])
        }
        // Drop trailing ```
        if s.hasSuffix("```") {
            s = String(s.dropLast(3))
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// Prompt for `generateRoute` — asks the model to choose and order 3–5
    /// stops into a walkable loop and return a single JSON object.
    private static func routeGenerationPrompt(candidates: [Experience], cityCode: String) -> String {
        let candidateLines = candidates.prefix(40).map { exp in
            let coord = exp.coordinate.map { String(format: "%.4f,%.4f", $0.latitude, $0.longitude) } ?? "?"
            return "- \(exp.id): \(exp.title) [\(exp.category.rawValue), solo=\(String(format: "%.1f", exp.soloScore.overall)), @\(coord)]"
        }.joined(separator: "\n")
        return """
        You are planning ONE walkable route for a solo traveler in city \(cityCode).
        Choose 3 to 5 of the candidates below and order them into a sensible walk \
        (short hops, varied categories, a satisfying arc — e.g. coffee → culture → sunset viewpoint).

        Return ONLY a JSON object, no prose, with exactly these keys:
        {
          "orderedIds": ["id1","id2","id3"],   // 3–5 ids FROM the candidates, in walking order
          "title": "短而具体的路线名",            // concise, evocative; the traveler's language is fine
          "summary": "one sentence on the vibe of this walk",
          "reasonNow": "optional: why it's good right now, or empty string",
          "tags": ["culture","coffee"]          // 1–3 category tags
        }

        Candidates:
        \(candidateLines)
        """
    }

    /// Decode the single JSON object returned by `routeGenerationPrompt`.
    private static func parseRoutePlan(_ raw: String) throws -> GeneratedRoutePlan {
        guard
            let start = raw.firstIndex(of: "{"),
            let end = raw.lastIndex(of: "}"),
            start <= end,
            let data = String(raw[start...end]).data(using: .utf8)
        else { throw AIError.decodingFailed("no JSON in route plan") }
        return try JSONDecoder().decode(GeneratedRoutePlan.self, from: data)
    }

    /// A readable title when the model gives none — "<first> → <last> 散步".
    private static func fallbackRouteTitle(_ ordered: [Experience]) -> String {
        guard let first = ordered.first else {
            return NSLocalizedString("route.generate.fallback.title", comment: "Default generated route title")
        }
        if ordered.count == 1 { return first.title }
        let last = ordered[ordered.count - 1]
        return String(
            format: NSLocalizedString("route.generate.fallback.titleFormat",
                                      comment: "Generated route title: '<first> → <last>'"),
            first.title, last.title
        )
    }

    /// Distinct category raw-values across the stops, capped at 3, for tags.
    private static func tags(from ordered: [Experience]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for exp in ordered {
            let tag = exp.category.rawValue
            if seen.insert(tag).inserted { out.append(tag) }
            if out.count == 3 { break }
        }
        return out
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

    // MARK: - Web search enrichment (US-016)

    /// Send a web-search-style query to the AI and return the raw text response.
    /// Used by `WebSearchEnrichmentSource` to fetch objective, cross-verifiable
    /// facts for top-N ranked experiences. Throws `AIError.missingAPIKey` when
    /// no key is configured — callers treat that as a silent skip.
    public func sendWebSearchQuery(prompt: String) async throws -> String {
        try await sendMessage(prompt: prompt, kind: .explanation)
    }

    // MARK: - Synthesize from OSM POIs (Explore Here)

    /// Maximum POIs sent to the model in one call. Sized to accommodate the
    /// merged output of a 4-ring Pro radial Explore (≈60 POIs after dedupe)
    /// so the entire ring stack can share a single synthesis call rather
    /// than burning 4× the daily quota. See docs/PRD/pro-radial-explore.md
    /// (US-MR-03 / option B).
    public static let synthesisLimit = 60

    /// Convert a batch of OSM POIs into Experiences. The hot path:
    /// 1. Cache hit (SHA256 of inputs + model name + 30-day TTL) →
    ///    return persisted Experiences without HTTP.
    /// 2. Quota check (Pro: 30 synthesis/day) → if exceeded, fall back
    ///    to skeleton mode and set `quotaExceededAt`.
    /// 3. Real DeepSeek call → on success, persist + return; on failure,
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
            await MainActor.run { self.lastSynthesisQuality = .cached }
            await AIObservability.shared.trackEvent(.synthesisCacheHit, metadata: [
                "city": cityCode, "poi_count": String(capped.count),
            ])
            return cached
        }

        // US-015 quota check: cache hits don't count, network calls do.
        // checkAndIncrementQuota atomically checks and, if under limit,
        // increments. Returns true = limit already hit (degrade now).
        let quotaHit = await checkAndIncrementQuota(kind: .synthesis)
        if quotaHit {
            await setQuotaExceeded()
            // Expected degradation (not an error) — skeleton, no Sentry report.
            await MainActor.run { self.lastSynthesisQuality = .skeleton }
            return capped.map { Self.skeletonExperience(from: $0, cityCode: cityCode) }
        }

        // Epic E US-031: route through Supabase Edge Function instead
        // of direct Anthropic when the flag is on. This is the path
        // that lets us avoid bundling DEEPSEEK_API_KEY in the iOS app.
        if FeatureFlags.routeAIThroughEdge && FeatureFlags.backendSync {
            do {
                let experiences = try await synthesizeViaEdge(
                    pois: capped, cityCode: cityCode, locale: locale, cacheKey: cacheKey
                )
                await writeCachedSynthesis(
                    cacheKey: cacheKey, experiences: experiences, modelName: modelName
                )
                await MainActor.run { self.lastSynthesisQuality = .real }
                return experiences
            } catch {
                // Edge Function failed — skeleton fallback (no cache write).
                await reportSkeletonFallback(error)
                return capped.map { Self.skeletonExperience(from: $0, cityCode: cityCode) }
            }
        }

        let prompt = Self.synthesisPrompt(pois: capped, cityCode: cityCode, locale: locale)
        do {
            let raw = try await sendMessage(prompt: prompt, kind: .synthesis)
            let parsed = try Self.parseSynthesizedExperiences(raw, pois: capped, cityCode: cityCode)
            // Wikidata P18 photo enrichment for places that had no cheaper image
            // source (no OSM `image`/`wikimedia_commons` tag). Bounded + best-effort:
            // it never throws and is capped so it can't stall Explore. Done before
            // the cache write so the cached set carries the photos too.
            let experiences = await Self.enrichWithWikidataPhotos(parsed, pois: capped, session: session)
            await writeCachedSynthesis(
                cacheKey: cacheKey,
                experiences: experiences,
                modelName: modelName
            )
            await MainActor.run { self.lastSynthesisQuality = .real }
            await AIObservability.shared.trackEvent(.synthesisSuccess, metadata: [
                "city": cityCode, "poi_count": String(capped.count),
                "experience_count": String(experiences.count),
            ])
            return experiences
        } catch {
            // Skeleton fallback — never written to cache so a
            // transient network blip doesn't poison the cache for 30
            // days. Log the cause: this catch used to swallow the error
            // silently, which made "Explore only ever shows skeletons"
            // impossible to diagnose from the outside.
            Self.logger.error("synthesis failed, falling back to skeleton: \(String(describing: error), privacy: .public)")
            await reportSkeletonFallback(error)
            return capped.map { Self.skeletonExperience(from: $0, cityCode: cityCode) }
        }
    }

    /// Shared skeleton-fallback bookkeeping for the two synthesis paths:
    /// flip `lastSynthesisQuality` to `.skeleton` and report the underlying
    /// cause to Sentry under the `AIService.skeleton_fallback` subsystem so
    /// "Explore only ever shows skeletons" is diagnosable from telemetry.
    private func reportSkeletonFallback(_ error: Error) async {
        await MainActor.run {
            self.lastSynthesisQuality = .skeleton
            SentryService.capture(
                error: error,
                context: ["subsystem": "AIService.skeleton_fallback"]
            )
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
                        // type=.amap surfaces AutoNavi provenance in
                        // ExperienceDetailView's source-strength chip so users
                        // on the mainland can see amap actually contributed
                        // (previously the chip just showed "user").
                        InformationSource(
                            type: poi.tags["source"] == "amap" ? .amap : .user,
                            url: poi.tags["source"] == "amap"
                                ? nil
                                : URL(string: "https://www.openstreetmap.org/node/\(poi.osmId)"),
                            attribution: poi.tags["source"] == "amap"
                                ? "© AutoNavi (Amap) + AI"
                                : "© OpenStreetMap contributors + AI",
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

    /// Ask the `enrich-user-experience` Edge Function to AI-complete a
    /// user-created place (Phase 2 UGC). Returns a copy of `candidate` with the
    /// trust-critical fields filled in (whyItMatters, Solo Score, bestTimes,
    /// realInconveniences) — the user never self-reports these. The id,
    /// coordinates, place names, photos, and `candidate` status are preserved.
    ///
    /// Returns `nil` (caller keeps the original candidate) when: backend sync is
    /// off, the user isn't signed in / not Pro, or the function errors. Enrichment
    /// is best-effort polish, never a gate on the place existing.
    public func enrichUserExperience(_ candidate: Experience, locale: Locale = .current) async -> Experience? {
        guard isProTier else { return nil }

        struct EnrichRequest: Encodable {
            let experienceId: String
            let title: String
            let oneLiner: String
            let description: String
            let category: String
            let coordinates: [Double]
            let cityCode: String
            let locale: String
        }
        let body = EnrichRequest(
            experienceId: candidate.id,
            title: candidate.title,
            oneLiner: candidate.oneLiner,
            description: candidate.whyItMatters,
            category: candidate.category.rawValue,
            coordinates: candidate.location.coordinates,
            cityCode: candidate.location.cityCode,
            locale: locale.identifier
        )
        guard let bodyData = try? JSONEncoder().encode(body) else { return nil }

        let result = await SupabaseClient.shared.invoke(function: "enrich-user-experience", body: bodyData)
        guard case .success(let data) = result, !data.isEmpty else { return nil }

        struct EnrichResponse: Decodable {
            let enriched: EnrichItem
        }
        struct InconvenienceItem: Decodable {
            let category: String
            let text: String
        }
        struct EnrichItem: Decodable {
            let whyItMatters: String
            let soloOverall: Double
            let soloHint: String?
            let bestStartHour: Int?
            let bestEndHour: Int?
            let durationMinMinutes: Int?
            let durationMaxMinutes: Int?
            let realInconveniences: [InconvenienceItem]?
        }
        let decoded: EnrichResponse
        do {
            decoded = try JSONDecoder().decode(EnrichResponse.self, from: data)
        } catch {
            // #66: previously `try?` silently swallowed the parse failure, so
            // the user just saw their UGC place permanently stuck on the
            // skeleton Solo Score with no signal to debug. Capture metadata
            // (no raw body) so we can find the wrong-shape responses.
            // SentryService is @MainActor; hop over fire-and-forget.
            let captureErr = error.localizedDescription
            let captureLen = data.count
            Task { @MainActor in
                SentryService.capture(
                    message: "AI JSON parse failed: enrichUserExperience",
                    level: .warning,
                    context: [
                        "prompt_type": "enrich",
                        "error": captureErr,
                        "raw_body_length": captureLen
                    ]
                )
            }
            return nil
        }
        let item = decoded.enriched

        let overall = max(0, min(10, item.soloOverall))
        let breakdown = SoloScore.Breakdown(
            seatingFriendly: overall, soloPatronRatio: overall, staffPressure: overall,
            soloPortioning: overall, ambianceFit: overall, safety: overall
        )
        let startHour = item.bestStartHour.map { max(0, min(23, $0)) }
        let endHour = item.bestEndHour.map { max(0, min(23, $0)) }
        let bestTimes: [TimeWindow] = (startHour != nil && endHour != nil)
            ? [TimeWindow(startHour: startHour!, endHour: endHour!)] : candidate.bestTimes
        let dMin = item.durationMinMinutes ?? candidate.durationMinutes.min
        let dMax = max(dMin, item.durationMaxMinutes ?? candidate.durationMinutes.max)
        let inconveniences: [RealInconvenience] = (item.realInconveniences ?? []).compactMap {
            guard let cat = RealInconvenience.Category(rawValue: $0.category) else { return nil }
            return RealInconvenience(category: cat, text: $0.text)
        }
        let now = Date()

        return Experience(
            id: candidate.id,
            title: candidate.title,
            oneLiner: candidate.oneLiner,
            whyItMatters: item.whyItMatters,
            category: candidate.category,
            location: candidate.location,
            bestTimes: bestTimes,
            durationMinutes: .init(min: dMin, max: dMax),
            howTo: candidate.howTo,
            realInconveniences: inconveniences,
            soloScore: SoloScore(overall: overall, breakdown: breakdown, hint: item.soloHint, basedOnCount: 0),
            sources: [InformationSource(type: .user, attribution: "you + AI", verifiedAt: now)],
            confidence: Confidence(
                level: 1,
                lastVerifiedAt: now,
                reason: "User-created, AI-enriched, awaiting verification",
                signals: .init(aiScrapeAgeDays: 0, passiveGpsHits30d: 0, activeReports30d: 0, trustedVerifications: 0)
            ),
            nearbyExperienceIds: candidate.nearbyExperienceIds,
            stats: candidate.stats,
            status: .candidate,
            createdAt: candidate.createdAt,
            updatedAt: now,
            userTags: candidate.userTags
        )
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

    // MARK: - US-014: Multi-source confidence & attribution

    /// Apply `CompiledPlace` provenance metadata to a synthesized Experience.
    /// When a place was assembled from ≥2 distinct sources, this bumps the
    /// confidence level and enriches the `sources` list with per-source entries
    /// so the detail view can surface the "verified by multiple sources" indicator.
    ///
    /// Call this after `synthesizeExperiences` to upgrade the raw synthesis
    /// with accurate cross-source attribution.
    public static func applyMultiSourceAttribution(
        to experience: Experience,
        compiledPlace: CompiledPlace
    ) -> Experience {
        let sourcesCount = compiledPlace.sourcesCount
        guard sourcesCount >= 2 else { return experience }
        let now = Date()

        // Build per-source InformationSource entries for every contributor.
        var infoSources: [InformationSource] = experience.sources
        let presentSources = Set([compiledPlace.name.source]
            + [compiledPlace.rating?.source, compiledPlace.openingHours?.source,
               compiledPlace.priceLevel?.source, compiledPlace.website?.source,
               compiledPlace.phone?.source, compiledPlace.address?.source]
            .compactMap { $0 })

        for tag in presentSources {
            let alreadyPresent = infoSources.contains { src in
                (src.attribution ?? "").localizedCaseInsensitiveContains(tag.rawValue)
            }
            guard !alreadyPresent else { continue }
            let attribution: String
            let url: URL?
            switch tag {
            case .osm:
                attribution = "© OpenStreetMap contributors"
                url = nil
            case .foursquare:
                attribution = "Foursquare Places"
                url = nil
            case .mapkit:
                attribution = "Apple Maps"
                url = nil
            case .web:
                attribution = "Web"
                url = nil
            }
            infoSources.append(InformationSource(
                type: .user,
                url: url,
                attribution: attribution,
                verifiedAt: now
            ))
        }

        // Bump basedOnCount to reflect multi-source verification.
        let bumpedCount = max(experience.soloScore.basedOnCount, sourcesCount)
        let bumpedScore = SoloScore(
            overall: experience.soloScore.overall,
            breakdown: experience.soloScore.breakdown,
            hint: experience.soloScore.hint,
            basedOnCount: bumpedCount
        )

        // Bump confidence level using CompiledPlace's mapping.
        let newLevel = max(experience.confidence.level, CompiledPlace.confidenceLevel(for: compiledPlace))
        let bumpedConfidence = Confidence(
            level: newLevel,
            lastVerifiedAt: experience.confidence.lastVerifiedAt,
            reason: "AI-synthesized from \(sourcesCount) cross-verified sources",
            signals: experience.confidence.signals
        )

        return Experience(
            id: experience.id,
            title: experience.title,
            oneLiner: experience.oneLiner,
            whyItMatters: experience.whyItMatters,
            category: experience.category,
            location: experience.location,
            bestTimes: experience.bestTimes,
            durationMinutes: experience.durationMinutes,
            howTo: experience.howTo,
            realInconveniences: experience.realInconveniences,
            soloScore: bumpedScore,
            sources: infoSources,
            confidence: bumpedConfidence,
            nearbyExperienceIds: experience.nearbyExperienceIds,
            stats: experience.stats,
            status: experience.status,
            createdAt: experience.createdAt,
            updatedAt: experience.updatedAt,
            userTags: experience.userTags
        )
    }

    // MARK: - Synthesize helpers

    /// Pull the cross-channel hard signals a POI carries (from Foursquare /
    /// MapKit enrichment) out of its tag bag and into the typed location
    /// fields. OSM-only POIs simply have none of these keys, so everything
    /// stays nil. `placeNameLocal`/`placeNameRomanized` keep the raw name pair.
    static func enrichedLocation(
        from poi: OverpassService.POI,
        cityCode: String
    ) -> ExperienceLocation {
        // Foursquare rating is already 0–10. Clamp defensively.
        let rating = poi.tags["fsq_rating"].flatMap(Double.init).map { max(0, min(10, $0)) }
        let openingHours = poi.tags["opening_hours"]
        let priceLevel = poi.tags["fsq_price"].flatMap(Double.init).map { max(1, min(4, $0)) }
        let website = poi.tags["website"]
        let phone = poi.tags["phone"]
        let addr = poi.tags["addr"]
        // Zero-cost photo resolution from OSM `image` / `wikimedia_commons`
        // tags. The `wikidata` P18 fallback needs a network call and is
        // resolved separately (lazily) so it never blocks Explore.
        let photoUrls = ExperienceImageService.syncPhotoURLs(from: poi.tags)
        return ExperienceLocation(
            coordinates: [poi.lon, poi.lat],
            cityCode: cityCode,
            addressHint: addr,
            placeNameLocal: poi.name,
            placeNameRomanized: poi.nameEn,
            rating: rating,
            openingHours: openingHours,
            priceLevel: priceLevel,
            website: website,
            phone: phone,
            photoUrls: photoUrls
        )
    }

    /// Maximum POIs we'll resolve a Wikidata photo for in one synthesis run.
    /// Bounds the network fan-out so a dense Pro Explore can't fire dozens of
    /// EntityData requests.
    private static let wikidataEnrichCap = 12

    /// Best-effort Wikidata P18 photo enrichment. For each experience that has
    /// NO photo yet but whose POI carries a `wikidata` tag, resolves the entity's
    /// image to a Commons thumbnail and folds it into `location.photoUrls`.
    ///
    /// Never throws and never blocks Explore meaningfully: only the first
    /// `wikidataEnrichCap` candidates are looked up, requests run concurrently,
    /// and any failure leaves that experience unchanged. Experiences that already
    /// have a photo (OSM `image`/`wikimedia_commons`) pass through untouched.
    static func enrichWithWikidataPhotos(
        _ experiences: [Experience],
        pois: [OverpassService.POI],
        session: URLSession
    ) async -> [Experience] {
        let poiById = Dictionary(uniqueKeysWithValues: pois.map { ($0.osmId, $0) })

        // Index of experiences that need (and can get) a Wikidata lookup.
        let candidates: [(index: Int, qid: String)] = experiences.enumerated().compactMap { idx, exp in
            guard exp.location.photoUrls?.isEmpty ?? true else { return nil }
            guard let osmId = Int64(exp.id.replacingOccurrences(of: "exp_osm_", with: "")),
                  let poi = poiById[osmId],
                  ExperienceImageService.needsWikidataLookup(tags: poi.tags),
                  let qid = poi.tags["wikidata"] else { return nil }
            return (idx, qid)
        }
        guard !candidates.isEmpty else { return experiences }

        let capped = Array(candidates.prefix(wikidataEnrichCap))
        // Resolve concurrently; collect (index → url) for the ones that hit.
        let resolved: [(Int, String)] = await withTaskGroup(of: (Int, String?).self) { group in
            for candidate in capped {
                group.addTask {
                    let url = await ExperienceImageService.wikidataImageURL(
                        entityId: candidate.qid, session: session
                    )
                    return (candidate.index, url)
                }
            }
            var out: [(Int, String)] = []
            for await (index, url) in group {
                if let url { out.append((index, url)) }
            }
            return out
        }
        guard !resolved.isEmpty else { return experiences }

        var result = experiences
        for (index, url) in resolved {
            let enrichedLocation = result[index].location.withPhotoUrls([url])
            result[index] = result[index].copy(location: enrichedLocation)
        }
        return result
    }

    /// True when a POI carries at least one provider hard signal (rating /
    /// hours / price). Used to decide whether the AI may cite real data for
    /// this place rather than staying generic.
    static func hasHardSignals(_ poi: OverpassService.POI) -> Bool {
        poi.tags["fsq_rating"] != nil
            || poi.tags["opening_hours"] != nil
            || poi.tags["fsq_price"] != nil
    }

    private static func synthesisPrompt(pois: [OverpassService.POI], cityCode: String, locale: Locale) -> String {
        let langTag = locale.language.languageCode?.identifier ?? "en"
        let lines = pois.map { poi -> String in
            let displayName = poi.nameEn ?? poi.name
            let tagSummary = poi.tags
                .filter { [
                    "amenity", "tourism", "leisure", "natural", "shop", "cuisine",
                    "opening_hours", "internet_access", "fee", "outdoor_seating",
                ].contains($0.key) }
                .map { "\($0.key)=\($0.value)" }
                .sorted()
                .joined(separator: ", ")
            // Real provider signals (Foursquare / MapKit) the model is ALLOWED
            // to cite verbatim. Absent for OSM-only POIs.
            var signals: [String] = []
            if let r = poi.tags["fsq_rating"] { signals.append("rating=\(r)/10") }
            if let p = poi.tags["fsq_price"] { signals.append("priceLevel=\(p)/4") }
            if let pop = poi.tags["fsq_popularity"] { signals.append("popularity=\(pop)") }
            if let addr = poi.tags["addr"] { signals.append("address=\"\(addr)\"") }
            let signalSummary = signals.isEmpty ? "" : " realSignals=[\(signals.joined(separator: ", "))]"
            return "- osmId=\(poi.osmId) name=\"\(poi.name)\" nameEn=\"\(displayName)\" lat=\(poi.lat) lon=\(poi.lon) tags=[\(tagSummary)]\(signalSummary)"
        }.joined(separator: "\n")

        return """
        You are writing solo-traveler-focused entries for real places sourced from OpenStreetMap.

        CRITICAL CONSTRAINTS — your output is read by users on the ground:
        - You have TWO kinds of input per POI: OSM `tags` (categorical, reliable) and an optional `realSignals` bag (rating/priceLevel/popularity/address sourced from Foursquare or Apple Maps — REAL provider data you MAY cite).
        - You MAY reference anything in `realSignals` as fact: cite the rating, reflect the price level in your framing, use the address in orientation. These are real.
        - You may NOT invent specifics NOT present in either bag: no menu items, dish names, owner backstories, or interior/seating details. If `realSignals` has no opening hours, do not state hours.
        - When a POI has NO `realSignals`, fall back to generic-safe framing exactly as before: bestStartHour 9 / bestEndHour 21 when category gives no better hint.
        - howTo must contain navigation/orientation steps only. Do NOT write "order the X", "try the X", "ask for X", "sit at the bar/window/back" — those are interior specifics you cannot verify.
        - Solo Score: anchor on REAL signals when present. A high rating (>= 8/10) or strong popularity supports up to 9.0–9.5; a low/absent rating or sparse data should stay 6.5–8.0. With NO realSignals, keep it conservative 7.0–8.0. Make the six breakdown dimensions genuinely DIFFERENT from each other based on the place type (e.g. a library scores high on seatingFriendly + low staffPressure; a bar scores lower on soloPatronRatio) — do NOT output the same number across all six.

        CATEGORY-SPECIFIC SHAPE — a temple, a noodle shop, and a café need DIFFERENT facts. Tailor your output to the POI's category:

        • food → frame around the meal & eating alone. Score soloPortioning + staffPressure hardest. Highlights to prefer: pricePerPerson (only if realSignals priceLevel present), waitTime (only if you can infer a queue from popularity), signature (ONLY a cuisine type derivable from the `cuisine=` tag, e.g. "Vietnamese" — NEVER an invented dish name).
        • coffee / work → frame around lingering & focus. Score seatingFriendly + ambianceFit hardest. Highlights to prefer: wifi (only if `internet_access` tag present), power, longStay, vibe.
        • culture → frame around the sight & its meaning. Score safety + ambianceFit. Highlights to prefer: ticket (only if `fee`/`fee=no` tag present), bestLight (from category knowledge, e.g. temples at sunrise), duration.
        • nature → frame around the outdoor moment. Score safety + soloPatronRatio. Highlights to prefer: bestLight, duration, vibe.
        • wellness → frame around the calm solo ritual. Score ambianceFit + staffPressure. Highlights to prefer: booking, duration, vibe.
        • nightlife → frame around the evening scene for one. Score soloPatronRatio + safety hardest. Highlights to prefer: vibe, booking.
        • hidden / other → keep it generic; at most one `note` highlight.

        HIGHLIGHTS RULES (the `highlights` array): 0–3 short scannable facts, each {kind,label,value}. `kind` MUST be one of: signature, pricePerPerson, waitTime, wifi, power, longStay, bestLight, ticket, duration, booking, vibe, note. Emit a highlight ONLY when its value is derivable from a tag or realSignal or safe category knowledge (bestLight/duration are OK from category alone). `label` is a 1-word noun ("Wi-Fi", "Signature", "Best light"), `value` is ≤4 words ("fast", "Vietnamese", "sunrise"). NEVER invent menu items, prices without priceLevel, or hours without opening_hours. Prefer FEWER true highlights over padding. Output `highlights: []` when nothing is derivable.

        DISTANCE AWARENESS: The POI list may span 0–12 km from the user (a Pro radial Explore covers 4 rings: 1.5/3/6/12 km). Infer approximate distance from each POI's lat/lon relative to the others; closer POIs should lean toward in-the-moment framings (walk-up, sidewalk), farther POIs toward half-day-out framings (worth a transit ride). Do NOT mention distances or rings explicitly in the output — just let the framing reflect the proximity.

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
          "soloOverall": <number 6.0-9.5>,
          "soloBreakdown": {
            "seatingFriendly": <0-10>,
            "soloPatronRatio": <0-10>,
            "staffPressure": <0-10>,
            "soloPortioning": <0-10>,
            "ambianceFit": <0-10>,
            "safety": <0-10>
          },
          "highlights": [
            {"kind": "<one of the allowed kinds>", "label": "<1-word noun>", "value": "<=4 words>"}
          ]
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
            let soloBreakdown: Breakdown?
            let highlights: [Highlight]?

            struct Breakdown: Decodable {
                let seatingFriendly: Double?
                let soloPatronRatio: Double?
                let staffPressure: Double?
                let soloPortioning: Double?
                let ambianceFit: Double?
                let safety: Double?
            }

            struct Highlight: Decodable {
                let kind: String?
                let label: String?
                let value: String?
            }
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
            // Wider clamp now that real signals can justify higher/lower scores;
            // still bounded to a sane 5.0–9.8 to reject obvious model garbage.
            let overall = max(5.0, min(9.8, item.soloOverall ?? 7.0))
            // Prefer the model's per-dimension breakdown when it returned one;
            // fall back to `overall` per dimension only when absent. Each dim
            // independently clamped 0–10.
            func dim(_ value: Double?) -> Double { max(0, min(10, value ?? overall)) }
            let breakdown = SoloScore.Breakdown(
                seatingFriendly: dim(item.soloBreakdown?.seatingFriendly),
                soloPatronRatio: dim(item.soloBreakdown?.soloPatronRatio),
                staffPressure: dim(item.soloBreakdown?.staffPressure),
                soloPortioning: dim(item.soloBreakdown?.soloPortioning),
                ambianceFit: dim(item.soloBreakdown?.ambianceFit),
                safety: dim(item.soloBreakdown?.safety)
            )
            let howTo = (item.howTo ?? []).enumerated().map { HowToStep(order: $0.offset + 1, text: $0.element) }
            let highlights = Self.mapHighlights(
                item.highlights?.map { (kind: $0.kind, label: $0.label, value: $0.value) }
            )
            // basedOnCount reflects whether this score is anchored on real
            // provider signals (>0) or pure category inference (0).
            let basedOnCount = hasHardSignals(poi) ? 1 : 0
            return Experience(
                id: "exp_osm_\(poi.osmId)",
                title: item.title,
                oneLiner: item.oneLiner,
                whyItMatters: item.whyItMatters,
                category: category,
                location: enrichedLocation(from: poi, cityCode: cityCode),
                bestTimes: [TimeWindow(startHour: startHour, endHour: endHour)],
                durationMinutes: .init(min: dMin, max: dMax),
                howTo: howTo,
                realInconveniences: [],
                soloScore: SoloScore(overall: overall, breakdown: breakdown, hint: item.soloHint, basedOnCount: basedOnCount),
                sources: [
                    InformationSource(
                        type: .user,
                        url: URL(string: "https://www.openstreetmap.org/node/\(poi.osmId)"),
                        attribution: basedOnCount > 0
                            ? "© OpenStreetMap contributors + Foursquare/Apple Maps + AI"
                            : "© OpenStreetMap contributors + AI",
                        verifiedAt: now
                    )
                ],
                confidence: Confidence(
                    // Real provider signals bump confidence one notch above the
                    // pure-OSM baseline so the UI's confidence chip reflects it.
                    level: basedOnCount > 0 ? 2 : 1,
                    lastVerifiedAt: now,
                    reason: basedOnCount > 0
                        ? "AI-synthesized from OpenStreetMap + Foursquare/Apple Maps signals"
                        : "AI-synthesized from OpenStreetMap, unverified",
                    signals: .init(aiScrapeAgeDays: 0, passiveGpsHits30d: 0, activeReports30d: 0, trustedVerifications: 0)
                ),
                nearbyExperienceIds: [],
                stats: .init(completionCount: 0, averageRating: 0),
                status: .candidate,
                createdAt: now,
                updatedAt: now,
                categoryHighlights: highlights
            )
        }
    }

    /// Map raw AI highlight triples to validated `CategoryHighlight` values:
    /// drops any with an unknown `kind` or empty label/value, trims, and caps
    /// the count so a card never overflows. Returns nil when nothing survives so
    /// the Experience leaves `categoryHighlights` nil rather than an empty array.
    ///
    /// Takes plain optional-string triples (not a Decodable type) so it stays
    /// decoupled from the function-local `Item` shape and is unit-testable.
    static func mapHighlights(
        _ raw: [(kind: String?, label: String?, value: String?)]?
    ) -> [CategoryHighlight]? {
        guard let raw else { return nil }
        let mapped: [CategoryHighlight] = raw.compactMap { h in
            guard
                let kindRaw = h.kind,
                let kind = CategoryHighlight.Kind(rawValue: kindRaw),
                let label = h.label?.trimmingCharacters(in: .whitespacesAndNewlines),
                let value = h.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                !label.isEmpty, !value.isEmpty
            else { return nil }
            // Cap length: the prompt asks for a 1-word label / ≤4-word value,
            // but that's an instruction to the LLM, not a guarantee. A malformed
            // response with a 500-char value would persist to SwiftData and be
            // read verbatim by VoiceOver. Bound it defensively.
            return CategoryHighlight(
                kind: kind,
                label: String(label.prefix(40)),
                value: String(value.prefix(40))
            )
        }
        guard !mapped.isEmpty else { return nil }
        return Array(mapped.prefix(3))
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
            location: enrichedLocation(from: poi, cityCode: cityCode),
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

    // MARK: - P1.2 #122 Taste Profile

    /// Deterministic on-device taste profile generator (P1.2 #122).
    ///
    /// Returns the embedding/descriptors the new `TasteProfile` model needs
    /// to bootstrap a user from `OnboardingVibeStep` *without* a server hop.
    /// Vision-LLM enrichment lives behind a feature flag we can flip on
    /// later; the fallback here is the contract — onboarding must never
    /// stall on an LLM round-trip or missing API key.
    ///
    /// Confidence grows with input richness — pure style picks land at 0.30,
    /// adding photos and a free-form vibe nudges it toward 0.55. The real
    /// 0.95 ceiling comes later from `TasteUpdateService` once 5+ visits
    /// have refined the embedding.
    public func generateTasteProfile(
        photos: [Data],
        style: UserPreferences.SoloTravelStyle?,
        freeformVibe: String?
    ) async -> (embedding: [Float], descriptors: [String], confidence: Double) {
        let seed = Self.tasteSeed(
            style: style,
            photoCount: photos.count,
            vibe: freeformVibe
        )
        let embedding = Self.deterministicEmbedding(seed: seed, dim: 64)
        let descriptors = Self.descriptors(style: style, vibe: freeformVibe)
        // Match the descriptor path's trim — a whitespace-only vibe contributes
        // no descriptors, so it shouldn't bump confidence either.
        let trimmedVibe = freeformVibe?.trimmingCharacters(in: .whitespacesAndNewlines)
        let confidence = Self.confidence(
            photoCount: photos.count,
            hasStyle: style != nil,
            hasVibe: !(trimmedVibe?.isEmpty ?? true)
        )
        return (embedding, descriptors, confidence)
    }

    /// Hash the structured inputs to a single seed. Style/photoCount/vibe each
    /// fold into the same accumulator so changing any one of them shifts the
    /// whole embedding — exactly the property a user expects when they redo
    /// onboarding with new answers.
    static func tasteSeed(
        style: UserPreferences.SoloTravelStyle?,
        photoCount: Int,
        vibe: String?
    ) -> UInt64 {
        var acc: UInt64 = 0xCAFE_BABE_DEAD_BEEF
        if let style = style {
            for byte in style.rawValue.utf8 {
                acc &+= UInt64(byte)
                acc &*= 0x100_0000_01B3 // FNV prime
            }
        }
        acc ^= UInt64(truncatingIfNeeded: photoCount) &* 0x9E37_79B9_7F4A_7C15 as UInt64
        if let vibe = vibe?.trimmingCharacters(in: .whitespacesAndNewlines), !vibe.isEmpty {
            for byte in vibe.utf8 {
                acc &+= UInt64(byte)
                acc &*= 0x100_0000_01B3
            }
        }
        return acc
    }

    /// SplitMix64 PRNG → Float vector in [-1, 1]. Self-contained so we don't
    /// pull in GameplayKit just for a deterministic stream.
    static func deterministicEmbedding(seed: UInt64, dim: Int) -> [Float] {
        var state = seed == 0 ? 0xCAFE_BABE_DEAD_BEEF : seed
        var out: [Float] = []
        out.reserveCapacity(dim)
        for _ in 0..<dim {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z = z ^ (z >> 31)
            let normalized = Float(z & 0xFFFF_FFFF) / Float(UInt32.max)
            out.append(normalized * 2 - 1) // map [0,1] → [-1, 1]
        }
        return out
    }

    /// Map style + vibe to a short descriptor list. Style provides the base
    /// vocabulary; vibe contributes up to 2 trimmed lowercase words.
    static func descriptors(
        style: UserPreferences.SoloTravelStyle?,
        vibe: String?
    ) -> [String] {
        var descriptors: [String] = []
        if let style = style {
            switch style {
            case .explorer:      descriptors.append(contentsOf: ["curious", "wandering", "outdoor"])
            case .worker:        descriptors.append(contentsOf: ["quiet", "wifi-friendly", "focused"])
            case .foodie:        descriptors.append(contentsOf: ["culinary", "local", "lively"])
            case .cultureSeeker: descriptors.append(contentsOf: ["historic", "arty", "reflective"])
            }
        }
        if let vibe = vibe?.trimmingCharacters(in: .whitespacesAndNewlines), !vibe.isEmpty {
            let extra = vibe
                .lowercased()
                .split(whereSeparator: { !$0.isLetter })
                .prefix(2)
                .map(String.init)
            descriptors.append(contentsOf: extra)
        }
        if descriptors.isEmpty {
            descriptors = ["unspecified"]
        }
        return Array(descriptors.prefix(5))
    }

    /// Confidence schedule — fallback floor 0.30, +0.05 per photo (cap 3),
    /// +0.10 for a non-empty free-form vibe. Stays under the 0.95 ceiling
    /// reserved for the TasteUpdateService accumulating from real visits.
    static func confidence(
        photoCount: Int,
        hasStyle: Bool,
        hasVibe: Bool
    ) -> Double {
        var c = hasStyle ? 0.30 : 0.20
        c += min(0.15, 0.05 * Double(photoCount))
        if hasVibe { c += 0.10 }
        return min(0.55, c)
    }
}
