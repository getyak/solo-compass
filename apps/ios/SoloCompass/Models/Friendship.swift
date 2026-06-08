/// Friendship — a confirmed, bidirectional, persistent relationship.
///
/// Stored once per pair using an ordered pair (`userLowId < userHighId`
/// lexicographically) so A↔B is a single row and lookups are idempotent.
/// Promotes a one-off companion tie into a long-term connection that unlocks
/// direct companion invites, persistent DMs, and a full read-only profile.
///
/// Mirrors `packages/core/src/friend.ts`. Keep field names in sync
/// (guarded by `pnpm parity:check`).

import Foundation

// MARK: - FriendshipId

/// Strongly-typed identifier for a Friendship. Format: `fnd_<random_id>`.
public struct FriendshipId: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

// MARK: - FriendCode

/// A short, shareable code a user hands out to be added (e.g. "SOLO-7K2F-9XQR").
/// Rotatable — issuing a new one invalidates the old. Never the raw UserId.
public struct FriendCode: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

// MARK: - Friendship

/// A confirmed, bidirectional friendship.
public struct Friendship: Identifiable, Codable, Sendable {
    public let id: FriendshipId
    /// Lexicographically smaller of the two UserIds.
    public let userLowId: String
    /// Lexicographically larger of the two UserIds.
    public let userHighId: String
    /// Who originally sent the accepted request (provenance, not direction).
    public let initiatedBy: String
    /// The persistent 1:1 conversation backing this friendship (lazily created).
    public let conversationId: ConversationId?
    /// ISO 8601 UTC when the friendship became active (request accepted).
    public let acceptedAt: String
    /// ISO 8601 UTC timestamp.
    public let createdAt: String
    /// ISO 8601 UTC timestamp.
    public let updatedAt: String

    public init(
        id: FriendshipId,
        userLowId: String,
        userHighId: String,
        initiatedBy: String,
        conversationId: ConversationId? = nil,
        acceptedAt: String,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.userLowId = userLowId
        self.userHighId = userHighId
        self.initiatedBy = initiatedBy
        self.conversationId = conversationId
        self.acceptedAt = acceptedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // Custom decoder: `conversationId` is optional (lazily created on first DM).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(FriendshipId.self, forKey: .id)
        userLowId = try c.decode(String.self, forKey: .userLowId)
        userHighId = try c.decode(String.self, forKey: .userHighId)
        initiatedBy = try c.decode(String.self, forKey: .initiatedBy)
        conversationId = try c.decodeIfPresent(ConversationId.self, forKey: .conversationId)
        acceptedAt = try c.decode(String.self, forKey: .acceptedAt)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
    }
}

// MARK: - View helpers

extension Friendship {
    /// The *other* participant from a given viewer's perspective.
    public func otherUserId(viewer: String) -> String {
        viewer == userLowId ? userHighId : userLowId
    }

    /// Build the canonical ordered pair from two raw UserIds, so callers don't
    /// have to remember which goes low/high.
    public static func orderedPair(_ a: String, _ b: String) -> (low: String, high: String) {
        a < b ? (a, b) : (b, a)
    }
}

// MARK: - Preview samples

extension Friendship {
    static let sample = Friendship(
        id: FriendshipId(rawValue: "fnd_preview"),
        userLowId: "user_preview_a",
        userHighId: "user_preview_b",
        initiatedBy: "user_preview_a",
        conversationId: ConversationId(rawValue: "conv_friend_preview"),
        acceptedAt: "2026-06-08T10:00:00Z",
        createdAt: "2026-06-08T10:00:00Z",
        updatedAt: "2026-06-08T10:00:00Z"
    )
}
