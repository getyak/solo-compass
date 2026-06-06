import CoreLocation
import Foundation

// MARK: - RouteSharePayload

/// Pure-data input to the route share card. Decoupled from `Route` so the card
/// can be previewed / rendered without standing up the experience service, and
/// so the visual layer never reaches back into model logic.
///
/// `coordinates` are the route's stops in walking order (`[lon, lat]` →
/// `CLLocationCoordinate2D`). They drive the map snapshot and the vector trace.
/// An empty array means coordinates couldn't be resolved → caller falls back to
/// the gradient card.
struct RouteSharePayload: Hashable {
    let title: String
    let summary: String
    let placeLabel: String          // region / city, already human-readable
    let category: ExperienceCategory // drives gradient + emoji (mirrors RouteDetailView hero)
    let durationMinutes: Int
    let distanceMeters: Int
    let paceLabel: String
    let stopCount: Int
    let walkedByCount: Int
    let tags: [String]
    let brandHandle: String
    let coordinates: [CLLocationCoordinate2D]

    init(
        title: String,
        summary: String,
        placeLabel: String,
        category: ExperienceCategory,
        durationMinutes: Int,
        distanceMeters: Int,
        paceLabel: String,
        stopCount: Int,
        walkedByCount: Int,
        tags: [String],
        coordinates: [CLLocationCoordinate2D] = [],
        brandHandle: String = "solocompass.app"
    ) {
        self.title = title
        self.summary = summary
        self.placeLabel = placeLabel
        self.category = category
        self.durationMinutes = durationMinutes
        self.distanceMeters = distanceMeters
        self.paceLabel = paceLabel
        self.stopCount = stopCount
        self.walkedByCount = walkedByCount
        self.tags = Array(tags.prefix(3))
        self.coordinates = coordinates
        self.brandHandle = brandHandle
    }

    /// Build from a `Route` plus its resolved primary category, stop count, and
    /// ordered stop coordinates.
    init(route: Route, category: ExperienceCategory, stopCount: Int, coordinates: [CLLocationCoordinate2D]) {
        self.init(
            title: route.title,
            summary: route.summary,
            placeLabel: route.region.isEmpty ? route.cityCode : route.region,
            category: category,
            durationMinutes: route.estimatedDuration,
            distanceMeters: route.distanceMeters,
            paceLabel: route.pace.localizedLabel,
            stopCount: stopCount,
            walkedByCount: route.verification.walkedByCount,
            tags: route.tags,
            coordinates: coordinates
        )
    }

    /// True when there are enough points to draw a line (vs. a single pin).
    var hasDrawableRoute: Bool { coordinates.count >= 2 }

    /// True when at least one coordinate resolved (map / trace are possible).
    var hasAnyCoordinate: Bool { !coordinates.isEmpty }

    /// Human distance: "1.2 km" above 1000 m, else "650 m".
    var distanceLabel: String {
        if distanceMeters >= 1000 {
            let km = Double(distanceMeters) / 1000
            return String(format: "%.1f km", km)
        }
        return "\(distanceMeters) m"
    }

    /// Multi-line plain-text share body — the "copy as text" / fallback path.
    var shareText: String {
        var lines: [String] = []
        lines.append("🧭 \(title)")
        if !summary.isEmpty { lines.append(summary) }
        var facts: [String] = []
        if !placeLabel.isEmpty { facts.append("📍 \(placeLabel)") }
        facts.append("⏱ \(durationMinutes) min")
        facts.append("📏 \(distanceLabel)")
        facts.append("👣 \(stopCount) \(NSLocalizedString("route.share.stops", comment: "stops unit"))")
        lines.append(facts.joined(separator: "  ·  "))
        if walkedByCount > 0 {
            let fmt = NSLocalizedString("route.share.walkedBy", comment: "walked-by social proof")
            lines.append(String(format: fmt, walkedByCount))
        }
        if !tags.isEmpty {
            lines.append(tags.map { "#\($0)" }.joined(separator: " "))
        }
        lines.append("— \(brandHandle)")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Hashable conformance

extension RouteSharePayload {
    static func == (lhs: RouteSharePayload, rhs: RouteSharePayload) -> Bool {
        lhs.title == rhs.title &&
        lhs.summary == rhs.summary &&
        lhs.placeLabel == rhs.placeLabel &&
        lhs.category == rhs.category &&
        lhs.durationMinutes == rhs.durationMinutes &&
        lhs.distanceMeters == rhs.distanceMeters &&
        lhs.paceLabel == rhs.paceLabel &&
        lhs.stopCount == rhs.stopCount &&
        lhs.walkedByCount == rhs.walkedByCount &&
        lhs.tags == rhs.tags &&
        lhs.brandHandle == rhs.brandHandle &&
        lhs.coordinates.count == rhs.coordinates.count &&
        zip(lhs.coordinates, rhs.coordinates).allSatisfy {
            $0.latitude == $1.latitude && $0.longitude == $1.longitude
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(summary)
        hasher.combine(stopCount)
        hasher.combine(distanceMeters)
        hasher.combine(coordinates.count)
    }
}
