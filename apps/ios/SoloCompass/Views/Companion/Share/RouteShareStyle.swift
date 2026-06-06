import Foundation

// MARK: - RouteShareStyle

/// The three ways a route can be exported from `RouteShareSheet`.
///
/// - `map`:   real MapKit street basemap (`MKMapSnapshotter`) with the route
///            polyline + numbered stops drawn on top — Strava / Komoot feel.
/// - `trace`: no basemap; the polyline is normalised and drawn as a pure vector
///            stroke over the category gradient — minimal / 小红书 feel. Also the
///            fallback target when a snapshot can't be produced (offline, error).
/// - `text`:  the existing multi-line plain-text summary.
enum RouteShareStyle: String, CaseIterable, Identifiable {
    case map
    case trace
    case text

    var id: String { rawValue }

    var label: String {
        switch self {
        case .map:
            return NSLocalizedString("route.share.style.map", comment: "Map basemap card style")
        case .trace:
            return NSLocalizedString("route.share.style.trace", comment: "Minimal vector line card style")
        case .text:
            return NSLocalizedString("route.share.mode.text", comment: "Plain text mode")
        }
    }

    /// Whether this style renders a visual image (vs. plain text).
    var isVisualCard: Bool {
        self != .text
    }
}
