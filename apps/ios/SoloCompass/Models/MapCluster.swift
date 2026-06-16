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

    static func cluster(
        _ experiences: [Experience],
        spanLatitudeDelta: Double
    ) -> [MapItem] {
        if experiences.count <= skipClusteringThreshold {
            return experiences.map { .single($0) }
        }
        let cellSize = cellSize(for: spanLatitudeDelta)
        guard cellSize > 0 else {
            return experiences.map { .single($0) }
        }

        var grid: [String: [Experience]] = [:]
        for exp in experiences {
            guard let coord = exp.coordinate else { continue }
            let row = Int(floor(coord.latitude / cellSize))
            let col = Int(floor(coord.longitude / cellSize))
            let key = "\(row)_\(col)"
            grid[key, default: []].append(exp)
        }

        return grid.map { key, group in
            if group.count == 1 {
                return .single(group[0])
            } else {
                let avgLat = group.compactMap(\.coordinate).map(\.latitude).reduce(0, +) / Double(group.count)
                let avgLon = group.compactMap(\.coordinate).map(\.longitude).reduce(0, +) / Double(group.count)
                return .cluster(MapCluster(
                    id: "cluster_\(key)",
                    coordinate: CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon),
                    experiences: group
                ))
            }
        }
    }

    private static func cellSize(for spanLatitudeDelta: Double) -> Double {
        if spanLatitudeDelta < 0.05 { return 0 }
        return spanLatitudeDelta / 10.0
    }
}
