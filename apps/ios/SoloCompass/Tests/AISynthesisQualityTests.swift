import XCTest
import SwiftData
@testable import SoloCompass

/// US-003: verify `AIService.lastSynthesisQuality` transitions correctly
/// across the three synthesis paths the UI transparency badge depends on: // anti-pattern-lint:allow transparency indicator for AI synthesis quality, not gamification
/// `.real` on a successful model call, `.skeleton` on fallback, and
/// `.cached` on a cache hit.
final class AISynthesisQualityTests: XCTestCase {

    private func makePOI(osmId: Int64 = 1) -> OverpassService.POI {
        OverpassService.POI(
            osmId: osmId,
            name: "Test Cafe",
            nameEn: "Test Cafe",
            lat: 18.79,
            lon: 98.98,
            tags: ["amenity": "cafe"]
        )
    }

    /// Wrap a synthesis JSON array as a DeepSeek chat-completion response so
    /// `sendMessage` → `parseSynthesizedExperiences` succeeds.
    private func chatCompletion(wrapping content: String) -> String {
        "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\(content.debugDescription)}}]}"
    }

    private func stubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AgentStubProtocol.self]
        return URLSession(configuration: config)
    }

    /// Default initial state is `.real` (no synthesis has run yet); the
    /// fallback path must flip it to `.skeleton`.
    func testFallbackPathSetsSkeleton() async throws {
        // No API key override → `sendMessage` throws `.missingAPIKey`
        // → the catch branch returns skeletons.
        UserDefaults.standard.removeObject(forKey: "deepseek_api_key_override")

        let service = AIService(session: stubbedSession())
        let result = try await service.synthesizeExperiences(
            from: [makePOI()], cityCode: "CNX"
        )

        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(service.lastSynthesisQuality, .skeleton)
    }

    /// A successful model call sets `.real`; replaying the same inputs hits
    /// the persisted cache and sets `.cached`.
    func testRealThenCachedTransition() async throws {
        let synthesisJSON = """
        [{"osmId":1,"title":"Quiet Corner Cafe","oneLiner":"A calm solo spot",\
        "whyItMatters":"Great for reading alone","category":"coffee",\
        "bestStartHour":9,"bestEndHour":17,"soloOverall":8.2}]
        """
        AgentStubProtocol.responseBody = chatCompletion(wrapping: synthesisJSON)

        UserDefaults.standard.set("test-key", forKey: "deepseek_api_key_override")
        defer { UserDefaults.standard.removeObject(forKey: "deepseek_api_key_override") }

        // In-memory context so the success path can persist to cache and the
        // replay can hit it.
        let container = SoloCompassModelContainer.makeInMemory()
        let service = AIService(session: stubbedSession(), modelContext: ModelContext(container))

        // First call → real synthesis.
        let first = try await service.synthesizeExperiences(from: [makePOI()], cityCode: "CNX")
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(service.lastSynthesisQuality, .real)

        // Second call with identical inputs → cache hit.
        let second = try await service.synthesizeExperiences(from: [makePOI()], cityCode: "CNX")
        XCTAssertFalse(second.isEmpty)
        XCTAssertEqual(service.lastSynthesisQuality, .cached)
    }
}
