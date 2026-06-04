import CoreLocation

/// Pure resolver for the single experience surfaced in the BottomInfoSheet's
/// peek summary card ("此刻最值得去").
///
/// Extracted as a free-standing, side-effect-free function so the selection
/// logic is unit-testable without standing up a SwiftUI graph. `CompassMapView`
/// calls `resolve` from its `peekExperience` computed property.
///
/// Precedence:
///  1. The first AI smart-pick id (`smartPickIds.first`) that is present in
///     `experiences` — the AI's top recommendation, when it is currently visible.
///  2. Otherwise the experience nearest the reference coordinate.
///  3. `nil` when `experiences` is empty.
enum PeekPickResolver {
    /// Resolve the peek experience from the visible set.
    ///
    /// - Parameters:
    ///   - experiences: the currently visible experiences.
    ///   - smartPickIds: AI-ranked top pick ids (highest priority first).
    ///   - referenceCoordinate: user location or map center; used for the
    ///     nearest-fallback. When `nil`, the first visible experience is returned
    ///     as the fallback (no distance ordering is possible).
    /// - Returns: the experience to feature in the peek card, or `nil` if none.
    static func resolve(
        experiences: [Experience],
        smartPickIds: [String],
        referenceCoordinate: CLLocationCoordinate2D?
    ) -> Experience? {
        guard !experiences.isEmpty else { return nil }

        // 1. Prefer the first smart pick that is actually visible.
        for id in smartPickIds {
            if let match = experiences.first(where: { $0.id == id }) {
                return match
            }
        }

        // 2. Fallback: nearest to the reference coordinate.
        guard let ref = referenceCoordinate else {
            return experiences.first
        }
        // Allocate the reference CLLocation once, outside the comparison closure.
        let refLocation = CLLocation(latitude: ref.latitude, longitude: ref.longitude)
        return experiences.min(by: { lhs, rhs in
            distance(from: refLocation, to: lhs) < distance(from: refLocation, to: rhs)
        })
    }

    /// Whether the resolved peek experience is the AI smart pick (drives the gold
    /// gradient + AI Pick tag). True only when the resolution returned a
    /// smart-pick id.
    static func isSmartPick(
        resolved: Experience?,
        smartPickIds: [String]
    ) -> Bool {
        guard let resolved else { return false }
        return smartPickIds.contains(resolved.id)
    }

    /// Great-circle distance in meters; missing coordinates sort last.
    private static func distance(from origin: CLLocation, to experience: Experience) -> CLLocationDistance {
        guard let coord = experience.coordinate else { return .greatestFiniteMagnitude }
        return origin.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
    }
}
