
/// CompanionBlock — a block record between two users (US-014).
///
/// Mirrors the `companion_blocks` table in 0003_companion.sql.
/// The blocker writes the record; the Edge Function excludes both sides
/// from discovery queries.

public struct CompanionBlock: Codable, Sendable {
    public let blockerId: String
    public let blockedId: String
    /// ISO 8601 UTC timestamp.
    public let createdAt: String

    public init(blockerId: String, blockedId: String, createdAt: String) {
        self.blockerId = blockerId
        self.blockedId = blockedId
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case blockerId = "blocker_id"
        case blockedId = "blocked_id"
        case createdAt = "created_at"
    }
}
