import Foundation

/// City-aware proximity thresholds. Dense cities (Tokyo, Shenzhen) use tighter
/// radii because 150 m already spans multiple blocks; rural or sprawling cities
/// use wider radii so "almost there" still feels useful.
enum ProximityConfig {
    /// Proximity radius (metres) below which the app shows the "Almost there"
    /// pulse and micro-label.
    static func nearbyThreshold(for cityCode: String?) -> Double {
        guard let code = cityCode?.lowercased() else { return defaultNearbyMeters }
        if let override = cityOverrides[code] { return override }
        return defaultNearbyMeters
    }

    private static let defaultNearbyMeters: Double = 150

    private static let cityOverrides: [String: Double] = [
        // Dense Asian metros — 150 m = several blocks
        "tokyo": 100,
        "tyo": 100,
        "osaka": 100,
        "shenzhen": 100,
        "szx": 100,
        "cn-深圳市": 100,
        "hong-kong": 100,
        "hkg": 100,
        "singapore": 100,
        "sin": 100,
        "taipei": 100,
        "tpe": 100,
        "seoul": 120,
        "icn": 120,
        "bangkok": 120,
        "bkk": 120,

        // Sprawling / rural — 150 m is barely next door
        "chiang-mai": 200,
        "cmi": 200,
        "vientiane": 250,
        "vte": 250,
        "bali": 300,
        "dps": 300,
    ]
}
