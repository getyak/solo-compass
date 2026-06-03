import Foundation
import CoreLocation

/// Assembles a `Route` from an ordered list of experiences, deriving the
/// distance and duration estimates that the raw `Route` initializer leaves to
/// the caller. Shared by the manual "create your own route" flow and the AI
/// route generator so both produce consistent, walkable estimates.
///
/// Pure value logic, no UI or persistence — unit-testable in isolation.
public enum RouteBuilder {
    /// Average solo walking speed in metres per minute (~4.8 km/h).
    public static let walkMetersPerMinute: Double = 80
    /// Dwell time added per stop (browsing, a coffee, a photo) in minutes.
    public static let dwellMinutesPerStop: Int = 20

    /// Straight-line (Haversine) distance in metres summed over consecutive
    /// stops. Experiences without a coordinate are skipped for the leg they
    /// would anchor, so a missing coordinate never inflates the total.
    public static func totalDistanceMeters(_ experiences: [Experience]) -> Int {
        let coords = experiences.compactMap(\.coordinate)
        guard coords.count >= 2 else { return 0 }
        var total: Double = 0
        for i in 1..<coords.count {
            let a = CLLocation(latitude: coords[i - 1].latitude, longitude: coords[i - 1].longitude)
            let b = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
            total += a.distance(from: b)
        }
        return Int(total.rounded())
    }

    /// Estimated total minutes: walking time across the legs plus a dwell
    /// buffer per stop. Always ≥ the dwell time of a single stop so a one-stop
    /// route still reads as a real outing rather than "0 min".
    public static func estimatedDurationMinutes(_ experiences: [Experience]) -> Int {
        guard !experiences.isEmpty else { return 0 }
        let walkMinutes = Double(totalDistanceMeters(experiences)) / walkMetersPerMinute
        let dwell = dwellMinutesPerStop * experiences.count
        return Int(walkMinutes.rounded()) + dwell
    }

    /// Greedy nearest-neighbour ordering starting from `origin` (or the first
    /// experience when no origin is supplied). Used as the local fallback when
    /// the AI generator is unavailable, so a route is still a sensible walk
    /// rather than an arbitrary order.
    public static func nearestNeighbourOrder(
        _ experiences: [Experience],
        from origin: CLLocationCoordinate2D? = nil
    ) -> [Experience] {
        var remaining = experiences
        guard !remaining.isEmpty else { return [] }

        var ordered: [Experience] = []
        var cursor: CLLocationCoordinate2D
        if let origin {
            cursor = origin
        } else {
            let first = remaining.removeFirst()
            ordered.append(first)
            cursor = first.coordinate ?? origin ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }

        while !remaining.isEmpty {
            let cursorLoc = CLLocation(latitude: cursor.latitude, longitude: cursor.longitude)
            // Pick the closest remaining experience; those without a coordinate
            // sort last (infinite distance) so they don't anchor the walk.
            let nextIndex = remaining.indices.min { lhs, rhs in
                distance(from: cursorLoc, to: remaining[lhs]) < distance(from: cursorLoc, to: remaining[rhs])
            }
            guard let nextIndex else { break }
            let next = remaining.remove(at: nextIndex)
            ordered.append(next)
            if let coord = next.coordinate { cursor = coord }
        }
        return ordered
    }

    /// Build a `Route` from an ordered list of experiences. Distance and
    /// duration are derived; the caller supplies the editorial metadata
    /// (title, summary, pace, source, tags, reasonNow).
    public static func makeRoute(
        id: RouteId,
        title: String,
        summary: String,
        orderedExperiences: [Experience],
        cityCode: String,
        region: String = "",
        pace: Pace = .relaxed,
        tags: [String] = [],
        source: RouteSource,
        authorId: String? = nil,
        bestStartHour: Double? = nil,
        reasonNow: String? = nil
    ) -> Route {
        Route(
            id: id,
            title: title,
            summary: summary,
            experienceIds: orderedExperiences.map(\.id),
            cityCode: cityCode,
            region: region,
            estimatedDuration: estimatedDurationMinutes(orderedExperiences),
            distanceMeters: totalDistanceMeters(orderedExperiences),
            pace: pace,
            tags: tags,
            source: source,
            authorId: authorId,
            bestStartHour: bestStartHour,
            bestNow: false,
            reasonNow: reasonNow,
            verification: RouteVerification(status: .proposed, walkedByCount: 0, walkedBy: [])
        )
    }

    // MARK: - Private

    private static func distance(from loc: CLLocation, to experience: Experience) -> CLLocationDistance {
        guard let coord = experience.coordinate else { return .greatestFiniteMagnitude }
        return loc.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
    }
}
