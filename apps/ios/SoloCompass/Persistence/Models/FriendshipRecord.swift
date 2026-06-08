import Foundation
import SwiftData

/// SwiftData representation of a `Friendship`.
///
/// Stored once per pair (`userLowId < userHighId`). All fields scalar; the
/// optional `conversationId` is nil until the first DM lazily creates the
/// backing conversation.
@Model
public final class FriendshipRecord {
    @Attribute(.unique) public var id: String

    public var userLowId: String
    public var userHighId: String
    public var initiatedBy: String
    /// ConversationId raw value, nil until the first DM is opened.
    public var conversationId: String?
    /// ISO 8601 UTC when the friendship became active.
    public var acceptedAt: String
    /// ISO 8601 UTC timestamp.
    public var createdAt: String
    /// ISO 8601 UTC timestamp.
    public var updatedAt: String

    public init(
        id: String,
        userLowId: String,
        userHighId: String,
        initiatedBy: String,
        conversationId: String?,
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
}

// MARK: - Two-way mapping

extension FriendshipRecord {
    public convenience init(from friendship: Friendship) {
        self.init(
            id: friendship.id.rawValue,
            userLowId: friendship.userLowId,
            userHighId: friendship.userHighId,
            initiatedBy: friendship.initiatedBy,
            conversationId: friendship.conversationId?.rawValue,
            acceptedAt: friendship.acceptedAt,
            createdAt: friendship.createdAt,
            updatedAt: friendship.updatedAt
        )
    }

    public var asValue: Friendship {
        Friendship(
            id: FriendshipId(rawValue: id),
            userLowId: userLowId,
            userHighId: userHighId,
            initiatedBy: initiatedBy,
            conversationId: conversationId.map { ConversationId(rawValue: $0) },
            acceptedAt: acceptedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
