import Foundation
import CoreLocation

/// WGS84 ↔ GCJ-02 ("Mars coordinate system") conversion and a China-mainland
/// gate, used at the boundary of any data source that speaks GCJ-02 (Amap /
/// AutoNavi). The rest of the app works exclusively in WGS84 GeoJSON
/// `[lon, lat]` (see CLAUDE.md), so conversion is confined to the edge of
/// `AmapPOIService`: WGS84 in, WGS84 out.
///
/// Why this exists
/// ----------------
/// Chinese mapping regulations require civilian map data to use GCJ-02, an
/// obfuscation of WGS84 that offsets coordinates by 50–500 m. Amap returns
/// GCJ-02; plotting it on a WGS84 (Mapbox/MapKit-in-WGS84) map without
/// converting puts every pin one street over. The forward transform (WGS84 →
/// GCJ-02) is the published, deterministic state-bureau algorithm. There is no
/// official inverse (測繪法 forbids publishing it), so `gcj02ToWgs84` recovers
/// WGS84 by iterating the forward transform to a fixed point — accurate to
/// well under a metre, which is far below GPS noise.
///
/// Coordinates use `CLLocationCoordinate2D` (lat/lon) here because conversion
/// math is latitude/longitude-symmetric and CoreLocation is the lingua franca
/// of the POI services; callers map to/from `[lon, lat]` at their own edge.
enum CoordinateConverter {
    // MARK: - Constants (state-bureau GCJ-02 algorithm)

    /// Semi-major axis of the Krasovsky 1940 ellipsoid (metres) — the datum the
    /// GCJ-02 offset algorithm is defined against.
    private static let a = 6_378_245.0
    /// Eccentricity squared of the Krasovsky 1940 ellipsoid.
    private static let ee = 0.006_693_421_622_965_943

    // MARK: - Public API

    /// Convert a WGS84 (GPS) coordinate to GCJ-02 for sending to Amap.
    /// Coordinates outside mainland China are returned unchanged — GCJ-02 is
    /// only defined inside the national boundary, and Hong Kong / Macau / Taiwan
    /// publish in WGS84.
    static func wgs84ToGcj02(_ wgs: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard isInsideChinaMainland(wgs) else { return wgs }
        let (dLat, dLon) = offset(lat: wgs.latitude, lon: wgs.longitude)
        return CLLocationCoordinate2D(
            latitude: wgs.latitude + dLat,
            longitude: wgs.longitude + dLon
        )
    }

    /// Convert a GCJ-02 coordinate (as returned by Amap) back to WGS84 for
    /// storage / display in the app's native coordinate system.
    ///
    /// There is no closed-form inverse, so we treat `gcj` as a first guess for
    /// the unknown WGS84 point and refine it: re-encode the guess, measure how
    /// far the result drifts from `gcj`, subtract that drift, repeat. Converges
    /// to sub-millimetre in a handful of iterations because the offset field is
    /// smooth and slowly varying.
    static func gcj02ToWgs84(_ gcj: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard isInsideChinaMainland(gcj) else { return gcj }
        var wgs = gcj
        // 5 iterations drives the residual below ~1e-7° (~1 cm) everywhere in
        // China; the loop is cheap and the extra rounds cost nothing.
        //
        // Apply `offset` directly rather than calling `wgs84ToGcj02`: the latter
        // re-runs the `isInsideChinaMainland` gate every iteration, so an
        // intermediate estimate that drifts a hair outside the bounding box near
        // a border would return the identity for that round and stall
        // convergence. We already gated `gcj` above, so the offset always applies.
        for _ in 0..<5 {
            let (dLat, dLon) = offset(lat: wgs.latitude, lon: wgs.longitude)
            // encoded = wgs + offset (what wgs84ToGcj02 would produce).
            wgs = CLLocationCoordinate2D(
                latitude: wgs.latitude + (gcj.latitude - (wgs.latitude + dLat)),
                longitude: wgs.longitude + (gcj.longitude - (wgs.longitude + dLon))
            )
        }
        return wgs
    }

    /// Whether a coordinate falls inside mainland China's rough bounding box.
    ///
    /// Deliberately a coarse rectangle, matching the heuristic every GCJ-02
    /// implementation uses: the goal is "should I apply the Mars offset", and
    /// the offset is only meaningful on the mainland. Hong Kong, Macau, and
    /// Taiwan are excluded so their WGS84 data is left untouched and routed to
    /// the overseas (Overpass) explore branch.
    static func isInsideChinaMainland(_ c: CLLocationCoordinate2D) -> Bool {
        let lat = c.latitude, lon = c.longitude

        // Coarse outer span of the mainland.
        guard lon >= 73.66, lon <= 135.05 else { return false }
        guard lat >= 18.0, lat <= 53.55 else { return false }

        // South-west cut. The naive `lat >= 18.0` box reaches far enough south
        // and west to swallow northern mainland-SE-Asia (Chiang Mai is
        // 18.79°N / 98.99°E). The mainland's south-west land border with
        // Myanmar/Laos sits around 21°N once you go west of ~102°E, while
        // Hainan (down to ~18.1°N) lives east of ~108°E. So raise the southern
        // floor only on the western side, leaving Hainan untouched.
        if lon < 108.0, lat < 21.1 { return false }

        // Carve out Taiwan (WGS84 island): inside the coarse box but routed to
        // the overseas (WGS84 / Overpass) branch.
        if lon >= 119.3, lon <= 122.0,
           lat >= 21.5, lat <= 25.5 {
            return false
        }
        // Carve out Macau SAR (publishes WGS84): the peninsula + Taipa/Coloane
        // islands, west of the Pearl River estuary. Macau's main urban area sits
        // at/below ~22.20°N (Macau Tower 22.186, Ruins of St. Paul's 22.197); the
        // Gongbei border checkpoint is the ~22.215°N seam with Zhuhai. The upper
        // bound is held at 22.205°N so mainland Zhuhai (Xiangzhou 22.27°N) stays
        // on the Amap branch — a wider HK+Macau box used to swallow it.
        if lon >= 113.52, lon <= 113.60,
           lat >= 22.10, lat <= 22.205 {
            return false
        }
        // Carve out Hong Kong SAR (publishes WGS84): HK Island, Kowloon, and the
        // New Territories. Upper latitude bound is the Shenzhen River (~22.515°N),
        // the HK/Shenzhen administrative boundary — this includes northern NT
        // (Fanling 22.49°N, Sheung Shui 22.50°N, Tai Po 22.45°N) on the HK side
        // while Shenzhen's CBD (22.54°N) stays on the mainland Amap branch.
        if lon >= 113.82, lon <= 114.45,
           lat >= 22.15, lat <= 22.515 {
            return false
        }
        return true
    }

    // MARK: - State-bureau offset

    /// The GCJ-02 offset (Δlat, Δlon in degrees) at a WGS84 point. This is the
    /// canonical published transform — magic polynomials and all.
    private static func offset(lat: Double, lon: Double) -> (dLat: Double, dLon: Double) {
        // Algorithm works in a coordinate frame shifted by (105°E, 35°N).
        let x = lon - 105.0
        let y = lat - 35.0

        var dLat = transformLat(x: x, y: y)
        var dLon = transformLon(x: x, y: y)

        let radLat = lat / 180.0 * .pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = magic.squareRoot()

        dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * .pi)
        dLon = (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * .pi)
        return (dLat, dLon)
    }

    private static func transformLat(x: Double, y: Double) -> Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y
            + 0.1 * x * y + 0.2 * abs(x).squareRoot()
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * .pi) + 320.0 * sin(y * .pi / 30.0)) * 2.0 / 3.0
        return ret
    }

    private static func transformLon(x: Double, y: Double) -> Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x
            + 0.1 * x * y + 0.1 * abs(x).squareRoot()
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
        return ret
    }
}
