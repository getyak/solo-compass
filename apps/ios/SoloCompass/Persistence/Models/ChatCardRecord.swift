import Foundation
import SwiftData

@Model
public final class ChatCardRecord {
    @Attribute(.unique) public var id: String
    public var sessionId: String
    public var messageId: String
    public var orderIndex: Int
    public var kind: String
    public var payloadBlob: Data?
    public var createdAt: String

    public init(
        id: String,
        sessionId: String,
        messageId: String,
        orderIndex: Int,
        kind: String,
        payloadBlob: Data?,
        createdAt: String
    ) {
        self.id = id
        self.sessionId = sessionId
        self.messageId = messageId
        self.orderIndex = orderIndex
        self.kind = kind
        self.payloadBlob = payloadBlob
        self.createdAt = createdAt
    }
}
