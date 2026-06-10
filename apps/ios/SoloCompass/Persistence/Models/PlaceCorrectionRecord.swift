import Foundation
import SwiftData

// MARK: - Domain value

/// A pending correction proposal for one canonical field of an experience —
/// shown as an amber card above the prose ("营业时间: 09:00 → 09:30"). When enough
/// travelers confirm, the AI folds it into the record. Stored as a plain value;
/// the store maps both ways (`PlaceCorrectionRecord.asValue` / `.init(from:)`).
public struct PlaceCorrection: Identifiable, Hashable, Sendable {
    /// Lifecycle of a proposal. `pending` shows the card; `accepted`/`dismissed`
    /// remove it (a one-way action, persisted so it stays resolved across launches).
    public enum Status: String, Codable, Hashable, Sendable {
        case pending
        case accepted
        case dismissed
    }

    public let id: String
    public let experienceId: String
    /// The field being corrected, e.g. "营业时间".
    public let field: String
    /// The current (struck-through) value, e.g. "09:00 – 21:00".
    public let oldVal: String
    /// The proposed value, e.g. "09:30 – 21:00".
    public let newVal: String
    /// Provenance line, e.g. "3 位旅人在过去 2 周提到".
    public let sourceNote: String
    public var status: Status
    /// ISO 8601 UTC creation timestamp, e.g. "2026-06-08T06:00:00Z".
    public let createdAt: String

    public init(
        id: String,
        experienceId: String,
        field: String,
        oldVal: String,
        newVal: String,
        sourceNote: String,
        status: Status,
        createdAt: String
    ) {
        self.id = id
        self.experienceId = experienceId
        self.field = field
        self.oldVal = oldVal
        self.newVal = newVal
        self.sourceNote = sourceNote
        self.status = status
        self.createdAt = createdAt
    }
}

// MARK: - Persistence record

/// SwiftData representation of one correction proposal. Scalar-only, `status`
/// stored as its raw string, timestamps ISO 8601 UTC — consistent with the rest
/// of the persistence layer. Linked to its place by a plain `experienceId`.
@Model
public final class PlaceCorrectionRecord {
    @Attribute(.unique) public var id: String

    /// Foreign key → `Experience.id`.
    public var experienceId: String
    public var field: String
    public var oldVal: String
    public var newVal: String
    public var sourceNote: String
    /// Raw value of `PlaceCorrection.Status` (pending|accepted|dismissed).
    public var status: String
    /// ISO 8601 UTC creation timestamp.
    public var createdAt: String

    public init(
        id: String,
        experienceId: String,
        field: String,
        oldVal: String,
        newVal: String,
        sourceNote: String,
        status: String,
        createdAt: String
    ) {
        self.id = id
        self.experienceId = experienceId
        self.field = field
        self.oldVal = oldVal
        self.newVal = newVal
        self.sourceNote = sourceNote
        self.status = status
        self.createdAt = createdAt
    }
}

// MARK: - Two-way mapping

extension PlaceCorrectionRecord {
    public convenience init(from correction: PlaceCorrection) {
        self.init(
            id: correction.id,
            experienceId: correction.experienceId,
            field: correction.field,
            oldVal: correction.oldVal,
            newVal: correction.newVal,
            sourceNote: correction.sourceNote,
            status: correction.status.rawValue,
            createdAt: correction.createdAt
        )
    }

    public var asValue: PlaceCorrection {
        PlaceCorrection(
            id: id,
            experienceId: experienceId,
            field: field,
            oldVal: oldVal,
            newVal: newVal,
            sourceNote: sourceNote,
            status: PlaceCorrection.Status(rawValue: status) ?? .pending,
            createdAt: createdAt
        )
    }
}
