import XCTest
@testable import SoloCompass

/// `WebSearchService` fronts the `tavily-search` Edge Function. These tests pin
/// the input contract (empty query never calls the network), the decode path
/// (envelope → results), the best-effort failure contract (any error → empty),
/// and the `WebSearchResult.host` display helper.
@MainActor
final class WebSearchServiceTests: XCTestCase {

    /// Records the last invoked function + body and returns canned data, so the
    /// service's request shaping and response decoding can be driven in isolation.
    private final class StubClient: SupabaseClientProtocol {
        var responseJSON: String = #"{"results":[]}"#
        var returnsEmptyData = false
        var failure: SupabaseClient.SupabaseError?
        private(set) var invokeCount = 0
        private(set) var lastFunction: String?
        private(set) var lastBody: Data?

        var currentSession: SupabaseClient.Session? {
            SupabaseClient.Session(
                userId: "u", accessToken: "at", refreshToken: "rt",
                expiresAt: Date().addingTimeInterval(3600)
            )
        }

        func invoke(function: String, body: Data) async -> Result<Data, SupabaseClient.SupabaseError> {
            invokeCount += 1
            lastFunction = function
            lastBody = body
            if let failure { return .failure(failure) }
            if returnsEmptyData { return .success(Data()) }
            return .success(Data(responseJSON.utf8))
        }

        func get(table: String, query: [URLQueryItem]) async -> Result<Data, SupabaseClient.SupabaseError> { .success(Data()) }
        func signInAnonymously() async -> Result<SupabaseClient.Session, SupabaseClient.SupabaseError> { .failure(.notSignedIn) }
        func refreshSession() async -> Result<SupabaseClient.Session, SupabaseClient.SupabaseError> { .failure(.notSignedIn) }
        func linkAppleIdentity(identityToken: String, nonce: String) async -> Result<SupabaseClient.Session, SupabaseClient.SupabaseError> { .failure(.notSignedIn) }
        var isAnonymous: Bool { get async { false } }
        func post(table: String, body: Data) async -> Result<Data, SupabaseClient.SupabaseError> { .success(Data()) }
        func delete(table: String, id: String) async -> Result<Void, SupabaseClient.SupabaseError> { .success(()) }
    }

    func testEmptyQueryNeverCallsNetwork() async {
        let stub = StubClient()
        let service = WebSearchService(client: stub)
        let results = await service.search(query: "   ")
        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(stub.invokeCount, 0, "empty query must short-circuit before invoke")
    }

    func testDecodesResultsFromEnvelope() async {
        let stub = StubClient()
        stub.responseJSON = """
        {"query":"coffee","results":[
          {"title":"Best Cafes","url":"https://example.com/cafes","content":"A list of cafes."},
          {"title":"More Coffee","url":"https://blog.example.org/coffee","content":"Even more."}
        ]}
        """
        let service = WebSearchService(client: stub)
        let results = await service.search(query: "coffee")

        XCTAssertEqual(stub.lastFunction, "tavily-search")
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.first?.title, "Best Cafes")
        XCTAssertEqual(results.first?.url, "https://example.com/cafes")
    }

    func testEmptyDataDegradesToEmptyResults() async {
        let stub = StubClient()
        stub.returnsEmptyData = true
        let service = WebSearchService(client: stub)
        let results = await service.search(query: "anything")
        XCTAssertTrue(results.isEmpty)
    }

    func testFailureDegradesToEmptyResults() async {
        let stub = StubClient()
        stub.failure = .notSignedIn
        let service = WebSearchService(client: stub)
        let results = await service.search(query: "anything")
        XCTAssertTrue(results.isEmpty, "any client failure must degrade to empty, never throw")
    }

    func testNewsTopicSendsDaysInBody() async {
        let stub = StubClient()
        let service = WebSearchService(client: stub)
        _ = await service.search(query: "exhibitions", topic: .news, days: 7)

        let body = try? JSONSerialization.jsonObject(with: stub.lastBody ?? Data()) as? [String: Any]
        XCTAssertEqual(body?["topic"] as? String, "news")
        XCTAssertEqual(body?["days"] as? Int, 7)
    }

    func testHostStripsWww() {
        let r = WebSearchResult(title: "T", url: "https://www.example.com/path?q=1", content: "")
        XCTAssertEqual(r.host, "example.com")
    }

    func testHostFallsBackToRawURLWhenUnparseable() {
        let r = WebSearchResult(title: "T", url: "not a url", content: "")
        // No host component → returns the raw string rather than crashing.
        XCTAssertEqual(r.host, "not a url")
    }
}
