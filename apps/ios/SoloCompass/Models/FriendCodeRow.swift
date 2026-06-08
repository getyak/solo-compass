/// FriendCodeRow — a backend `friend_codes` row mapping a shareable code to a user.
///
/// US-013: a user hands out a short, human-readable code (`SOLO-XXXX-XXXX`,
/// excluding the visually-ambiguous `0/O/1/I`) so others can add them without
/// leaking the raw UserId. Codes are *rotatable*: issuing a new one stamps the
/// previous row's `revoked_at`, leaving an auditable trail while only the
/// newest, non-revoked row resolves.
///
/// The active code is lazily generated on first open of the AddFriendSheet.

import Foundation

// MARK: - FriendCodeId

/// Strongly-typed identifier for a friend_codes row. Format: `fcode_<random_id>`.
public struct FriendCodeId: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

// MARK: - FriendCodeRow

/// A persisted code → user mapping. `revokedAt == nil` means the code is active.
public struct FriendCodeRow: Identifiable, Codable, Sendable {
    public let id: FriendCodeId
    /// The user this code resolves to.
    public let ownerId: String
    /// The shareable code value, e.g. "SOLO-7K2F-9XQR".
    public let code: FriendCode
    /// ISO 8601 UTC when this code was revoked (rotated out). `nil` = still active.
    public let revokedAt: String?
    /// ISO 8601 UTC timestamp.
    public let createdAt: String
    /// ISO 8601 UTC timestamp.
    public let updatedAt: String

    public init(
        id: FriendCodeId,
        ownerId: String,
        code: FriendCode,
        revokedAt: String? = nil,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.ownerId = ownerId
        self.code = code
        self.revokedAt = revokedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // Custom decoder: `revokedAt` is optional (only set once rotated out).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(FriendCodeId.self, forKey: .id)
        ownerId = try c.decode(String.self, forKey: .ownerId)
        code = try c.decode(FriendCode.self, forKey: .code)
        revokedAt = try c.decodeIfPresent(String.self, forKey: .revokedAt)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
    }

    /// Whether this row is the currently-active (non-revoked) code.
    public var isActive: Bool { revokedAt == nil }
}

// MARK: - Code generation

extension FriendCode {
    /// Alphabet excluding visually-ambiguous glyphs (`0/O/1/I`) so a code is
    /// unambiguous when read aloud or hand-typed.
    static let unambiguousAlphabet = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")

    /// Generate a fresh `SOLO-XXXX-XXXX` code from the unambiguous alphabet.
    /// Two 4-char groups → ~32^8 ≈ 1.1e12 space; collision handling is the
    /// backend's unique-index job.
    public static func generate() -> FriendCode {
        func group() -> String {
            String((0..<4).map { _ in unambiguousAlphabet.randomElement() ?? "X" })
        }
        return FriendCode(rawValue: "SOLO-\(group())-\(group())")
    }

    /// US-014: validate a hand-typed/scanned code against the canonical
    /// `SOLO-XXXX-XXXX` shape (two 4-char groups from the unambiguous alphabet).
    /// The input is expected pre-normalised (trimmed + uppercased) by the caller.
    public static func isValidFormat(_ raw: String) -> Bool {
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "SOLO" else { return false }
        let allowed = Set(unambiguousAlphabet)
        return parts[1].count == 4 && parts[2].count == 4
            && parts[1].allSatisfy(allowed.contains)
            && parts[2].allSatisfy(allowed.contains)
    }
}
