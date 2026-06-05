import XCTest
import CoreLocation
import SwiftData
@testable import SoloCompass

/// US-003: the 12-hour TTL must invalidate stale rows. A record observed 13
/// hours ago is past the `12 * 3600` window, so the next `current(at:)` must
/// re-fetch from the network rather than returning the stale snapshot.
@MainActor
final class WeatherCacheTTLTests: XCTestCase {

    private let coord = CLLocationCoordinate2D(latitude: 21.0285, longitude: 105.8542)

    /// A 13-hour-old cached record → second call hits the network again.
    func testStaleRecordTriggersRefetch() async throws {
        let container = SoloCompassModelContainer.makeInMemory()
        let context = ModelContext(container)

        // Seed a 13-hour-old snapshot under the cell key the service will use.
        let staleDate = Date().addingTimeInterval(-13 * 3600)
        let staleSnapshot = WeatherSnapshot(
            tempC: 5.0,
            condition: .snow,
            precipChancePct: 60,
            windKph: 10,
            observedAt: staleDate
        )
        let key = WeatherService.coordKey(lat: coord.latitude, lon: coord.longitude)
        let json = try JSONEncoder().encode(staleSnapshot)
        context.insert(WeatherCacheRecord(coordKey: key, snapshotJSON: json, observedAt: staleDate))
        try context.save()

        // Fresh network body differs from the stale snapshot so we can prove the
        // service returned the network result, not the cache.
        let fetcher = CountingWeatherFetcher(body: sampleWeatherJSON)
        let service = WeatherService(
            container: container,
            fetcher: fetcher,
            apiKeyProvider: { "test-key" },
            isOnlineProvider: { true }
        )

        let result = try await service.current(at: coord)
        XCTAssertEqual(fetcher.callCount, 1, "stale record must trigger a network re-fetch")
        XCTAssertEqual(result.tempC, 21.5, accuracy: 0.001, "returned the fresh network snapshot")
        XCTAssertEqual(result.condition, .clear)
    }

    /// A record observed 11 hours ago is still fresh → no network call.
    func testFreshRecordSkipsNetwork() async throws {
        let container = SoloCompassModelContainer.makeInMemory()
        let context = ModelContext(container)

        let freshDate = Date().addingTimeInterval(-11 * 3600)
        let freshSnapshot = WeatherSnapshot(
            tempC: 18.0,
            condition: .cloudy,
            precipChancePct: 20,
            windKph: 8,
            observedAt: freshDate
        )
        let key = WeatherService.coordKey(lat: coord.latitude, lon: coord.longitude)
        let json = try JSONEncoder().encode(freshSnapshot)
        context.insert(WeatherCacheRecord(coordKey: key, snapshotJSON: json, observedAt: freshDate))
        try context.save()

        let fetcher = CountingWeatherFetcher(body: sampleWeatherJSON)
        let service = WeatherService(
            container: container,
            fetcher: fetcher,
            apiKeyProvider: { "test-key" },
            isOnlineProvider: { true }
        )

        let result = try await service.current(at: coord)
        XCTAssertEqual(fetcher.callCount, 0, "fresh record must not hit the network")
        XCTAssertEqual(result.tempC, 18.0, accuracy: 0.001, "returned the cached snapshot")
        XCTAssertEqual(result.condition, .cloudy)
    }
}
