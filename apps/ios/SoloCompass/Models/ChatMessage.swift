
/// ChatMessage — a single message within a Conversation.
///
/// Mirrors `packages/core/src/companion.ts`. Keep field names in sync.

// MARK: - ChatMessageId

/// Strongly-typed identifier for a ChatMessage, preventing raw-string ID mix-ups.
public struct ChatMessageId: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

// MARK: - ChatMessage

/// A single message sent within a Conversation, including its body and read receipt.
public struct ChatMessage: Identifiable, Codable, Sendable {
    public let id: ChatMessageId
    public let conversationId: ConversationId
    public let senderId: String
    public let body: String
    /// ISO 8601 UTC timestamp when the recipient read the message.
    public let readAt: String?
    /// ISO 8601 UTC timestamp.
    public let createdAt: String

    public init(
        id: ChatMessageId,
        conversationId: ConversationId,
        senderId: String,
        body: String,
        readAt: String? = nil,
        createdAt: String
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.body = body
        self.readAt = readAt
        self.createdAt = createdAt
    }
}

// MARK: - Preview sample

extension ChatMessage {
    static let sample = ChatMessage(
        id: ChatMessageId(rawValue: "cmsg_preview"),
        conversationId: ConversationId(rawValue: "conv_preview"),
        senderId: "user_preview_b",
        body: "Looking forward to exploring Tokyo together!",
        readAt: "2026-02-05T14:35:00Z",
        createdAt: "2026-02-05T14:30:00Z"
    )
}
