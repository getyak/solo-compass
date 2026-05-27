import Foundation

/// CompanionRequest — a request from one user to another to travel together.
///
/// Mirrors `packages/core/src/companion.ts`. Keep field names in sync.

// MARK: - CompanionRequestId

public struct CompanionRequestId: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

// MARK: - CompanionRequestStatus

public enum CompanionRequestStatus: String, Codable, Sendable {
    case pending
    case accepted
    case declined
    case withdrawn
}

// MARK: - CompanionRequest

public struct CompanionRequest: Identifiable, Codable, Sendable {
    public let id: CompanionRequestId
    public let postId: CompanionPostId
    public let requesterId: String
    public let recipientId: String
    public let status: CompanionRequestStatus
    /// Optional introductory note from the requester.
    public let note: String?
    /// ISO 8601 UTC timestamp.
    public let createdAt: String
    /// ISO 8601 UTC timestamp.
    public let updatedAt: String

    public init(
        id: CompanionRequestId,
        postId: CompanionPostId,
        requesterId: String,
        recipientId: String,
        status: CompanionRequestStatus,
        note: String? = nil,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.postId = postId
        self.requesterId = requesterId
        self.recipientId = recipientId
        self.status = status
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Preview sample

extension CompanionRequest {
    static let sample = CompanionRequest(
        id: CompanionRequestId(rawValue: "creq_preview"),
        postId: CompanionPostId(rawValue: "cpost_preview"),
        requesterId: "user_preview_b",
        recipientId: "user_preview",
        status: .pending,
        note: "Hey! I'll also be in Tokyo then. Would love to explore together.",
        createdAt: "2026-02-01T10:00:00Z",
        updatedAt: "2026-02-01T10:00:00Z"
    )
}
