import Foundation
import SwiftData

/// SwiftData representation of a `Conversation`.
///
/// Stores all scalar fields natively; `participantIds` is a JSON-encoded `[String]`
/// blob. Strategy mirrors `RouteRecord`: avoid relationships for flat structures.
@Model
public final class ConversationRecord {
    @Attribute(.unique) public var id: String

    public var requestId: String
    /// JSON-encoded `[String]`.
    public var participantIdsBlob: Data
    /// Raw value of `ConversationType`.
    public var type: String
    public var routeId: String?
    public var lastMessageAt: String?
    /// ISO 8601 UTC timestamp.
    public var createdAt: String
    /// ISO 8601 UTC timestamp.
    public var updatedAt: String

    public init(
        id: String,
        requestId: String,
        participantIdsBlob: Data,
        type: String,
        routeId: String?,
        lastMessageAt: String?,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.requestId = requestId
        self.participantIdsBlob = participantIdsBlob
        self.type = type
        self.routeId = routeId
        self.lastMessageAt = lastMessageAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Two-way mapping

extension ConversationRecord {
    public static func fromValue(_ conversation: Conversation) -> ConversationRecord {
        let blob: Data
        do {
            blob = try JSONEncoder().encode(conversation.participantIds)
        } catch {
            fatalError("Failed to encode participantIds for ConversationRecord \(conversation.id.rawValue): \(error)")
        }
        return ConversationRecord(
            id: conversation.id.rawValue,
            requestId: conversation.requestId.rawValue,
            participantIdsBlob: blob,
            type: conversation.type.rawValue,
            routeId: conversation.routeId,
            lastMessageAt: conversation.lastMessageAt,
            createdAt: conversation.createdAt,
            updatedAt: conversation.updatedAt
        )
    }

    public var asValue: Conversation {
        let participantIds: [String]
        do {
            participantIds = try JSONDecoder().decode([String].self, from: participantIdsBlob)
        } catch {
            fatalError("Failed to decode participantIdsBlob for ConversationRecord \(id): \(error)")
        }
        return Conversation(
            id: ConversationId(rawValue: id),
            requestId: CompanionRequestId(rawValue: requestId),
            participantIds: participantIds,
            type: ConversationType(rawValue: type) ?? .oneOnOne,
            routeId: routeId,
            lastMessageAt: lastMessageAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
