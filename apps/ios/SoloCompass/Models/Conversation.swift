import Foundation

/// Conversation — a messaging thread opened after a CompanionRequest is accepted,
/// or a group chat formed around a Route companion slot.
///
/// Mirrors `packages/core/src/companion.ts`. Keep field names in sync.

// MARK: - ConversationId

public struct ConversationId: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

// MARK: - ConversationType

/// Discriminates between a one-on-one companion thread and a route-anchored group chat.
public enum ConversationType: String, Codable, Sendable, CaseIterable {
    /// A private thread between two users following an accepted CompanionRequest.
    case oneOnOne
    /// A group chat anchored to a specific Route companion slot.
    case groupRoute
}

// MARK: - Conversation

public struct Conversation: Identifiable, Codable, Sendable {
    public let id: ConversationId
    public let requestId: CompanionRequestId
    public let participantIds: [String]
    /// Discriminates one-on-one vs. route group chat. Defaults to `.oneOnOne`.
    public let type: ConversationType
    /// Non-nil when `type == .groupRoute`; the Route this group chat is anchored to.
    public let routeId: String?
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
        type: ConversationType = .oneOnOne,
        routeId: String? = nil,
        lastMessageAt: String? = nil,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.requestId = requestId
        self.participantIds = participantIds
        self.type = type
        self.routeId = routeId
        self.lastMessageAt = lastMessageAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // Custom decoder: `type` defaults to `.oneOnOne` when absent (legacy payloads).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(ConversationId.self, forKey: .id)
        requestId = try c.decode(CompanionRequestId.self, forKey: .requestId)
        participantIds = try c.decode([String].self, forKey: .participantIds)
        type = try c.decodeIfPresent(ConversationType.self, forKey: .type) ?? .oneOnOne
        routeId = try c.decodeIfPresent(String.self, forKey: .routeId)
        lastMessageAt = try c.decodeIfPresent(String.self, forKey: .lastMessageAt)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
    }
}

// MARK: - Preview samples

extension Conversation {
    static let sample = Conversation(
        id: ConversationId(rawValue: "conv_preview"),
        requestId: CompanionRequestId(rawValue: "creq_preview"),
        participantIds: ["user_preview", "user_preview_b"],
        lastMessageAt: "2026-02-05T14:30:00Z",
        createdAt: "2026-02-02T09:00:00Z",
        updatedAt: "2026-02-05T14:30:00Z"
    )

    static let groupRouteSample = Conversation(
        id: ConversationId(rawValue: "conv_group_preview"),
        requestId: CompanionRequestId(rawValue: "creq_group_preview"),
        participantIds: ["user_preview", "user_preview_b", "user_preview_c"],
        type: .groupRoute,
        routeId: "route_preview",
        lastMessageAt: "2026-02-06T10:00:00Z",
        createdAt: "2026-02-06T09:00:00Z",
        updatedAt: "2026-02-06T10:00:00Z"
    )
}
