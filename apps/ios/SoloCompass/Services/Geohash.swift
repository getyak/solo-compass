import Foundation
import CoreLocation

/// Minimal geohash encoder — Base32 grid subdivision.
///
/// Only encoding is implemented (device→server). Precision 6 yields ~600m×600m cells.
public enum Geohash {
    private static let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    /// Encode a coordinate to a geohash string of the given precision (default 6).
    public static func encode(latitude: Double, longitude: Double, precision: Int = 6) -> String {
        var minLat = -90.0, maxLat = 90.0
        var minLon = -180.0, maxLon = 180.0
        var isEven = true
        var bit = 4
        var charIndex = 0
        var result = ""

        while result.count < precision {
            let mid: Double
            if isEven {
                mid = (minLon + maxLon) / 2
                if longitude >= mid { charIndex |= (1 << bit); minLon = mid } else { maxLon = mid }
            } else {
                mid = (minLat + maxLat) / 2
                if latitude >= mid { charIndex |= (1 << bit); minLat = mid } else { maxLat = mid }
            }
            isEven.toggle()
            if bit == 0 {
                result.append(base32[charIndex])
                charIndex = 0
                bit = 4
            } else {
                bit -= 1
            }
        }
        return result
    }

    /// Convenience overload accepting CLLocationCoordinate2D.
    public static func encode(_ coordinate: CLLocationCoordinate2D, precision: Int = 6) -> String {
        encode(latitude: coordinate.latitude, longitude: coordinate.longitude, precision: precision)
    }
}
