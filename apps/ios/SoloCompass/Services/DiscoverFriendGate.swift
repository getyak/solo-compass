import Foundation

/// Anti-abuse guardrails for adding a friend straight from an anonymized
/// Discover post (US-016).
///
/// A `discover`-sourced friend request is the lowest-trust path into the
/// friendship graph: the requester and recipient have never interacted, so it
/// is the most attractive vector for spam / mass-adds. Two pure checks gate it:
///
/// 1. **Reporter-weight floor** — the *post author's* `reporter_weight` must be
///    ≥ `0.3` (the same `companionReporterWeightThreshold` used to gate
///    discovery visibility). A heavily-reported author can't be befriended.
/// 2. **Rate limit** — at most `maxPerWindow` discover-adds inside a rolling
///    `window`. Stops a single user from spraying requests across the feed.
///
/// Both are *frontend prechecks*: they fail fast with a friendly message before
/// any network write. The backend (`friend_requests` RLS + the request Edge
/// Function) re-enforces both rules as the canonical trust boundary, so a
/// patched client can never bypass them — the precheck is purely UX.
///
/// Pure value type (no I/O) so the rules are unit-testable in isolation.
public struct DiscoverFriendGate: Sendable {
    /// Minimum author reporter_weight to allow a discover-sourced add.
    /// Shares the discovery-visibility threshold so the two stay in lock-step.
    public static let reporterWeightFloor = companionReporterWeightThreshold

    /// Max discover-adds allowed inside `window`.
    public let maxPerWindow: Int
    /// Rolling window length for the rate limit.
    public let window: TimeInterval

    public init(maxPerWindow: Int = 10, window: TimeInterval = 3600) {
        self.maxPerWindow = maxPerWindow
        self.window = window
    }

    /// Why a discover-add was refused by the frontend precheck.
    public enum Denial: Equatable, Sendable {
        /// The post author's reporter_weight is below the floor.
        case lowReporterWeight
        /// The user has hit the rolling-window rate limit.
        case rateLimited
    }

    /// Evaluate the precheck.
    ///
    /// - Parameters:
    ///   - reporterWeight: the post author's trust weight (0.0–1.0).
    ///   - recentAddTimestamps: timestamps of the user's prior discover-adds.
    ///   - now: the evaluation instant (injected for deterministic tests).
    /// - Returns: `nil` when the add is allowed, or the `Denial` reason.
    public func evaluate(
        reporterWeight: Double,
        recentAddTimestamps: [Date],
        now: Date = Date()
    ) -> Denial? {
        if reporterWeight < Self.reporterWeightFloor {
            return .lowReporterWeight
        }
        let cutoff = now.addingTimeInterval(-window)
        let withinWindow = recentAddTimestamps.filter { $0 > cutoff }.count
        if withinWindow >= maxPerWindow {
            return .rateLimited
        }
        return nil
    }
}
