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
///  2. Warm-start fallback: the visible experience with the highest Solo Score.
///     Surfaces the strongest real pick the instant the map loads, before the
///     AI ranker has had a chance to run. Ties (Δ < 0.05) break to the nearest
///     one so the suggestion is plausibly walkable.
///  3. `nil` when `experiences` is empty.
enum PeekPickResolver {
    /// Resolve the peek experience from the visible set.
    ///
    /// - Parameters:
    ///   - experiences: the currently visible experiences.
    ///   - smartPickIds: AI-ranked top pick ids (highest priority first).
    ///   - referenceCoordinate: user location or map center; used to break
    ///     Solo-Score ties in the warm-start fallback.
    ///   - excludedIds: ids the traveler shuffled away via "换一个". The
    ///     resolver skips them — unless the exclusion covers every visible
    ///     experience, in which case the rotation wraps around to the full set
    ///     so the shuffle never comes back empty-handed.
    /// - Returns: the experience to feature in the peek card, or `nil` if none.
    static func resolve(
        experiences: [Experience],
        smartPickIds: [String],
        referenceCoordinate: CLLocationCoordinate2D?,
        excluding excludedIds: Set<String> = []
    ) -> Experience? {
        guard !experiences.isEmpty else { return nil }

        let remaining = experiences.filter { !excludedIds.contains($0.id) }
        let pool = remaining.isEmpty ? experiences : remaining

        // 1. Prefer the first smart pick that is actually visible.
        for id in smartPickIds {
            if let match = pool.first(where: { $0.id == id }) {
                return match
            }
        }

        // 2. Warm-start: highest Solo Score. "Best place in view" beats
        //    "whatever happens to be nearest", which can be a low-quality pin.
        let refLocation = referenceCoordinate.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
        }
        return pool.max(by: { lhs, rhs in
            let scoreGap = rhs.soloScore.overall - lhs.soloScore.overall
            if abs(scoreGap) < 0.05, let ref = refLocation {
                // Effectively tied → prefer closer.
                return distance(from: ref, to: lhs) > distance(from: ref, to: rhs)
            }
            return scoreGap > 0
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
