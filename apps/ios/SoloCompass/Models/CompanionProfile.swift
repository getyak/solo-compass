/// CompanionProfile — the user's public-facing companion identity.
///
/// Mirrors `packages/core/src/companion.ts`. Keep field names in sync.

// MARK: - CompanionProfileId

/// Strongly-typed identifier for a CompanionProfile, preventing raw-string ID mix-ups.
public struct CompanionProfileId: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

// MARK: - CompanionVisibility

/// Controls whether and to whom a user appears in companion discovery.
public enum CompanionVisibility: String, Codable, CaseIterable, Sendable {
    /// User never appears in any discovery list. Default.
    case off
    /// Visible only to users whose itineraries overlap.
    case itinerary_only
    /// Visible to overlapping itineraries and nearby users.
    case nearby_and_itinerary
}

// MARK: - UserRole

/// Platform-level access role. Mirrors `UserRole` in `packages/core/src/companion.ts`.
///
/// Orthogonal to the P2P friend graph — `moderator` and `admin` can read the
/// full moderation queue and take moderation actions. Defaults to `.user`;
/// elevation is server-side only.
public enum UserRole: String, Codable, CaseIterable, Sendable {
    case user
    case moderator
    case admin

    /// True when this role can access the moderation queue and act on reports.
    public var canModerate: Bool {
        self == .moderator || self == .admin
    }
}

// MARK: - CompanionProfile

/// A user's public-facing companion identity — avatar, bio, languages, and discovery visibility.
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
    /// Platform access role. Default: .user. Elevated server-side only.
    public let role: UserRole
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
        role: UserRole = .user,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.userId = userId
        self.avatarEmoji = avatarEmoji
        self.bio = bio
        self.languages = languages
        self.visibility = visibility
        self.role = role
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // Custom decoder so older payloads / cached rows without `role` (or
    // `visibility`) decode leniently to a default rather than throwing — same
    // posture as FriendRequest / Friendship / Conversation.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(CompanionProfileId.self, forKey: .id)
        self.userId = try c.decode(String.self, forKey: .userId)
        self.avatarEmoji = try c.decode(String.self, forKey: .avatarEmoji)
        self.bio = try c.decode(String.self, forKey: .bio)
        self.languages = try c.decode([String].self, forKey: .languages)
        self.visibility = (try? c.decode(CompanionVisibility.self, forKey: .visibility)) ?? .off
        self.role = (try? c.decode(UserRole.self, forKey: .role)) ?? .user
        self.createdAt = try c.decode(String.self, forKey: .createdAt)
        self.updatedAt = try c.decode(String.self, forKey: .updatedAt)
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
        role: .user,
        createdAt: "2026-01-01T00:00:00Z",
        updatedAt: "2026-01-01T00:00:00Z"
    )
}
