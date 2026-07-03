import Foundation
import CoreLocation

/// Slice C of the Explore-Mode redesign: a computed view model that
/// projects the existing scattered explore state (`isExploring`,
/// `exploreProgress`, `visibleExperiences`, `exploreRadiusOverlay`, …)
/// into a single object the UI overlay can bind to.
///
/// Deliberately a derived struct, not a stored enum: it does NOT replace
/// `isExploring: Bool` or `ExploreProgress`. Those keep driving the
/// pipeline and their existing tests. This wraps them so a UI overlay
/// (mode chrome, live feed, handoff card) can reason about the session
/// as a single thing.
///
/// Lifecycle:
///   .idle          → not exploring. UI shows normal map + FAB.
///   .active(...)   → exploring in progress. UI enters "Explore Mode":
///                    dim non-added pins, show single status pill, radius
///                    ring anchored at `anchorCoordinate`, live-feed sheet.
///   .handoff(...)  → scan finished with ≥1 result. UI shows the result-set
///                    card with 4 CTAs. Auto-minimizes after 10 s inactivity.
public struct ExploreSession: Equatable {

    /// Coarse-grained phase the overlay UI cares about. Collapses the
    /// finer-grained `ExploreProgress` enum (5 variants covering
    /// multiRing / progressive / synthesize / expand) into the 4 buckets
    /// a user can distinguish from a single pill.
    public enum Phase: Equatable {
        case scanning       // hitting OSM / Amap / MapKit / Foursquare
        case verifying      // (reserved for future cross-source verify)
        case synthesizing   // AIService generating the Experience batch
        case widening       // progressive ring expanded to a bigger radius
    }

    public enum State: Equatable {
        case idle
        case active(
            phase: Phase,
            radiusMeters: Double,
            anchor: CLLocationCoordinate2D,
            addedCount: Int,
            verifiedCount: Int
        )
        case handoff(HandoffResult)
        case cancelled(kept: Int)
        case failed(reason: String)

        public static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle):
                return true
            case let (.active(p1, r1, a1, ac1, vc1), .active(p2, r2, a2, ac2, vc2)):
                return p1 == p2
                    && r1 == r2
                    && a1.latitude == a2.latitude
                    && a1.longitude == a2.longitude
                    && ac1 == ac2
                    && vc1 == vc2
            case let (.handoff(h1), .handoff(h2)):
                return h1 == h2
            case let (.cancelled(k1), .cancelled(k2)):
                return k1 == k2
            case let (.failed(r1), .failed(r2)):
                return r1 == r2
            default:
                return false
            }
        }
    }

    /// Payload for the handoff card — everything it needs to render the
    /// summary + 4 CTAs without touching the ViewModel directly.
    public struct HandoffResult: Equatable {
        public let addedCount: Int
        public let verifiedCount: Int
        public let finalRadiusKm: Int
        public let cityName: String?
        public let addedIds: [String]        // for "Save as walk" & "Clear these"
        public let canExpand: Bool           // false when at max ring (100 km)

        public init(
            addedCount: Int,
            verifiedCount: Int,
            finalRadiusKm: Int,
            cityName: String?,
            addedIds: [String],
            canExpand: Bool
        ) {
            self.addedCount = addedCount
            self.verifiedCount = verifiedCount
            self.finalRadiusKm = finalRadiusKm
            self.cityName = cityName
            self.addedIds = addedIds
            self.canExpand = canExpand
        }
    }

    public let state: State

    public init(state: State) {
        self.state = state
    }

    // MARK: - Derivations

    /// True while any Explore-Mode chrome should be visible. UI gates the
    /// overlay + dim on this so it clears immediately when we exit any
    /// non-idle state.
    public var isActive: Bool {
        switch state {
        case .idle:                                            return false
        case .active, .handoff, .cancelled, .failed:           return true
        }
    }

    /// Handoff-only accessor for the result-set card binding.
    public var handoffResult: HandoffResult? {
        if case .handoff(let r) = state { return r }
        return nil
    }
}

// MARK: - Phase → single-line pill copy

public extension ExploreSession.Phase {
    /// Localization key for a scanning-in-progress pill. Keeps the copy
    /// centralized so the overlay never picks the wrong one.
    var pillLocalizationKey: String {
        switch self {
        case .scanning:     return "exploreMode.pill.scanning"
        case .verifying:    return "exploreMode.pill.verifying"
        case .synthesizing: return "exploreMode.pill.synthesizing"
        case .widening:     return "exploreMode.pill.widening"
        }
    }
}
