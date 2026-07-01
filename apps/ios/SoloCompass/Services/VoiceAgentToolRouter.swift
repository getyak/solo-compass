import Foundation
import CoreLocation

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
    public enum RouterError: Error, LocalizedError {
        case unknownTool(String)
        case invalidArguments(tool: String, reason: String)
        case experienceNotFound(String)
        case underlying(String)

        public var errorDescription: String? {
            switch self {
            case .unknownTool(let name):
                return "Unknown tool: \(name)"
            case .invalidArguments(let tool, let reason):
                return "Bad arguments for \(tool): \(reason)"
            case .experienceNotFound(let id):
                return "Experience not found: \(id)"
            case .underlying(let msg):
                return msg
            }
        }
    }

    private weak var mapViewModel: MapViewModel?
    private let preferences: UserPreferences
    /// Used by `build_route` to string nearby experiences into a walk. Optional
    /// so legacy callers (and tests) that don't build routes compile unchanged;
    /// when absent, `build_route` returns a graceful error instead of crashing.
    private let aiService: AIService?

    /// Side effect of the last `execute(_:)` call that the chat surface can turn
    /// into an inline card (places to show, a route to adopt). Reset to `nil` at
    /// the start of every `execute(_:)` so the orchestrator only ever reads the
    /// effect of the call it just made. This is intentionally OUT of the
    /// model-facing JSON contract — the model gets counts/ids, the UI gets cards.
    public enum ToolEffect: Equatable {
        case experiences([Experience])
        case route(RouteProposal)
    }
    public private(set) var lastEffect: ToolEffect?

    public init(
        mapViewModel: MapViewModel,
        preferences: UserPreferences,
        aiService: AIService? = nil
    ) {
        self.mapViewModel = mapViewModel
        self.preferences = preferences
        self.aiService = aiService
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

            default:
                throw RouterError.unknownTool(call.name)
            }
        } catch {
            return Self.errorJSON(error)
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
        guard let vm = mapViewModel else {
            throw RouterError.underlying("map view model deallocated")
        }
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
        guard let vm = mapViewModel else {
            throw RouterError.underlying("map view model deallocated")
        }
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
        guard let vm = mapViewModel else {
            throw RouterError.underlying("map view model deallocated")
        }
        // PRD: AI must only reference experience_ids it saw in the
        // VISIBLE_EXPERIENCES injection. We hard-fail unknown ids so
        // hallucinated ones round-trip back to the model as
        // `unknown_experience_id` and it can self-correct.
        guard let exp = vm.visibleExperiences.first(where: { $0.id == parsed.experience_id }) else {
            throw RouterError.experienceNotFound(parsed.experience_id)
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
        guard let vm = mapViewModel else {
            throw RouterError.underlying("map view model deallocated")
        }
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
        guard let vm = mapViewModel else {
            throw RouterError.underlying("map view model deallocated")
        }
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

    // MARK: - build_route (conversational route creation)

    private struct BuildRouteArgs: Decodable {
        let experience_ids: [String]?
    }

    /// String nearby experiences into one walkable route and surface it as an
    /// adoptable chat card (NOT saved). The LLM inside `generateRoute` already
    /// factors current time / best-now windows / solo score; the system prompt
    /// (orchestrator) injects weather + visited context. When `experience_ids`
    /// are given, they're prioritised as the candidate pool; otherwise the whole
    /// visible set is the pool.
    private func executeBuildRoute(args: String) async throws -> String {
        let parsed: BuildRouteArgs = try Self.decode(args, tool: "build_route")
        guard let vm = mapViewModel else {
            throw RouterError.underlying("map view model deallocated")
        }
        guard let ai = aiService else {
            throw RouterError.underlying("route building unavailable")
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

    private func executeNavigateTo(args: String) throws -> String {
        let parsed: ExperienceIDArgs = try Self.decode(args, tool: "navigate_to")
        guard let vm = mapViewModel else {
            throw RouterError.underlying("map view model deallocated")
        }
        guard let exp = vm.visibleExperiences.first(where: { $0.id == parsed.experience_id }) else {
            throw RouterError.experienceNotFound(parsed.experience_id)
        }
        guard let coord = exp.coordinate else {
            throw RouterError.underlying("experience has no coordinate")
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
        guard let vm = mapViewModel else {
            throw RouterError.underlying("map view model deallocated")
        }
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
            return Self.errorJSON(RouterError.underlying("map view model deallocated"))
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

    private static func errorJSON(_ error: Error) -> String {
        let payload: [String: Any] = [
            "ok": false,
            "error": (error as? LocalizedError)?.errorDescription ?? "\(error)",
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return #"{"ok":false,"error":"unknown"}"#
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
        guard let vm = mapViewModel else {
            throw RouterError.underlying("map view model deallocated")
        }
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
}
