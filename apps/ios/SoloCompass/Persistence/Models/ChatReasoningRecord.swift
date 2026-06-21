import Foundation
import SwiftData

@Model
public final class ChatReasoningRecord {
    @Attribute(.unique) public var id: String
    public var sessionId: String
    public var messageId: String
    public var summary: String
    public var detailBlob: Data?
    public var createdAt: String

    public init(
        id: String,
        sessionId: String,
        messageId: String,
        summary: String,
        detailBlob: Data?,
        createdAt: String
    ) {
        self.id = id
        self.sessionId = sessionId
        self.messageId = messageId
        self.summary = summary
        self.detailBlob = detailBlob
        self.createdAt = createdAt
    }
}
