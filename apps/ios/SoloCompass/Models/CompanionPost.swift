
/// CompanionPost — a discoverable post signalling openness to meeting companions.
///
/// Mirrors `packages/core/src/companion.ts`. Keep field names in sync.

// MARK: - CompanionPostId

public struct CompanionPostId: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

// MARK: - CompanionPostMode

public enum CompanionPostMode: String, Codable, Sendable {
    case itinerary
    case nearby
}

// MARK: - CompanionPost

public struct CompanionPost: Identifiable, Codable, Sendable {
    public let id: CompanionPostId
    public let authorId: String
    /// itinerary: tied to a named trip; nearby: open-ended local availability.
    public let mode: CompanionPostMode
    /// Present when mode=itinerary.
    public let itineraryId: ItineraryId?
    /// Short text intro visible to other users before they send a request.
    public let blurb: String
    /// Activity categories the author is interested in.
    public let categories: [ExperienceCategory]
    /// ISO 3166-1 alpha-3 or city code where the author is active.
    public let cityCode: String
    /// ISO 8601 date string (YYYY-MM-DD). Null for nearby-mode posts.
    public let activeFrom: String?
    /// ISO 8601 date string (YYYY-MM-DD). Null for nearby-mode posts.
    public let activeTo: String?
    /// ISO 8601 UTC timestamp.
    public let createdAt: String
    /// ISO 8601 UTC timestamp.
    public let updatedAt: String

    public init(
        id: CompanionPostId,
        authorId: String,
        mode: CompanionPostMode,
        itineraryId: ItineraryId? = nil,
        blurb: String,
        categories: [ExperienceCategory],
        cityCode: String,
        activeFrom: String? = nil,
        activeTo: String? = nil,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.authorId = authorId
        self.mode = mode
        self.itineraryId = itineraryId
        self.blurb = blurb
        self.categories = categories
        self.cityCode = cityCode
        self.activeFrom = activeFrom
        self.activeTo = activeTo
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Preview sample

extension CompanionPost {
    static let sample = CompanionPost(
        id: CompanionPostId(rawValue: "cpost_preview"),
        authorId: "user_preview",
        mode: .itinerary,
        itineraryId: ItineraryId(rawValue: "itin_preview"),
        blurb: "Looking for a travel buddy for Tokyo — coffee shops and hidden temples.",
        categories: [.coffee, .culture],
        cityCode: "TYO",
        activeFrom: "2026-04-01",
        activeTo: "2026-04-10",
        createdAt: "2026-01-15T09:00:00Z",
        updatedAt: "2026-01-15T09:00:00Z"
    )
}
