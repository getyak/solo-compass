
/// Route — an ordered sequence of experiences plus metadata describing how
/// to walk it, who has walked it, and (optionally) which companion slot is
/// attached.
///
/// Value-type only at this stage; persistence, rendering, and mutation
/// arrive in later stories. Mirrors the route shape planned for
/// `packages/core/src/route.ts` — keep field names in sync when that lands.

// MARK: - RouteId

/// Strongly-typed identifier for a Route, preventing raw-string ID mix-ups.
public struct RouteId: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

// MARK: - Enums

/// How leisurely or intense a route's pace is, from relaxed strolls to packed itineraries.
public enum Pace: String, Codable, Sendable, CaseIterable {
    case relaxed
    case standard
    case packed
}

/// Where a route originated — editorial curation, AI generation, a user, or co-creation.
public enum RouteSource: String, Codable, Sendable, CaseIterable {
    case editorial
    case aiGenerated
    case userCreated
    case coCreated
}

/// How much real-world walking has validated a route, from merely proposed to fully verified.
public enum VerificationStatus: String, Codable, Sendable, CaseIterable {
    case proposed
    case walkedBy
    case verified
}

// MARK: - RouteVerification

/// Tracks who has walked a route and its resulting verification status.
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

// MARK: - Companion enums

/// Lifecycle of a route's companion slot — whether it is open to joiners, forming, closed, or completed.
public enum CompanionStatus: String, Codable, Sendable, CaseIterable {
    case open
    case forming
    case closed
    case completed
}

/// A companion group's desired walking pace, including a flexible option that defers to the group.
public enum PacePreference: String, Codable, Sendable, CaseIterable {
    case relaxed
    case standard
    case packed
    case flexible
}

/// Visibility for a route's companion slot.
///
/// Named `RouteCompanionVisibility` to avoid collision with the existing
/// `CompanionVisibility` enum in `CompanionProfile.swift`, which describes
/// a user's overall discoverability (off/itinerary_only/nearby_and_itinerary).
public enum RouteCompanionVisibility: String, Codable, Sendable, CaseIterable {
    case `public`
    case linkOnly
}

/// State of a request to join a route's companion slot, from pending through accepted, declined, or withdrawn.
public enum JoinRequestStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case accepted
    case declined
    case withdrawn
}

// MARK: - JoinRequestId (branded)

/// Strongly-typed identifier for a JoinRequest, preventing raw-string ID mix-ups.
public struct JoinRequestId: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

// MARK: - JoinRequest

/// A user's request to join a route's companion group, with their message and current status.
public struct JoinRequest: Codable, Hashable, Sendable, Identifiable {
    public let id: JoinRequestId
    public var requesterId: String
    public var message: String
    public var status: JoinRequestStatus
    /// ISO 8601 UTC timestamp.
    public var createdAt: String

    public init(
        id: JoinRequestId,
        requesterId: String,
        message: String,
        status: JoinRequestStatus = .pending,
        createdAt: String
    ) {
        self.id = id
        self.requesterId = requesterId
        self.message = message
        self.status = status
        self.createdAt = createdAt
    }
}

// MARK: - DepartureWindow

/// The date range and time hint during which a companion group plans to set out.
public struct DepartureWindow: Codable, Hashable, Sendable {
    /// ISO 8601 date (YYYY-MM-DD) for the window start.
    public var from: String
    /// ISO 8601 date (YYYY-MM-DD) for the window end.
    public var to: String
    /// Free-form local time hint, e.g. "morning", "18:30".
    public var time: String

    public init(startDate: String, to: String, time: String) {
        self.from = startDate
        self.to = to
        self.time = time
    }
}

// MARK: - RouteCompanion

/// The companion slot attached to a route — its host, members, join requests, and departure plans.
public struct RouteCompanion: Codable, Hashable, Sendable {
    public var status: CompanionStatus
    public var hostId: String
    public var departureWindow: DepartureWindow
    public var departureLabel: String
    public var pacePreference: PacePreference
    public var maxMembers: Int
    public var confirmedMembers: [String]
    public var joinRequests: [JoinRequest]
    public var visibility: RouteCompanionVisibility
    public var groupConversationId: String?
    public var hostMessage: String?

    public init(
        status: CompanionStatus = .open,
        hostId: String,
        departureWindow: DepartureWindow,
        departureLabel: String,
        pacePreference: PacePreference = .standard,
        maxMembers: Int,
        confirmedMembers: [String] = [],
        joinRequests: [JoinRequest] = [],
        visibility: RouteCompanionVisibility = .public,
        groupConversationId: String? = nil,
        hostMessage: String? = nil
    ) {
        self.status = status
        self.hostId = hostId
        self.departureWindow = departureWindow
        self.departureLabel = departureLabel
        self.pacePreference = pacePreference
        self.maxMembers = maxMembers
        self.confirmedMembers = confirmedMembers
        self.joinRequests = joinRequests
        self.visibility = visibility
        self.groupConversationId = groupConversationId
        self.hostMessage = hostMessage
    }

    /// Convenience no-arg init used in tests and previews.
    public init() {
        self.status = .open
        self.hostId = ""
        self.departureWindow = DepartureWindow(startDate: "", to: "", time: "")
        self.departureLabel = ""
        self.pacePreference = .standard
        self.maxMembers = 4
        self.confirmedMembers = []
        self.joinRequests = []
        self.visibility = .public
        self.groupConversationId = nil
        self.hostMessage = nil
    }
}

// MARK: - Route

/// An ordered sequence of experiences to walk, with pacing, verification, and an optional companion slot.
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
