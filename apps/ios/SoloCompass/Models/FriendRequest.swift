/// FriendRequest — a pending bid to form a persistent friendship.
///
/// Mirrors `packages/core/src/friend.ts`. Keep field names in sync
/// (guarded by `pnpm parity:check`).

import Foundation

// MARK: - FriendRequestId

/// Strongly-typed identifier for a FriendRequest. Format: `freq_<random_id>`.
public struct FriendRequestId: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

// MARK: - FriendRequestStatus

/// Lifecycle of a friend request.
public enum FriendRequestStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case accepted
    case declined
    case withdrawn
    case expired
}

// MARK: - FriendRequestSource

/// How the requester reached the recipient — drives anti-abuse weighting.
public enum FriendRequestSource: String, Codable, Sendable, CaseIterable {
    /// Already in a companion conversation together.
    case companionChat = "companion_chat"
    /// In the same route group chat.
    case routeGroup = "route_group"
    /// Scanned / typed a friend code.
    case friendCode = "friend_code"
    /// Added directly from an anonymized discover post.
    case discover
}

// MARK: - FriendRequest

/// A request from one user to another to become friends.
public struct FriendRequest: Identifiable, Codable, Sendable {
    public let id: FriendRequestId
    public let requesterId: String
    public let recipientId: String
    public let status: FriendRequestStatus
    public let source: FriendRequestSource
    /// Optional one-line hello, max 120 chars.
    public let note: String?
    /// ISO 8601 UTC. Auto-expires 14 days after creation.
    public let expiresAt: String
    /// ISO 8601 UTC timestamp.
    public let createdAt: String
    /// ISO 8601 UTC timestamp.
    public let updatedAt: String

    public init(
        id: FriendRequestId,
        requesterId: String,
        recipientId: String,
        status: FriendRequestStatus = .pending,
        source: FriendRequestSource,
        note: String? = nil,
        expiresAt: String,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.requesterId = requesterId
        self.recipientId = recipientId
        self.status = status
        self.source = source
        self.note = note
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // Custom decoder: `status` defaults to `.pending` when absent (legacy payloads).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(FriendRequestId.self, forKey: .id)
        requesterId = try c.decode(String.self, forKey: .requesterId)
        recipientId = try c.decode(String.self, forKey: .recipientId)
        status = try c.decodeIfPresent(FriendRequestStatus.self, forKey: .status) ?? .pending
        source = try c.decode(FriendRequestSource.self, forKey: .source)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        expiresAt = try c.decode(String.self, forKey: .expiresAt)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
    }
}

// MARK: - Preview samples

extension FriendRequest {
    static let sample = FriendRequest(
        id: FriendRequestId(rawValue: "freq_preview"),
        requesterId: "user_preview_a",
        recipientId: "user_preview_b",
        status: .pending,
        source: .friendCode,
        note: "Hey! We climbed the same trail — let's stay in touch.",
        expiresAt: "2026-06-22T09:00:00Z",
        createdAt: "2026-06-08T09:00:00Z",
        updatedAt: "2026-06-08T09:00:00Z"
    )
}
