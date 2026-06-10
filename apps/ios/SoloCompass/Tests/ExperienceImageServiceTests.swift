import XCTest
@testable import SoloCompass

/// Unit tests for the pure URL-construction and parsing helpers in
/// `ExperienceImageService` and the highlight mapping in `AIService`. These are
/// network-free: only the string/JSON transforms are exercised, since those are
/// where the accuracy of the image pipeline actually lives.
final class ExperienceImageServiceTests: XCTestCase {

    // MARK: - syncPhotoURLs

    func testSyncPhotoURLs_prefersDirectImageThenCommons() {
        let tags = [
            "image": "https://example.org/photo.jpg",
            "wikimedia_commons": "File:Wat_Phra_Singh.jpg",
        ]
        let urls = ExperienceImageService.syncPhotoURLs(from: tags)
        XCTAssertEqual(urls?.count, 2)
        XCTAssertEqual(urls?.first, "https://example.org/photo.jpg")
        XCTAssertTrue(urls?[1].contains("Special:FilePath/Wat_Phra_Singh.jpg") ?? false)
    }

    func testSyncPhotoURLs_nilWhenNoImageTags() {
        XCTAssertNil(ExperienceImageService.syncPhotoURLs(from: ["amenity": "cafe"]))
    }

    func testSyncPhotoURLs_rejectsNonHTTPImage() {
        // A javascript: or file: scheme must not become a card image.
        let urls = ExperienceImageService.syncPhotoURLs(from: ["image": "javascript:alert(1)"])
        XCTAssertNil(urls)
    }

    // MARK: - commonsFilePathURL

    func testCommonsFilePathURL_stripsFilePrefixAndEncodes() {
        let url = ExperienceImageService.commonsFilePathURL(from: "File:Eiffel Tower.jpg")
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.contains("Special:FilePath/Eiffel%20Tower.jpg"))
        XCTAssertTrue(url!.contains("width="))
    }

    func testCommonsFilePathURL_acceptsBareName() {
        let url = ExperienceImageService.commonsFilePathURL(from: "Photo.jpg")
        XCTAssertTrue(url?.contains("Special:FilePath/Photo.jpg") ?? false)
    }

    func testCommonsFilePathURL_nilOnEmpty() {
        XCTAssertNil(ExperienceImageService.commonsFilePathURL(from: "  "))
    }

    // MARK: - normalizedWikidataQID

    func testWikidataQID_fromBare() {
        XCTAssertEqual(ExperienceImageService.normalizedWikidataQID("Q243"), "Q243")
    }

    func testWikidataQID_fromURL() {
        XCTAssertEqual(
            ExperienceImageService.normalizedWikidataQID("https://www.wikidata.org/wiki/Q243"),
            "Q243"
        )
    }

    func testWikidataQID_nilWhenAbsent() {
        XCTAssertNil(ExperienceImageService.normalizedWikidataQID("not-an-id"))
    }

    func testNeedsWikidataLookup_onlyWhenNoCheaperSource() {
        XCTAssertTrue(ExperienceImageService.needsWikidataLookup(tags: ["wikidata": "Q1"]))
        XCTAssertFalse(ExperienceImageService.needsWikidataLookup(
            tags: ["wikidata": "Q1", "image": "https://x.org/a.jpg"]
        ))
        XCTAssertFalse(ExperienceImageService.needsWikidataLookup(tags: ["amenity": "cafe"]))
    }

    // MARK: - parseP18FileName

    func testParseP18FileName_extractsImage() {
        let json = """
        {"entities":{"Q243":{"claims":{"P18":[{"mainsnak":{"datavalue":{"value":"Tower.jpg"}}}]}}}}
        """.data(using: .utf8)!
        XCTAssertEqual(ExperienceImageService.parseP18FileName(json, qid: "Q243"), "Tower.jpg")
    }

    func testParseP18FileName_nilWhenNoP18() {
        let json = """
        {"entities":{"Q243":{"claims":{}}}}
        """.data(using: .utf8)!
        XCTAssertNil(ExperienceImageService.parseP18FileName(json, qid: "Q243"))
    }

    // MARK: - AIService.mapHighlights

    func testMapHighlights_dropsUnknownKindAndEmpties() {
        let raw: [(kind: String?, label: String?, value: String?)] = [
            ("wifi", "Wi-Fi", "fast"),          // valid
            ("bogus", "X", "y"),                 // unknown kind → dropped
            ("signature", "Signature", "  "),    // empty value → dropped
            ("ticket", "Ticket", "free"),        // valid
        ]
        let mapped = AIService.mapHighlights(raw)
        XCTAssertEqual(mapped?.count, 2)
        XCTAssertEqual(mapped?.first?.kind, .wifi)
        XCTAssertEqual(mapped?.first?.value, "fast")
    }

    func testMapHighlights_capsAtThree() {
        let raw: [(kind: String?, label: String?, value: String?)] = (0..<6).map { _ in
            ("vibe", "Vibe", "calm")
        }
        XCTAssertEqual(AIService.mapHighlights(raw)?.count, 3)
    }

    func testMapHighlights_nilWhenNoneSurvive() {
        let raw: [(kind: String?, label: String?, value: String?)] = [("bogus", "X", "y")]
        XCTAssertNil(AIService.mapHighlights(raw))
    }

    func testMapHighlights_nilOnNilInput() {
        XCTAssertNil(AIService.mapHighlights(nil))
    }

    func testMapHighlights_capsLabelAndValueLength() {
        // A malformed/adversarial LLM response with an overlong value must be
        // truncated before it persists / reaches VoiceOver.
        let long = String(repeating: "x", count: 500)
        let raw: [(kind: String?, label: String?, value: String?)] = [("note", long, long)]
        let mapped = AIService.mapHighlights(raw)
        XCTAssertEqual(mapped?.count, 1)
        XCTAssertLessThanOrEqual(mapped?.first?.label.count ?? 999, 40)
        XCTAssertLessThanOrEqual(mapped?.first?.value.count ?? 999, 40)
    }

    // MARK: - normalizedDirectImageURL (https hardening)

    func testDirectImageURL_rejectsHTTP() {
        // http:// is rejected to block mixed-content + IP tracking via OSM tags.
        XCTAssertNil(ExperienceImageService.normalizedDirectImageURL("http://192.168.1.1/a.jpg"))
    }

    func testDirectImageURL_acceptsHTTPS() {
        XCTAssertEqual(
            ExperienceImageService.normalizedDirectImageURL("https://x.org/a.jpg"),
            "https://x.org/a.jpg"
        )
    }

    func testDirectImageURL_rejectsSchemeRelativeNoHost() {
        XCTAssertNil(ExperienceImageService.normalizedDirectImageURL("https://"))
    }

    // MARK: - wikidataImageURL (async, stubbed network)

    private func stubbedSession(_ handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)) -> URLSession {
        StubURLProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func httpResponse(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://www.wikidata.org/")!,
            statusCode: status, httpVersion: nil, headerFields: nil
        )!
    }

    func testWikidataImageURL_resolvesP18ToCommonsURL() async {
        let session = stubbedSession { _ in
            let body = #"{"entities":{"Q243":{"claims":{"P18":[{"mainsnak":{"datavalue":{"value":"Tower.jpg"}}}]}}}}"#
            return (self.httpResponse(200), body.data(using: .utf8)!)
        }
        let url = await ExperienceImageService.wikidataImageURL(entityId: "Q243", session: session)
        XCTAssertNotNil(url)
        XCTAssertTrue(url?.contains("Special:FilePath/Tower.jpg") ?? false)
    }

    func testWikidataImageURL_nilOnNon200() async {
        let session = stubbedSession { _ in (self.httpResponse(404), Data()) }
        let url = await ExperienceImageService.wikidataImageURL(entityId: "Q243", session: session)
        XCTAssertNil(url)
    }

    func testWikidataImageURL_nilWhenNoP18() async {
        let session = stubbedSession { _ in
            (self.httpResponse(200), #"{"entities":{"Q243":{"claims":{}}}}"#.data(using: .utf8)!)
        }
        let url = await ExperienceImageService.wikidataImageURL(entityId: "Q243", session: session)
        XCTAssertNil(url)
    }

    func testWikidataImageURL_nilOnBadId() async {
        let session = stubbedSession { _ in (self.httpResponse(200), Data()) }
        let url = await ExperienceImageService.wikidataImageURL(entityId: "not-an-id", session: session)
        XCTAssertNil(url)
    }

    // MARK: - enrichWithWikidataPhotos (end-to-end)

    private func osmPOI(id: Int64, tags: [String: String]) -> OverpassService.POI {
        OverpassService.POI(osmId: id, name: "P\(id)", nameEn: "P\(id)", lat: 1, lon: 2, tags: tags)
    }

    func testEnrich_addsPhotoForWikidataOnlyPOI() async {
        let session = stubbedSession { _ in
            let body = #"{"entities":{"Q5":{"claims":{"P18":[{"mainsnak":{"datavalue":{"value":"Wat.jpg"}}}]}}}}"#
            return (self.httpResponse(200), body.data(using: .utf8)!)
        }
        let poi = osmPOI(id: 5, tags: ["tourism": "attraction", "wikidata": "Q5"])
        let exp = AIService.skeletonExperience(from: poi, cityCode: "CNX")
        XCTAssertNil(exp.location.photoUrls, "precondition: no photo before enrich")

        let enriched = await AIService.enrichWithWikidataPhotos([exp], pois: [poi], session: session)
        XCTAssertTrue(enriched[0].location.photoUrls?.first?.contains("Wat.jpg") ?? false)
    }

    func testEnrich_skipsPOIThatAlreadyHasPhoto() async {
        // image tag already gives a photo → no Wikidata lookup, value unchanged.
        let session = stubbedSession { _ in (self.httpResponse(500), Data()) } // would fail if called
        let poi = osmPOI(id: 6, tags: ["image": "https://x.org/a.jpg", "wikidata": "Q6"])
        let exp = AIService.skeletonExperience(from: poi, cityCode: "CNX")
        XCTAssertEqual(exp.location.photoUrls?.first, "https://x.org/a.jpg")

        let enriched = await AIService.enrichWithWikidataPhotos([exp], pois: [poi], session: session)
        XCTAssertEqual(enriched[0].location.photoUrls?.first, "https://x.org/a.jpg")
    }

    func testEnrich_noWikidataTagPassesThrough() async {
        let session = stubbedSession { _ in (self.httpResponse(500), Data()) }
        let poi = osmPOI(id: 7, tags: ["amenity": "cafe"])
        let exp = AIService.skeletonExperience(from: poi, cityCode: "CNX")
        let enriched = await AIService.enrichWithWikidataPhotos([exp], pois: [poi], session: session)
        XCTAssertNil(enriched[0].location.photoUrls)
    }
}
