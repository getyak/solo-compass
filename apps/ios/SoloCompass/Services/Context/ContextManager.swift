import Foundation
import MapKit

// MARK: - Supporting types (Swift mirror of packages/core/src/llm-context.ts)

public struct WeatherSnapshot: Codable, Sendable {
    public let condition: String
    public let tempCelsius: Double
    /// 0–1
    public let humidity: Double

    public init(condition: String, tempCelsius: Double, humidity: Double) {
        self.condition = condition
        self.tempCelsius = tempCelsius
        self.humidity = humidity
    }
}

public struct ViewportBBox: Codable, Sendable {
    public let minLon: Double
    public let minLat: Double
    public let maxLon: Double
    public let maxLat: Double

    public init(minLon: Double, minLat: Double, maxLon: Double, maxLat: Double) {
        self.minLon = minLon
        self.minLat = minLat
        self.maxLon = maxLon
        self.maxLat = maxLat
    }
}

public struct LLMContextPreferences: Codable, Sendable {
    public let soloTravelStyle: String
    public let preferredCategories: [String]
    public let maxDistanceKm: Double

    public init(soloTravelStyle: String, preferredCategories: [String], maxDistanceKm: Double) {
        self.soloTravelStyle = soloTravelStyle
        self.preferredCategories = preferredCategories
        self.maxDistanceKm = maxDistanceKm
    }
}

public struct LLMContext: Codable, Sendable {
    /// [longitude, latitude] or nil when permission denied.
    public let location: [Double]?
    public let viewportBBox: ViewportBBox
    /// Top-20 experience IDs in the viewport, ordered by solo score descending.
    public let viewportPois: [String]
    public let preferences: LLMContextPreferences
    /// ISO 8601 local time.
    public let localTime: String
    public let weather: WeatherSnapshot?

    public init(
        location: [Double]?,
        viewportBBox: ViewportBBox,
        viewportPois: [String],
        preferences: LLMContextPreferences,
        localTime: String,
        weather: WeatherSnapshot? = nil
    ) {
        self.location = location
        self.viewportBBox = viewportBBox
        self.viewportPois = viewportPois
        self.preferences = preferences
        self.localTime = localTime
        self.weather = weather
    }

    public func jsonString() -> String? {
        guard let data = try? JSONEncoder.iso8601Encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Protocol

public protocol ContextManager: Sendable {
    /// Produce a fresh LLMContext snapshot. Must complete in < 50 ms.
    func snapshot() async -> LLMContext
}

// MARK: - DefaultContextManager

/// Aggregates live app state into an LLMContext snapshot for every LLM call.
public actor DefaultContextManager: ContextManager {

    private let locationService: LocationService
    private let preferences: UserPreferences
    /// Returns the viewport map rect and the visible sorted experiences.
    private let viewportProvider: @Sendable () -> (MKMapRect, [Experience])

    public init(
        locationService: LocationService,
        preferences: UserPreferences,
        viewportProvider: @escaping @Sendable () -> (MKMapRect, [Experience])
    ) {
        self.locationService = locationService
        self.preferences = preferences
        self.viewportProvider = viewportProvider
    }

    public func snapshot() async -> LLMContext {
        // Capture live state off the actor.
        let (rect, allPois) = viewportProvider()
        let currentLocation = await MainActor.run { locationService.currentLocation }
        let style = await MainActor.run { preferences.soloTravelStyle }
        let cats = await MainActor.run { preferences.preferredCategories }
        let maxKm = await MainActor.run { preferences.maxDistanceKm }

        // Location: [lon, lat] or nil.
        let locationPair: [Double]? = currentLocation.map {
            [$0.coordinate.longitude, $0.coordinate.latitude]
        }

        // Viewport bounding box from MKMapRect.
        let bbox = bboxFrom(rect: rect)

        // Top-20 POI IDs, sorted by solo score descending (trim if > 20).
        let sorted = allPois
            .sorted { $0.soloScore.overall > $1.soloScore.overall }
        let top20 = Array(sorted.prefix(20)).map(\.id)

        // Preferences.
        let prefs = LLMContextPreferences(
            soloTravelStyle: style.rawValue,
            preferredCategories: cats.map(\.rawValue),
            maxDistanceKm: maxKm
        )

        // ISO 8601 local time.
        let localTime = ISO8601DateFormatter().string(from: Date())

        return LLMContext(
            location: locationPair,
            viewportBBox: bbox,
            viewportPois: top20,
            preferences: prefs,
            localTime: localTime,
            weather: nil
        )
    }

    // MARK: - Helpers

    private func bboxFrom(rect: MKMapRect) -> ViewportBBox {
        let ne = MKMapPoint(x: rect.maxX, y: rect.minY)
        let sw = MKMapPoint(x: rect.minX, y: rect.maxY)
        let neCoord = ne.coordinate
        let swCoord = sw.coordinate
        return ViewportBBox(
            minLon: swCoord.longitude,
            minLat: swCoord.latitude,
            maxLon: neCoord.longitude,
            maxLat: neCoord.latitude
        )
    }
}
