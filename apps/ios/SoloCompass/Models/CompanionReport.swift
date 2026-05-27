import Foundation

/// CompanionReport — a safety report filed against another user.
///
/// Mirrors `packages/core/src/companion.ts`. Keep field names in sync.

// MARK: - CompanionReportId

public struct CompanionReportId: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

// MARK: - CompanionReportReason

public enum CompanionReportReason: String, Codable, Sendable {
    case spam
    case harassment
    case inappropriate_content
    case fake_profile
    case other
}

// MARK: - CompanionReport

public struct CompanionReport: Identifiable, Codable, Sendable {
    public let id: CompanionReportId
    public let reporterId: String
    public let targetUserId: String
    public let reason: CompanionReportReason
    /// Optional free-text details.
    public let details: String?
    /// ISO 8601 UTC timestamp.
    public let createdAt: String

    public init(
        id: CompanionReportId,
        reporterId: String,
        targetUserId: String,
        reason: CompanionReportReason,
        details: String? = nil,
        createdAt: String
    ) {
        self.id = id
        self.reporterId = reporterId
        self.targetUserId = targetUserId
        self.reason = reason
        self.details = details
        self.createdAt = createdAt
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
