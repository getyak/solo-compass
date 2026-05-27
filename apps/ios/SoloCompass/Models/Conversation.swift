import Foundation

/// Conversation — a messaging thread opened after a CompanionRequest is accepted.
///
/// Mirrors `packages/core/src/companion.ts`. Keep field names in sync.

// MARK: - ConversationId

public struct ConversationId: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

// MARK: - Conversation

public struct Conversation: Identifiable, Codable, Sendable {
    public let id: ConversationId
    public let requestId: CompanionRequestId
    public let participantIds: [String]
    /// ISO 8601 UTC timestamp of the most recent message.
    public let lastMessageAt: String?
    /// ISO 8601 UTC timestamp.
    public let createdAt: String
    /// ISO 8601 UTC timestamp.
    public let updatedAt: String

    public init(
        id: ConversationId,
        requestId: CompanionRequestId,
        participantIds: [String],
        lastMessageAt: String? = nil,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.requestId = requestId
        self.participantIds = participantIds
        self.lastMessageAt = lastMessageAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Preview sample

extension Conversation {
    static let sample = Conversation(
        id: ConversationId(rawValue: "conv_preview"),
        requestId: CompanionRequestId(rawValue: "creq_preview"),
        participantIds: ["user_preview", "user_preview_b"],
        lastMessageAt: "2026-02-05T14:30:00Z",
        createdAt: "2026-02-02T09:00:00Z",
        updatedAt: "2026-02-05T14:30:00Z"
    )
}
