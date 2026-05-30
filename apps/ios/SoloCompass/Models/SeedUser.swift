/// A lightweight user fixture loaded from `seed_users.json`.
///
/// Used only by `UserDirectory` for in-memory lookup during development and
/// testing — no persistence, no Supabase mapping.
public struct SeedUser: Codable, Sendable, Hashable {
    /// Short handle used as the primary key (e.g. "maya").
    public let handle: String
    /// One-line bio shown in companion UI.
    public let blurb: String
    /// Hex color string for the user's avatar chip (e.g. "#E8826A").
    public let color: String
    /// Total number of trips recorded.
    public let trips: Int
    /// Route ids this user has walked.
    public let walked: [String]
    /// Companion safety opt-in status. `nil` means unknown — the UI must show
    /// "—" rather than fabricate a value. Absent from older seed JSON, so this
    /// is decoded leniently (missing key → nil).
    public let optedIn: Bool?

    public init(
        handle: String,
        blurb: String,
        color: String,
        trips: Int,
        walked: [String],
        optedIn: Bool? = nil
    ) {
        self.handle = handle
        self.blurb = blurb
        self.color = color
        self.trips = trips
        self.walked = walked
        self.optedIn = optedIn
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.handle = try container.decode(String.self, forKey: .handle)
        self.blurb = try container.decode(String.self, forKey: .blurb)
        self.color = try container.decode(String.self, forKey: .color)
        self.trips = try container.decode(Int.self, forKey: .trips)
        self.walked = try container.decode([String].self, forKey: .walked)
        self.optedIn = try container.decodeIfPresent(Bool.self, forKey: .optedIn)
    }
}
