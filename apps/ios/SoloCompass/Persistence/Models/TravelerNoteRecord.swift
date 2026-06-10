import Foundation
import SwiftData

// MARK: - Domain value

/// A traveler-contributed note attached to an experience — the "AI + travelers
/// co-write" layer. A note is either a lived `experience` ("Tuesday afternoon was
/// dead quiet") or a `correction` proposal folded into the feed. Kept as a plain
/// value so views never touch the `@Model` directly; the store maps both ways
/// (`TravelerNoteRecord.asValue` / `.init(from:)`).
public struct TravelerNote: Identifiable, Hashable, Sendable {
    /// What kind of contribution this is. Drives the small tag next to the author.
    public enum Kind: String, Codable, Hashable, Sendable {
        case experience  // a lived observation
        case correction  // a fix to a canonical field
    }

    public let id: String
    public let experienceId: String
    /// Single-glyph avatar initial (e.g. "J"). For the current user this is "你".
    public let authorInitial: String
    /// Hex string for the avatar disc, e.g. "#9B6A3A". `nil` → use the accent.
    public let authorColor: String?
    public let text: String
    public let kind: Kind
    /// ISO 8601 UTC creation timestamp, e.g. "2026-06-08T06:00:00Z".
    public let createdAt: String
    /// How many other travelers have confirmed this note.
    public var confirms: Int
    /// Whether the AI has folded this note into the canonical description.
    public let aiAdopted: Bool
    /// True for notes the current user authored (no "confirm" affordance shown).
    public let isMine: Bool

    public init(
        id: String,
        experienceId: String,
        authorInitial: String,
        authorColor: String?,
        text: String,
        kind: Kind,
        createdAt: String,
        confirms: Int,
        aiAdopted: Bool,
        isMine: Bool
    ) {
        self.id = id
        self.experienceId = experienceId
        self.authorInitial = authorInitial
        self.authorColor = authorColor
        self.text = text
        self.kind = kind
        self.createdAt = createdAt
        self.confirms = confirms
        self.aiAdopted = aiAdopted
        self.isMine = isMine
    }
}

// MARK: - Persistence record

/// SwiftData representation of one traveler note. Scalar-only fields stored
/// natively, `kind` stored as its raw string, timestamps as ISO 8601 UTC —
/// consistent with `ChatMessageRecord` / `RouteRecord`. The link to its place is
/// a plain `experienceId` foreign key (no `@Relationship`).
@Model
public final class TravelerNoteRecord {
    @Attribute(.unique) public var id: String

    /// Foreign key → `Experience.id`.
    public var experienceId: String
    public var authorInitial: String
    public var authorColor: String?
    public var text: String
    /// Raw value of `TravelerNote.Kind` (experience|correction).
    public var kind: String
    /// ISO 8601 UTC creation timestamp.
    public var createdAt: String
    public var confirms: Int
    public var aiAdopted: Bool
    public var isMine: Bool

    public init(
        id: String,
        experienceId: String,
        authorInitial: String,
        authorColor: String?,
        text: String,
        kind: String,
        createdAt: String,
        confirms: Int,
        aiAdopted: Bool,
        isMine: Bool
    ) {
        self.id = id
        self.experienceId = experienceId
        self.authorInitial = authorInitial
        self.authorColor = authorColor
        self.text = text
        self.kind = kind
        self.createdAt = createdAt
        self.confirms = confirms
        self.aiAdopted = aiAdopted
        self.isMine = isMine
    }
}

// MARK: - Two-way mapping

extension TravelerNoteRecord {
    public convenience init(from note: TravelerNote) {
        self.init(
            id: note.id,
            experienceId: note.experienceId,
            authorInitial: note.authorInitial,
            authorColor: note.authorColor,
            text: note.text,
            kind: note.kind.rawValue,
            createdAt: note.createdAt,
            confirms: note.confirms,
            aiAdopted: note.aiAdopted,
            isMine: note.isMine
        )
    }

    public var asValue: TravelerNote {
        TravelerNote(
            id: id,
            experienceId: experienceId,
            authorInitial: authorInitial,
            authorColor: authorColor,
            text: text,
            kind: TravelerNote.Kind(rawValue: kind) ?? .experience,
            createdAt: createdAt,
            confirms: confirms,
            aiAdopted: aiAdopted,
            isMine: isMine
        )
    }
}
