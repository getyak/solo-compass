/// Route — an ordered sequence of experiences plus metadata describing how
/// to walk it, who has walked it, and (optionally) which companion slot is
/// attached.
///
/// Value-type only at this stage; persistence, rendering, and mutation
/// arrive in later stories. Mirrors the route shape planned for
/// `packages/core/src/route.ts` — keep field names in sync when that lands.

import Foundation

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

// MARK: - Compiled workday plan

/// One evidence warning carried through from the deterministic route compiler.
/// Warnings are retained on-device so a saved route never loses the uncertainty
/// that was visible when the traveler adopted it.
public struct CompiledRouteWarning: Codable, Hashable, Sendable {
    public var code: String
    public var featureKey: String?
    public var message: String

    public init(code: String, featureKey: String? = nil, message: String) {
        self.code = code
        self.featureKey = featureKey
        self.message = message
    }
}

/// A stop placed on an exact local-day timeline by the constraint solver.
public struct CompiledRouteStop: Codable, Hashable, Sendable, Identifiable {
    public var id: String { taskId }
    public var taskId: String
    public var taskKind: String
    public var experienceId: String
    public var title: String
    public var arrivalMinute: Int
    public var startMinute: Int
    public var endMinute: Int
    public var travelFromPreviousMinutes: Int
    public var distanceFromPreviousMeters: Int?
    public var waitMinutes: Int
    public var warnings: [CompiledRouteWarning]

    public init(
        taskId: String,
        taskKind: String,
        experienceId: String,
        title: String,
        arrivalMinute: Int,
        startMinute: Int,
        endMinute: Int,
        travelFromPreviousMinutes: Int,
        distanceFromPreviousMeters: Int? = nil,
        waitMinutes: Int,
        warnings: [CompiledRouteWarning] = []
    ) {
        self.taskId = taskId
        self.taskKind = taskKind
        self.experienceId = experienceId
        self.title = title
        self.arrivalMinute = arrivalMinute
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.travelFromPreviousMinutes = travelFromPreviousMinutes
        self.distanceFromPreviousMeters = distanceFromPreviousMeters
        self.waitMinutes = waitMinutes
        self.warnings = warnings
    }
}

/// A task-specific alternative that remains valid when its primary stop fails.
public struct CompiledRouteFallback: Codable, Hashable, Sendable, Identifiable {
    public var id: String { "\(taskId):\(experienceId)" }
    public var taskId: String
    public var primaryExperienceId: String
    public var experienceId: String
    public var title: String
    public var startMinute: Int
    public var endMinute: Int
    public var extraTravelMinutes: Int
    public var warnings: [CompiledRouteWarning]

    public init(
        taskId: String,
        primaryExperienceId: String,
        experienceId: String,
        title: String,
        startMinute: Int,
        endMinute: Int,
        extraTravelMinutes: Int,
        warnings: [CompiledRouteWarning] = []
    ) {
        self.taskId = taskId
        self.primaryExperienceId = primaryExperienceId
        self.experienceId = experienceId
        self.title = title
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.extraTravelMinutes = extraTravelMinutes
        self.warnings = warnings
    }
}

/// Persisted output of the server-side time-window solver. The LLM may explain
/// this plan, but it never chooses stops, invents opening windows, or edits the
/// timeline. `evidenceCoverage` is deliberately stored with the schedule.
public struct CompiledWorkdayPlan: Codable, Hashable, Sendable {
    public var localDate: String
    public var startsAtMinute: Int
    public var endsAtMinute: Int
    public var totalTravelMinutes: Int
    public var totalWaitMinutes: Int
    public var evidenceCoverage: String
    public var refreshScheduled: Bool
    public var cacheStatus: String
    public var stops: [CompiledRouteStop]
    public var fallbacks: [CompiledRouteFallback]
    public var warnings: [CompiledRouteWarning]

    public init(
        localDate: String,
        startsAtMinute: Int,
        endsAtMinute: Int,
        totalTravelMinutes: Int,
        totalWaitMinutes: Int,
        evidenceCoverage: String,
        refreshScheduled: Bool,
        cacheStatus: String,
        stops: [CompiledRouteStop],
        fallbacks: [CompiledRouteFallback] = [],
        warnings: [CompiledRouteWarning] = []
    ) {
        self.localDate = localDate
        self.startsAtMinute = startsAtMinute
        self.endsAtMinute = endsAtMinute
        self.totalTravelMinutes = totalTravelMinutes
        self.totalWaitMinutes = totalWaitMinutes
        self.evidenceCoverage = evidenceCoverage
        self.refreshScheduled = refreshScheduled
        self.cacheStatus = cacheStatus
        self.stops = stops
        self.fallbacks = fallbacks
        self.warnings = warnings
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
    /// Short human reason explaining why this route is surfaced right now,
    /// shown as the "此刻理由" banner in now-context (e.g. "日落將至 · 30 分鐘後是最佳光線").
    public var reasonNow: String?
    public var verification: RouteVerification
    public var companion: RouteCompanion?
    /// Exact, evidence-backed schedule for routes produced by the workday
    /// compiler. Nil for editorial, manual, and ordinary walk routes.
    public var compiledPlan: CompiledWorkdayPlan?

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
        reasonNow: String? = nil,
        verification: RouteVerification = RouteVerification(),
        companion: RouteCompanion? = nil,
        compiledPlan: CompiledWorkdayPlan? = nil
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
        self.reasonNow = reasonNow
        self.verification = verification
        self.companion = companion
        self.compiledPlan = compiledPlan
    }

    // MARK: - Runtime now-window check

    /// How many hours after `bestStartHour` the route still counts as "best now".
    /// Sunset/golden-hour style windows read as ~3h; tune here if needed.
    private static let nowWindowHours: Double = 3

    /// Runtime "best right now" check derived from `bestStartHour`, mirroring the
    /// intent of `Experience.isBestNow(at:)`. When a `bestStartHour` is set, the
    /// route is best-now while the current hour falls inside
    /// `[bestStartHour, bestStartHour + nowWindowHours)` (wrapping past midnight).
    /// Falls back to the static `bestNow` field when no `bestStartHour` is present
    /// — so seed data that only carries the boolean still behaves as before.
    public func isBestNow(at date: Date = Date()) -> Bool {
        guard let start = bestStartHour else { return bestNow }
        let hour = Double(Calendar.current.component(.hour, from: date))
        let end = start + Self.nowWindowHours
        if end <= 24 {
            return hour >= start && hour < end
        }
        // Window wraps past midnight (e.g. start 22 → end 25 ⇒ 22..24 or 0..1).
        return hour >= start || hour < (end - 24)
    }
}
