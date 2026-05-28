import Foundation

/// Route — an ordered sequence of experiences plus metadata describing how
/// to walk it, who has walked it, and (optionally) which companion slot is
/// attached.
///
/// Value-type only at this stage; persistence, rendering, and mutation
/// arrive in later stories. Mirrors the route shape planned for
/// `packages/core/src/route.ts` — keep field names in sync when that lands.

// MARK: - RouteId

public struct RouteId: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

// MARK: - Enums

public enum Pace: String, Codable, Sendable, CaseIterable {
    case relaxed
    case standard
    case packed
}

public enum RouteSource: String, Codable, Sendable, CaseIterable {
    case editorial
    case aiGenerated
    case userCreated
    case coCreated
}

public enum VerificationStatus: String, Codable, Sendable, CaseIterable {
    case proposed
    case walkedBy
    case verified
}

// MARK: - RouteVerification

public struct RouteVerification: Codable, Hashable, Sendable {
    public var status: VerificationStatus
    public var walkedByCount: Int
    public var walkedBy: [String]

    public init(
        status: VerificationStatus = .proposed,
        walkedByCount: Int = 0,
        walkedBy: [String] = []
    ) {
        self.status = status
        self.walkedByCount = walkedByCount
        self.walkedBy = walkedBy
    }
}

// MARK: - RouteCompanion (placeholder — filled in US-013)

public struct RouteCompanion: Codable, Hashable, Sendable {
    public init() {}
}

// MARK: - Route

public struct Route: Identifiable, Codable, Sendable {
    public let id: RouteId
    public var title: String
    public var summary: String
    /// Ordered sequence of experience identifiers that make up this route.
    public var experienceIds: [String]
    public var cityCode: String
    public var region: String
    /// Estimated total duration in minutes.
    public var estimatedDuration: Int
    public var distanceMeters: Int
    public var pace: Pace
    public var tags: [String]
    public var source: RouteSource
    public var authorId: String?
    /// Suggested start hour in the route's local timezone (0–23, fractional ok).
    public var bestStartHour: Double?
    /// Whether the route is currently inside its preferred window.
    public var bestNow: Bool
    public var verification: RouteVerification
    public var companion: RouteCompanion?

    public init(
        id: RouteId,
        title: String,
        summary: String,
        experienceIds: [String],
        cityCode: String,
        region: String,
        estimatedDuration: Int,
        distanceMeters: Int,
        pace: Pace,
        tags: [String] = [],
        source: RouteSource,
        authorId: String? = nil,
        bestStartHour: Double? = nil,
        bestNow: Bool = false,
        verification: RouteVerification = RouteVerification(),
        companion: RouteCompanion? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.experienceIds = experienceIds
        self.cityCode = cityCode
        self.region = region
        self.estimatedDuration = estimatedDuration
        self.distanceMeters = distanceMeters
        self.pace = pace
        self.tags = tags
        self.source = source
        self.authorId = authorId
        self.bestStartHour = bestStartHour
        self.bestNow = bestNow
        self.verification = verification
        self.companion = companion
    }
}
