import Foundation

/// Base32 geohash encoder + 8-neighbor helper used by the Overpass POI cache.
///
/// Why geohash over the legacy "round lat/lon to 0.01°" scheme:
///   * Same-length hashes naturally form a hierarchical grid — easy to
///     widen / narrow precision without rewriting the key format.
///   * Neighbor cells are computable, so a fetch whose radius spans the
///     edge of one bucket can pull adjacent buckets from cache without
///     re-issuing the Overpass query.
///   * The cell sizes are well-documented (precision 6 ≈ 1.2 km × 0.6 km
///     at the equator) which lines up with our typical "explore here"
///     3 km radius.
///
/// Zero third-party deps — pure Swift, deterministic.
public enum GeohashUtils {
    /// Standard geohash base32 alphabet (no a/i/l/o to avoid look-alikes).
    private static let alphabet: [Character] = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    /// Index table for fast decode of any alphabet character.
    private static let alphabetIndex: [Character: Int] = {
        var m: [Character: Int] = [:]
        for (i, c) in alphabet.enumerated() { m[c] = i }
        return m
    }()

    /// Encode `(lat, lon)` into a base32 geohash of the given precision.
    /// Precision 6 → ~1.2 km × 0.6 km cells, which matches the radius
    /// range we use for "explore here" (1.5–4 km).
    public static func encode(latitude: Double, longitude: Double, precision: Int = 6) -> String {
        precondition(precision > 0 && precision <= 12, "geohash precision must be 1...12")
        precondition(latitude >= -90 && latitude <= 90, "latitude out of range")
        precondition(longitude >= -180 && longitude <= 180, "longitude out of range")

        var latRange = (-90.0, 90.0)
        var lonRange = (-180.0, 180.0)
        var hash = ""
        var bit = 0
        var ch = 0
        var even = true

        while hash.count < precision {
            if even {
                let mid = (lonRange.0 + lonRange.1) / 2
                if longitude >= mid {
                    ch = (ch << 1) | 1
                    lonRange.0 = mid
                } else {
                    ch = ch << 1
                    lonRange.1 = mid
                }
            } else {
                let mid = (latRange.0 + latRange.1) / 2
                if latitude >= mid {
                    ch = (ch << 1) | 1
                    latRange.0 = mid
                } else {
                    ch = ch << 1
                    latRange.1 = mid
                }
            }
            even.toggle()
            bit += 1
            if bit == 5 {
                hash.append(alphabet[ch])
                bit = 0
                ch = 0
            }
        }
        return hash
    }

    /// Decode a geohash to its bounding box `(latMin, lonMin, latMax, lonMax)`.
    /// Returns `nil` if the input contains non-alphabet characters.
    public static func decode(_ hash: String) -> (latMin: Double, lonMin: Double, latMax: Double, lonMax: Double)? {
        var latRange = (-90.0, 90.0)
        var lonRange = (-180.0, 180.0)
        var even = true

        for c in hash {
            guard let idx = alphabetIndex[c] else { return nil }
            for bitOffset in (0...4).reversed() {
                let bit = (idx >> bitOffset) & 1
                if even {
                    let mid = (lonRange.0 + lonRange.1) / 2
                    if bit == 1 { lonRange.0 = mid } else { lonRange.1 = mid }
                } else {
                    let mid = (latRange.0 + latRange.1) / 2
                    if bit == 1 { latRange.0 = mid } else { latRange.1 = mid }
                }
                even.toggle()
            }
        }
        return (latRange.0, lonRange.0, latRange.1, lonRange.1)
    }

    /// Center coordinate of the cell.
    public static func center(_ hash: String) -> (lat: Double, lon: Double)? {
        guard let bbox = decode(hash) else { return nil }
        return ((bbox.latMin + bbox.latMax) / 2, (bbox.lonMin + bbox.lonMax) / 2)
    }

    /// The 8 neighbors of a geohash cell (N, NE, E, SE, S, SW, W, NW), in
    /// that fixed order. Cells at the global poles or anti-meridian may
    /// yield fewer than 8 unique neighbors; entries that fall outside the
    /// valid lat range are filtered out.
    public static func neighbors(of hash: String) -> [String] {
        guard let bbox = decode(hash) else { return [] }
        let latStep = bbox.latMax - bbox.latMin
        let lonStep = bbox.lonMax - bbox.lonMin
        let cLat = (bbox.latMin + bbox.latMax) / 2
        let cLon = (bbox.lonMin + bbox.lonMax) / 2
        let precision = hash.count

        let offsets: [(Double, Double)] = [
            ( latStep,  0),       // N
            ( latStep,  lonStep), // NE
            ( 0,        lonStep), // E
            (-latStep,  lonStep), // SE
            (-latStep,  0),       // S
            (-latStep, -lonStep), // SW
            ( 0,       -lonStep), // W
            ( latStep, -lonStep)  // NW
        ]

        return offsets.compactMap { (dLat, dLon) -> String? in
            let lat = cLat + dLat
            var lon = cLon + dLon
            guard lat >= -90, lat <= 90 else { return nil }
            // Wrap longitude across the anti-meridian.
            if lon > 180 { lon -= 360 } else if lon < -180 { lon += 360 }
            return encode(latitude: lat, longitude: lon, precision: precision)
        }
    }

    /// Center + 8 neighbors, deduplicated, in deterministic order
    /// (center first). Used by cross-bucket cache lookups.
    public static func centerAndNeighbors(of hash: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for h in [hash] + neighbors(of: hash) where seen.insert(h).inserted {
            result.append(h)
        }
        return result
    }
}
