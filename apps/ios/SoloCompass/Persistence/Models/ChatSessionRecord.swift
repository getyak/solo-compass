import Foundation
import SwiftData

/// SwiftData representation of one saved chat conversation (a session the user
/// can reopen from history). Holds only conversation-level metadata; the actual
/// messages live in `ChatMessageRecord` rows linked by `sessionId`.
///
/// Consistent with the rest of the persistence layer: branded/UUID ids stored
/// as `String`, timestamps as ISO 8601 UTC strings, no `@Relationship`.
@Model
public final class ChatSessionRecord {
    @Attribute(.unique) public var id: String

    /// `Experience.id` this conversation was scoped to (per-place chat), or nil
    /// for the global "+ button" chat.
    public var scopedExperienceId: String?
    /// Short title for the history list — derived from the first user message.
    /// Optional so a session that only ever held a greeting still saves.
    public var title: String?
    /// ISO 8601 UTC — when the conversation started.
    public var createdAt: String
    /// ISO 8601 UTC — last time a message was appended. Drives history ordering
    /// (most-recent first) so the list reads like a messaging app.
    public var updatedAt: String
    /// Cached count of user+assistant messages, for the history subtitle without
    /// fetching every message row.
    public var messageCount: Int

    public init(
        id: String,
        scopedExperienceId: String?,
        title: String?,
        createdAt: String,
        updatedAt: String,
        messageCount: Int
    ) {
        self.id = id
        self.scopedExperienceId = scopedExperienceId
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messageCount = messageCount
    }
}
