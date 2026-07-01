import CoreLocation

/// A group of overlapping map pins collapsed into a single cluster marker.
struct MapCluster: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let experiences: [Experience]

    var count: Int { experiences.count }

    var dominantCategory: ExperienceCategory {
        let counts = Dictionary(grouping: experiences, by: \.category)
            .mapValues(\.count)
        return counts.max(by: { $0.value < $1.value })?.key ?? .coffee
    }
}

/// Either a single experience pin or a cluster of overlapping pins.
enum MapItem: Identifiable {
    case single(Experience)
    case cluster(MapCluster)

    var id: String {
        switch self {
        case .single(let exp): return exp.id
        case .cluster(let c): return c.id
        }
    }

    var coordinate: CLLocationCoordinate2D? {
        switch self {
        case .single(let exp): return exp.coordinate
        case .cluster(let c): return c.coordinate
        }
    }
}

enum MapClusterEngine {
    /// Below this pin count, clustering is skipped — a handful of pins never
    /// visually overlap enough to justify collapsing into a numbered circle.
    static let skipClusteringThreshold = 15

    /// Zoom bands for cell sizing. Using discrete bands (instead of a
    /// continuous `spanLatitudeDelta / 10` formula) means small pan/zoom
    /// jitter no longer changes the grid resolution, which was making
    /// experience markers pop between "clustered" and "single" every frame.
    static let streetBandSpan: Double = 0.05  // below → no clustering
    static let districtBandSpan: Double = 0.15
    static let cityBandSpan: Double = 0.5

    /// The three discrete cell sizes each zoom band maps to (in degrees).
    /// Chosen so a typical city view produces roughly 6–12 clusters —
    /// visually calm without hiding density.
    static let districtCellSize: Double = 0.015
    static let cityCellSize: Double = 0.05
    static let regionCellSize: Double = 0.15

    static func cluster(
        _ experiences: [Experience],
        spanLatitudeDelta: Double
    ) -> [MapItem] {
        if experiences.count <= skipClusteringThreshold {
            // Sort .single output by id so ForEach never sees a reshuffled
            // sequence across body invocations (Dictionary iteration is not
            // deterministic; passing an unsorted array to ForEach is what
            // made pins visually flicker in and out).
            return experiences
                .sorted { $0.id < $1.id }
                .map { .single($0) }
        }
        let cellSize = cellSize(for: spanLatitudeDelta)
        guard cellSize > 0 else {
            return experiences
                .sorted { $0.id < $1.id }
                .map { .single($0) }
        }

        var grid: [String: [Experience]] = [:]
        for exp in experiences {
            guard let coord = exp.coordinate else { continue }
            let row = Int(floor(coord.latitude / cellSize))
            let col = Int(floor(coord.longitude / cellSize))
            let key = "\(row)_\(col)"
            grid[key, default: []].append(exp)
        }

        // Sort by grid key so ForEach receives a stable ordering across
        // renders — Swift `Dictionary` iteration order is not guaranteed,
        // and without this the marker `.transition(.scale)` would fire on
        // every body pass even when the underlying data hadn't changed.
        return grid.keys.sorted().map { key in
            let group = grid[key]!
            if group.count == 1 {
                return .single(group[0])
            } else {
                // Centroid = geometric center of the grid cell, NOT the mean
                // of the group's coordinates. The mean shifts whenever any
                // member enters/exits the cell (from a nearby pan or a GPS
                // fix update), which is exactly the "marker drifts back and
                // forth" behaviour the user reported. The cell-center is
                // fixed for a given (row, col, cellSize) triple.
                let parts = key.split(separator: "_")
                let row = Double(parts[0]) ?? 0
                let col = Double(parts[1]) ?? 0
                let centerLat = (row + 0.5) * cellSize
                let centerLon = (col + 0.5) * cellSize
                return .cluster(MapCluster(
                    id: "cluster_\(key)",
                    coordinate: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                    experiences: group.sorted { $0.id < $1.id }
                ))
            }
        }
    }

    /// Snaps `spanLatitudeDelta` to one of three discrete cell sizes so
    /// small camera adjustments don't continuously reshape the grid.
    /// Returns 0 when the span is small enough to skip clustering.
    static func cellSize(for spanLatitudeDelta: Double) -> Double {
        if spanLatitudeDelta < streetBandSpan { return 0 }
        if spanLatitudeDelta < districtBandSpan { return districtCellSize }
        if spanLatitudeDelta < cityBandSpan { return cityCellSize }
        return regionCellSize
    }
}
