import XCTest
import CoreLocation
import SwiftData
@testable import SoloCompass

// MARK: - Counting mock fetcher

/// `WeatherDataFetching` mock that counts calls and returns a canned body.
/// US-003 asserts the network seam is hit exactly once across two `current`
/// calls when the first response is cached.
final class CountingWeatherFetcher: WeatherDataFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var _callCount = 0
    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _callCount
    }

    let body: Data

    init(body: Data) {
        self.body = body
    }

    func data(from url: URL) async throws -> (Data, URLResponse) {
        lock.lock(); _callCount += 1; lock.unlock()
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (body, response)
    }
}

/// A canonical OpenWeather current-weather JSON body: clear sky, 21.5°C.
let sampleWeatherJSON = """
{
  "weather": [{ "id": 800, "main": "Clear" }],
  "main": { "temp": 21.5 },
  "wind": { "speed": 3.0 },
  "clouds": { "all": 0 }
}
""".data(using: .utf8)!

@MainActor
final class WeatherServiceTests: XCTestCase {

    private func makeService(
        fetcher: WeatherDataFetching,
        container: ModelContainer,
        online: Bool = true
    ) -> WeatherService {
        WeatherService(
            container: container,
            fetcher: fetcher,
            apiKeyProvider: { "test-key" },
            isOnlineProvider: { online }
        )
    }

    private let coord = CLLocationCoordinate2D(latitude: 21.0285, longitude: 105.8542)

    /// First call hits the network; second call (same cell, fresh) hits the
    /// cache. The mock fetcher must have been invoked exactly once.
    func testSecondCallHitsCache() async throws {
        let container = SoloCompassModelContainer.makeInMemory()
        let fetcher = CountingWeatherFetcher(body: sampleWeatherJSON)
        let service = makeService(fetcher: fetcher, container: container)

        let first = try await service.current(at: coord)
        XCTAssertEqual(fetcher.callCount, 1, "first call should hit network")
        XCTAssertEqual(first.tempC, 21.5, accuracy: 0.001)
        XCTAssertEqual(first.condition, .clear)

        let second = try await service.current(at: coord)
        XCTAssertEqual(fetcher.callCount, 1, "second call should hit cache, not network")
        XCTAssertEqual(second.tempC, 21.5, accuracy: 0.001)
    }

    /// No API key configured → `.noAPIKey` on a cache miss.
    func testNoAPIKeyThrows() async {
        let container = SoloCompassModelContainer.makeInMemory()
        let fetcher = CountingWeatherFetcher(body: sampleWeatherJSON)
        let service = WeatherService(
            container: container,
            fetcher: fetcher,
            apiKeyProvider: { nil },
            isOnlineProvider: { true }
        )
        do {
            _ = try await service.current(at: coord)
            XCTFail("expected WeatherError.noAPIKey")
        } catch WeatherError.noAPIKey {
            // expected
        } catch {
            XCTFail("expected .noAPIKey, got \(error)")
        }
        XCTAssertEqual(fetcher.callCount, 0, "no key → no network call")
    }

    /// Offline + empty cache → `.networkUnavailable`, no network call.
    func testOfflineMissThrowsNetworkUnavailable() async {
        let container = SoloCompassModelContainer.makeInMemory()
        let fetcher = CountingWeatherFetcher(body: sampleWeatherJSON)
        let service = makeService(fetcher: fetcher, container: container, online: false)
        do {
            _ = try await service.current(at: coord)
            XCTFail("expected WeatherError.networkUnavailable")
        } catch WeatherError.networkUnavailable {
            // expected
        } catch {
            XCTFail("expected .networkUnavailable, got \(error)")
        }
        XCTAssertEqual(fetcher.callCount, 0, "offline must never hit the network")
    }

    /// Condition mapping sanity across the OpenWeather id buckets.
    func testConditionMapping() {
        XCTAssertEqual(WeatherService.mapCondition(id: 211, cloudPct: 0), .storm)
        XCTAssertEqual(WeatherService.mapCondition(id: 500, cloudPct: 0), .rain)
        XCTAssertEqual(WeatherService.mapCondition(id: 601, cloudPct: 0), .snow)
        XCTAssertEqual(WeatherService.mapCondition(id: 741, cloudPct: 0), .fog)
        XCTAssertEqual(WeatherService.mapCondition(id: 800, cloudPct: 0), .clear)
        XCTAssertEqual(WeatherService.mapCondition(id: 802, cloudPct: 40), .partlyCloudy)
        XCTAssertEqual(WeatherService.mapCondition(id: 804, cloudPct: 90), .cloudy)
    }
}
