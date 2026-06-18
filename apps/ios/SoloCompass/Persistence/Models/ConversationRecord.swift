import Foundation
import SwiftData

/// SwiftData representation of a `Conversation`.
///
/// Stores all scalar fields natively; `participantIds` is a JSON-encoded `[String]`
/// blob. Strategy mirrors `RouteRecord`: avoid relationships for flat structures.
@Model
public final class ConversationRecord {
    @Attribute(.unique) public var id: String

    /// Nil for `friendDirect` conversations, which have no backing CompanionRequest.
    /// Optional column → relaxing from non-optional is a SwiftData lightweight migration.
    public var requestId: String?
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
    /// When true, the chat is frozen — no new messages can be sent (route completed).
    public var isReadOnly: Bool

    public init(
        id: String,
        requestId: String?,
        participantIdsBlob: Data,
        type: String,
        routeId: String?,
        lastMessageAt: String?,
        createdAt: String,
        updatedAt: String,
        isReadOnly: Bool = false
    ) {
        self.id = id
        self.requestId = requestId
        self.participantIdsBlob = participantIdsBlob
        self.type = type
        self.routeId = routeId
        self.lastMessageAt = lastMessageAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isReadOnly = isReadOnly
    }
}

// MARK: - Two-way mapping

extension ConversationRecord {
    public static func fromValue(_ conversation: Conversation) -> ConversationRecord {
        // Encoding `[String]` to JSON cannot fail in practice. We keep the
        // do/catch so a future, lossy participantIds shape still produces a
        // record (with an empty blob) and a Sentry breadcrumb rather than
        // crashing the app at write time.
        let blob: Data = (try? JSONEncoder().encode(conversation.participantIds)) ?? Data("[]".utf8)
        if blob.count == 2 && !conversation.participantIds.isEmpty {
            PersistenceLog.recordDecodeFailure(
                PersistenceCodecError(
                    context: "ConversationRecord.fromValue",
                    recordId: conversation.id.rawValue,
                    underlying: NSError(
                        domain: "PersistenceCodec",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "participantIds encode failed; persisted as empty blob"]
                    )
                )
            )
        }
        return ConversationRecord(
            id: conversation.id.rawValue,
            requestId: conversation.requestId?.rawValue,
            participantIdsBlob: blob,
            type: conversation.type.rawValue,
            routeId: conversation.routeId,
            lastMessageAt: conversation.lastMessageAt,
            createdAt: conversation.createdAt,
            updatedAt: conversation.updatedAt,
            isReadOnly: conversation.isReadOnly
        )
    }

    public var asValue: Conversation {
        // Schema-evolution safety: a malformed blob from an older app
        // version used to call `fatalError` and crash the app on launch.
        // We now downgrade to an empty participants list and log the
        // failure so the row stays visible (and triagable) instead of
        // bringing the whole UI down.
        let participantIds: [String]
        if let decoded = try? JSONDecoder().decode([String].self, from: participantIdsBlob) {
            participantIds = decoded
        } else {
            PersistenceLog.recordDecodeFailure(
                PersistenceCodecError(
                    context: "ConversationRecord.asValue",
                    recordId: id,
                    underlying: NSError(
                        domain: "PersistenceCodec",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "participantIdsBlob decode failed"]
                    )
                )
            )
            participantIds = []
        }
        return Conversation(
            id: ConversationId(rawValue: id),
            requestId: requestId.map { CompanionRequestId(rawValue: $0) },
            participantIds: participantIds,
            type: ConversationType(rawValue: type) ?? .oneOnOne,
            routeId: routeId,
            lastMessageAt: lastMessageAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isReadOnly: isReadOnly
        )
    }
}
