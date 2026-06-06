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
        recordAddedEffect(before: before, vm: vm)
        return Self.successJSON([
            "added_count": vm.lastExploreAddedCount,
            "radius_meters": radius,
            "progressive": useProgressive,
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
        recordAddedEffect(before: before, vm: vm)
        return Self.successJSON([
            "query": parsed.query,
            "added_count": vm.lastExploreAddedCount,
            "radius_meters": radius,
            "progressive": useProgressive,
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
}
