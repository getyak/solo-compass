/// ChatMessage — a single message within a Conversation.
///
/// Mirrors `packages/core/src/companion.ts`. Keep field names in sync.

// MARK: - ChatMessageId

/// Strongly-typed identifier for a ChatMessage, preventing raw-string ID mix-ups.
public struct ChatMessageId: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

// MARK: - ChatAttachment

/// A media or document attachment carried by a `ChatMessage`.
///
/// Mirrors `ChatAttachment` in `packages/core/src/companion.ts`. Synthesized
/// Codable uses camelCase keys to round-trip the TS JSON payload verbatim.
public struct ChatAttachment: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    /// Discriminates a previewable image from an arbitrary file.
    public let kind: Kind
    public let fileName: String
    public let mimeType: String
    public let fileSizeBytes: Int
    /// Path within the `chat-media` bucket: `{conversationId}/{messageId}/{attachmentId}-{fileName}`.
    public let storagePath: String
    /// Pixel width, image kind only.
    public let width: Int?
    /// Pixel height, image kind only.
    public let height: Int?

    /// Discriminates a previewable image from an arbitrary file.
    public enum Kind: String, Codable, Sendable {
        case image
        case file
    }

    public init(
        id: String,
        kind: Kind,
        fileName: String,
        mimeType: String,
        fileSizeBytes: Int,
        storagePath: String,
        width: Int? = nil,
        height: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.fileName = fileName
        self.mimeType = mimeType
        self.fileSizeBytes = fileSizeBytes
        self.storagePath = storagePath
        self.width = width
        self.height = height
    }
}

// MARK: - ChatMessage

/// A single message sent within a Conversation, including its body and read receipt.
public struct ChatMessage: Identifiable, Codable, Sendable {
    public let id: ChatMessageId
    public let conversationId: ConversationId
    public let senderId: String
    public let body: String
    /// Attachments carried by this message. Nil/empty when text-only.
    public let attachments: [ChatAttachment]?
    /// ISO 8601 UTC timestamp when the recipient read the message.
    public let readAt: String?
    /// ISO 8601 UTC timestamp.
    public let createdAt: String

    public init(
        id: ChatMessageId,
        conversationId: ConversationId,
        senderId: String,
        body: String,
        attachments: [ChatAttachment]? = nil,
        readAt: String? = nil,
        createdAt: String
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.body = body
        self.attachments = attachments
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
