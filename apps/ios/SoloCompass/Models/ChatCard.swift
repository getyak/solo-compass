import Foundation

/// A structured, tappable artifact rendered inline in the chat message stream.
///
/// The agent no longer hijacks the map when it has something to show — instead a
/// tool result produces one of these cards, which `ChatSheet` renders below the
/// assistant bubble that triggered it. Tapping a card is the ONLY thing that
/// touches the map (selects a place / saves a route), so the user stays in
/// control of context switches. See [[project_routes_now_only]] for the related
/// route-surfacing decision.
///
/// Value-typed (no main-actor isolation) so it can be stored, compared, and
/// passed across the orchestrator → view boundary. Not `Sendable`: it wraps
/// `Experience`, which is a value type but not declared `Sendable`, and these
/// cards never cross an isolation boundary (they live on the `@MainActor`
/// orchestrator and are read by `@MainActor` views).
public enum ChatCard: Identifiable, Equatable {
    /// One or more places the agent surfaced (from explore_nearby / search_places
    /// / recommend). Rendered as a horizontal rail of `ChatExperienceCard`s.
    case experiences(id: UUID, [Experience])
    /// A proposed walk the agent strung together. NOT yet saved — the user taps
    /// "采用这条路线" on the card to persist it and open its detail.
    case route(id: UUID, RouteProposal)

    public var id: UUID {
        switch self {
        case let .experiences(id, _): return id
        case let .route(id, _): return id
        }
    }

    public static func == (lhs: ChatCard, rhs: ChatCard) -> Bool {
        lhs.id == rhs.id
    }
}

/// A route the agent built but has not committed. Carries the resolved stop
/// experiences (so the card can render names / categories without a lookup) and
/// an optional per-stop "why this stop" line for the elegant reasoning display.
public struct RouteProposal: Equatable {
    /// The fully-built (but unsaved) route. `experienceIds` is the ordered walk.
    public let route: Route
    /// Stop experiences in walk order, resolved from `route.experienceIds`.
    public let stops: [Experience]
    /// Optional per-stop rationale, parallel to `stops`. Empty when the model
    /// gave only a route-level summary. Used to render the "为什么选它" lines.
    public let stopReasons: [String]

    public init(route: Route, stops: [Experience], stopReasons: [String] = []) {
        self.route = route
        self.stops = stops
        self.stopReasons = stopReasons
    }

    public static func == (lhs: RouteProposal, rhs: RouteProposal) -> Bool {
        let sameRoute: Bool = lhs.route.id == rhs.route.id
        let lhsStopIds: [String] = lhs.stops.map(\.id)
        let rhsStopIds: [String] = rhs.stops.map(\.id)
        let sameStops: Bool = lhsStopIds == rhsStopIds
        let sameReasons: Bool = lhs.stopReasons == rhs.stopReasons
        return sameRoute && sameStops && sameReasons
    }
}

/// One step in the agent's visible "thinking" trace. The orchestrator records
/// these as it works so the chat can show *what* the model is reasoning about
/// (analyzing weather / location / places you've been) instead of an opaque
/// spinner. Kept deliberately small and value-typed so it's trivially testable.
public struct ReasoningStep: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        case thinking      // model is deliberating
        case tool          // a tool is running (search, explore, build route…)
        case insight       // a derived conclusion worth surfacing
    }

    public let id: UUID
    public let kind: Kind
    /// Already-localized, human-readable label (e.g. "🔍 正在分析附近的咖啡馆…").
    public let label: String

    public init(id: UUID = UUID(), kind: Kind, label: String) {
        self.id = id
        self.kind = kind
        self.label = label
    }
}
