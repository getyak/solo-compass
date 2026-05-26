import XCTest
import CoreLocation
@testable import SoloCompass

// MARK: - US-002: exploreProgressively stage loop

/// Builds a minimal Overpass JSON response containing `count` POIs
/// scattered at `spreadMeters` distance from `center` in a rough arc.
private func overpassJSON(
    center: CLLocationCoordinate2D,
    count: Int,
    spreadMeters: Double,
    startId: Int64 = 1
) -> String {
    let latOffset = spreadMeters / 111_320.0
    var elements: [String] = []
    for i in 0..<count {
        let id = startId + Int64(i)
        // Vary longitude slightly so cells differ
        let lonOffset = Double(i) * 0.0001
        let lat = center.latitude + latOffset
        let lon = center.longitude + lonOffset
        elements.append(
            #"{"type":"node","id":\#(id),"lat":\#(lat),"lon":\#(lon),"tags":{"amenity":"cafe","name":"Place-\#(id)"}}"#
        )
    }
    return #"{"elements":[\#(elements.joined(separator: ","))]}"#
}

/// Minimal stub URLProtocol that records how many Overpass calls were made
/// and returns pre-configured responses keyed by the radius appearing in the
/// request body ("around:RADIUS,").
private final class OverpassRadiusStub: URLProtocol {
    // nonisolated(unsafe) lets us mutate from the protocol dispatch thread.
    nonisolated(unsafe) static var responsesByRadius: [Int: String] = [:]
    nonisolated(unsafe) static var fallbackResponse: String = #"{"elements":[]}"#
    nonisolated(unsafe) static var overpassCallCount: Int = 0
    nonisolated(unsafe) static var aiResponse: String = #"{"choices":[{"message":{"content":"[]"}}]}"#

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let isOverpass = host.contains("overpass") || host.contains("openstreetmap") || request.url?.path.contains("interpreter") == true

        let responseBody: String
        if isOverpass {
            Self.overpassCallCount += 1
            // Try to extract radius from the request body ("around:RADIUS,").
            let bodyData = request.httpBody
                ?? (request.httpBodyStream.flatMap { stream -> Data? in
                    stream.open(); defer { stream.close() }
                    var d = Data(); let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                    defer { buf.deallocate() }
                    while stream.hasBytesAvailable { let n = stream.read(buf, maxLength: 4096); if n <= 0 { break }; d.append(buf, count: n) }
                    return d.isEmpty ? nil : d
                })
            let bodyStr = bodyData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            // Pattern: "around:5000," or "around:10000,"
            var matched = Self.fallbackResponse
            for (radius, json) in Self.responsesByRadius {
                if bodyStr.contains("around:\(radius),") {
                    matched = json
                    break
                }
            }
            responseBody = matched
        } else {
            // AI / other endpoint — return the canned AI response.
            responseBody = Self.aiResponse
        }

        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(responseBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class ExploreProgressivelyTests: XCTestCase {

    private let paris = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)

    private func makeAgent(session: URLSession) -> EnrichmentAgent {
        EnrichmentAgent(
            overpassService: OverpassService(session: session, maxResults: 30, repository: nil),
            mapKitService: MapKitPOIService(),
            foursquareService: FoursquareService(session: session),
            geocodeService: StubReverseGeocodeService(),
            aiService: AIService(session: session, modelContext: nil)
        )
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OverpassRadiusStub.self]
        return URLSession(configuration: config)
    }

    override func setUp() {
        super.setUp()
        OverpassRadiusStub.responsesByRadius = [:]
        OverpassRadiusStub.fallbackResponse = #"{"elements":[]}"#
        OverpassRadiusStub.overpassCallCount = 0
        // Set a fake key so synthesizeExperiences takes the network path.
        // The stub returns an invalid AI body which causes decodingFailed,
        // triggering the skeleton fallback: one Experience per POI.
        setenv("DEEPSEEK_API_KEY", "sk-test-stub", 1)
        // Return invalid JSON for AI calls → skeleton fallback.
        OverpassRadiusStub.aiResponse = #"{"invalid":"not-openai-format"}"#
    }

    override func tearDown() {
        super.tearDown()
        unsetenv("DEEPSEEK_API_KEY")
    }

    // MARK: - Short-circuit: enough at 5km, must not expand

    /// When the 5km ring already delivers >= enoughThreshold experiences,
    /// the 10km and wider rings must not be fetched.
    func testShortCircuitWhenEnoughAt5km() async {
        // 10 POIs inside the 5km ring (enoughThreshold == 8).
        let inner5km = overpassJSON(
            center: paris,
            count: 10,
            spreadMeters: 3_000,  // 3km < 5km ring
            startId: 1
        )
        OverpassRadiusStub.responsesByRadius = [
            5_000: inner5km,
            // 10_000 and beyond intentionally absent — if they're called, the count increments.
        ]

        let session = makeSession()
        let agent = makeAgent(session: session)
        let results = await agent.exploreProgressively(
            at: paris,
            cityCode: "fr-paris"
        )

        // Only 1 Overpass call (for 5km) should have been made.
        XCTAssertEqual(OverpassRadiusStub.overpassCallCount, 1,
            "Should stop after 5km ring when enough POIs are collected; got \(OverpassRadiusStub.overpassCallCount) calls")
        // We got results (skeleton experiences from synthesizeExperiences).
        XCTAssertFalse(results.isEmpty, "Expected non-empty results from the 5km ring")
    }

    // MARK: - Expansion: sparse 5km triggers 10km

    /// When the 5km ring is sparse (< enoughThreshold), the agent must
    /// advance to the 10km ring.
    func testExpandsWhen5kmSparse() async {
        // Only 2 POIs in the 5km ring — below enoughThreshold of 8.
        let sparse5km = overpassJSON(
            center: paris,
            count: 2,
            spreadMeters: 3_000,
            startId: 100
        )
        // 10km ring returns more POIs in the annulus (7km–10km from center).
        let richer10km = overpassJSON(
            center: paris,
            count: 12,
            spreadMeters: 8_000,  // 8km — inside 10km ring, outside 5km ring
            startId: 200
        )
        OverpassRadiusStub.responsesByRadius = [
            5_000: sparse5km,
            10_000: richer10km
        ]

        let session = makeSession()
        let agent = makeAgent(session: session)
        _ = await agent.exploreProgressively(
            at: paris,
            cityCode: "fr-paris"
        )

        // At least 2 Overpass calls: one for 5km, one for 10km.
        XCTAssertGreaterThanOrEqual(OverpassRadiusStub.overpassCallCount, 2,
            "Should expand to 10km ring when 5km is sparse; got \(OverpassRadiusStub.overpassCallCount) calls")
    }

    // MARK: - Dedupe: same osmId appearing in both rings is counted only once

    /// Simulate data-source inconsistency: Overpass returns POI 999 within the
    /// 5km ring; the 10km fetch also returns POI 999 BUT at a slightly shifted
    /// coordinate that puts it in the `[5km, 10km)` annulus (as if the DB had a
    /// coordinate correction). The osmId dedupe must prevent it from being
    /// synthesized twice.
    func testDedupeRemovesOverlappingPois() async {
        // Stage 1: 2 POIs inside 5km, including osmId 999 at 4km.
        let inner4kmLat = paris.latitude + (4_000.0 / 111_320.0)
        let uniqueLat2km = paris.latitude + (2_000.0 / 111_320.0)
        let sparse5kmJSON = #"""
        {"elements":[
            {"type":"node","id":1,"lat":\#(uniqueLat2km),"lon":\#(paris.longitude),
             "tags":{"amenity":"cafe","name":"Inner Cafe"}},
            {"type":"node","id":999,"lat":\#(inner4kmLat),"lon":\#(paris.longitude),
             "tags":{"amenity":"cafe","name":"Shared Place"}}
        ]}
        """#

        // Stage 2: 10km fetch returns the SAME osmId 999 shifted into the annulus
        // (7km) plus a genuinely new place (id 2 at 8km).
        let annulus7kmLat = paris.latitude + (7_000.0 / 111_320.0)
        let annulus8kmLat = paris.latitude + (8_000.0 / 111_320.0)
        let richer10kmJSON = #"""
        {"elements":[
            {"type":"node","id":999,"lat":\#(annulus7kmLat),"lon":\#(paris.longitude),
             "tags":{"amenity":"cafe","name":"Shared Place (shifted)"}},
            {"type":"node","id":2,"lat":\#(annulus8kmLat),"lon":\#(paris.longitude),
             "tags":{"amenity":"cafe","name":"New Annulus Place"}}
        ]}
        """#

        OverpassRadiusStub.responsesByRadius = [
            5_000: sparse5kmJSON,
            10_000: richer10kmJSON
        ]

        let session = makeSession()
        let agent = makeAgent(session: session)

        var allResults: [Experience] = []
        _ = await agent.exploreProgressively(
            at: paris,
            cityCode: "fr-paris",
            onBatch: { batch in allResults.append(contentsOf: batch) }
        )

        // osmId 999 should produce at most one skeleton experience (exp_osm_999).
        let exp999 = allResults.filter { $0.id == "exp_osm_999" }
        XCTAssertLessThanOrEqual(exp999.count, 1,
            "osmId 999 must not be synthesized more than once; found \(exp999.count) copies")

        // We should have had at least 2 Overpass calls (sparse 5km → expand to 10km).
        XCTAssertGreaterThanOrEqual(OverpassRadiusStub.overpassCallCount, 2,
            "Expected expansion past 5km ring for sparse input")
    }

    // MARK: - onBatch callback fires per stage

    /// Results from each stage are delivered incrementally via onBatch,
    /// not only at the end.
    func testOnBatchFiresIncrementally() async {
        let inner5km = overpassJSON(center: paris, count: 2, spreadMeters: 3_000, startId: 300)
        let annulus10km = overpassJSON(center: paris, count: 6, spreadMeters: 8_000, startId: 400)
        OverpassRadiusStub.responsesByRadius = [
            5_000: inner5km,
            10_000: annulus10km
        ]

        var batchCount = 0
        let session = makeSession()
        let agent = makeAgent(session: session)
        _ = await agent.exploreProgressively(
            at: paris,
            cityCode: "fr-paris",
            onBatch: { _ in batchCount += 1 }
        )

        // onBatch must have fired at least once (for non-empty stages).
        XCTAssertGreaterThan(batchCount, 0,
            "onBatch must be called at least once when stages produce results")
    }
}

// MARK: - US-001: radius ladder constants and ringFilter

final class EnrichmentAgentRingFilterTests: XCTestCase {

    // MARK: - Constants

    func testProgressiveRadiiValues() {
        XCTAssertEqual(EnrichmentAgent.progressiveRadii, [5_000, 10_000, 25_000, 100_000])
    }

    func testEnoughThreshold() {
        XCTAssertEqual(EnrichmentAgent.enoughThreshold, 8)
    }

    // MARK: - ringFilter

    private let center = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522) // Paris

    /// Build a POI at a given distance (approx) due north of center.
    private func poi(distanceMeters: Double, id: Int64 = 0) -> OverpassService.POI {
        // 1 degree latitude ≈ 111_320 m
        let latOffset = distanceMeters / 111_320.0
        return OverpassService.POI(
            osmId: id,
            name: "POI-\(Int(distanceMeters))m",
            nameEn: nil,
            lat: center.latitude + latOffset,
            lon: center.longitude,
            tags: [:]
        )
    }

    func testRingFilterKeepsPoiInsideRadius() {
        let inside = poi(distanceMeters: 3_000, id: 1)
        let result = EnrichmentAgent.ringFilter(
            pois: [inside],
            center: center,
            within: 5_000,
            beyond: 0
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].osmId, 1)
    }

    func testRingFilterDropsPoiOutsideWithin() {
        let outside = poi(distanceMeters: 6_000, id: 2)
        let result = EnrichmentAgent.ringFilter(
            pois: [outside],
            center: center,
            within: 5_000,
            beyond: 0
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testRingFilterDropsPoiInsideBeyond() {
        let tooClose = poi(distanceMeters: 3_000, id: 3)
        let result = EnrichmentAgent.ringFilter(
            pois: [tooClose],
            center: center,
            within: 10_000,
            beyond: 5_000
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testRingFilterKeepsPoiInAnnulus() {
        let inRing = poi(distanceMeters: 7_000, id: 4)
        let result = EnrichmentAgent.ringFilter(
            pois: [inRing],
            center: center,
            within: 10_000,
            beyond: 5_000
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].osmId, 4)
    }

    func testRingFilterMixedBatch() {
        let inner = poi(distanceMeters: 3_000, id: 10)   // in [0, 5000)  ✓
        let mid   = poi(distanceMeters: 7_000, id: 11)   // in [5000, 10000) — excluded when within=5000
        let outer = poi(distanceMeters: 12_000, id: 12)  // beyond 10000 — excluded

        let innerRing = EnrichmentAgent.ringFilter(
            pois: [inner, mid, outer],
            center: center,
            within: 5_000,
            beyond: 0
        )
        XCTAssertEqual(innerRing.count, 1)
        XCTAssertEqual(innerRing[0].osmId, 10)

        let annulus = EnrichmentAgent.ringFilter(
            pois: [inner, mid, outer],
            center: center,
            within: 10_000,
            beyond: 5_000
        )
        XCTAssertEqual(annulus.count, 1)
        XCTAssertEqual(annulus[0].osmId, 11)
    }

    func testRingFilterEmptyInput() {
        let result = EnrichmentAgent.ringFilter(
            pois: [],
            center: center,
            within: 5_000
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testRingFilterBeyondDefaultsToZero() {
        let near = poi(distanceMeters: 1_000, id: 20)
        let result = EnrichmentAgent.ringFilter(
            pois: [near],
            center: center,
            within: 5_000
        )
        XCTAssertEqual(result.count, 1)
    }
}
