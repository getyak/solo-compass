import CoreLocation
import MapKit
import UIKit

// MARK: - RouteMapSnapshotter

/// Wraps `MKMapSnapshotter` to produce a dark-mode street basemap fitted to a
/// route's stops. Async + timed-out + error-typed so the share sheet can fall
/// back to the vector `trace` style when no snapshot can be produced (offline,
/// throttled, error).
@MainActor
enum RouteMapSnapshotter {
    enum SnapshotError: Error {
        case noCoordinates
        case snapshotFailed
        case timedOut
    }

    /// Pure geometry: the smallest `MKMapRect` containing all stops, padded so
    /// the polyline never touches the edge. At least ~500m of view to avoid a
    /// single tightly-cropped point. `nonisolated` so it's unit-testable off the
    /// main actor.
    nonisolated static func boundingMapRect(_ coords: [CLLocationCoordinate2D], padding: Double = 0.25) -> MKMapRect {
        guard !coords.isEmpty else { return .null }
        let union = coords.reduce(MKMapRect.null) { acc, c in
            let pt = MKMapPoint(c)
            let r = MKMapRect(x: pt.x, y: pt.y, width: 0, height: 0)
            return acc.union(r)
        }
        let dx = union.size.width * padding
        let dy = union.size.height * padding
        // ~500m floor expressed in map points so single/near-coincident stops
        // still get geographic context instead of an over-zoomed crop.
        let floor = MKMapPointsPerMeterAtLatitude(coords[0].latitude) * 500
        return union.insetBy(dx: -max(dx, floor), dy: -max(dy, floor))
    }

    /// Render a basemap image of `size` (points) fitted to `coordinates`.
    /// Forces dark mode so the white polyline halo reads on any tile.
    static func snapshot(
        coordinates: [CLLocationCoordinate2D],
        size: CGSize,
        scale: CGFloat,
        timeout: TimeInterval = 4.0
    ) async throws -> UIImage {
        guard !coordinates.isEmpty else { throw SnapshotError.noCoordinates }

        let options = MKMapSnapshotter.Options()
        options.mapRect = boundingMapRect(coordinates)
        options.size = size
        options.scale = scale
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)

        let snapshotter = MKMapSnapshotter(options: options)

        return try await withThrowingTaskGroup(of: UIImage.self) { group in
            group.addTask {
                let snapshot = try await snapshotter.start()
                return snapshot.image
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw SnapshotError.timedOut
            }
            // First to finish wins; cancel the loser.
            guard let result = try await group.next() else {
                throw SnapshotError.snapshotFailed
            }
            group.cancelAll()
            return result
        }
    }
}
