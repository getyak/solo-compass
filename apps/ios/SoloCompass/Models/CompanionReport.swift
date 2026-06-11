/// CompanionReport — a safety report filed against another user.
///
/// Mirrors `packages/core/src/companion.ts`. Keep field names in sync.

// MARK: - CompanionReportId

/// Strongly-typed identifier for a companion safety report, preventing raw-string ID mix-ups.
public struct CompanionReportId: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

// MARK: - CompanionReportReason

/// The category a user selects when reporting another user for unsafe or unwanted behavior.
public enum CompanionReportReason: String, Codable, Sendable {
    case spam
    case harassment
    case inappropriate_content
    case fake_profile
    case other
}

// MARK: - CompanionReport

/// A safety report one user files against another to flag abuse for moderation.
public struct CompanionReport: Identifiable, Codable, Sendable {
    public let id: CompanionReportId
    public let reporterId: String
    public let targetUserId: String
    public let reason: CompanionReportReason
    /// Optional free-text details.
    public let details: String?
    /// ISO 8601 UTC timestamp.
    public let createdAt: String
    /// ISO 8601 UTC timestamp when a moderator handled this report. nil = open.
    public let resolvedAt: String?
    /// The moderator/admin user id that resolved this report.
    public let resolvedBy: String?

    public init(
        id: CompanionReportId,
        reporterId: String,
        targetUserId: String,
        reason: CompanionReportReason,
        details: String? = nil,
        createdAt: String,
        resolvedAt: String? = nil,
        resolvedBy: String? = nil
    ) {
        self.id = id
        self.reporterId = reporterId
        self.targetUserId = targetUserId
        self.reason = reason
        self.details = details
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.resolvedBy = resolvedBy
    }

    // Custom Codable: PostgREST returns snake_case columns, and older rows
    // predate the resolution fields. Decode tolerates both camelCase and
    // snake_case keys (missing → nil / open). Encode emits camelCase (the
    // shape the rest of the app and the TS core type use).
    private enum CodingKeys: String, CodingKey {
        case id
        case reporterId, reporter_id
        case targetUserId, target_user_id
        case reason
        case details
        case createdAt, created_at
        case resolvedAt, resolved_at
        case resolvedBy, resolved_by
    }

    /// First non-nil string across the given keys (camelCase then snake_case).
    private static func firstString(
        _ c: KeyedDecodingContainer<CodingKeys>,
        _ keys: [CodingKeys]
    ) -> String? {
        for key in keys {
            // `try?` flattens the `String??` from decodeIfPresent to `String?`.
            if let v = try? c.decodeIfPresent(String.self, forKey: key) { return v }
        }
        return nil
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(CompanionReportId.self, forKey: .id)
        self.reporterId = Self.firstString(c, [.reporterId, .reporter_id]) ?? ""
        self.targetUserId = Self.firstString(c, [.targetUserId, .target_user_id]) ?? ""
        self.reason = (try? c.decode(CompanionReportReason.self, forKey: .reason)) ?? .other
        self.details = Self.firstString(c, [.details])
        self.createdAt = Self.firstString(c, [.createdAt, .created_at]) ?? ""
        self.resolvedAt = Self.firstString(c, [.resolvedAt, .resolved_at])
        self.resolvedBy = Self.firstString(c, [.resolvedBy, .resolved_by])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(reporterId, forKey: .reporterId)
        try c.encode(targetUserId, forKey: .targetUserId)
        try c.encode(reason, forKey: .reason)
        try c.encodeIfPresent(details, forKey: .details)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(resolvedAt, forKey: .resolvedAt)
        try c.encodeIfPresent(resolvedBy, forKey: .resolvedBy)
    }
}

// MARK: - Preview sample

extension CompanionReport {
    static let sample = CompanionReport(
        id: CompanionReportId(rawValue: "crep_preview"),
        reporterId: "user_preview",
        targetUserId: "user_preview_bad",
        reason: .spam,
        details: "Sent multiple unsolicited messages.",
        createdAt: "2026-03-01T08:00:00Z"
    )
}
