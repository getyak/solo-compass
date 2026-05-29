
/// CompanionProfile — the user's public-facing companion identity.
///
/// Mirrors `packages/core/src/companion.ts`. Keep field names in sync.

// MARK: - CompanionProfileId

public struct CompanionProfileId: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

// MARK: - CompanionVisibility

public enum CompanionVisibility: String, Codable, CaseIterable, Sendable {
    /// User never appears in any discovery list. Default.
    case off
    /// Visible only to users whose itineraries overlap.
    case itinerary_only
    /// Visible to overlapping itineraries and nearby users.
    case nearby_and_itinerary
}

// MARK: - CompanionProfile

public struct CompanionProfile: Identifiable, Codable, Sendable {
    public let id: CompanionProfileId
    public let userId: String
    /// Emoji or short generated avatar token. No real photo.
    public let avatarEmoji: String
    /// Short bio, max 280 chars.
    public let bio: String
    /// ISO language codes (e.g. ["en", "zh"]).
    public let languages: [String]
    /// Controls whether and how the user appears in discovery. Default: off.
    public let visibility: CompanionVisibility
    /// ISO 8601 UTC timestamp.
    public let createdAt: String
    /// ISO 8601 UTC timestamp.
    public let updatedAt: String

    public init(
        id: CompanionProfileId,
        userId: String,
        avatarEmoji: String,
        bio: String,
        languages: [String],
        visibility: CompanionVisibility = .off,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.userId = userId
        self.avatarEmoji = avatarEmoji
        self.bio = bio
        self.languages = languages
        self.visibility = visibility
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Preview sample

extension CompanionProfile {
    static let sample = CompanionProfile(
        id: CompanionProfileId(rawValue: "cprof_preview"),
        userId: "user_preview",
        avatarEmoji: "🧭",
        bio: "Solo traveler, 12 countries. Loves quiet coffee shops, hidden temples, and dawn hikes.",
        languages: ["en", "zh"],
        visibility: .itinerary_only,
        createdAt: "2026-01-01T00:00:00Z",
        updatedAt: "2026-01-01T00:00:00Z"
    )
}
