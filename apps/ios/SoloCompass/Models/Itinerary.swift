/// Itinerary — a named trip plan owned by one user.
///
/// Mirrors `packages/core/src/companion.ts`. Keep field names in sync.

// MARK: - ItineraryId

/// Strongly-typed identifier for an itinerary, preventing raw-string ID mix-ups.
public struct ItineraryId: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

// MARK: - Itinerary

/// A named trip plan owned by one user, scoping a set of experiences over a date range.
public struct Itinerary: Identifiable, Codable, Sendable {
    public let id: ItineraryId
    public let ownerId: String
    public let title: String
    /// ISO 3166-1 alpha-3 or city code scoping this itinerary.
    public let cityCode: String
    /// ISO 8601 date string (YYYY-MM-DD).
    public let startDate: String
    /// ISO 8601 date string (YYYY-MM-DD).
    public let endDate: String
    public let experienceIds: [String]
    public let note: String?
    /// Whether the owner is open to meeting companions on this trip.
    public let openToCompanions: Bool
    /// ISO 8601 UTC timestamp.
    public let createdAt: String
    /// ISO 8601 UTC timestamp.
    public let updatedAt: String

    public init(
        id: ItineraryId,
        ownerId: String,
        title: String,
        cityCode: String,
        startDate: String,
        endDate: String,
        experienceIds: [String],
        note: String? = nil,
        openToCompanions: Bool,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.ownerId = ownerId
        self.title = title
        self.cityCode = cityCode
        self.startDate = startDate
        self.endDate = endDate
        self.experienceIds = experienceIds
        self.note = note
        self.openToCompanions = openToCompanions
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Preview sample

extension Itinerary {
    static let sample = Itinerary(
        id: ItineraryId(rawValue: "itin_preview"),
        ownerId: "user_preview",
        title: "Tokyo Spring 2026",
        cityCode: "TYO",
        startDate: "2026-04-01",
        endDate: "2026-04-10",
        experienceIds: [],
        note: "Focus on cherry blossom spots and quiet cafes.",
        openToCompanions: true,
        createdAt: "2026-01-15T09:00:00Z",
        updatedAt: "2026-01-15T09:00:00Z"
    )
}
