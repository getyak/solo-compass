import Foundation
import CoreLocation

// MARK: - Evidence-backed workday route compiler

/// JSON values accepted by the small constraint surface exposed to the agent.
/// Objects are intentionally excluded: workability constraints are scalar or
/// list comparisons, which keeps model-produced arguments bounded and auditable.
enum WorkdayConstraintValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case strings([String])
    case numbers([Double])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .boolean(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([String].self) { self = .strings(value); return }
        if let value = try? container.decode([Double].self) { self = .numbers(value); return }
        throw DecodingError.typeMismatch(
            WorkdayConstraintValue.self,
            .init(codingPath: decoder.codingPath, debugDescription: "expected a scalar or homogeneous array")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .strings(let value): try container.encode(value)
        case .numbers(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct WorkdayFeatureConstraint: Codable, Hashable, Sendable {
    let featureKey: String
    let `operator`: String
    let expected: WorkdayConstraintValue?
    let hard: Bool?
    let acceptableStatuses: [String]?
    let minimumConfidence: Double?
}

struct WorkdayRouteTaskInput: Codable, Hashable, Sendable {
    let id: String
    let kind: String
    let durationMinutes: Int
    let earliestStartMinute: Int?
    let latestEndMinute: Int?
    let candidateIds: [String]
    let constraints: [WorkdayFeatureConstraint]?
    let openingRequirement: String?
}

struct WorkdayBudgetInput: Codable, Hashable, Sendable {
    let maxAmount: Double
    let currency: String
}

struct WorkdayPlanIntentInput: Codable, Hashable, Sendable {
    let startMinute: Int
    let endMinute: Int
    let tasks: [WorkdayRouteTaskInput]
    let maxTravelMinutes: Int?
    let maxWaitMinutes: Int?
    let budget: WorkdayBudgetInput?
    let allowUnknownSpend: Bool?
    let allowUnknownOpeningHours: Bool?
    let fallbackMaxExtraTravelMinutes: Int?
}

struct WorkdayRouteCompileInput: Codable, Hashable, Sendable {
    let origin: [Double]
    let radiusMeters: Int
    let localDate: String
    let mode: String
    let intent: WorkdayPlanIntentInput
}

struct WorkdayRouteRejection: Codable, Hashable, Sendable {
    let code: String
    let count: Int
}

enum WorkdayRouteCompilation {
    case solved(Route)
    case unsatisfiable(failedTaskId: String, rejections: [WorkdayRouteRejection])
}

@MainActor
protocol WorkdayRouteCompiling: AnyObject {
    func compile(
        input: WorkdayRouteCompileInput,
        candidates: [Experience],
        cityCode: String
    ) async throws -> WorkdayRouteCompilation
}

/// Authenticated client for `/api/routes/compile`. The endpoint is the only
/// authority for stop order, travel time, time windows, and fallbacks; the LLM
/// is deliberately kept out of those decisions.
@MainActor
final class WorkdayRouteCompilerService: WorkdayRouteCompiling {
    enum CompilerError: Error, LocalizedError {
        case unconfigured
        case authentication(String)
        case rejected(status: Int, message: String)
        case invalidResponse(String)

        var errorDescription: String? {
            switch self {
            case .unconfigured:
                return "SOLO_API_BASE_URL is not configured"
            case .authentication(let message):
                return "route compiler authentication failed: \(message)"
            case .rejected(let status, let message):
                return "route compiler HTTP \(status): \(message)"
            case .invalidResponse(let message):
                return "route compiler response is invalid: \(message)"
            }
        }
    }

    private struct APIError: Decodable { let error: String }

    private struct APIWarning: Decodable {
        let code: String
        let featureKey: String?
        let message: String
    }

    private struct APIStop: Decodable {
        let taskId: String
        let taskKind: String
        let candidateId: String
        let experienceId: String
        let title: String
        let arrivalMinute: Int
        let startMinute: Int
        let endMinute: Int
        let travelFromPreviousMinutes: Int
        let distanceFromPreviousMeters: Int?
        let waitMinutes: Int
        let warnings: [APIWarning]
    }

    private struct APIFallback: Decodable {
        let taskId: String
        let primaryCandidateId: String
        let candidateId: String
        let experienceId: String
        let title: String
        let startMinute: Int
        let endMinute: Int
        let extraTravelMinutes: Int
        let warnings: [APIWarning]
    }

    private struct APISolution: Decodable {
        let stops: [APIStop]
        let fallbacks: [APIFallback]
        let totalTravelMinutes: Int
        let totalDistanceMeters: Int?
        let totalWaitMinutes: Int
        let startsAtMinute: Int
        let endsAtMinute: Int
        let warnings: [APIWarning]
    }

    private struct APIResult: Decodable {
        let status: String
        let solution: APISolution?
        let failedTaskId: String?
        let rejections: [WorkdayRouteRejection]?
    }

    private struct APIResponse: Decodable {
        let result: APIResult
        let evidenceCoverage: String
        let refreshScheduled: Bool
        let cache: String
    }

    private let session: URLSession
    private let baseURL: URL?
    private let authClient: any SupabaseClientProtocol

    init(
        session: URLSession = .shared,
        baseURL: URL? = nil,
        authClient: (any SupabaseClientProtocol)? = nil
    ) {
        self.session = session
        self.baseURL = baseURL ?? Secrets.resolvedAPIBaseURL()
        self.authClient = authClient ?? SupabaseClient.shared
    }

    func compile(
        input: WorkdayRouteCompileInput,
        candidates: [Experience],
        cityCode: String
    ) async throws -> WorkdayRouteCompilation {
        guard let baseURL else { throw CompilerError.unconfigured }

        let auth = await authClient.signInAnonymously()
        let accessToken: String
        switch auth {
        case .success(let session):
            accessToken = session.accessToken
        case .failure(let error):
            throw CompilerError.authentication(error.localizedDescription)
        }

        let endpoint = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("routes")
            .appendingPathComponent("compile")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(input)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CompilerError.invalidResponse("missing HTTP response")
        }
        guard http.statusCode == 200 || http.statusCode == 422 else {
            let message = (try? JSONDecoder().decode(APIError.self, from: data).error)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw CompilerError.rejected(status: http.statusCode, message: message)
        }

        let decoded: APIResponse
        do {
            decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        } catch {
            throw CompilerError.invalidResponse(error.localizedDescription)
        }

        if decoded.result.status == "unsatisfiable" {
            guard let failedTaskId = decoded.result.failedTaskId else {
                throw CompilerError.invalidResponse("unsatisfiable result omitted failedTaskId")
            }
            return .unsatisfiable(
                failedTaskId: failedTaskId,
                rejections: decoded.result.rejections ?? []
            )
        }
        guard decoded.result.status == "solved", let solution = decoded.result.solution else {
            throw CompilerError.invalidResponse("unknown result status \(decoded.result.status)")
        }

        let candidateById = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        let orderedExperiences = try solution.stops.map { stop -> Experience in
            guard let candidate = candidateById[stop.experienceId] else {
                throw CompilerError.invalidResponse(
                    "compiled stop \(stop.experienceId) is outside the visible candidate set"
                )
            }
            return candidate
        }
        let experienceIdByCandidateId = Dictionary(
            uniqueKeysWithValues: solution.stops.map { ($0.candidateId, $0.experienceId) }
        )
        let warnings: (APIWarning) -> CompiledRouteWarning = {
            CompiledRouteWarning(code: $0.code, featureKey: $0.featureKey, message: $0.message)
        }
        let compiledPlan = CompiledWorkdayPlan(
            localDate: input.localDate,
            startsAtMinute: solution.startsAtMinute,
            endsAtMinute: solution.endsAtMinute,
            totalTravelMinutes: solution.totalTravelMinutes,
            totalWaitMinutes: solution.totalWaitMinutes,
            evidenceCoverage: decoded.evidenceCoverage,
            refreshScheduled: decoded.refreshScheduled,
            cacheStatus: decoded.cache,
            stops: solution.stops.map {
                CompiledRouteStop(
                    taskId: $0.taskId,
                    taskKind: $0.taskKind,
                    experienceId: $0.experienceId,
                    title: $0.title,
                    arrivalMinute: $0.arrivalMinute,
                    startMinute: $0.startMinute,
                    endMinute: $0.endMinute,
                    travelFromPreviousMinutes: $0.travelFromPreviousMinutes,
                    distanceFromPreviousMeters: $0.distanceFromPreviousMeters,
                    waitMinutes: $0.waitMinutes,
                    warnings: $0.warnings.map(warnings)
                )
            },
            fallbacks: solution.fallbacks.map {
                CompiledRouteFallback(
                    taskId: $0.taskId,
                    primaryExperienceId: experienceIdByCandidateId[$0.primaryCandidateId]
                        ?? $0.primaryCandidateId,
                    experienceId: $0.experienceId,
                    title: $0.title,
                    startMinute: $0.startMinute,
                    endMinute: $0.endMinute,
                    extraTravelMinutes: $0.extraTravelMinutes,
                    warnings: $0.warnings.map(warnings)
                )
            },
            warnings: solution.warnings.map(warnings)
        )

        let title = NSLocalizedString("route.workday.title", comment: "Compiled workday route title")
        let summary = String(
            format: NSLocalizedString("route.workday.summary", comment: "Compiled workday route summary"),
            orderedExperiences.count,
            solution.totalTravelMinutes
        )
        let reasonNow = decoded.evidenceCoverage == "fresh"
            ? NSLocalizedString("route.workday.evidence.fresh", comment: "Fresh route evidence")
            : NSLocalizedString("route.workday.evidence.partial", comment: "Partial route evidence")
        let route = Route(
            id: RouteId(rawValue: "compiled-\(UUID().uuidString.prefix(8))"),
            title: title,
            summary: summary,
            experienceIds: orderedExperiences.map(\.id),
            cityCode: cityCode,
            region: orderedExperiences.first?.location.addressHint ?? "",
            estimatedDuration: max(0, solution.endsAtMinute - solution.startsAtMinute),
            distanceMeters: solution.totalDistanceMeters ?? 0,
            pace: .standard,
            tags: ["workday", "evidence-backed"],
            source: .aiGenerated,
            bestStartHour: Double(solution.startsAtMinute) / 60,
            reasonNow: reasonNow,
            verification: RouteVerification(),
            compiledPlan: compiledPlan
        )
        return .solved(route)
    }
}

/// Shared protocol so ExploreNearbyArgs / SearchPlacesArgs can reuse the same
/// filter-building helper without duplicating field access. (US-019)
private protocol QualityArgsProvider {
    var categories: [String]? { get }
    var solo_score_min: Double? { get }
    var rating_min: Double? { get }
    var ambiance_min: Double? { get }
}

/// Maps DeepSeek `tool_calls` to concrete app actions.
///
/// US-VA-03: 5 tools defined in docs/PRD/voice-agent.md §4 — explore_nearby,
/// filter_by_category, show_details, save_to_favorites, dismiss_recommendation.
/// Each `execute(...)` returns a JSON string suitable for feeding back to
/// DeepSeek as a `tool` role message (the orchestrator in US-VA-06 wraps it
/// with `VoiceAgentSession.appendToolResult(...)`).
///
/// Held weakly by the orchestrator so the router can't keep the view model
/// alive past sheet dismissal.
@MainActor
public final class VoiceAgentToolRouter {

    /// Failures encountered while dispatching a voice assistant tool call.
    ///
    /// Each case carries the tool name (when known) so the router can
    /// classify to a `ToolOutcome` on the way out — see `errorJSON(_:)`.
    /// Kept as `LocalizedError` because the outcome hint falls back to
    /// `errorDescription` for `.default` catches.
    public enum RouterError: Error, LocalizedError {
        case unknownTool(String)
        case invalidArguments(tool: String, reason: String)
        case experienceNotFound(tool: String, id: String, visibleHint: String? = nil)
        /// Prerequisite service (map view model, aiService, etc.) unavailable
        /// this turn. Always terminal — the model can't recover with different args.
        case dependencyUnavailable(tool: String, dependency: String, hint: String)
        /// Wraps an upstream error the tool couldn't recover from. Prefer
        /// specific cases above whenever possible so the outcome classifier
        /// can offer a meaningful hint.
        case underlying(tool: String, message: String)

        public var errorDescription: String? {
            switch self {
            case .unknownTool(let name):
                return "Unknown tool: \(name)"
            case .invalidArguments(let tool, let reason):
                return "Bad arguments for \(tool): \(reason)"
            case .experienceNotFound(_, let id, _):
                return "Experience not found: \(id)"
            case .dependencyUnavailable(let tool, let dependency, _):
                return "\(tool): \(dependency) unavailable"
            case .underlying(_, let message):
                return message
            }
        }
    }

    private weak var mapViewModel: MapViewModel?
    private let preferences: UserPreferences
    /// Used by `build_route` to string nearby experiences into a walk. Optional
    /// so legacy callers (and tests) that don't build routes compile unchanged;
    /// when absent, `build_route` returns a graceful error instead of crashing.
    private let aiService: AIService?
    /// Deterministic, authenticated compiler for task/time-window routes.
    /// Unlike `build_route`, this service never delegates stop order to an LLM.
    private let workdayCompiler: any WorkdayRouteCompiling

    /// Per-turn retry counter — see `ToolRetryLedger`. The orchestrator resets
    /// it at each new user turn. `internal` so tests can assert
    /// budget-exhaustion behaviour end-to-end without leaking the type
    /// through the router's public surface.
    let retryLedger = ToolRetryLedger()

    /// ③ Memory三层 slice A: per-orchestrator episode store the
    /// `recall_memory` tool searches. Populated externally (typically by
    /// `MemoryDigestService` on session end); tests can seed directly.
    let memoryStore = MemoryEpisodeStore()

    /// Side effect of the last `execute(_:)` call that the chat surface can turn
    /// into an inline card (places to show, a route to adopt). Reset to `nil` at
    /// the start of every `execute(_:)` so the orchestrator only ever reads the
    /// effect of the call it just made. This is intentionally OUT of the
    /// model-facing JSON contract — the model gets counts/ids, the UI gets cards.
    public enum ToolEffect: Equatable {
        case experiences([Experience])
        case route(RouteProposal)
        /// City OS v2: 在地 events surfaced by `find_local_events`, rendered as
        /// `ChatEventCard`s the user can tap to jump to on the map.
        case events([CityEvent])
        /// Live web-search sources surfaced by `web_search`, rendered as
        /// tappable source-link cards (Perplexity-style provenance) beneath the
        /// agent's grounded answer.
        case webSources([WebSearchResult])
    }
    public private(set) var lastEffect: ToolEffect?

    /// City OS v2 content plane — resolves `get_city_kit` / `find_local_events`.
    /// Weak so the router can't outlive the view's services; a nil service
    /// yields the standard dependency-unavailable envelope.
    private weak var cityBriefService: CityBriefService?
    /// City OS v2 visa math — `get_city_kit`'s visa numbers come from here, so
    /// the model never invents day counts.
    private weak var complianceService: ComplianceService?

    /// Live web search backing the `web_search` tool. Defaults to the shared
    /// instance; injectable so tests can stub the network.
    private let webSearchService: WebSearchService

    public convenience init(
        mapViewModel: MapViewModel,
        preferences: UserPreferences,
        aiService: AIService? = nil,
        cityBriefService: CityBriefService? = nil,
        complianceService: ComplianceService? = nil,
        webSearchService: WebSearchService? = nil
    ) {
        self.init(
            mapViewModel: mapViewModel,
            preferences: preferences,
            aiService: aiService,
            cityBriefService: cityBriefService,
            complianceService: complianceService,
            webSearchService: webSearchService,
            workdayCompiler: WorkdayRouteCompilerService()
        )
    }

    /// Internal injection seam for deterministic compiler tests.
    init(
        mapViewModel: MapViewModel,
        preferences: UserPreferences,
        aiService: AIService? = nil,
        cityBriefService: CityBriefService? = nil,
        complianceService: ComplianceService? = nil,
        webSearchService: WebSearchService? = nil,
        workdayCompiler: any WorkdayRouteCompiling
    ) {
        self.mapViewModel = mapViewModel
        self.preferences = preferences
        self.aiService = aiService
        self.workdayCompiler = workdayCompiler
        self.cityBriefService = cityBriefService
        self.complianceService = complianceService
        self.webSearchService = webSearchService ?? WebSearchService.shared
    }

    // MARK: - Tool catalog

    /// Tool defs handed to `AIService.sendAgentMessage(...)`. JSON Schemas
    /// mirror the PRD verbatim so the model gets the same contract spec'd
    /// in docs/PRD/voice-agent.md §4.
    public static let allTools: [AIService.AgentTool] = [
        .init(
            name: "explore_nearby",
            description: "Fetch real OSM POIs near a coordinate and enrich them with AI. Use when the user wants new places not in the current visible set, or moves to a new area. Returns the count of newly added experiences.",
            parametersJSON: #"""
            {
              "type": "object",
              "properties": {
                "latitude":  {"type": "number"},
                "longitude": {"type": "number"},
                "radius_meters": {"type": "integer", "minimum": 500, "maximum": 100000, "description": "Overrides the progressive starting ring when provided"},
                "categories": {"type": "array", "items": {"type": "string", "enum": ["culture","nature","food","coffee","work","wellness","nightlife","hidden"]}, "description": "Optional category filter list"},
                "solo_score_min": {"type": "number", "minimum": 0, "maximum": 10, "description": "Minimum solo-traveler score"},
                "rating_min":     {"type": "number", "minimum": 0, "maximum": 10, "description": "Minimum provider rating"},
                "ambiance_min":   {"type": "number", "minimum": 0, "maximum": 10, "description": "Minimum ambiance fit score"},
                "progressive":    {"type": "boolean", "default": true, "description": "When true, use progressive multi-ring explore (recommended)"}
              }
            }
            """#
        ),
        .init(
            name: "web_search",
            description: "Search the live web for current, real-world information you don't already know or that changes over time — opening hours, this week's events/exhibitions, recent news, prices, whether a place still exists, travel advisories. Returns real web pages (title, url, snippet) to ground your answer; cite them. Use this instead of guessing from training knowledge whenever the question is time-sensitive or asks about a specific real place/event. Do NOT use it for on-map actions (use explore_nearby / search_places for those).",
            parametersJSON: #"""
            {
              "type": "object",
              "required": ["query"],
              "properties": {
                "query": {"type": "string", "description": "The natural-language search query, e.g. 'exhibitions in Shenzhen this week' or 'Giang Cafe Hanoi opening hours'"},
                "topic": {"type": "string", "enum": ["general", "news"], "default": "general", "description": "Use 'news' for time-sensitive/recent-events queries; 'general' otherwise"},
                "days": {"type": "integer", "minimum": 1, "maximum": 30, "description": "For topic=news only: how many days back to search"}
              }
            }
            """#
        ),
        .init(
            name: "filter_by_category",
            description: "Filter visible experiences on the map to a single category. Use this whenever the user asks for a specific type of place (coffee, food, etc).",
            parametersJSON: #"""
            {
              "type": "object",
              "required": ["category"],
              "properties": {
                "category": {
                  "type": "string",
                  "enum": ["culture","nature","food","coffee","work","wellness","nightlife","hidden"]
                }
              }
            }
            """#
        ),
        .init(
            name: "show_details",
            description: "Open the full detail sheet for one experience. Use when the user asks 'tell me more about X' or refers to a specific item by its position ('the second one').",
            parametersJSON: #"""
            {
              "type": "object",
              "required": ["experience_id"],
              "properties": {
                "experience_id": {"type": "string"}
              }
            }
            """#
        ),
        .init(
            name: "save_to_favorites",
            description: "Add or remove an experience from the user's favorites. Toggle semantics — call again to un-favorite.",
            parametersJSON: #"""
            {
              "type": "object",
              "required": ["experience_id"],
              "properties": {
                "experience_id": {"type": "string"}
              }
            }
            """#
        ),
        .init(
            name: "dismiss_recommendation",
            description: "Temporarily hide one experience from the current visible set. Does NOT persist — refreshes will bring it back. Use when the user says 'not that one' or 'skip this'.",
            parametersJSON: #"""
            {
              "type": "object",
              "required": ["experience_id"],
              "properties": {
                "experience_id": {"type": "string"}
              }
            }
            """#
        ),
        .init(
            name: "search_places",
            description: "Search for a specific type or named place near a coordinate (e.g. 'ramen', '7-Eleven', 'rooftop bar'). Fetches real OSM POIs matching the query and synthesises them. Returns count of newly added experiences.",
            parametersJSON: #"""
            {
              "type": "object",
              "required": ["query"],
              "properties": {
                "query": {"type": "string", "description": "Name or category to search for, e.g. 'ramen', 'convenience store', 'rooftop bar'"},
                "latitude":  {"type": "number"},
                "longitude": {"type": "number"},
                "radius_meters": {"type": "integer", "minimum": 500, "maximum": 100000, "description": "Overrides the progressive starting ring when provided"},
                "categories": {"type": "array", "items": {"type": "string", "enum": ["culture","nature","food","coffee","work","wellness","nightlife","hidden"]}, "description": "Optional category filter list"},
                "solo_score_min": {"type": "number", "minimum": 0, "maximum": 10, "description": "Minimum solo-traveler score"},
                "rating_min":     {"type": "number", "minimum": 0, "maximum": 10, "description": "Minimum provider rating"},
                "ambiance_min":   {"type": "number", "minimum": 0, "maximum": 10, "description": "Minimum ambiance fit score"},
                "progressive":    {"type": "boolean", "default": true, "description": "When true, use progressive multi-ring explore (recommended)"}
              }
            }
            """#
        ),
        .init(
            name: "navigate_to",
            description: "Open the user's preferred map app with walking directions to an experience. Use when the user says 'take me there', 'directions', or 'navigate'.",
            parametersJSON: #"""
            {
              "type": "object",
              "required": ["experience_id"],
              "properties": {
                "experience_id": {"type": "string", "description": "ID of the experience to navigate to. Must be from CURRENT VISIBLE EXPERIENCES."}
              }
            }
            """#
        ),
        .init(
            name: "filter_visible",
            description: "Filter the currently visible experiences in place using quality dimensions — no network call. Use when the user wants to narrow the existing set by score, rating, ambiance, quietness, etc. Returns the count remaining after filtering.",
            parametersJSON: #"""
            {
              "type": "object",
              "properties": {
                "category":       {"type": "string", "enum": ["culture","nature","food","coffee","work","wellness","nightlife","hidden"]},
                "solo_score_min": {"type": "number", "minimum": 0, "maximum": 10},
                "rating_min":     {"type": "number", "minimum": 0, "maximum": 10},
                "ambiance_min":   {"type": "number", "minimum": 0, "maximum": 10},
                "quietness":      {"type": "boolean"},
                "solo_friendly":  {"type": "boolean"},
                "price_max":      {"type": "number", "minimum": 1, "maximum": 4}
              }
            }
            """#
        ),
        .init(
            name: "expand_radius",
            description: "Advance the explore ring by one step outward from the last explore center (5 km → 10 km → 25 km → 100 km). Use when the user says 'show more', 'expand', or 'widen the search'. No-op if already at 100 km.",
            parametersJSON: #"""
            {
              "type": "object",
              "properties": {}
            }
            """#
        ),
        .init(
            name: "build_route",
            description: "String the user's nearby places into ONE walkable route, ordered into a sensible walk with a title, summary, and a 'why now' line that reflects the current time, weather, and which places the user has or hasn't visited. Use when the user asks you to plan a walk, build a route, or 'string these together'. Returns a proposed route as an inline card the user can adopt — it is NOT saved until the user taps adopt. Prefer experience_ids from CURRENT VISIBLE EXPERIENCES; omit them to let the system pick the best nearby stops.",
            parametersJSON: #"""
            {
              "type": "object",
              "properties": {
                "experience_ids": {"type": "array", "items": {"type": "string"}, "description": "Optional preferred stop ids (from CURRENT VISIBLE EXPERIENCES) to prioritise. When omitted, the system chooses the best nearby stops."}
              }
            }
            """#
        ),
        .init(
            name: "compile_workday_route",
            description: "Compile an evidence-backed work block or workday with exact local time windows, deterministic walking/cycling/driving time, hard workability constraints, and a per-task fallback. Use for requests such as deep work → lunch → video call, or whenever opening hours / Wi-Fi / quietness / outlets must be treated as constraints. The compiler only uses CURRENT VISIBLE EXPERIENCES; call explore_nearby or search_places first when coverage is thin. Never silently relax a hard constraint. Returns an adoptable route card and does not save until the user taps Open.",
            parametersJSON: #"""
            {
              "type": "object",
              "required": ["start_minute", "end_minute", "tasks"],
              "properties": {
                "local_date": {"type": "string", "pattern": "^\\d{4}-\\d{2}-\\d{2}$", "description": "Local calendar date. Omit for today."},
                "start_minute": {"type": "integer", "minimum": 0, "maximum": 1439, "description": "Minutes after local midnight."},
                "end_minute": {"type": "integer", "minimum": 1, "maximum": 1440},
                "radius_meters": {"type": "integer", "minimum": 100, "maximum": 10000, "default": 3000},
                "mode": {"type": "string", "enum": ["pedestrian", "bicycle", "auto"], "default": "pedestrian"},
                "max_travel_minutes": {"type": "integer", "minimum": 1, "maximum": 600},
                "max_wait_minutes": {"type": "integer", "minimum": 0, "maximum": 600},
                "fallback_max_extra_travel_minutes": {"type": "integer", "minimum": 0, "maximum": 60, "default": 10},
                "allow_unknown_spend": {"type": "boolean", "default": false},
                "allow_unknown_opening_hours": {"type": "boolean", "default": false},
                "budget": {
                  "type": "object",
                  "required": ["max_amount", "currency"],
                  "properties": {
                    "max_amount": {"type": "number", "minimum": 0},
                    "currency": {"type": "string", "pattern": "^[A-Za-z]{3}$"}
                  }
                },
                "tasks": {
                  "type": "array",
                  "minItems": 1,
                  "maxItems": 6,
                  "items": {
                    "type": "object",
                    "required": ["id", "kind", "duration_minutes"],
                    "properties": {
                      "id": {"type": "string", "maxLength": 60},
                      "kind": {"type": "string", "enum": ["deep_work", "video_call", "meal", "explore", "break", "custom"]},
                      "duration_minutes": {"type": "integer", "minimum": 10, "maximum": 480},
                      "earliest_start_minute": {"type": "integer", "minimum": 0, "maximum": 1439},
                      "latest_end_minute": {"type": "integer", "minimum": 1, "maximum": 1440},
                      "opening_requirement": {"type": "string", "enum": ["known_open", "allow_unknown", "ignore"], "default": "known_open"},
                      "constraints": {
                        "type": "array",
                        "maxItems": 12,
                        "items": {
                          "type": "object",
                          "required": ["feature_key", "operator"],
                          "properties": {
                            "feature_key": {"type": "string", "enum": ["work.wifi_reliability", "work.wifi_speed_mbps", "work.noise_level", "work.power_outlets", "work.seat_availability", "work.video_call_fit", "work.long_stay_policy", "work.minimum_spend"]},
                            "operator": {"type": "string", "enum": ["eq", "gte", "lte", "in", "contains", "truthy"]},
                            "expected": {"description": "Scalar or homogeneous string/number array used by the operator."},
                            "hard": {"type": "boolean", "default": true},
                            "acceptable_statuses": {"type": "array", "items": {"type": "string", "enum": ["resolved", "stale", "conflicted", "unknown"]}},
                            "minimum_confidence": {"type": "number", "minimum": 0, "maximum": 1, "default": 0.6}
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
            """#
        ),

        // MARK: - P2.1 additions (#210 – #216) + P3.5 (#352)
        // Seven new tools introduced in Phase 2/3. Each is RAG-anchored:
        // when the tool needs to point at a place, it must return an id
        // from CURRENT VISIBLE EXPERIENCES or from a prior explore/search
        // result. The system prompt already carries that rule so the
        // per-tool descriptions just reference it here.

        .init(
            name: "suggest_now_action",
            description: "Given the user's current location and time-of-day, pick ONE visible experience that fits this exact moment (open now, matches their taste, hasn't been visited recently) and return it as a card with a one-sentence hook plus a small 'on-the-way' hint. RAG-anchored — never invent a POI, only use ids from CURRENT VISIBLE EXPERIENCES. (#210)",
            parametersJSON: #"""
            {
              "type": "object",
              "properties": {
                "reason_hint": {"type": "string", "description": "Optional freeform user cue ('need to sit', 'want coffee', 'nothing planned')"}
              }
            }
            """#
        ),
        .init(
            name: "open_blindbox",
            description: "Launch a blindbox trip — the app picks 3–5 anchor experiences the user hasn't seen and reveals them one at a time as they walk. Free tier: $1.99 IAP per launch (com.solocompass.consumable.blindbox.single); Pro: 5 launches per month free. Only call when the user explicitly asks for a surprise / random trip. (#211)",
            parametersJSON: #"""
            {
              "type": "object",
              "properties": {
                "duration_hours": {"type": "number", "minimum": 0.5, "maximum": 12, "default": 3, "description": "How long the blindbox trip should last"}
              }
            }
            """#
        ),
        .init(
            name: "bury_capsule",
            description: "Save a time capsule anchored to an experience — text / voice / photo payload that surfaces on a chosen future date (3, 6, or 12 months out). Use when the user wants to 'leave a note for future me' at a specific place. (#212)",
            parametersJSON: #"""
            {
              "type": "object",
              "required": ["experience_id", "content_type", "months_from_now"],
              "properties": {
                "experience_id":   {"type": "string", "description": "id from CURRENT VISIBLE EXPERIENCES"},
                "content_type":    {"type": "string", "enum": ["text","voice","photo"]},
                "content_preview": {"type": "string", "description": "Short human-readable preview (≤80 chars). Not the payload — that is captured by the compose UI."},
                "months_from_now": {"type": "integer", "minimum": 1, "maximum": 24, "default": 12}
              }
            }
            """#
        ),
        .init(
            name: "recall_pattern",
            description: "Summarise the user's own visit pattern for a period — top categories, dominant cities, standout moments. Reads on-device VisitRecord history only. Use when the user asks 'what have I been doing lately' / 'what's my month been like'. (#213)",
            parametersJSON: #"""
            {
              "type": "object",
              "properties": {
                "period": {"type": "string", "enum": ["week","month","quarter","year"], "default": "month"}
              }
            }
            """#
        ),
        .init(
            name: "sos_plan",
            description: "Generate a 4-hour alternate route when the user's original plan fell through ('it's raining', 'the temple is closed', 'friend cancelled'). Pro users: 3 free per month. Free tier: $2.99 IAP per invocation (com.solocompass.consumable.sos.single). Returns a card with 3 anchor stops + weather-appropriate reasoning. (#214)",
            parametersJSON: #"""
            {
              "type": "object",
              "properties": {
                "trigger":        {"type": "string", "description": "What broke — e.g. 'rain', 'closed', 'cancelled'"},
                "duration_hours": {"type": "number", "minimum": 1, "maximum": 8, "default": 4}
              }
            }
            """#
        ),
        .init(
            name: "unwalked_path",
            description: "Counterfactual walk — 'what would the OTHER version of today have looked like' given the user's actual visits. Single-purchase $4.99 IAP (com.solocompass.consumable.unwalked.single). Trigger only when the user asks retrospectively about a specific day. Emits a route card and a short essay tying it back to their taste profile. (#215)",
            parametersJSON: #"""
            {
              "type": "object",
              "required": ["date"],
              "properties": {
                "date": {"type": "string", "format": "date", "description": "ISO date (YYYY-MM-DD) of the day to reflect on"}
              }
            }
            """#
        ),
        .init(
            name: "recall_local_scene",
            description: "Surface community / subculture context for the current city — running clubs, book stores hosting events, weekly life-drawing, etc. Pro-only feature (no per-call IAP). Reads local scene fixtures + optional Eventbrite / Meetup enrichment when configured. (#352)",
            parametersJSON: #"""
            {
              "type": "object",
              "properties": {
                "topic": {"type": "string", "description": "Optional user cue — 'live music', 'books', 'runners', 'queer nightlife'"}
              }
            }
            """#
        ),

        // ③ Memory三层 slice A: explicit long-term recall.
        // The model reaches for this when the user says "the last time…",
        // "that place I liked…", "what did we try before…" — anything that
        // references prior sessions. Kept out of the always-injected memory
        // block so cold-start tokens stay lean.
        .init(
            name: "recall_memory",
            description: "Search the user's past sessions for episodes matching a natural-language query (place, mood, decision). Use ONLY when the user explicitly references prior context ('remember that cafe', '上次在深圳', 'what did we do yesterday'). Returns up to `limit` episodes ranked by relevance.",
            parametersJSON: #"""
            {
              "type": "object",
              "required": ["query"],
              "properties": {
                "query": {"type": "string", "description": "Natural-language search phrase. Use the user's own words when possible."},
                "city_code": {"type": "string", "description": "Optional current city code to constrain recall to episodes anchored there or global."},
                "limit": {"type": "integer", "minimum": 1, "maximum": 5, "default": 3}
              }
            }
            """#
        ),

        // City OS v2 (PRD solo-city-os-v2 §5.2–5.3): the landing kit + local
        // events for the current city. Content is city-shared and pre-compiled
        // server-side; these tools READ it and return compact facts — the model
        // never invents kit copy, visa numbers, or events.
        .init(
            name: "get_city_kit",
            description: "Return the 落地包 landing-kit essentials for the current city — connectivity (net), money, visa/tax, and safety. Use when the user asks how to get online, get cash, visa rules, days left, emergency numbers, or 'what do I need to know landing here'. Visa day counts come from the user's own stored entry date; if none is set, the visa numbers are omitted and you should tell them to set their entry date in the 落地包.",
            parametersJSON: #"""
            {
              "type": "object",
              "properties": {
                "city_code": {"type": "string", "description": "Optional; defaults to the current map city."},
                "kinds": {"type": "array", "items": {"type": "string", "enum": ["net","money","visa","safety"]}, "description": "Optional subset of kit sections to return; omit for all four."}
              }
            }
            """#
        ),
        .init(
            name: "find_local_events",
            description: "Find 在地 local happenings this week for the current city — festivals, markets, and travel notices — each with a solo-friendliness score and a one-line 'is it good to go alone' note. Use when the user asks what's on, what to do this weekend, or wants something happening nearby. Results appear as tappable cards the user can jump to on the map. Notices (road closures, strikes) are included but have no solo score.",
            parametersJSON: #"""
            {
              "type": "object",
              "properties": {
                "city_code": {"type": "string", "description": "Optional; defaults to the current map city."},
                "within_days": {"type": "integer", "minimum": 1, "maximum": 30, "default": 7, "description": "Only include events starting within this many days."},
                "solo_score_min": {"type": "number", "minimum": 0, "maximum": 10, "description": "Optional minimum solo-friendliness score (notices are always kept)."},
                "query": {"type": "string", "description": "Optional keyword matched against event names/notes. Content is often local-language, so omit this for broad questions like 'what's on this weekend' — the time window already handles those. If nothing matches the keyword, the full week's list is returned with query_relaxed=true."}
              }
            }
            """#
        ),
    ]

    // MARK: - Execution

    /// Route one DeepSeek `tool_call` to the matching app action. Returns
    /// a JSON string that the orchestrator feeds back as the `tool` row
    /// content. Failures are represented as `{"ok":false,"error":"…"}`
    /// rather than thrown so the agent can recover via the model.
    public func execute(_ call: VoiceAgentSession.ToolCall) async -> String {
        // Only the effect of THIS call should be visible to the orchestrator.
        lastEffect = nil
        do {
            switch call.name {
            case "explore_nearby":
                return try await executeExploreNearby(args: call.argumentsJSON)
            case "build_route":
                return try await executeBuildRoute(args: call.argumentsJSON)
            case "compile_workday_route":
                return try await executeCompileWorkdayRoute(args: call.argumentsJSON)
            case "filter_by_category":
                return try executeFilterByCategory(args: call.argumentsJSON)
            case "show_details":
                return try executeShowDetails(args: call.argumentsJSON)
            case "save_to_favorites":
                return try executeSaveToFavorites(args: call.argumentsJSON)
            case "dismiss_recommendation":
                return try executeDismissRecommendation(args: call.argumentsJSON)
            case "search_places":
                return try await executeSearchPlaces(args: call.argumentsJSON)
            case "web_search":
                return try await executeWebSearch(args: call.argumentsJSON)
            case "navigate_to":
                return try executeNavigateTo(args: call.argumentsJSON)
            case "filter_visible":
                return try executeFilterVisible(args: call.argumentsJSON)
            case "expand_radius":
                return await executeExpandRadius()

            // P2.1 additions (#210 – #216) + P3.5 (#352). Each returns a
            // JSON envelope; see the corresponding `execute…` handler for
            // the exact payload shape.
            case "suggest_now_action":
                return try executeSuggestNowAction(args: call.argumentsJSON)
            case "open_blindbox":
                return try executeOpenBlindbox(args: call.argumentsJSON)
            case "bury_capsule":
                return try executeBuryCapsule(args: call.argumentsJSON)
            case "recall_pattern":
                return try executeRecallPattern(args: call.argumentsJSON)
            case "sos_plan":
                return try executeSOSPlan(args: call.argumentsJSON)
            case "unwalked_path":
                return try executeUnwalkedPath(args: call.argumentsJSON)
            case "recall_local_scene":
                return try executeRecallLocalScene(args: call.argumentsJSON)
            case "recall_memory":
                return try executeRecallMemory(args: call.argumentsJSON)

            // City OS v2 kit / events.
            case "get_city_kit":
                return try await executeGetCityKit(args: call.argumentsJSON)
            case "find_local_events":
                return try await executeFindLocalEvents(args: call.argumentsJSON)

            default:
                throw RouterError.unknownTool(call.name)
            }
        } catch {
            return errorJSON(error)
        }
    }

    // MARK: - Per-tool handlers

    private struct ExploreNearbyArgs: Decodable, QualityArgsProvider {
        let latitude: Double?
        let longitude: Double?
        let radius_meters: Int?
        let categories: [String]?
        let solo_score_min: Double?
        let rating_min: Double?
        let ambiance_min: Double?
        let progressive: Bool?
    }

    private func executeExploreNearby(args: String) async throws -> String {
        let parsed: ExploreNearbyArgs = try Self.decode(args, tool: "explore_nearby")
        let vm = try requireMapVM(tool: "explore_nearby")
        let coord = CLLocationCoordinate2D(
            latitude: parsed.latitude ?? MapViewModel.defaultCenter.latitude,
            longitude: parsed.longitude ?? MapViewModel.defaultCenter.longitude
        )
        let useProgressive = parsed.progressive ?? true
        // Explicit radius_meters overrides the progressive starting ring.
        let radius = parsed.radius_meters ?? 3000
        let category = parsed.categories?.compactMap(ExperienceCategory.init(rawValue:)).first
        // Snapshot the visible set so we can diff which places this explore added
        // and surface them as inline chat cards (the agent no longer jumps the map).
        let before = Set(vm.visibleExperiences.map(\.id))
        if useProgressive {
            await vm.exploreProgressively(
                at: coord,
                startingRadiusMeters: parsed.radius_meters,
                category: category,
                filter: Self.buildFilter(from: parsed)
            )
        } else {
            await vm.exploreNearby(at: coord, radiusMeters: radius, category: category)
        }
        // If the first ring came up empty, don't surrender — widen the search
        // automatically (the agent should compile the wider surroundings rather
        // than reply "found nothing"). Only meaningful on the progressive path,
        // which owns the ring ladder.
        var stagesExpanded = 0
        var ladderExhausted = false
        if useProgressive {
            let outcome = await autoExpandUntilResults(vm: vm)
            stagesExpanded = outcome.stagesExpanded
            ladderExhausted = outcome.exhausted
        }
        // Re-diff against the original snapshot so cards reflect everything the
        // auto-expansion surfaced, not just the (empty) first ring.
        recordAddedEffect(before: before, vm: vm)
        return Self.successJSON([
            "added_count": vm.lastExploreAddedCount,
            "radius_meters": radius,
            "progressive": useProgressive,
            "auto_expanded_stages": stagesExpanded,
            "search_exhausted": ladderExhausted,
        ])
    }

    /// Diff the visible set against a pre-call snapshot and record the newly
    /// added experiences as a `.experiences` effect (capped to a sane card rail
    /// length). No-op when nothing new arrived, so a refresh-that-found-nothing
    /// doesn't spawn an empty card.
    private func recordAddedEffect(before: Set<String>, vm: MapViewModel) {
        let added = vm.visibleExperiences.filter { !before.contains($0.id) }
        guard !added.isEmpty else { return }
        lastEffect = .experiences(Array(added.prefix(Self.maxCardExperiences)))
    }

    /// Max places surfaced as cards from a single explore/search so the chat
    /// rail stays scannable rather than dumping 30 cards.
    private static let maxCardExperiences = 6

    /// Hard ceiling on automatic radius expansions per explore/search call so a
    /// genuinely empty area can't loop forever. The ring ladder tops out at
    /// 100 km in a handful of stages, so this comfortably covers the full ladder.
    private static let maxAutoExpandStages = 6

    /// When the initial explore/search found nothing new, keep widening the
    /// search ring (5 → 10 → 25 → 100 km) automatically until SOMETHING new
    /// turns up or the ladder is exhausted — so the agent compiles the
    /// surrounding area on its own instead of giving up and going silent.
    ///
    /// Returns how many stages it expanded (0 when the first ring already had
    /// results) and whether the ladder was exhausted, for the tool reply so the
    /// agent can tell the user how far it had to look.
    private func autoExpandUntilResults(vm: MapViewModel) async -> (stagesExpanded: Int, exhausted: Bool) {
        var stages = 0
        while vm.lastExploreAddedCount == 0, stages < Self.maxAutoExpandStages {
            // nil = a wider ring was launched; non-nil reason = already at max.
            if await vm.expandOneStage() != nil {
                return (stages, true)
            }
            stages += 1
        }
        return (stages, false)
    }

    private struct FilterByCategoryArgs: Decodable {
        let category: String
    }

    private func executeFilterByCategory(args: String) throws -> String {
        let parsed: FilterByCategoryArgs = try Self.decode(args, tool: "filter_by_category")
        guard let category = ExperienceCategory(rawValue: parsed.category) else {
            throw RouterError.invalidArguments(
                tool: "filter_by_category",
                reason: "unknown category '\(parsed.category)'"
            )
        }
        let vm = try requireMapVM(tool: "filter_by_category")
        vm.selectCategory(category)
        return Self.successJSON([
            "category": category.rawValue,
            "visible_count": vm.visibleExperiences.count,
        ])
    }

    private struct ExperienceIDArgs: Decodable {
        let experience_id: String
    }

    private func executeShowDetails(args: String) throws -> String {
        let parsed: ExperienceIDArgs = try Self.decode(args, tool: "show_details")
        let vm = try requireMapVM(tool: "show_details")
        // PRD: AI must only reference experience_ids it saw in the
        // VISIBLE_EXPERIENCES injection. We hard-fail unknown ids so
        // hallucinated ones round-trip back to the model as
        // `unknown_experience_id` and it can self-correct.
        guard let exp = vm.visibleExperiences.first(where: { $0.id == parsed.experience_id }) else {
            throw RouterError.experienceNotFound(
                tool: "show_details",
                id: parsed.experience_id,
                visibleHint: visibleIDHint(from: vm)
            )
        }
        // 不再自动跳转 / 弹详情打断用户 — surface the place as an inline chat card
        // instead. The user taps the card to reveal it on the map (or open its
        // detail). The agent presenting a place must never seize the map context.
        lastEffect = .experiences([exp])
        return Self.successJSON(["experience_id": exp.id, "title": exp.title])
    }

    private func executeSaveToFavorites(args: String) throws -> String {
        let parsed: ExperienceIDArgs = try Self.decode(args, tool: "save_to_favorites")
        let wasFavorited = preferences.isFavorited(parsed.experience_id)
        preferences.toggleFavorite(parsed.experience_id)
        return Self.successJSON([
            "experience_id": parsed.experience_id,
            "now_favorited": !wasFavorited,
        ])
    }

    private func executeDismissRecommendation(args: String) throws -> String {
        let parsed: ExperienceIDArgs = try Self.decode(args, tool: "dismiss_recommendation")
        let vm = try requireMapVM(tool: "dismiss_recommendation")
        vm.dismissFromVisible(parsed.experience_id)
        return Self.successJSON([
            "experience_id": parsed.experience_id,
            "visible_count": vm.visibleExperiences.count,
        ])
    }

    private struct SearchPlacesArgs: Decodable, QualityArgsProvider {
        let query: String
        let latitude: Double?
        let longitude: Double?
        let radius_meters: Int?
        let categories: [String]?
        let solo_score_min: Double?
        let rating_min: Double?
        let ambiance_min: Double?
        let progressive: Bool?
    }

    private func executeSearchPlaces(args: String) async throws -> String {
        let parsed: SearchPlacesArgs = try Self.decode(args, tool: "search_places")
        let vm = try requireMapVM(tool: "search_places")
        let coord = CLLocationCoordinate2D(
            latitude: parsed.latitude ?? MapViewModel.defaultCenter.latitude,
            longitude: parsed.longitude ?? MapViewModel.defaultCenter.longitude
        )
        let useProgressive = parsed.progressive ?? true
        let radius = parsed.radius_meters ?? 2000
        let category = parsed.categories?.compactMap(ExperienceCategory.init(rawValue:)).first
        let before = Set(vm.visibleExperiences.map(\.id))
        if useProgressive {
            await vm.exploreProgressively(
                at: coord,
                startingRadiusMeters: parsed.radius_meters,
                category: category,
                filter: Self.buildFilter(from: parsed)
            )
        } else {
            await vm.exploreNearby(at: coord, radiusMeters: radius, category: category)
        }
        // Same auto-widen behavior as explore_nearby: a query that found nothing
        // in the first ring keeps expanding instead of returning an empty result
        // and stalling the agent.
        var stagesExpanded = 0
        var ladderExhausted = false
        if useProgressive {
            let outcome = await autoExpandUntilResults(vm: vm)
            stagesExpanded = outcome.stagesExpanded
            ladderExhausted = outcome.exhausted
        }
        recordAddedEffect(before: before, vm: vm)
        return Self.successJSON([
            "query": parsed.query,
            "added_count": vm.lastExploreAddedCount,
            "radius_meters": radius,
            "progressive": useProgressive,
            "auto_expanded_stages": stagesExpanded,
            "search_exhausted": ladderExhausted,
        ])
    }

    // MARK: - web_search (live web search via Tavily)

    private struct WebSearchArgs: Decodable {
        let query: String
        let topic: String?
        let days: Int?
    }

    /// Run a live web search and hand the model back real pages to ground its
    /// answer. The result envelope includes the snippets (so the model can cite
    /// them) and sets `lastEffect = .webSources` (so the UI can render tappable
    /// source cards). Best-effort: an empty result set is a valid, non-error
    /// outcome — the model then answers from its own knowledge and says so.
    private func executeWebSearch(args: String) async throws -> String {
        let parsed: WebSearchArgs = try Self.decode(args, tool: "web_search")
        let query = parsed.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw RouterError.invalidArguments(tool: "web_search", reason: "query must not be empty")
        }

        let topic: WebSearchService.Topic = (parsed.topic == "news") ? .news : .general
        let results = await webSearchService.search(query: query, topic: topic, days: parsed.days)

        // Surface source cards to the UI only when the search actually returned
        // pages — an empty result leaves the chat clean.
        if !results.isEmpty {
            lastEffect = .webSources(results)
        }

        // Model-facing envelope: the snippets are what it summarizes. Keep it
        // compact — title, url, and the bounded content per source.
        let sources: [[String: Any]] = results.map { r in
            ["title": r.title, "url": r.url, "content": r.content]
        }
        return Self.successJSON([
            "query": query,
            "result_count": results.count,
            "sources": sources,
        ])
    }

    // MARK: - build_route (conversational route creation)

    private struct BuildRouteArgs: Decodable {
        let experience_ids: [String]?
    }

    private struct CompileWorkdayConstraintArgs: Decodable {
        let feature_key: String
        let `operator`: String
        let expected: WorkdayConstraintValue?
        let hard: Bool?
        let acceptable_statuses: [String]?
        let minimum_confidence: Double?
    }

    private struct CompileWorkdayTaskArgs: Decodable {
        let id: String
        let kind: String
        let duration_minutes: Int
        let earliest_start_minute: Int?
        let latest_end_minute: Int?
        let opening_requirement: String?
        let constraints: [CompileWorkdayConstraintArgs]?
    }

    private struct CompileWorkdayBudgetArgs: Decodable {
        let max_amount: Double
        let currency: String
    }

    private struct CompileWorkdayArgs: Decodable {
        let local_date: String?
        let start_minute: Int
        let end_minute: Int
        let radius_meters: Int?
        let mode: String?
        let max_travel_minutes: Int?
        let max_wait_minutes: Int?
        let fallback_max_extra_travel_minutes: Int?
        let allow_unknown_spend: Bool?
        let allow_unknown_opening_hours: Bool?
        let budget: CompileWorkdayBudgetArgs?
        let tasks: [CompileWorkdayTaskArgs]
    }

    private struct CompiledRouteToolPayload: Encodable {
        let route_title: String
        let stop_count: Int
        let estimated_minutes: Int
        let fallback_count: Int
        let evidence_coverage: String
        let cache: String
        let refresh_scheduled: Bool
    }

    private struct UnsatisfiableRouteToolPayload: Encodable {
        let failed_task_id: String
        let rejections: [WorkdayRouteRejection]
    }

    /// String nearby experiences into one walkable route and surface it as an
    /// adoptable chat card (NOT saved). `generateRoute` deterministically picks
    /// and orders grounded candidates; the LLM can only edit route copy. When
    /// `experience_ids` are given, they're prioritised as the candidate pool;
    /// otherwise the whole visible set is the pool.
    private func executeBuildRoute(args: String) async throws -> String {
        let parsed: BuildRouteArgs = try Self.decode(args, tool: "build_route")
        let vm = try requireMapVM(tool: "build_route")
        guard let ai = aiService else {
            throw RouterError.dependencyUnavailable(tool: "build_route", dependency: "aiService", hint: "Route building is not wired in this session. Suggest visible places one at a time instead.")
        }

        // Build the candidate pool: preferred ids first (when valid), else the
        // full visible set. The route generator picks/orders the final stops.
        let visible = vm.visibleExperiences
        let candidates: [Experience]
        if let preferred = parsed.experience_ids, !preferred.isEmpty {
            let preferredSet = Set(preferred)
            let picked = visible.filter { preferredSet.contains($0.id) }
            // Fall back to the full set if none of the preferred ids were visible
            // (model hallucinated ids) so we still produce a route.
            candidates = picked.count >= 2 ? picked : visible
        } else {
            candidates = visible
        }
        guard candidates.count >= 2 else {
            throw RouterError.invalidArguments(
                tool: "build_route",
                reason: "need at least 2 nearby places to build a route"
            )
        }

        let cityCode = vm.selectedCity ?? candidates.first?.location.cityCode ?? "osm"
        let route = try await ai.generateRoute(
            from: candidates,
            cityCode: cityCode,
            userCoordinate: vm.exploreAnchorCoordinate
        )
        // Resolve stops in walk order so the card can render names without a lookup.
        let byId = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        let stops = route.experienceIds.compactMap { byId[$0] }
        let proposal = RouteProposal(route: route, stops: stops)
        lastEffect = .route(proposal)
        return Self.successJSON([
            "route_title": route.title,
            "stop_count": stops.count,
            "estimated_minutes": route.estimatedDuration,
        ])
    }

    /// Compile a task-shaped work block against server-side evidence and a real
    /// travel matrix. All current visible ids are passed as explicit candidate
    /// pools so the returned route stays RAG-grounded and fully renderable.
    private func executeCompileWorkdayRoute(args: String) async throws -> String {
        let parsed: CompileWorkdayArgs = try Self.decode(args, tool: "compile_workday_route")
        let vm = try requireMapVM(tool: "compile_workday_route")

        guard parsed.start_minute >= 0,
              parsed.start_minute < parsed.end_minute,
              parsed.end_minute <= 1440 else {
            throw RouterError.invalidArguments(
                tool: "compile_workday_route",
                reason: "start_minute must be before end_minute within one local day"
            )
        }
        guard (1...6).contains(parsed.tasks.count) else {
            throw RouterError.invalidArguments(
                tool: "compile_workday_route",
                reason: "tasks must contain 1 through 6 items"
            )
        }
        let taskIds = parsed.tasks.map(\.id)
        guard Set(taskIds).count == taskIds.count, taskIds.allSatisfy({ !$0.isEmpty }) else {
            throw RouterError.invalidArguments(
                tool: "compile_workday_route",
                reason: "task ids must be non-empty and unique"
            )
        }
        let validTaskKinds: Set<String> = [
            "deep_work", "video_call", "meal", "explore", "break", "custom",
        ]
        let validModes: Set<String> = ["pedestrian", "bicycle", "auto"]
        let selectedMode = parsed.mode ?? "pedestrian"
        guard validModes.contains(selectedMode) else {
            throw RouterError.invalidArguments(
                tool: "compile_workday_route",
                reason: "mode must be pedestrian, bicycle, or auto"
            )
        }
        guard parsed.tasks.allSatisfy({
            validTaskKinds.contains($0.kind)
                && (10...480).contains($0.duration_minutes)
                && ($0.earliest_start_minute.map { (0...1439).contains($0) } ?? true)
                && ($0.latest_end_minute.map { (1...1440).contains($0) } ?? true)
        }) else {
            throw RouterError.invalidArguments(
                tool: "compile_workday_route",
                reason: "each task needs a supported kind, 10–480 minute duration, and valid local-day windows"
            )
        }
        if let budget = parsed.budget {
            guard budget.max_amount >= 0,
                  budget.currency.range(of: #"^[A-Za-z]{3}$"#, options: .regularExpression) != nil else {
                throw RouterError.invalidArguments(
                    tool: "compile_workday_route",
                    reason: "budget needs a non-negative max_amount and a three-letter currency"
                )
            }
        }

        let visible = vm.visibleExperiences.filter { $0.coordinate != nil }
        guard !visible.isEmpty else {
            throw RouterError.invalidArguments(
                tool: "compile_workday_route",
                reason: "no visible places with coordinates; call explore_nearby first"
            )
        }
        let visibleIds = visible.map(\.id)
        let date = parsed.local_date ?? Self.localDateString(Date())
        guard Self.isValidLocalDateString(date) else {
            throw RouterError.invalidArguments(
                tool: "compile_workday_route",
                reason: "local_date must be a real YYYY-MM-DD calendar date"
            )
        }
        let anchor = vm.exploreAnchorCoordinate
        let cityCode = vm.selectedCity ?? visible.first?.location.cityCode ?? "osm"
        let taskInputs = parsed.tasks.map { task in
            WorkdayRouteTaskInput(
                id: task.id,
                kind: task.kind,
                durationMinutes: task.duration_minutes,
                earliestStartMinute: task.earliest_start_minute,
                latestEndMinute: task.latest_end_minute,
                candidateIds: visibleIds,
                constraints: task.constraints?.map {
                    WorkdayFeatureConstraint(
                        featureKey: $0.feature_key,
                        operator: $0.operator,
                        expected: $0.expected,
                        hard: $0.hard,
                        acceptableStatuses: $0.acceptable_statuses,
                        minimumConfidence: $0.minimum_confidence
                    )
                },
                openingRequirement: task.opening_requirement
            )
        }
        let input = WorkdayRouteCompileInput(
            origin: [anchor.longitude, anchor.latitude],
            radiusMeters: max(100, min(10_000, parsed.radius_meters ?? 3_000)),
            localDate: date,
            mode: selectedMode,
            intent: WorkdayPlanIntentInput(
                startMinute: parsed.start_minute,
                endMinute: parsed.end_minute,
                tasks: taskInputs,
                maxTravelMinutes: parsed.max_travel_minutes,
                maxWaitMinutes: parsed.max_wait_minutes,
                budget: parsed.budget.map {
                    WorkdayBudgetInput(
                        maxAmount: $0.max_amount,
                        currency: $0.currency.uppercased()
                    )
                },
                allowUnknownSpend: parsed.allow_unknown_spend,
                allowUnknownOpeningHours: parsed.allow_unknown_opening_hours,
                fallbackMaxExtraTravelMinutes: parsed.fallback_max_extra_travel_minutes ?? 10
            )
        )

        let result: WorkdayRouteCompilation
        do {
            result = try await workdayCompiler.compile(
                input: input,
                candidates: visible,
                cityCode: cityCode
            )
        } catch let error as WorkdayRouteCompilerService.CompilerError {
            switch error {
            case .unconfigured:
                throw RouterError.dependencyUnavailable(
                    tool: "compile_workday_route",
                    dependency: "route compiler",
                    hint: "The authenticated route compiler is not configured on this build. Do not invent a timed plan; offer build_route for an unconstrained walk instead."
                )
            case .rejected(let status, let message) where status == 400 || status == 202:
                throw RouterError.invalidArguments(
                    tool: "compile_workday_route",
                    reason: message
                )
            default:
                throw RouterError.underlying(
                    tool: "compile_workday_route",
                    message: error.localizedDescription
                )
            }
        }

        switch result {
        case .solved(let route):
            let byId = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })
            let stops = route.experienceIds.compactMap { byId[$0] }
            guard stops.count == route.experienceIds.count, let plan = route.compiledPlan else {
                throw RouterError.underlying(
                    tool: "compile_workday_route",
                    message: "compiler returned a route that cannot be rendered from visible evidence"
                )
            }
            lastEffect = .route(RouteProposal(route: route, stops: stops))
            let payload = CompiledRouteToolPayload(
                route_title: route.title,
                stop_count: stops.count,
                estimated_minutes: route.estimatedDuration,
                fallback_count: plan.fallbacks.count,
                evidence_coverage: plan.evidenceCoverage,
                cache: plan.cacheStatus,
                refresh_scheduled: plan.refreshScheduled
            )
            let outcome: ToolOutcome<CompiledRouteToolPayload> = .ok(
                payload: payload,
                hint: "The card contains the authoritative schedule and fallbacks. Explain it briefly; do not rewrite its times or claim partial evidence is fresh."
            )
            return outcome.encodeForModel()

        case .unsatisfiable(let failedTaskId, let rejections):
            let payload = UnsatisfiableRouteToolPayload(
                failed_task_id: failedTaskId,
                rejections: rejections
            )
            let codes = rejections.map(\.code).joined(separator: ", ")
            let outcome: ToolOutcome<UnsatisfiableRouteToolPayload> = .retryable(
                reason: .notEnoughContext,
                hint: "No route satisfies task '\(failedTaskId)' (\(codes)). Keep hard constraints intact. Explore for more candidates once, or ask the user which time window / constraint they want to relax; never relax it silently.",
                partial: payload
            )
            return outcome.encodeForModel()
        }
    }

    private static func localDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func isValidLocalDateString(_ value: String) -> Bool {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }

    private func executeNavigateTo(args: String) throws -> String {
        let parsed: ExperienceIDArgs = try Self.decode(args, tool: "navigate_to")
        let vm = try requireMapVM(tool: "navigate_to")
        guard let exp = vm.visibleExperiences.first(where: { $0.id == parsed.experience_id }) else {
            throw RouterError.experienceNotFound(
                tool: "navigate_to",
                id: parsed.experience_id,
                visibleHint: visibleIDHint(from: vm)
            )
        }
        guard let coord = exp.coordinate else {
            throw RouterError.underlying(tool: "navigate_to", message: "The chosen experience has no coordinate — cannot open a map link.")
        }
        // Open Apple Maps by default — NavigationLauncher picks the best available app.
        NavigationLauncher.open(app: .appleMaps, coordinate: coord, name: exp.title)
        return Self.successJSON(["experience_id": exp.id, "title": exp.title])
    }

    // MARK: - filter_visible (US-020)

    private struct FilterVisibleArgs: Decodable {
        let category: String?
        let solo_score_min: Double?
        let rating_min: Double?
        let ambiance_min: Double?
        let quietness: Bool?
        let solo_friendly: Bool?
        let price_max: Double?
    }

    private func executeFilterVisible(args: String) throws -> String {
        let parsed: FilterVisibleArgs = try Self.decode(args, tool: "filter_visible")
        let vm = try requireMapVM(tool: "filter_visible")
        let filter = ExperienceFilter(
            category: parsed.category,
            soloScoreMin: parsed.solo_score_min,
            ratingMin: parsed.rating_min,
            ambianceMin: parsed.ambiance_min,
            quietness: parsed.quietness ?? false,
            soloFriendly: parsed.solo_friendly ?? false,
            priceMax: parsed.price_max
        )
        let remaining = vm.applyQualityFilter(filter)
        return Self.successJSON([
            "remaining_count": remaining,
        ])
    }

    // MARK: - expand_radius (US-021)

    private func executeExpandRadius() async -> String {
        guard let vm = mapViewModel else {
            return errorJSON(RouterError.dependencyUnavailable(tool: "expand_radius", dependency: "map view model", hint: "The map session isn't active. Ask the user to reopen the map before this tool can run."))
        }
        if let noopReason = await vm.expandOneStage() {
            return Self.successJSON([
                "expanded": false,
                "reason": noopReason,
            ])
        }
        return Self.successJSON([
            "expanded": true,
            "added_count": vm.lastExploreAddedCount,
        ])
    }

    // MARK: - Shared filter builder (US-019)

    private static func buildFilter<T>(from args: T) -> ExperienceFilter where T: QualityArgsProvider {
        ExperienceFilter(
            category: args.categories?.compactMap(ExperienceCategory.init(rawValue:)).first?.rawValue,
            soloScoreMin: args.solo_score_min,
            ratingMin: args.rating_min,
            ambianceMin: args.ambiance_min
        )
    }

    // MARK: - Codec helpers

    private static func decode<T: Decodable>(_ argsJSON: String, tool: String) throws -> T {
        guard let data = argsJSON.data(using: .utf8) else {
            throw RouterError.invalidArguments(tool: tool, reason: "arguments not valid UTF-8")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw RouterError.invalidArguments(
                tool: tool, reason: error.localizedDescription
            )
        }
    }

    private static func successJSON(_ fields: [String: Any]) -> String {
        var payload = fields
        payload["ok"] = true
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return #"{"ok":true}"#
    }

    /// Classify a thrown error to a structured `ToolOutcome` wire payload.
    ///
    /// Everything the router throws lands here. Router-level cases
    /// (`RouterError`) map to specific `.retryable` / `.fatal` outcomes with
    /// hints; anything else is a `.fatal(.unrecoverableUpstream)` so the model
    /// stops calling the same tool.
    ///
    /// `retryLedger` is checked for repeat offences: same (tool, reason) hit
    /// more than `ToolRetryLedger.retryCap` times this turn escalates to
    /// `.fatal(.retryBudgetExhausted)` — the model has already had its shots
    /// at fixing the same problem and must stop.
    private func errorJSON(_ error: Error) -> String {
        // Empty-payload outcomes still need a Payload phantom; use `Never` via
        // an uninhabited Encodable stub so no accidental payload leaks in.
        typealias Never_ = _EmptyPayload
        switch error {
        case RouterError.unknownTool(let name):
            let outcome: ToolOutcome<Never_> = .fatal(
                reason: .unknownTool,
                hint: "'\(name)' is not a known tool. Available tools are listed in the TOOLS AVAILABLE section of the system prompt. Do not retry."
            )
            return outcome.encodeForModel()

        case RouterError.invalidArguments(let tool, let reason):
            let reasonKey = ToolOutcome<Never_>.RetryReason.invalidArgs.rawValue
            if retryLedger.record(tool: tool, reason: reasonKey) > ToolRetryLedger.retryCap {
                let outcome: ToolOutcome<Never_> = .fatal(
                    reason: .retryBudgetExhausted,
                    hint: "'\(tool)' rejected its arguments \(ToolRetryLedger.retryCap + 1) times this turn. Stop retrying and tell the user what you needed."
                )
                return outcome.encodeForModel()
            }
            let outcome: ToolOutcome<Never_> = .retryable(
                reason: .invalidArgs,
                hint: "'\(tool)' rejected its arguments: \(reason). Read the tool's JSON schema, fix the offending field, and try once more."
            )
            return outcome.encodeForModel()

        case RouterError.experienceNotFound(let tool, let id, let visibleHint):
            let reasonKey = ToolOutcome<Never_>.RetryReason.notFound.rawValue
            if retryLedger.record(tool: tool, reason: reasonKey) > ToolRetryLedger.retryCap {
                let outcome: ToolOutcome<Never_> = .fatal(
                    reason: .retryBudgetExhausted,
                    hint: "'\(tool)' has been called \(ToolRetryLedger.retryCap + 1) times with an unknown experience id. Ask the user to clarify which place they mean."
                )
                return outcome.encodeForModel()
            }
            let hint: String = {
                let base = "experience_id '\(id)' is not in CURRENT VISIBLE EXPERIENCES."
                if let h = visibleHint { return "\(base) \(h)" }
                return "\(base) Pick an id from the CURRENT VISIBLE EXPERIENCES list, or call explore_nearby / search_places first."
            }()
            let outcome: ToolOutcome<Never_> = .retryable(reason: .notFound, hint: hint)
            return outcome.encodeForModel()

        case RouterError.dependencyUnavailable(_, _, let hint):
            let outcome: ToolOutcome<Never_> = .fatal(reason: .dependencyUnavailable, hint: hint)
            return outcome.encodeForModel()

        case RouterError.underlying(_, let message):
            let outcome: ToolOutcome<Never_> = .fatal(
                reason: .unrecoverableUpstream,
                hint: "Upstream error: \(message). Do not retry this tool this turn — surface the issue to the user."
            )
            return outcome.encodeForModel()

        default:
            let outcome: ToolOutcome<Never_> = .fatal(
                reason: .unrecoverableUpstream,
                hint: (error as? LocalizedError)?.errorDescription ?? "\(error)"
            )
            return outcome.encodeForModel()
        }
    }

    /// Placeholder payload for error outcomes — carries no fields but keeps
    /// `ToolOutcome`'s generic contract satisfied. Never encoded (error cases
    /// pass `nil` payload).
    private struct _EmptyPayload: Encodable {}

    /// Shared prerequisite check for every handler that needs the map. Throws
    /// a `.dependencyUnavailable` fatal outcome when the view model has been
    /// deallocated — no point retrying this turn.
    private func requireMapVM(tool: String) throws -> MapViewModel {
        guard let vm = mapViewModel else {
            throw RouterError.dependencyUnavailable(
                tool: tool,
                dependency: "map view model",
                hint: "The map session isn't active. Ask the user to reopen the map before this tool can run."
            )
        }
        return vm
    }

    /// Build a compact hint for `.experienceNotFound` that lists a few valid
    /// ids from the current visible set — the highest-leverage nudge the model
    /// can act on without another tool call.
    private func visibleIDHint(from vm: MapViewModel, limit: Int = 3) -> String {
        let sample = vm.visibleExperiences.prefix(limit)
        guard !sample.isEmpty else {
            return "No experiences are currently visible on the map — call explore_nearby or search_places first."
        }
        let list = sample.map { "\($0.id) — \($0.title)" }.joined(separator: "; ")
        return "Valid ids include: \(list)."
    }

    // MARK: - P2.1 / P3.5 handlers (#210 – #216, #352)
    //
    // These handlers ship as v1 slim implementations that respect the
    // tool contract without adding new external dependencies:
    // - RAG-anchored tools (suggest_now_action) pick from the map view
    //   model's visible experiences, so we never fabricate a POI.
    // - IAP-gated tools (open_blindbox, sos_plan, unwalked_path) short-
    //   circuit to a `paywall_required` payload when the entitlement is
    //   missing — the chat surface renders that as a paywall CTA card.
    // - Persistence-oriented tools (bury_capsule) return a "recorded:false,
    //   reason:store_not_wired" envelope until CapsuleStore lands (#243);
    //   the LLM already tolerates false-ok envelopes.

    private struct SuggestNowArgs: Decodable {
        let reason_hint: String?
    }

    private func executeSuggestNowAction(args: String) throws -> String {
        let parsed: SuggestNowArgs = try Self.decode(args, tool: "suggest_now_action")
        let vm = try requireMapVM(tool: "suggest_now_action")
        // Pick the highest-solo-score visible experience the user hasn't
        // already marked completed. Never invent — if the visible pool is
        // empty we return a graceful "no candidates" envelope.
        let pool = vm.visibleExperiences.filter {
            !preferences.completedExperiences.contains($0.id)
        }
        guard let pick = pool.max(by: { $0.soloScore.overall < $1.soloScore.overall }) else {
            return Self.successJSON([
                "candidate_id": NSNull(),
                "reason": "no_visible_candidates",
                "user_hint": parsed.reason_hint ?? "",
            ])
        }
        // Surface as an inline card the way show_details does.
        lastEffect = .experiences([pick])
        return Self.successJSON([
            "candidate_id": pick.id,
            "title": pick.title,
            "solo_score": pick.soloScore.overall,
            "user_hint": parsed.reason_hint ?? "",
        ])
    }

    private struct OpenBlindboxArgs: Decodable {
        let duration_hours: Double?
    }

    private func executeOpenBlindbox(args: String) throws -> String {
        let parsed: OpenBlindboxArgs = try Self.decode(args, tool: "open_blindbox")
        let duration = parsed.duration_hours ?? 3.0
        // Real launch flow lives in BlindboxOrchestrator (#231) and its
        // sheet UI (#230). Until those wire up, the tool result is a
        // "paywall_required" envelope so the chat surface can render a
        // CTA card that opens the paywall.
        return Self.successJSON([
            "state": "paywall_required",
            "product_id": SubscriptionService.blindboxSingleProductID,
            "duration_hours": duration,
        ])
    }

    private struct BuryCapsuleArgs: Decodable {
        let experience_id: String
        let content_type: String
        let content_preview: String?
        let months_from_now: Int
    }

    private func executeBuryCapsule(args: String) throws -> String {
        let parsed: BuryCapsuleArgs = try Self.decode(args, tool: "bury_capsule")
        let allowed: Set<String> = ["text", "voice", "photo"]
        guard allowed.contains(parsed.content_type) else {
            throw RouterError.invalidArguments(
                tool: "bury_capsule",
                reason: "content_type must be text|voice|photo"
            )
        }
        // Persistence itself is deferred to CapsuleStore (#243). The tool
        // still validates + echoes so the chat surface can pop the compose
        // sheet without a round trip.
        return Self.successJSON([
            "recorded": false,
            "reason": "compose_sheet_pending",
            "experience_id": parsed.experience_id,
            "content_type": parsed.content_type,
            "months_from_now": parsed.months_from_now,
        ])
    }

    private struct RecallPatternArgs: Decodable {
        let period: String?
    }

    private func executeRecallPattern(args: String) throws -> String {
        let parsed: RecallPatternArgs = try Self.decode(args, tool: "recall_pattern")
        let period = parsed.period ?? "month"
        // Reads on-device VisitRecord via preferences.visitHistory as a
        // v1 proxy — the SwiftData path lands in a follow-up. Returns a
        // deterministic aggregate the LLM can turn into a sentence.
        // visitHistory is `[String: Date]` — one entry per Experience visited.
        // Count entries (not sum-of-Date) as the v1 proxy for total visits.
        let totalVisits = preferences.visitHistory.count
        return Self.successJSON([
            "period": period,
            "visit_count": totalVisits,
            "top_categories": Array(preferences.preferredCategories.prefix(3)),
        ])
    }

    private struct SOSPlanArgs: Decodable {
        let trigger: String?
        let duration_hours: Double?
    }

    private func executeSOSPlan(args: String) throws -> String {
        let parsed: SOSPlanArgs = try Self.decode(args, tool: "sos_plan")
        return Self.successJSON([
            "state": "paywall_required",
            "product_id": SubscriptionService.sosSingleProductID,
            "trigger": parsed.trigger ?? "",
            "duration_hours": parsed.duration_hours ?? 4.0,
        ])
    }

    private struct UnwalkedPathArgs: Decodable {
        let date: String
    }

    private func executeUnwalkedPath(args: String) throws -> String {
        let parsed: UnwalkedPathArgs = try Self.decode(args, tool: "unwalked_path")
        // Loose ISO date validation — reject anything not YYYY-MM-DD-ish.
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        guard iso.date(from: parsed.date) != nil else {
            throw RouterError.invalidArguments(
                tool: "unwalked_path", reason: "date must be YYYY-MM-DD"
            )
        }
        return Self.successJSON([
            "state": "paywall_required",
            "product_id": SubscriptionService.unwalkedSingleProductID,
            "date": parsed.date,
        ])
    }

    private struct RecallLocalSceneArgs: Decodable {
        let topic: String?
    }

    private func executeRecallLocalScene(args: String) throws -> String {
        let parsed: RecallLocalSceneArgs = try Self.decode(args, tool: "recall_local_scene")
        // Pro-only. The chat surface renders a paywall CTA card when
        // `pro_required:true` comes back with no `scene` payload. Real
        // Eventbrite/Meetup fetches land in a follow-up when API keys
        // are configured.
        return Self.successJSON([
            "pro_required": true,
            "topic": parsed.topic ?? "",
            "scene": NSNull(),
        ])
    }

    // MARK: - recall_memory (③ slice A)

    private struct RecallMemoryArgs: Decodable {
        let query: String
        let city_code: String?
        let limit: Int?
    }

    /// Payload for a successful `recall_memory` call. Encoded via
    /// `ToolOutcome` so the wire shape is the new structured envelope, not
    /// the legacy `successJSON` blob.
    private struct RecallMemoryPayload: Encodable {
        struct Hit: Encodable {
            let id: String
            let occurred_at: String   // ISO 8601 UTC
            let city_code: String?
            let title: String
            let body: String
            let tags: [String]
            let score: Double
        }
        let hits: [Hit]
        let queried: String
    }

    /// Search the per-orchestrator episode store for context matching the
    /// user's query. Returns a `retryable` outcome with a widen-scope hint
    /// on an empty hit set — that's the whole reason to use structured
    /// outcomes: the model gets a concrete next move instead of "no data".
    private func executeRecallMemory(args: String) throws -> String {
        let parsed: RecallMemoryArgs = try Self.decode(args, tool: "recall_memory")

        let trimmed = parsed.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RouterError.invalidArguments(
                tool: "recall_memory",
                reason: "query must be a non-empty search phrase"
            )
        }
        let limit = max(1, min(5, parsed.limit ?? 3))

        let hits = memoryStore.search(
            query: trimmed,
            cityCode: parsed.city_code,
            limit: limit
        )

        // Empty result → retryable with a specific widen hint. The model
        // can re-query with the city filter dropped, or drop to broader
        // wording; the retry ledger stops it from looping.
        guard !hits.isEmpty else {
            let hint: String
            if parsed.city_code != nil {
                hint = "No episodes matched '\(trimmed)' scoped to city '\(parsed.city_code!)'. Retry once WITHOUT the city_code, or rephrase the query using different keywords the user actually said."
            } else {
                hint = "No episodes matched '\(trimmed)'. The store may have no relevant history yet, or the query is too narrow — tell the user you don't have that memory rather than retrying with the same phrase."
            }
            let outcome: ToolOutcome<RecallMemoryPayload> = .retryable(
                reason: .emptyResult,
                hint: hint,
                retryableWith: parsed.city_code != nil ? ["city_code": .string("")] : nil,
                partial: RecallMemoryPayload(hits: [], queried: trimmed)
            )
            return outcome.encodeForModel()
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        let payload = RecallMemoryPayload(
            hits: hits.map { h in
                RecallMemoryPayload.Hit(
                    id: h.episode.id.uuidString,
                    occurred_at: iso.string(from: h.episode.occurredAt),
                    city_code: h.episode.cityCode,
                    title: h.episode.title,
                    body: h.episode.body,
                    tags: h.episode.tags,
                    score: h.score
                )
            },
            queried: trimmed
        )
        let outcome: ToolOutcome<RecallMemoryPayload> = .ok(
            payload: payload,
            hint: "Cite the surfaced episodes with a natural aside — 'you mentioned X last time' — before your recommendation. Don't dump the full body verbatim."
        )
        return outcome.encodeForModel()
    }

    // MARK: - City OS v2 (get_city_kit / find_local_events)

    private struct GetCityKitArgs: Decodable {
        let city_code: String?
        let kinds: [String]?
    }

    /// Resolve the current city (arg or map selection), load the brief, and
    /// return the requested kit sections as compact facts. Visa day counts come
    /// ONLY from `ComplianceService` (never invented by the model); when the
    /// user hasn't set an entry date, the visa row carries a `visa_setup_needed`
    /// flag instead of numbers.
    private func executeGetCityKit(args: String) async throws -> String {
        let parsed: GetCityKitArgs = try Self.decode(args, tool: "get_city_kit")
        let service = try requireCityBrief(tool: "get_city_kit")
        let code = try resolveCityCode(param: parsed.city_code, tool: "get_city_kit")
        await service.load(cityCode: code)

        let wanted: Set<String>? = parsed.kinds.map(Set.init)
        let rows = service.kit.filter { wanted?.contains($0.kind.rawValue) ?? true }
        guard !rows.isEmpty else {
            return Self.successJSON([
                "city_code": code,
                "sections": [String](),
                "note": "no_kit_for_city",
            ])
        }

        let sections: [[String: Any]] = rows.map { item in
            var dict: [String: Any] = [
                "section": item.kind.rawValue,
                "name": item.name,
                "body": item.main,
            ]
            if let lens = item.lens { dict["lens"] = lens }
            if let label = item.linkLabel { dict["link_label"] = label }
            if item.kind == .visa {
                if let state = complianceService?.state() {
                    dict["visa_days_remaining"] = state.visaDaysRemaining
                    dict["tax_days_remaining"] = state.taxDaysRemaining
                    dict["days_stayed"] = state.daysStayed
                } else {
                    dict["visa_setup_needed"] = true
                }
            }
            if item.kind == .safety, let numbers = item.action?.numbers {
                dict["emergency_numbers"] = numbers.map { ["label": $0.label, "number": $0.number] }
            }
            return dict
        }
        return Self.successJSON(["city_code": code, "sections": sections])
    }

    private struct FindLocalEventsArgs: Decodable {
        let city_code: String?
        let within_days: Int?
        let solo_score_min: Double?
        let query: String?
    }

    /// Filter the city's active events by window / solo score / keyword and set
    /// a `.events` effect so the chat surface renders tappable event cards.
    /// Notices are always kept (a road closure isn't scored but matters).
    private func executeFindLocalEvents(args: String) async throws -> String {
        let parsed: FindLocalEventsArgs = try Self.decode(args, tool: "find_local_events")
        let service = try requireCityBrief(tool: "find_local_events")
        let code = try resolveCityCode(param: parsed.city_code, tool: "find_local_events")
        await service.load(cityCode: code)

        let now = Date()
        let withinDays = max(1, min(30, parsed.within_days ?? 7))
        let horizon = Calendar.current.date(byAdding: .day, value: withinDays, to: now) ?? now
        let queryLower = parsed.query?.lowercased()

        let windowed = service.activeEvents(now: now).filter { event in
            // Window: keep events with no start date, or starting before horizon.
            if let starts = event.startsAt, starts > horizon { return false }
            // Notices bypass the solo-score floor.
            if !event.isNotice, let floor = parsed.solo_score_min {
                guard let score = event.soloScore, score >= floor else { return false }
            }
            return true
        }

        // The keyword pass is soft: event content is usually local-language
        // (中文 names/notes) while the model's keyword tends to be English
        // ("weekend"), so a hard filter starves valid results into a false
        // "nothing on". When the keyword matches nothing, fall back to the
        // window-filtered list and flag it so the model can phrase honestly.
        var matches = windowed
        var queryRelaxed = false
        if let q = queryLower, !q.isEmpty {
            let keyworded = windowed.filter { event in
                let haystack = (event.name + " " + (event.soloNote ?? "") + " " + event.whenLabel).lowercased()
                return haystack.contains(q)
            }
            if keyworded.isEmpty {
                queryRelaxed = !windowed.isEmpty
            } else {
                matches = keyworded
            }
        }

        if !matches.isEmpty {
            lastEffect = .events(matches)
        }

        let payload: [[String: Any]] = matches.map { event in
            var dict: [String: Any] = [
                "id": event.id,
                "name": event.name,
                "when": event.whenLabel,
                "is_notice": event.isNotice,
            ]
            if let score = event.soloScore { dict["solo_score"] = score }
            if let note = event.soloNote { dict["solo_note"] = note }
            if event.lat != nil && event.lng != nil { dict["has_map_location"] = true }
            return dict
        }
        var envelope: [String: Any] = [
            "city_code": code,
            "count": matches.count,
            "within_days": withinDays,
            "events": payload,
        ]
        if queryRelaxed { envelope["query_relaxed"] = true }
        return Self.successJSON(envelope)
    }

    /// City OS content plane or the standard dependency-unavailable envelope.
    private func requireCityBrief(tool: String) throws -> CityBriefService {
        guard let service = cityBriefService else {
            throw RouterError.dependencyUnavailable(
                tool: tool,
                dependency: "cityBriefService",
                hint: "City OS content isn't available this session. Answer from general knowledge and suggest the user open the 落地包 / 在地 tabs on the map."
            )
        }
        return service
    }

    /// Resolve a lowercase city code from the tool arg or the map's selected
    /// city. Throws when neither is available so the model asks the user.
    private func resolveCityCode(param: String?, tool: String) throws -> String {
        if let param, !param.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return CityOSStore.normalizedCityKey(param)
        }
        if let selected = mapViewModel?.selectedCity, !selected.isEmpty {
            return CityOSStore.normalizedCityKey(selected)
        }
        throw RouterError.invalidArguments(
            tool: tool,
            reason: "no city_code given and no city is selected on the map — ask the user which city they mean"
        )
    }
}
