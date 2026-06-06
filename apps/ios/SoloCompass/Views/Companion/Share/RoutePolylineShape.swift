import CoreLocation
import SwiftUI

// MARK: - RouteNormalizer

/// Pure geometry: projects `[lon, lat]` coordinates into a unit square,
/// preserving aspect ratio (letterboxed, centred) so the route shape is never
/// stretched. Kept separate from the `Shape` so it can be unit-tested without UI.
///
/// Convention: project uses `[lon, lat]` (GeoJSON). Here `x = longitude`,
/// `y = latitude`; `y` is flipped at draw time so north points up.
enum RouteNormalizer {
    /// Normalised points in `[0, 1]²`, aspect-preserved & centred.
    /// Returns `[]` for empty input, a single centred point for one coordinate.
    static func normalize(_ coordinates: [CLLocationCoordinate2D]) -> [CGPoint] {
        guard !coordinates.isEmpty else { return [] }
        guard coordinates.count > 1 else { return [CGPoint(x: 0.5, y: 0.5)] }

        let lons = coordinates.map(\.longitude)
        let lats = coordinates.map(\.latitude)
        let minLon = lons.min()!, maxLon = lons.max()!
        let minLat = lats.min()!, maxLat = lats.max()!

        let spanLon = maxLon - minLon
        let spanLat = maxLat - minLat
        // Degenerate (all same lon or all same lat) → fall back to even spread.
        let span = max(spanLon, spanLat)
        guard span > 0 else {
            return coordinates.enumerated().map { i, _ in
                let t = coordinates.count == 1 ? 0.5 : Double(i) / Double(coordinates.count - 1)
                return CGPoint(x: t, y: 0.5)
            }
        }

        // Centre the smaller axis so the shape sits in the middle (letterbox).
        let offLon = (span - spanLon) / 2
        let offLat = (span - spanLat) / 2

        return coordinates.map { c in
            let nx = (c.longitude - minLon + offLon) / span
            let ny = (c.latitude - minLat + offLat) / span
            return CGPoint(x: nx, y: ny)
        }
    }

    /// Maps unit points into `rect` (with inset padding), flipping y so north is up.
    static func points(in rect: CGRect, normalized: [CGPoint], inset: CGFloat = 0.12) -> [CGPoint] {
        guard !normalized.isEmpty else { return [] }
        let pad = min(rect.width, rect.height) * inset
        let inner = rect.insetBy(dx: pad, dy: pad)
        return normalized.map { p in
            CGPoint(
                x: inner.minX + p.x * inner.width,
                y: inner.minY + (1 - p.y) * inner.height // flip y → north up
            )
        }
    }
}

// MARK: - RoutePolylineShape

/// A `Shape` that draws the normalised route polyline inside its frame. Shared
/// by the trace card (as the main visual) and the map card (as an overlay).
struct RoutePolylineShape: Shape {
    let coordinates: [CLLocationCoordinate2D]
    var inset: CGFloat = 0.12

    func path(in rect: CGRect) -> Path {
        let pts = RouteNormalizer.points(
            in: rect,
            normalized: RouteNormalizer.normalize(coordinates),
            inset: inset
        )
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        for p in pts.dropFirst() { path.addLine(to: p) }
        return path
    }
}

// MARK: - Numbered stop positions

extension RouteNormalizer {
    /// Convenience for placing numbered stop badges at the same projected points
    /// the polyline passes through.
    static func stopPoints(in rect: CGRect, coordinates: [CLLocationCoordinate2D], inset: CGFloat = 0.12) -> [CGPoint] {
        points(in: rect, normalized: normalize(coordinates), inset: inset)
    }
}
