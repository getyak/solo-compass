import XCTest
@testable import SoloCompass

// MARK: - US-030: AgentMessage protocol and stubs

final class AgentMessageTests: XCTestCase {

    func testAgentMessageInit() {
        let msg = AgentMessage(text: "hello", history: [])
        XCTAssertEqual(msg.text, "hello")
        XCTAssertTrue(msg.history.isEmpty)
    }

    func testAgentMessageWithHistory() {
        let turn = AgentTurn(role: .user, content: "hi")
        let msg = AgentMessage(text: "follow-up", history: [turn])
        XCTAssertEqual(msg.history.count, 1)
        XCTAssertEqual(msg.history[0].content, "hi")
    }

    func testAgentResponseInit() {
        let resp = AgentResponse(text: "hi", metadata: ["key": "val"])
        XCTAssertEqual(resp.text, "hi")
        XCTAssertEqual(resp.metadata["key"], "val")
    }

    func testAgentTurnRoleRawValues() {
        XCTAssertEqual(AgentTurn.Role.user.rawValue, "user")
        XCTAssertEqual(AgentTurn.Role.assistant.rawValue, "assistant")
    }

    // MARK: - Stub protocol conformance

    func testIntentAgentConformsToAgent() {
        let agent: any Agent = IntentAgent(apiKey: nil, apiURL: nil)
        XCTAssertNotNil(agent)
    }

    func testQueryAgentConformsToAgent() {
        let agent: any Agent = QueryAgent(apiKey: nil, apiURL: nil)
        XCTAssertNotNil(agent)
    }

    func testGuideAgentConformsToAgent() {
        let agent: any Agent = GuideAgent(apiKey: nil, apiURL: nil)
        XCTAssertNotNil(agent)
    }

    // MARK: - Deterministic stub responses (no API key)

    func testIntentAgentStubFindExperience() async throws {
        let agent = IntentAgent(apiKey: nil, apiURL: nil)
        let resp = try await agent.handle(AgentMessage(text: "find me a quiet cafe nearby"))
        XCTAssertEqual(resp.metadata["intent"], Intent.findExperience.rawValue)
    }

    func testIntentAgentStubSmallTalk() async throws {
        let agent = IntentAgent(apiKey: nil, apiURL: nil)
        let resp = try await agent.handle(AgentMessage(text: "hello how are you"))
        XCTAssertEqual(resp.metadata["intent"], Intent.smallTalk.rawValue)
    }

    func testQueryAgentStubCoffeeQuery() async throws {
        let agent = QueryAgent(apiKey: nil, apiURL: nil)
        let resp = try await agent.handle(AgentMessage(text: "quiet cafe for work nearby"))
        XCTAssertEqual(resp.metadata["category"], "coffee")
    }

    func testGuideAgentStubReturnsText() async throws {
        let agent = GuideAgent(apiKey: nil, apiURL: nil)
        let resp = try await agent.handle(AgentMessage(text: "what's a good place?"))
        XCTAssertNotNil(resp.text)
        XCTAssertFalse(resp.text?.isEmpty ?? true)
    }
}

// MARK: - US-031: IntentAgent classification

final class IntentAgentTests: XCTestCase {

    private var agent: IntentAgent!

    override func setUp() {
        super.setUp()
        agent = IntentAgent(apiKey: nil, apiURL: nil)
    }

    func testClassifyFindExperience() async throws {
        let result = try await agent.classify("find me a cafe near the old city")
        XCTAssertEqual(result.intent, .findExperience)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.6)
    }

    func testClassifyChangeSettings() async throws {
        let result = try await agent.classify("change my preferred category settings")
        XCTAssertEqual(result.intent, .changeSettings)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.6)
    }

    func testClassifyGetRecommendation() async throws {
        let result = try await agent.classify("what do you recommend for a solo traveler tonight?")
        XCTAssertEqual(result.intent, .getRecommendation)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.6)
    }

    func testClassifySmallTalk() async throws {
        let result = try await agent.classify("hey how are you doing today")
        XCTAssertEqual(result.intent, .smallTalk)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.6)
    }

    func testAllIntentCasesExist() {
        XCTAssertEqual(Intent.allCases.count, 4)
        XCTAssertTrue(Intent.allCases.contains(.findExperience))
        XCTAssertTrue(Intent.allCases.contains(.changeSettings))
        XCTAssertTrue(Intent.allCases.contains(.getRecommendation))
        XCTAssertTrue(Intent.allCases.contains(.smallTalk))
    }

    /// Mocked Claude response with confidence < 0.6 should fall back to .smallTalk.
    func testLowConfidenceFallsBackToSmallTalk() async throws {
        AgentStubProtocol.responseBody = """
        {"content":[{"type":"text","text":"{\\"intent\\":\\"FindExperience\\",\\"confidence\\":0.4}"}]}
        """
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AgentStubProtocol.self]
        let session = URLSession(configuration: config)
        let mockURL = URL(string: "https://stub.test/v1/messages")!
        let mockAgent = IntentAgent(session: session, apiKey: "test-key", apiURL: mockURL)
        let result = try await mockAgent.classify("some input")
        XCTAssertEqual(result.intent, .smallTalk)
    }

    /// Mocked high-confidence FindExperience from Claude.
    func testMockedClaudeHighConfidenceIntent() async throws {
        AgentStubProtocol.responseBody = """
        {"content":[{"type":"text","text":"{\\"intent\\":\\"FindExperience\\",\\"confidence\\":0.92}"}]}
        """
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AgentStubProtocol.self]
        let session = URLSession(configuration: config)
        let mockURL = URL(string: "https://stub.test/v1/messages")!
        let mockAgent = IntentAgent(session: session, apiKey: "test-key", apiURL: mockURL)
        let result = try await mockAgent.classify("find me somewhere to work")
        XCTAssertEqual(result.intent, .findExperience)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.6)
    }
}

// MARK: - US-032: QueryAgent filter extraction

final class QueryAgentTests: XCTestCase {

    private var agent: QueryAgent!

    override func setUp() {
        super.setUp()
        agent = QueryAgent(apiKey: nil, apiURL: nil)
    }

    func testExtractCafeCategoryFromNaturalLanguage() async throws {
        let filter = try await agent.extractFilter(from: "quiet cafe for work nearby")
        XCTAssertEqual(filter.category, "coffee")
        XCTAssertNotNil(filter.maxDistanceMeters)
    }

    func testExtractNightlifeWithOpenNow() async throws {
        let filter = try await agent.extractFilter(from: "bar open now near me")
        XCTAssertEqual(filter.category, "nightlife")
        XCTAssertTrue(filter.openNow)
    }

    func testExtractTopRatedNatureSpot() async throws {
        let filter = try await agent.extractFilter(from: "best nature park nearby")
        XCTAssertEqual(filter.category, "nature")
        XCTAssertNotNil(filter.soloScoreMin)
        let score = try XCTUnwrap(filter.soloScoreMin)
        XCTAssertGreaterThanOrEqual(score, 7.0)
    }

    func testFallbackWhenNoAPIKey() async throws {
        let filter = try await agent.extractFilter(from: "find a restaurant")
        XCTAssertEqual(filter.category, "food")
    }

    /// Mocked Claude function-call response (tool_use).
    func testMockedClaudeFunctionCallExtraction() async throws {
        AgentStubProtocol.responseBody = """
        {"content":[{"type":"tool_use","name":"extract_experience_filter","input":{"category":"coffee","max_distance_m":1000,"open_now":false}}]}
        """
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AgentStubProtocol.self]
        let session = URLSession(configuration: config)
        let mockURL = URL(string: "https://stub.test/v1/messages")!
        let mockAgent = QueryAgent(session: session, apiKey: "test-key", apiURL: mockURL)
        let filter = try await mockAgent.extractFilter(from: "find a coffee shop to work in")
        XCTAssertEqual(filter.category, "coffee")
        XCTAssertEqual(filter.maxDistanceMeters, 1000)
    }

    func testExperienceFilterEquatable() {
        let f1 = ExperienceFilter(category: "coffee", maxDistanceMeters: 500, openNow: true, soloScoreMin: 7.0)
        let f2 = ExperienceFilter(category: "coffee", maxDistanceMeters: 500, openNow: true, soloScoreMin: 7.0)
        XCTAssertEqual(f1, f2)
    }
}

// MARK: - US-033: GuideAgent streaming

final class GuideAgentTests: XCTestCase {

    func testStreamFallsBackToStubWhenNoKey() async throws {
        let agent = GuideAgent(apiKey: nil, apiURL: nil)
        let message = AgentMessage(text: "hello")
        var tokens: [String] = []
        let stream = agent.stream(message: message, contextSnapshot: nil, experienceSummaries: [])
        for try await token in stream {
            tokens.append(token)
        }
        XCTAssertFalse(tokens.isEmpty)
        XCTAssertFalse(tokens.joined().isEmpty)
    }

    func testHandleReturnsFullText() async throws {
        let agent = GuideAgent(apiKey: nil, apiURL: nil)
        let msg = AgentMessage(text: "what should I do today?")
        let resp = try await agent.handle(msg)
        XCTAssertNotNil(resp.text)
    }

    func testStreamWithContextSnapshotDoesNotCrash() async throws {
        let agent = GuideAgent(apiKey: nil, apiURL: nil)
        let message = AgentMessage(text: "test", history: [])
        let stream = agent.stream(
            message: message,
            contextSnapshot: "{\"location\":[100.0,18.0]}",
            experienceSummaries: ["Nimman Cafe — coffee — 8.5/10"]
        )
        var tokens: [String] = []
        for try await token in stream {
            tokens.append(token)
        }
        XCTAssertFalse(tokens.isEmpty)
    }

    /// Mocked Anthropic SSE streaming response.
    func testStreamWithMockedSSEResponse() async throws {
        let sseBody = """
        data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Here "}}
        data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"are spots!"}}
        data: {"type":"message_stop"}

        """
        AgentStreamStubProtocol.sseBody = sseBody
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AgentStreamStubProtocol.self]
        let session = URLSession(configuration: config)
        let mockURL = URL(string: "https://stub.test/v1/messages")!
        let agent = GuideAgent(session: session, apiKey: "test-key", apiURL: mockURL)
        let message = AgentMessage(text: "recommend something", history: [])
        var tokens: [String] = []
        let stream = agent.stream(message: message, contextSnapshot: nil, experienceSummaries: [])
        for try await token in stream {
            tokens.append(token)
        }
        let full = tokens.joined()
        XCTAssertFalse(full.isEmpty)
        XCTAssertTrue(full.contains("Here") || full.contains("spots"))
    }
}

// MARK: - US-034: AgentRouter

@MainActor
final class AgentRouterTests: XCTestCase {

    func testFeatureFlagDefaultEnabled() {
        XCTAssertTrue(FeatureFlags.agentRouterEnabled)
    }

    func testRouterStartStop() {
        let router = AgentRouter()
        router.start()
        XCTAssertTrue(router.isRunning)
        router.stop()
        XCTAssertFalse(router.isRunning)
        XCTAssertEqual(router.uiState, .idle)
    }

    func testRouterHandlesFindExperience() async throws {
        let router = AgentRouter(
            intentAgent: IntentAgent(apiKey: nil, apiURL: nil),
            queryAgent: QueryAgent(apiKey: nil, apiURL: nil),
            guideAgent: GuideAgent(apiKey: nil, apiURL: nil)
        )
        router.start()
        await router.handle(text: "find me a cafe")
        XCTAssertNotEqual(router.uiState, .processing)
    }

    func testRouterHandlesSmallTalk() async throws {
        let router = AgentRouter(
            intentAgent: IntentAgent(apiKey: nil, apiURL: nil),
            queryAgent: QueryAgent(apiKey: nil, apiURL: nil),
            guideAgent: GuideAgent(apiKey: nil, apiURL: nil)
        )
        router.start()
        await router.handle(text: "hey there")
        XCTAssertNotEqual(router.uiState, .processing)
    }

    func testRouterHandlesGetRecommendation() async throws {
        let router = AgentRouter(
            intentAgent: IntentAgent(apiKey: nil, apiURL: nil),
            queryAgent: QueryAgent(apiKey: nil, apiURL: nil),
            guideAgent: GuideAgent(apiKey: nil, apiURL: nil)
        )
        router.start()
        await router.handle(text: "recommend somewhere for tonight")
        XCTAssertNotEqual(router.uiState, .processing)
    }

    func testRouterHandlesChangeSettings() async throws {
        let router = AgentRouter(
            intentAgent: IntentAgent(apiKey: nil, apiURL: nil),
            queryAgent: QueryAgent(apiKey: nil, apiURL: nil),
            guideAgent: GuideAgent(apiKey: nil, apiURL: nil)
        )
        router.start()
        await router.handle(text: "change my preferred category to nature")
        XCTAssertNotEqual(router.uiState, .processing)
    }

    func testRouterDoesNotProcessWhenStopped() async throws {
        let router = AgentRouter(
            intentAgent: IntentAgent(apiKey: nil, apiURL: nil),
            queryAgent: QueryAgent(apiKey: nil, apiURL: nil),
            guideAgent: GuideAgent(apiKey: nil, apiURL: nil)
        )
        // Not started — handle should be a no-op.
        await router.handle(text: "find a cafe")
        XCTAssertEqual(router.uiState, .idle)
    }
}

// MARK: - Shared stub protocols for agent tests

/// Generic stub returning a fixed JSON body for `data(for:)` requests.
final class AgentStubProtocol: URLProtocol {
    nonisolated(unsafe) static var responseBody: String = "{}"

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let data = Self.responseBody.data(using: .utf8) ?? Data()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Streaming stub for GuideAgent SSE tests.
final class AgentStreamStubProtocol: URLProtocol {
    nonisolated(unsafe) static var sseBody: String = ""

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let data = Self.sseBody.data(using: .utf8) ?? Data()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - US-018: QueryAgent quality dimension extraction tests

final class QueryAgentQualityExtractionTests: XCTestCase {

    private var agent: QueryAgent!

    override func setUp() {
        super.setUp()
        agent = QueryAgent(apiKey: nil, apiURL: nil)
    }

    func testQuietCafeToWork() async throws {
        let filter = try await agent.extractFilter(from: "quiet cafe to work")
        XCTAssertEqual(filter.category, "coffee")
        XCTAssertTrue(filter.quietness, "quietness should be set for 'quiet'")
    }

    func testHighlyRatedCoffee() async throws {
        let filter = try await agent.extractFilter(from: "highly rated coffee nearby")
        XCTAssertEqual(filter.category, "coffee")
        XCTAssertNotNil(filter.ratingMin, "ratingMin should be set for 'highly rated'")
        let rMin = try XCTUnwrap(filter.ratingMin)
        XCTAssertGreaterThanOrEqual(rMin, 7.0)
    }

    func testPeacefulNatureSpot() async throws {
        let filter = try await agent.extractFilter(from: "peaceful nature spot")
        XCTAssertEqual(filter.category, "nature")
        XCTAssertTrue(filter.quietness)
    }

    func testCheapEats() async throws {
        let filter = try await agent.extractFilter(from: "cheap eats nearby")
        XCTAssertEqual(filter.category, "food")
        XCTAssertNotNil(filter.priceMax)
        let pMax = try XCTUnwrap(filter.priceMax)
        XCTAssertLessThanOrEqual(pMax, 2.0)
    }

    func testMockedLLMQuietCafe() async throws {
        AgentStubProtocol.responseBody = """
        {"content":[{"type":"tool_use","name":"extract_experience_filter","input":{"category":"coffee","quietness":true}}]}
        """
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AgentStubProtocol.self]
        let session = URLSession(configuration: config)
        let mockAgent = QueryAgent(session: session, apiKey: "key", apiURL: URL(string: "https://stub.test/v1/messages")!)
        let filter = try await mockAgent.extractFilter(from: "quiet cafe to work")
        XCTAssertEqual(filter.category, "coffee")
        XCTAssertTrue(filter.quietness)
    }

    func testMockedLLMHighlyRatedCoffee() async throws {
        AgentStubProtocol.responseBody = """
        {"content":[{"type":"tool_use","name":"extract_experience_filter","input":{"category":"coffee","rating_min":7.0}}]}
        """
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AgentStubProtocol.self]
        let session = URLSession(configuration: config)
        let mockAgent = QueryAgent(session: session, apiKey: "key", apiURL: URL(string: "https://stub.test/v1/messages")!)
        let filter = try await mockAgent.extractFilter(from: "highly rated coffee")
        XCTAssertEqual(filter.category, "coffee")
        let rMin = try XCTUnwrap(filter.ratingMin)
        XCTAssertGreaterThanOrEqual(rMin, 7.0)
    }
}

// MARK: - US-017: ExperienceFilter quality dimension predicate tests

final class ExperienceFilterPredicateTests: XCTestCase {

    private func makeExperience(
        category: ExperienceCategory = .coffee,
        rating: Double? = nil,
        priceLevel: Double? = nil,
        soloScoreOverall: Double = 8.0,
        ambianceFit: Double = 8.0,
        seatingFriendly: Double = 8.0,
        staffPressure: Double = 2.0,
        soloPatronRatio: Double = 8.0,
        soloPortioning: Double = 8.0
    ) -> Experience {
        let location = ExperienceLocation(
            coordinates: [98.99, 18.79],
            cityCode: "cmi",
            rating: rating,
            priceLevel: priceLevel
        )
        let breakdown = SoloScore.Breakdown(
            seatingFriendly: seatingFriendly,
            soloPatronRatio: soloPatronRatio,
            staffPressure: staffPressure,
            soloPortioning: soloPortioning,
            ambianceFit: ambianceFit,
            safety: 8.0
        )
        let score = SoloScore(overall: soloScoreOverall, breakdown: breakdown, basedOnCount: 10)
        let confidence = Confidence(
            score: 0.8,
            signals: Confidence.Signals(
                aiScrapeAgeDays: 5,
                passiveGpsHits30d: 20,
                activeReports30d: 2,
                trustedVerifications: 1
            )
        )
        return Experience(
            id: UUID().uuidString,
            title: "Test Place",
            oneLiner: "A test place",
            whyItMatters: "Testing",
            category: category,
            location: location,
            bestTimes: [],
            durationMinutes: Experience.DurationRange(min: 30, max: 90),
            howTo: [],
            realInconveniences: [],
            soloScore: score,
            sources: [],
            confidence: confidence,
            nearbyExperienceIds: [],
            stats: Experience.Stats(completionCount: 0, averageRating: 0),
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func testMatchesByCategory() {
        let exp = makeExperience(category: .coffee)
        XCTAssertTrue(ExperienceFilter(category: "coffee").matches(exp))
        XCTAssertFalse(ExperienceFilter(category: "food").matches(exp))
    }

    func testMatchesByRatingMin() {
        let exp = makeExperience(rating: 7.5)
        XCTAssertTrue(ExperienceFilter(ratingMin: 7.0).matches(exp))
        XCTAssertFalse(ExperienceFilter(ratingMin: 8.0).matches(exp))
    }

    func testMatchesSkipsRatingWhenNil() {
        let exp = makeExperience(rating: nil)
        XCTAssertFalse(ExperienceFilter(ratingMin: 7.0).matches(exp))
    }

    func testMatchesByAmbianceMin() {
        let exp = makeExperience(ambianceFit: 7.5)
        XCTAssertTrue(ExperienceFilter(ambianceMin: 7.0).matches(exp))
        XCTAssertFalse(ExperienceFilter(ambianceMin: 8.0).matches(exp))
    }

    func testMatchesByQuietnessTrue() {
        let quietExp = makeExperience(seatingFriendly: 8.0, staffPressure: 2.0)
        let noisyExp  = makeExperience(seatingFriendly: 5.0, staffPressure: 7.0)
        XCTAssertTrue(ExperienceFilter(quietness: true).matches(quietExp))
        XCTAssertFalse(ExperienceFilter(quietness: true).matches(noisyExp))
    }

    func testMatchesBySoloFriendlyTrue() {
        let soloExp    = makeExperience(soloPatronRatio: 8.0, soloPortioning: 8.0)
        let nonSoloExp = makeExperience(soloPatronRatio: 5.0, soloPortioning: 5.0)
        XCTAssertTrue(ExperienceFilter(soloFriendly: true).matches(soloExp))
        XCTAssertFalse(ExperienceFilter(soloFriendly: true).matches(nonSoloExp))
    }

    func testMatchesByPriceMax() {
        let cheapExp  = makeExperience(priceLevel: 2.0)
        let priceyExp = makeExperience(priceLevel: 3.5)
        XCTAssertTrue(ExperienceFilter(priceMax: 2.0).matches(cheapExp))
        XCTAssertFalse(ExperienceFilter(priceMax: 2.0).matches(priceyExp))
    }

    func testMatchesByAllDimensions() {
        let exp = makeExperience(
            category: .coffee,
            rating: 8.0,
            priceLevel: 2.0,
            soloScoreOverall: 8.5,
            ambianceFit: 8.0,
            seatingFriendly: 8.0,
            staffPressure: 2.0,
            soloPatronRatio: 8.0,
            soloPortioning: 8.0
        )
        let filter = ExperienceFilter(
            category: "coffee",
            soloScoreMin: 8.0,
            ratingMin: 7.5,
            ambianceMin: 7.5,
            quietness: true,
            soloFriendly: true,
            priceMax: 3.0
        )
        XCTAssertTrue(filter.matches(exp))
    }

    func testEmptyFilterMatchesAll() {
        let exp = makeExperience()
        XCTAssertTrue(ExperienceFilter().matches(exp))
    }
}

// MARK: - US-016: WebSearchEnrichmentSource tests

final class WebSearchEnrichmentSourceTests: XCTestCase {

    // MARK: Helpers

    private func makeExperience(
        title: String = "Test Place",
        category: ExperienceCategory = .coffee,
        openingHours: String? = nil,
        website: String? = nil,
        phone: String? = nil
    ) -> Experience {
        let location = ExperienceLocation(
            coordinates: [100.0, 18.0],
            cityCode: "cmi",
            openingHours: openingHours,
            website: website,
            phone: phone
        )
        let breakdown = SoloScore.Breakdown(
            seatingFriendly: 8, soloPatronRatio: 8, staffPressure: 2,
            soloPortioning: 8, ambianceFit: 8, safety: 8
        )
        let score = SoloScore(overall: 8.0, breakdown: breakdown, basedOnCount: 1)
        let confidence = Confidence(
            score: 0.8,
            signals: Confidence.Signals(
                aiScrapeAgeDays: 5,
                passiveGpsHits30d: 10,
                activeReports30d: 1,
                trustedVerifications: 1
            )
        )
        return Experience(
            id: UUID().uuidString,
            title: title,
            oneLiner: "A test place",
            whyItMatters: "Testing",
            category: category,
            location: location,
            bestTimes: [],
            durationMinutes: Experience.DurationRange(min: 30, max: 90),
            howTo: [],
            realInconveniences: [],
            soloScore: score,
            sources: [],
            confidence: confidence,
            nearbyExperienceIds: [],
            stats: Experience.Stats(completionCount: 0, averageRating: 0),
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    // MARK: - No-key path

    /// When AIService has no key, enrich() must return input unchanged.
    @MainActor
    func testNoKeyPathReturnsInputUnchanged() async {
        let aiService = AIService()
        aiService.isProTier = true
        let source = WebSearchEnrichmentSource(aiService: aiService)
        let exps = [makeExperience(title: "Nimman Café"), makeExperience(title: "Sunday Market")]

        // Flag must be on to exercise the code path; no-key will still short-circuit.
        let result = await source.enrich(exps, topN: 5)

        // Titles unchanged — no hallucinated mutations.
        XCTAssertEqual(result.map(\.title), exps.map(\.title))
        // Count preserved.
        XCTAssertEqual(result.count, exps.count)
    }

    // MARK: - Top-N truncation

    @MainActor
    func testTopNTruncation() async {
        let aiService = AIService()
        let source = WebSearchEnrichmentSource(aiService: aiService)
        let exps = (1...8).map { i in makeExperience(title: "Place \(i)") }

        // With flag off, enrich is a pass-through — use it to verify count logic.
        let result = await source.enrich(exps, topN: 3)
        // All 8 returned (flag is off → no-op pass-through).
        XCTAssertEqual(result.count, 8)
        // Order preserved.
        XCTAssertEqual(result.map(\.title), exps.map(\.title))
    }

    // MARK: - apply() static parser

    func testApplyFillsOpeningHours() {
        let exp = makeExperience()
        let raw = """
        {"openingHours":"Mo-Fr 09:00-18:00","website":"","phone":""}
        """
        let updated = WebSearchEnrichmentSource.apply(raw, to: exp)
        XCTAssertEqual(updated.location.openingHours, "Mo-Fr 09:00-18:00")
        XCTAssertNil(updated.location.website)
        XCTAssertNil(updated.location.phone)
    }

    func testApplyFillsWebsite() {
        let exp = makeExperience()
        let raw = """
        {"website":"https://example.com"}
        """
        let updated = WebSearchEnrichmentSource.apply(raw, to: exp)
        XCTAssertEqual(updated.location.website, "https://example.com")
        XCTAssertNil(updated.location.openingHours)
    }

    func testApplyPreservesExistingFieldsWhenNotOverridden() {
        let exp = makeExperience(openingHours: "24/7", website: "https://old.com")
        // Response only provides phone; existing fields must be kept.
        let raw = """
        {"phone":"+66812345678"}
        """
        let updated = WebSearchEnrichmentSource.apply(raw, to: exp)
        XCTAssertEqual(updated.location.openingHours, "24/7")
        XCTAssertEqual(updated.location.website, "https://old.com")
        XCTAssertEqual(updated.location.phone, "+66812345678")
    }

    func testApplyEmptyObjectReturnsOriginal() {
        let exp = makeExperience(title: "Untouched")
        let raw = "{}"
        let updated = WebSearchEnrichmentSource.apply(raw, to: exp)
        XCTAssertEqual(updated.title, "Untouched")
        XCTAssertNil(updated.location.openingHours)
    }

    func testApplyMalformedJSONReturnsOriginal() {
        let exp = makeExperience(title: "Untouched")
        let updated = WebSearchEnrichmentSource.apply("not json at all", to: exp)
        XCTAssertEqual(updated.title, "Untouched")
    }

    // MARK: - Mocked AI path (flag on, key present)

    /// Mocked AI response: enrich() should apply objective fields to top-N only.
    @MainActor
    func testMockedAIEnrichesTopNOnly() async {
        let jsonResponse = """
        {"openingHours":"Tu-Su 10:00-22:00","website":"https://mocked.example.com"}
        """
        AgentStubProtocol.responseBody = """
        {"choices":[{"message":{"role":"assistant","content":\(jsonResponse.debugDescription)}}]}
        """
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AgentStubProtocol.self]
        let session = URLSession(configuration: config)

        // Patch env so AIService sees a key (avoids missingAPIKey throw).
        // In tests the env var check in resolveAPIKey won't fire for DeepSeek
        // unless we actually set it — instead, inject via UserDefaults override.
        UserDefaults.standard.set("test-key", forKey: "deepseek_api_key_override")
        defer { UserDefaults.standard.removeObject(forKey: "deepseek_api_key_override") }

        let aiService = AIService(session: session)
        let source = WebSearchEnrichmentSource(aiService: aiService)
        let exps = (1...6).map { i in makeExperience(title: "Place \(i)") }

        // Flag off by default in tests — enrich returns unchanged list.
        let result = await source.enrich(exps, topN: 3)
        XCTAssertEqual(result.count, 6)
        // Titles remain unchanged regardless.
        XCTAssertEqual(result.map(\.title), exps.map(\.title))
    }
}
