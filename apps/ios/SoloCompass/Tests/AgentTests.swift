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

final class WorkdayCompilerStubProtocol: URLProtocol {
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var responseBody = "{}"
    nonisolated(unsafe) static var capturedRequest: URLRequest?
    nonisolated(unsafe) static var capturedBody: Data?

    override class func canInit(with request: URLRequest) -> Bool {
        capturedRequest = request
        if let body = request.httpBody { capturedBody = body }
        return true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        capturedRequest = request
        if let body = request.httpBody { capturedBody = body }
        return request
    }

    override func startLoading() {
        Self.capturedRequest = request
        Self.capturedBody = request.httpBody ?? StubURLProtocol.readBody(from: request.httpBodyStream)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.responseBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class WorkdayRouteCompilerServiceTests: XCTestCase {
    private func makeInput(candidateIds: [String]) -> WorkdayRouteCompileInput {
        WorkdayRouteCompileInput(
            origin: [98.99, 18.79],
            radiusMeters: 3_000,
            localDate: "2026-09-01",
            mode: "pedestrian",
            intent: WorkdayPlanIntentInput(
                startMinute: 540,
                endMinute: 900,
                tasks: [
                    WorkdayRouteTaskInput(
                        id: "focus",
                        kind: "deep_work",
                        durationMinutes: 120,
                        earliestStartMinute: 540,
                        latestEndMinute: 720,
                        candidateIds: candidateIds,
                        constraints: [
                            WorkdayFeatureConstraint(
                                featureKey: "work.power_outlets",
                                operator: "truthy",
                                expected: nil,
                                hard: true,
                                acceptableStatuses: ["resolved"],
                                minimumConfidence: 0.7
                            )
                        ],
                        openingRequirement: "known_open"
                    )
                ],
                maxTravelMinutes: 60,
                maxWaitMinutes: 20,
                budget: nil,
                allowUnknownSpend: false,
                allowUnknownOpeningHours: false,
                fallbackMaxExtraTravelMinutes: 10
            )
        )
    }

    private func makeService() -> WorkdayRouteCompilerService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WorkdayCompilerStubProtocol.self]
        let auth = MockSupabaseClient(sessionToReturn: SupabaseClient.Session(
            userId: "traveler-1",
            accessToken: "signed-token",
            refreshToken: "refresh-token",
            expiresAt: Date().addingTimeInterval(3600)
        ))
        return WorkdayRouteCompilerService(
            session: URLSession(configuration: config),
            baseURL: URL(string: "https://solo.example")!,
            authClient: auth
        )
    }

    override func setUp() {
        super.setUp()
        WorkdayCompilerStubProtocol.statusCode = 200
        WorkdayCompilerStubProtocol.responseBody = "{}"
        WorkdayCompilerStubProtocol.capturedRequest = nil
        WorkdayCompilerStubProtocol.capturedBody = nil
    }

    func testSolvedResponseBuildsPersistableScheduleAndSignedRequest() async throws {
        let candidates = Array(ExperienceService.hardcodedSeed.prefix(2))
        let primary = try XCTUnwrap(candidates.first)
        let fallback = try XCTUnwrap(candidates.dropFirst().first)
        WorkdayCompilerStubProtocol.responseBody = """
        {
          "result": {
            "status": "solved",
            "solution": {
              "stops": [{
                "taskId": "focus", "taskKind": "deep_work",
                "candidateId": "\(primary.id)", "experienceId": "\(primary.id)",
                "title": "\(primary.title)", "arrivalMinute": 535,
                "startMinute": 540, "endMinute": 660,
                "travelFromPreviousMinutes": 8,
                "distanceFromPreviousMeters": 620,
                "waitMinutes": 5, "warnings": []
              }],
              "fallbacks": [{
                "taskId": "focus", "primaryCandidateId": "\(primary.id)",
                "candidateId": "\(fallback.id)", "experienceId": "\(fallback.id)",
                "title": "\(fallback.title)", "arrivalMinute": 540,
                "startMinute": 545, "endMinute": 665,
                "incomingTravelMinutes": 13, "outgoingTravelMinutes": 0,
                "extraTravelMinutes": 5, "warnings": []
              }],
              "score": 8.7, "totalTravelMinutes": 8,
              "totalDistanceMeters": 620, "totalWaitMinutes": 5,
              "budgetEstimateIncomplete": false,
              "startsAtMinute": 540, "endsAtMinute": 660,
              "warnings": [],
              "solver": {"version": "1", "exploredStates": 4, "beamWidth": 20, "matrixMode": "pedestrian"}
            }
          },
          "evidenceCoverage": "partial",
          "refreshScheduled": true,
          "cache": "miss"
        }
        """

        let result = try await makeService().compile(
            input: makeInput(candidateIds: candidates.map(\.id)),
            candidates: candidates,
            cityCode: primary.location.cityCode
        )
        guard case .solved(let route) = result else {
            return XCTFail("expected solved route")
        }
        XCTAssertEqual(route.experienceIds, [primary.id])
        XCTAssertEqual(route.distanceMeters, 620)
        XCTAssertEqual(route.compiledPlan?.fallbacks.first?.experienceId, fallback.id)
        XCTAssertEqual(route.compiledPlan?.evidenceCoverage, "partial")
        XCTAssertTrue(route.compiledPlan?.refreshScheduled == true)

        let request = try XCTUnwrap(WorkdayCompilerStubProtocol.capturedRequest)
        XCTAssertEqual(request.url?.path, "/api/routes/compile")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer signed-token")
        let body = try XCTUnwrap(WorkdayCompilerStubProtocol.capturedBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["origin"] as? [Double], [98.99, 18.79])
    }

    func testUnsatisfiableResponsePreservesRejectionReason() async throws {
        let candidates = Array(ExperienceService.hardcodedSeed.prefix(1))
        WorkdayCompilerStubProtocol.statusCode = 422
        WorkdayCompilerStubProtocol.responseBody = """
        {
          "result": {
            "status": "unsatisfiable",
            "failedTaskId": "focus",
            "rejections": [{"code": "hard_constraint_unmet", "count": 3}],
            "exploredStates": 7
          },
          "evidenceCoverage": "partial",
          "refreshScheduled": true,
          "cache": "hit"
        }
        """
        let result = try await makeService().compile(
            input: makeInput(candidateIds: candidates.map(\.id)),
            candidates: candidates,
            cityCode: "cmi"
        )
        guard case let .unsatisfiable(taskId, rejections) = result else {
            return XCTFail("expected unsatisfiable result")
        }
        XCTAssertEqual(taskId, "focus")
        XCTAssertEqual(rejections, [WorkdayRouteRejection(code: "hard_constraint_unmet", count: 3)])
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
