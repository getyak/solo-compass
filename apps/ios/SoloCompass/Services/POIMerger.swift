import Foundation

// MARK: - POIMerger

/// Source-neutral POI merging primitives — extracted from `FoursquareService`
/// per audit M3. The original `FoursquareService.merge` / `enrichMerge`
/// remain as thin wrappers so existing call sites (MapViewModel + 5 sites in
/// EnrichmentAgent + 7 tests) keep compiling, but the actual logic lives
/// here in a service-neutral spot — merging Overpass with MapKit, or Amap
/// with Foursquare, no longer feels like "borrow Foursquare's helper."
///
/// Two operations:
///
/// - `merge`: winner-takes-all dedup by ~11 m coordinate cell, preserving
///   `primary`-first order. Used when both inputs are "discovery" sets and
///   you want each place once.
///
/// - `enrichMerge`: keeps `base`'s identity but folds a fixed allow-list of
///   *signal* tags from a matching `enrichment` POI in the same cell (so
///   an OSM/MapKit place gains rating/hours/price without losing its name
///   or source). Base tags always win on a collision; enrichment-only cells
///   are appended as standalone POIs.
public enum POIMerger {

    /// Tag keys promoted from `enrichment` into `base` by `enrichMerge`.
    /// These are the cross-verifiable objective fields the deep-dive
    /// pipeline cares about (audit M3 + the original FoursquareService doc).
    public static let signalKeys: [String] = [
        "fsq_rating",
        "opening_hours",
        "fsq_price",
        "website",
        "phone",
        "fsq_popularity",
        "addr",
    ]

    /// Winner-takes-all dedup. Both lists are walked in order; any POI
    /// whose 4-decimal coord cell (~11 m) is already represented is
    /// dropped. The order of `primary` is preserved; `secondary` rows
    /// that survive dedup are appended in their input order.
    public static func merge(
        primary: [POI],
        secondary: [POI]
    ) -> [POI] {
        var seen = Set<String>()
        var result: [POI] = []
        result.reserveCapacity(primary.count + secondary.count)
        for poi in primary {
            let key = cellKey(lat: poi.lat, lon: poi.lon)
            if seen.insert(key).inserted {
                result.append(poi)
            }
        }
        for poi in secondary {
            let key = cellKey(lat: poi.lat, lon: poi.lon)
            if seen.insert(key).inserted {
                result.append(poi)
            }
        }
        return result
    }

    /// Signal-fold merge. For each `base` POI, look up an `enrichment` POI
    /// in the same coord cell; if found, copy any whitelisted `signalKeys`
    /// the base is missing. `base`'s own tags always win on a key collision.
    /// Enrichment-only cells become standalone POIs at the end of the list.
    public static func enrichMerge(
        base: [POI],
        enrichment: [POI]
    ) -> [POI] {
        var enrichmentByCell: [String: POI] = [:]
        for poi in enrichment {
            enrichmentByCell[cellKey(lat: poi.lat, lon: poi.lon), default: poi] = poi
        }

        var usedCells = Set<String>()
        var result: [POI] = []
        result.reserveCapacity(base.count + enrichment.count)
        for poi in base {
            let key = cellKey(lat: poi.lat, lon: poi.lon)
            usedCells.insert(key)
            guard let match = enrichmentByCell[key] else {
                result.append(poi)
                continue
            }
            var tags = poi.tags
            for sk in signalKeys where tags[sk] == nil {
                if let value = match.tags[sk] { tags[sk] = value }
            }
            result.append(POI(
                osmId: poi.osmId,
                name: poi.name,
                nameEn: poi.nameEn,
                lat: poi.lat,
                lon: poi.lon,
                tags: tags
            ))
        }
        for poi in enrichment {
            let key = cellKey(lat: poi.lat, lon: poi.lon)
            if usedCells.insert(key).inserted {
                result.append(poi)
            }
        }
        return result
    }

    /// 4-decimal lat/lon bucket key (~11 m). Two POIs that round to the
    /// same cell are treated as the same place by both `merge` and
    /// `enrichMerge`.
    public static func cellKey(lat: Double, lon: Double) -> String {
        let rLat = (lat * 10_000).rounded() / 10_000
        let rLon = (lon * 10_000).rounded() / 10_000
        return String(format: "%.4f_%.4f", rLat, rLon)
    }
}
