import XCTest
@testable import SoloCompass

/// Nomad OS A2: `CityExperienceFetcher` reads a city's synthesized experiences
/// from `synthesized_experiences` and joins `osm_pois` for the coordinates the
/// payload lacks. These tests pin the join, the drop-on-missing-POI rule, and
/// the empty-return contract, with a stub Supabase client keyed by table name.
final class CityExperienceFetcherTests: XCTestCase {

    /// Returns canned JSON per table so the fetcher's two reads (synthesized
    /// payload, then osm_pois) can be driven independently.
    private final class StubSupabaseClient: SupabaseClientProtocol {
        var synthJSON: String = "[]"
        var poisJSON: String = "[]"
        /// When true, every `get` returns `.success(Data())` — the backend-off /
        /// offline shape the real client produces behind the flag gate.
        var returnsEmpty = false

        var currentSession: SupabaseClient.Session? {
            SupabaseClient.Session(
                userId: "u", accessToken: "at", refreshToken: "rt",
                expiresAt: Date().addingTimeInterval(3600)
            )
        }

        func get(table: String, query: [URLQueryItem]) async -> Result<Data, SupabaseClient.SupabaseError> {
            if returnsEmpty { return .success(Data()) }
            let json: String
            switch table {
            case "synthesized_experiences": json = synthJSON
            case "osm_pois": json = poisJSON
            default: json = "[]"
            }
            return .success(Data(json.utf8))
        }

        func signInAnonymously() async -> Result<SupabaseClient.Session, SupabaseClient.SupabaseError> { .failure(.notSignedIn) }
        func refreshSession() async -> Result<SupabaseClient.Session, SupabaseClient.SupabaseError> { .failure(.notSignedIn) }
        func invoke(function: String, body: Data) async -> Result<Data, SupabaseClient.SupabaseError> { .success(Data()) }
        func linkAppleIdentity(identityToken: String, nonce: String) async -> Result<SupabaseClient.Session, SupabaseClient.SupabaseError> { .failure(.notSignedIn) }
        var isAnonymous: Bool { get async { false } }
        func post(table: String, body: Data) async -> Result<Data, SupabaseClient.SupabaseError> { .success(Data()) }
        func delete(table: String, id: String) async -> Result<Void, SupabaseClient.SupabaseError> { .success(()) }
    }

    @MainActor
    private func makeFetcher(_ stub: StubSupabaseClient) -> CityExperienceFetcher {
        CityExperienceFetcher(supabase: stub)
    }

    // MARK: - Happy path

    /// A synthesized item whose osmId resolves in osm_pois becomes a complete
    /// Experience: coordinates ([lon, lat]) and names come from the POI, copy
    /// and score from the payload, and the id follows `exp_osm_<osmId>`.
    @MainActor
    func testJoinsPayloadWithPoiCoordinates() async {
        let stub = StubSupabaseClient()
        stub.synthJSON = """
        [{"payload":[
          {"osmId":111,"title":"Counter seat at Kinn","oneLiner":"Solo ramen","whyItMatters":"quiet","category":"food","bestStartHour":18,"bestEndHour":21,"soloOverall":8.5,"howTo":["walk in"],"soloHint":"sit at the bar"}
        ]}]
        """
        stub.poisJSON = """
        [{"osm_id":111,"name":"Kinn Ramen","name_en":"Kinn Ramen","lat":13.75,"lon":100.5,"tags":{}}]
        """
        let fetched = await makeFetcher(stub).fetchCityExperiences(cityCode: "bkk")

        XCTAssertEqual(fetched.count, 1)
        let exp = try! XCTUnwrap(fetched.first)
        XCTAssertEqual(exp.id, "exp_osm_111")
        XCTAssertEqual(exp.title, "Counter seat at Kinn")
        XCTAssertEqual(exp.location.coordinates, [100.5, 13.75], "coordinates must be [lon, lat] from the POI")
        XCTAssertEqual(exp.location.placeNameLocal, "Kinn Ramen")
        XCTAssertEqual(exp.location.cityCode, "bkk")
        XCTAssertEqual(exp.soloScore.overall, 8.5, accuracy: 0.001)
        XCTAssertEqual(exp.status, .candidate)
    }

    /// An item whose osmId is absent from osm_pois is dropped — a
    /// coordinate-less experience can't be pinned or ranked, so absence beats a
    /// half-record.
    @MainActor
    func testDropsItemsMissingFromPoiTable() async {
        let stub = StubSupabaseClient()
        stub.synthJSON = """
        [{"payload":[
          {"osmId":1,"title":"Has POI","oneLiner":"a","whyItMatters":"b","category":"coffee","soloOverall":7.0},
          {"osmId":2,"title":"No POI","oneLiner":"a","whyItMatters":"b","category":"coffee","soloOverall":7.0}
        ]}]
        """
        stub.poisJSON = """
        [{"osm_id":1,"name":"Only One","name_en":null,"lat":1.0,"lon":2.0,"tags":{}}]
        """
        let fetched = await makeFetcher(stub).fetchCityExperiences(cityCode: "bkk")

        XCTAssertEqual(fetched.count, 1, "the item with no matching POI must be dropped")
        XCTAssertEqual(fetched.first?.id, "exp_osm_1")
    }

    /// The amap `source` tag flips provenance to `.amap` with the AutoNavi
    /// attribution and no OSM url — parity with the write path.
    @MainActor
    func testAmapSourceTagSetsProvenance() async {
        let stub = StubSupabaseClient()
        stub.synthJSON = """
        [{"payload":[{"osmId":9,"title":"T","oneLiner":"a","whyItMatters":"b","category":"food","soloOverall":7.0}]}]
        """
        stub.poisJSON = """
        [{"osm_id":9,"name":"店","name_en":null,"lat":22.5,"lon":114.0,"tags":{"source":"amap"}}]
        """
        let fetched = await makeFetcher(stub).fetchCityExperiences(cityCode: "szx")

        let source = try! XCTUnwrap(fetched.first?.sources.first)
        XCTAssertEqual(source.type, .amap)
        XCTAssertNil(source.url, "amap places carry no OSM node url")
    }

    // MARK: - Empty / failure contract

    /// No synthesized rows → empty result, and osm_pois is never queried.
    @MainActor
    func testEmptySynthReturnsEmpty() async {
        let stub = StubSupabaseClient()
        stub.synthJSON = "[]"
        let fetched = await makeFetcher(stub).fetchCityExperiences(cityCode: "bkk")
        XCTAssertTrue(fetched.isEmpty)
    }

    /// Synthesized items present but osm_pois comes back empty (e.g. POI rows
    /// evicted) → empty, never coordinate-less experiences.
    @MainActor
    func testNoPoisReturnsEmpty() async {
        let stub = StubSupabaseClient()
        stub.synthJSON = """
        [{"payload":[{"osmId":5,"title":"T","oneLiner":"a","whyItMatters":"b","category":"food","soloOverall":7.0}]}]
        """
        stub.poisJSON = "[]"
        let fetched = await makeFetcher(stub).fetchCityExperiences(cityCode: "bkk")
        XCTAssertTrue(fetched.isEmpty)
    }

    /// The backend-off / offline shape (empty Data) yields an empty result, not
    /// a decode crash.
    @MainActor
    func testBackendOffReturnsEmpty() async {
        let stub = StubSupabaseClient()
        stub.returnsEmpty = true
        let fetched = await makeFetcher(stub).fetchCityExperiences(cityCode: "bkk")
        XCTAssertTrue(fetched.isEmpty)
    }

    /// A blank city code short-circuits before any network read.
    @MainActor
    func testBlankCityCodeReturnsEmpty() async {
        let stub = StubSupabaseClient()
        stub.synthJSON = """
        [{"payload":[{"osmId":1,"title":"T","oneLiner":"a","whyItMatters":"b","category":"food","soloOverall":7.0}]}]
        """
        let fetched = await makeFetcher(stub).fetchCityExperiences(cityCode: "   ")
        XCTAssertTrue(fetched.isEmpty)
    }
}
