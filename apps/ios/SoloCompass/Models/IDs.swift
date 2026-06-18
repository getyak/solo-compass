import Foundation

// MARK: - Branded IDs (audit H12)
//
// The codebase already has 11 branded ID structs (RouteId, ConversationId,
// CompanionPostId, FriendCodeId, FriendRequestId, JoinRequestId,
// CompanionReportId, CompanionProfileId, ChatMessageId, FriendshipId,
// CompanionRequestId) but Experience.id, ChatAttachment.id, the various
// `experienceIds: [String]`, `authorId: String?`, and `participantIds:
// [String]` collections still pass raw `String`. CLAUDE.md mandates
// branded types for all IDs.
//
// Migrating Experience.id directly would touch ~91 call sites + the
// Codable wire format + the SwiftData ExperienceRecord persistence
// schema. Rather than blocking a whole release on that, we introduce the
// brand here as a typed wrapper so:
//   - New code can declare `let id: ExperienceId` instead of `let id: String`
//   - Helpers can opt into the brand (`func favoriteExperience(_ id: ExperienceId)`)
//   - Future schema/parity work (Batch 4) flips Experience.id over without
//     re-introducing the type
//
// `RawRepresentable`-based brands are codable-transparent (encoded as the
// raw String), so adopting them later in Experience.id is a no-op on the
// JSON wire format.

/// Strongly-typed identifier for an Experience.
public struct ExperienceId: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// Strongly-typed identifier for an authenticated user (Supabase auth uid
/// or local device-anon uid emitted by `DeviceIdentityService`). Used for
/// `Route.authorId`, `Conversation.participantIds`, friendship endpoints, etc.
public struct UserId: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public extension ExperienceId {
    /// Convenience for constructing from string literals at call sites that
    /// already have a raw ID in hand (e.g. seed JSON, deep-link payloads).
    init(_ rawValue: String) { self.init(rawValue: rawValue) }
}

public extension UserId {
    init(_ rawValue: String) { self.init(rawValue: rawValue) }
}
