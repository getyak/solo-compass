import XCTest
@testable import SoloCompass

@MainActor
final class ReviewsServiceTests: XCTestCase {

    // MARK: - Unconfigured Release path

#if !DEBUG
    /// Verifies that fetchSoloScore returns the fallback immediately when no SOLO_API_BASE_URL
    /// env var is set (Release build). No URLSession call should be made.
    func testFetchSoloScoreReturnsFallbackWhenUnconfigured() async throws {
        // ReviewsService.init() with no baseURL arg and no SOLO_API_BASE_URL env var will
        // set isUnconfigured = true in Release, bypassing URLSession entirely.
        let fallback = SoloScore(
            overall: 0.75,
            breakdown: SoloScore.Breakdown(
                seatingFriendly: 0.8,
                soloPatronRatio: 0.7,
                staffPressure: 0.6,
                soloPortioning: 0.9,
                ambianceFit: 0.7,
                safety: 0.8
            ),
            hint: "test",
            basedOnCount: 0
        )

        let service = ReviewsService()
        let result = try await service.fetchSoloScore(experienceId: "test-id", fallback: fallback)
        XCTAssertEqual(result.overall, fallback.overall, accuracy: 0.001)
    }

    /// Verifies that fetchSoloScore throws notFound (not a timeout) when unconfigured
    /// and no fallback is provided.
    func testFetchSoloScoreThrowsNotFoundWhenUnconfiguredNoFallback() async {
        let service = ReviewsService()
        do {
            _ = try await service.fetchSoloScore(experienceId: "test-id", fallback: nil)
            XCTFail("Expected notFound error")
        } catch ReviewsServiceError.notFound(let id) {
            XCTAssertEqual(id, "test-id")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
#endif

    // MARK: - Configured path (DEBUG or explicit baseURL)

    /// Verifies that when a custom baseURL is provided, the service is not marked unconfigured
    /// and will attempt a real fetch (which fails against a bad URL and falls back).
    func testFetchSoloScoreWithExplicitBaseURLUsesFallback() async throws {
        let fallback = SoloScore(
            overall: 0.5,
            breakdown: SoloScore.Breakdown(
                seatingFriendly: 0.5,
                soloPatronRatio: 0.5,
                staffPressure: 0.5,
                soloPortioning: 0.5,
                ambianceFit: 0.5,
                safety: 0.5
            ),
            hint: nil,
            basedOnCount: 0
        )
        // Use a non-routable address so the request fails fast and the fallback is returned.
        let service = ReviewsService(
            baseURL: URL(string: "http://192.0.2.1:9999")! // TEST-NET, guaranteed unreachable
        )
        // The fetch will fail (connection refused / timeout) and return the fallback.
        let result = try await service.fetchSoloScore(experienceId: "exp-1", fallback: fallback)
        XCTAssertEqual(result.overall, fallback.overall, accuracy: 0.001)
    }
}
