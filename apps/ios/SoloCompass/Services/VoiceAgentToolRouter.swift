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

    public init(mapViewModel: MapViewModel, preferences: UserPreferences) {
        self.mapViewModel = mapViewModel
        self.preferences = preferences
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
    ]

    // MARK: - Execution

    /// Route one DeepSeek `tool_call` to the matching app action. Returns
    /// a JSON string that the orchestrator feeds back as the `tool` row
    /// content. Failures are represented as `{"ok":false,"error":"…"}`
    /// rather than thrown so the agent can recover via the model.
    public func execute(_ call: VoiceAgentSession.ToolCall) async -> String {
        do {
            switch call.name {
            case "explore_nearby":
                return try await executeExploreNearby(args: call.argumentsJSON)
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
        return Self.successJSON([
            "added_count": vm.lastExploreAddedCount,
            "radius_meters": radius,
            "progressive": useProgressive,
        ])
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
        vm.selectExperience(exp)
        vm.isShowingDetail = true
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
        return Self.successJSON([
            "query": parsed.query,
            "added_count": vm.lastExploreAddedCount,
            "radius_meters": radius,
            "progressive": useProgressive,
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
