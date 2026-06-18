import Foundation
import SwiftData

/// SwiftData representation of one persisted message inside a saved
/// **voice-agent** session — NOT the same thing as `Models/ChatMessage`,
/// which is the social-DM concept used by `ChatService`. Audit H14 flagged
/// the naming collision; this `@Model` class keeps its on-disk name because
/// SwiftData uses the Swift class name as the SQLite entity name (renaming
/// it would orphan every existing user's stored sessions). The eventual
/// migration path is a `.custom` stage in `SoloCompassMigrationPlan` that
/// renames the entity in one cohesive change — see audit task H14.
///
/// Mirrors `RouteRecord`'s strategy: scalar fields stored natively, the
/// tool-call array stored as a JSON `Data` blob, branded/UUID ids stored as
/// `String`, and timestamps stored as ISO 8601 UTC strings.
///
/// One row maps to one `VoiceAgentSession.Message`. The link to its owning
/// conversation is a plain `sessionId` foreign key (no `@Relationship`) to
/// stay consistent with the rest of the persistence layer.
@Model
public final class ChatMessageRecord {
    @Attribute(.unique) public var id: String

    /// Foreign key → `ChatSessionRecord.id`.
    public var sessionId: String
    /// Raw value of `VoiceAgentSession.Role` (system|user|assistant|tool).
    public var role: String
    public var content: String?
    /// Position within the conversation, ascending. Lets the fetch restore the
    /// exact order regardless of how SwiftData lays rows out on disk.
    public var orderIndex: Int
    /// ISO 8601 UTC creation timestamp.
    public var createdAt: String

    /// JSON-encoded `[CodableToolCall]` — nil for non-assistant rows or
    /// assistant rows that carried no tool calls.
    public var toolCallsBlob: Data?
    /// For tool rows: the `tool_call_id` this result answers.
    public var toolCallId: String?
    /// For tool rows: the name of the tool that produced this result.
    public var toolName: String?

    public init(
        id: String,
        sessionId: String,
        role: String,
        content: String?,
        orderIndex: Int,
        createdAt: String,
        toolCallsBlob: Data?,
        toolCallId: String?,
        toolName: String?
    ) {
        self.id = id
        self.sessionId = sessionId
        self.role = role
        self.content = content
        self.orderIndex = orderIndex
        self.createdAt = createdAt
        self.toolCallsBlob = toolCallsBlob
        self.toolCallId = toolCallId
        self.toolName = toolName
    }
}

/// Codable mirror of `VoiceAgentSession.ToolCall` (which is intentionally not
/// Codable in the domain layer). Used solely to (de)serialize the tool-call
/// blob on a `ChatMessageRecord`.
public struct CodableToolCall: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let argumentsJSON: String

    public init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

// MARK: - Two-way mapping

extension ChatMessageRecord {
    /// Build a record from a session message. `sessionId` and `orderIndex` are
    /// supplied by the store since they describe the message's place in a
    /// conversation, not the message itself.
    static func fromMessage(
        _ message: VoiceAgentSession.Message,
        sessionId: String,
        orderIndex: Int,
        createdAt: String
    ) -> ChatMessageRecord {
        let toolCallsBlob: Data?
        if message.toolCalls.isEmpty {
            toolCallsBlob = nil
        } else {
            let dtos = message.toolCalls.map {
                CodableToolCall(id: $0.id, name: $0.name, argumentsJSON: $0.argumentsJSON)
            }
            toolCallsBlob = try? JSONEncoder().encode(dtos)
        }
        return ChatMessageRecord(
            id: message.id.uuidString,
            sessionId: sessionId,
            role: message.role.rawValue,
            content: message.content,
            orderIndex: orderIndex,
            createdAt: createdAt,
            toolCallsBlob: toolCallsBlob,
            toolCallId: message.toolCallId,
            toolName: message.name
        )
    }

    /// Reconstruct a domain `Message`. Falls back to a fresh UUID if the stored
    /// id isn't a valid UUID string (shouldn't happen, but keeps decode total).
    var asMessage: VoiceAgentSession.Message {
        let decodedCalls: [VoiceAgentSession.ToolCall]
        if let blob = toolCallsBlob,
           let dtos = try? JSONDecoder().decode([CodableToolCall].self, from: blob) {
            decodedCalls = dtos.map {
                VoiceAgentSession.ToolCall(id: $0.id, name: $0.name, argumentsJSON: $0.argumentsJSON)
            }
        } else {
            decodedCalls = []
        }
        return VoiceAgentSession.Message(
            id: UUID(uuidString: id) ?? UUID(),
            role: VoiceAgentSession.Role(rawValue: role) ?? .assistant,
            content: content,
            toolCalls: decodedCalls,
            toolCallId: toolCallId,
            name: toolName
        )
    }
}
