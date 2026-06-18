import XCTest
@testable import SoloCompass

// Shared stub URLProtocol used by AISynthesisQualityTests and
// WebSearchEnrichmentSourceTests below. Was previously named
// AgentStubProtocol for the now-removed AgentRouter pipeline; kept under
// the same name so AISynthesisQualityTests stays untouched.
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
            level: 2,
            lastVerifiedAt: Date(),
            reason: "data-driven",
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

@MainActor
final class WebSearchEnrichmentSourceTests: XCTestCase {

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
            level: 2,
            lastVerifiedAt: Date(),
            reason: "data-driven",
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

    @MainActor
    func testNoKeyPathReturnsInputUnchanged() async {
        let aiService = AIService()
        aiService.isProTier = true
        let source = WebSearchEnrichmentSource(aiService: aiService)
        let exps = [makeExperience(title: "Nimman Café"), makeExperience(title: "Sunday Market")]
        let result = await source.enrich(exps, topN: 5)
        XCTAssertEqual(result.map(\.title), exps.map(\.title))
        XCTAssertEqual(result.count, exps.count)
    }

    @MainActor
    func testTopNTruncation() async {
        let aiService = AIService()
        let source = WebSearchEnrichmentSource(aiService: aiService)
        let exps = (1...8).map { i in makeExperience(title: "Place \(i)") }
        let result = await source.enrich(exps, topN: 3)
        XCTAssertEqual(result.count, 8)
        XCTAssertEqual(result.map(\.title), exps.map(\.title))
    }

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

        UserDefaults.standard.set("test-key", forKey: "deepseek_api_key_override")
        defer { UserDefaults.standard.removeObject(forKey: "deepseek_api_key_override") }

        let aiService = AIService(session: session)
        let source = WebSearchEnrichmentSource(aiService: aiService)
        let exps = (1...6).map { i in makeExperience(title: "Place \(i)") }

        let result = await source.enrich(exps, topN: 3)
        XCTAssertEqual(result.count, 6)
        XCTAssertEqual(result.map(\.title), exps.map(\.title))
    }
}
