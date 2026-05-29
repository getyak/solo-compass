import XCTest
import SwiftData
@testable import SoloCompass

/// Test resolver that always hands back a non-empty key, so the success
/// path runs regardless of whether the build baked a real `.env` key.
/// This is the seam US-001 added specifically for tests — injecting via
/// the wrong UserDefaults constant (`deepseek_api_key_override`) silently
/// no-ops because `DefaultAPIKeyResolver` reads `runtimeDeepSeekKey`, which
/// is exactly why this test was green on Macs (baked key) and red on CI
/// (placeholder secrets → empty baked key → missingAPIKey → skeleton).
private struct FixedAPIKeyResolver: APIKeyResolver {
    func resolveDeepSeekAPIKey() -> String { "test-key" }
}

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
        // Force an empty key via the resolver seam → `sendMessage` throws
        // `.missingAPIKey` → the catch branch returns skeletons. Injecting
        // here (rather than poking UserDefaults) makes the unconfigured
        // branch fire deterministically even on dev machines whose `.env`
        // bakes in a real DeepSeek key.
        Secrets.apiKeyResolver = EmptyAPIKeyResolver()
        defer { Secrets.apiKeyResolver = DefaultAPIKeyResolver() }

        let service = AIService(session: stubbedSession())
        let result = try await service.synthesizeExperiences(
            from: [makePOI()], cityCode: "CNX"
        )

        XCTAssertFalse(result.isEmpty)
        // Drain the MainActor queue so `lastSynthesisQuality` reflects the
        // hop done inside reportSkeletonFallback (AIService.swift:822).
        let quality = await MainActor.run { service.lastSynthesisQuality }
        XCTAssertEqual(quality, .skeleton)
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

        // Inject a non-empty key through the resolver seam so `resolveAPIKey`
        // returns it and the request actually goes out (to the stub). The old
        // `UserDefaults[deepseek_api_key_override]` write never worked — that
        // key name doesn't match `RuntimeKeys.deepSeekApiKey` — so the call
        // fell back to the baked key, empty on CI's placeholder secrets, which
        // is why this test was green on Macs but red on GitHub Actions.
        Secrets.apiKeyResolver = FixedAPIKeyResolver()
        defer { Secrets.apiKeyResolver = DefaultAPIKeyResolver() }

        // In-memory context so the success path can persist to cache and the
        // replay can hit it.
        let container = SoloCompassModelContainer.makeInMemory()
        let service = AIService(session: stubbedSession(), modelContext: ModelContext(container))

        // First call → real synthesis.
        let first = try await service.synthesizeExperiences(from: [makePOI()], cityCode: "CNX")
        XCTAssertFalse(first.isEmpty)
        // `lastSynthesisQuality` is set inside `await MainActor.run { ... }` at
        // AIService.swift:783/801 — on slow GitHub runners that hop completes
        // AFTER `synthesizeExperiences` returns to the test task. Read the
        // property back through the MainActor to drain the queue first.
        let firstQuality = await MainActor.run { service.lastSynthesisQuality }
        XCTAssertEqual(firstQuality, .real)

        // Second call with identical inputs → cache hit.
        let second = try await service.synthesizeExperiences(from: [makePOI()], cityCode: "CNX")
        XCTAssertFalse(second.isEmpty)
        let secondQuality = await MainActor.run { service.lastSynthesisQuality }
        XCTAssertEqual(secondQuality, .cached)
    }
}
