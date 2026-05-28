import Foundation

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

    public init(
        handle: String,
        blurb: String,
        color: String,
        trips: Int,
        walked: [String]
    ) {
        self.handle = handle
        self.blurb = blurb
        self.color = color
        self.trips = trips
        self.walked = walked
    }
}
