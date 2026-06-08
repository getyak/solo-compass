import Foundation
import SwiftData

/// SwiftData representation of a `FriendRequest`.
///
/// All fields are scalar, so no blob encoding is needed. Enums are stored as
/// their raw-value strings (matching the backend `text` columns).
@Model
public final class FriendRequestRecord {
    @Attribute(.unique) public var id: String

    public var requesterId: String
    public var recipientId: String
    /// FriendRequestStatus raw value: pending|accepted|declined|withdrawn|expired.
    public var status: String
    /// FriendRequestSource raw value: companion_chat|route_group|friend_code|discover.
    public var source: String
    public var note: String?
    /// ISO 8601 UTC. Auto-expires 14 days after creation.
    public var expiresAt: String
    /// ISO 8601 UTC timestamp.
    public var createdAt: String
    /// ISO 8601 UTC timestamp.
    public var updatedAt: String

    public init(
        id: String,
        requesterId: String,
        recipientId: String,
        status: String,
        source: String,
        note: String?,
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
}

// MARK: - Two-way mapping

extension FriendRequestRecord {
    public convenience init(from request: FriendRequest) {
        self.init(
            id: request.id.rawValue,
            requesterId: request.requesterId,
            recipientId: request.recipientId,
            status: request.status.rawValue,
            source: request.source.rawValue,
            note: request.note,
            expiresAt: request.expiresAt,
            createdAt: request.createdAt,
            updatedAt: request.updatedAt
        )
    }

    public var asValue: FriendRequest {
        FriendRequest(
            id: FriendRequestId(rawValue: id),
            requesterId: requesterId,
            recipientId: recipientId,
            status: FriendRequestStatus(rawValue: status) ?? .pending,
            source: FriendRequestSource(rawValue: source) ?? .discover,
            note: note,
            expiresAt: expiresAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
