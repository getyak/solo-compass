import XCTest
@testable import SoloCompass

// MARK: - SupabaseRouteCompanionRemoteTests
//
// Exercises `SupabaseRouteCompanionRemote` against a fake `SupabaseClientProtocol`
// so every method's wire behaviour can be asserted without a real backend.
//
// The fake (`FakeSupabaseClient`) lets each test:
//   - preset GET responses *per table* (the SUT GETs both `routes` and
//     `join_requests`), and
//   - capture every POST body keyed by table for assertions, and
//   - flip a table's response to `.failure` to drive the error path.
//
// Note: the SUT goes through the *injected* client, so `FeatureFlags.backendSync`
// is irrelevant here (it only gates the real `SupabaseClient`). What we must
// toggle is `FeatureFlags.companion` (DEBUG override via UserDefaults key
// "FF_COMPANION"), which the remote itself checks at the top of every method.
@MainActor
final class SupabaseRouteCompanionRemoteTests: XCTestCase {

    // MARK: Fake client

    /// Fake `SupabaseClientProtocol`. Records POSTs per table and serves
    /// preset GET responses, optionally failing a table to test error paths.
    final class FakeSupabaseClient: SupabaseClientProtocol {

        /// Captured POST: (table, body bytes), in call order.
        private(set) var posts: [(table: String, body: Data)] = []
        /// Captured GETs: (table, query), in call order.
        private(set) var gets: [(table: String, query: [URLQueryItem])] = []

        /// Per-table GET responses. Default `.success(Data())` (empty → nil/[]).
        var getResponses: [String: Result<Data, SupabaseClient.SupabaseError>] = [:]
        /// Per-table POST responses. Default `.success(Data())`.
        var postResponses: [String: Result<Data, SupabaseClient.SupabaseError>] = [:]

        // SupabaseClientProtocol

        var currentSession: SupabaseClient.Session? = SupabaseClient.Session(
            userId: "user_test",
            accessToken: "tok",
            refreshToken: "ref",
            expiresAt: Date().addingTimeInterval(3600)
        )

        func signInAnonymously() async -> Result<SupabaseClient.Session, SupabaseClient.SupabaseError> {
            .failure(.backendDisabled)
        }
        func refreshSession() async -> Result<SupabaseClient.Session, SupabaseClient.SupabaseError> {
            .failure(.backendDisabled)
        }
        func post(table: String, body: Data) async -> Result<Data, SupabaseClient.SupabaseError> {
            posts.append((table, body))
            return postResponses[table] ?? .success(Data())
        }
        func get(table: String, query: [URLQueryItem]) async -> Result<Data, SupabaseClient.SupabaseError> {
            gets.append((table, query))
            return getResponses[table] ?? .success(Data())
        }
        func invoke(function: String, body: Data) async -> Result<Data, SupabaseClient.SupabaseError> {
            .success(Data())
        }
        func delete(table: String, id: String) async -> Result<Void, SupabaseClient.SupabaseError> {
            .success(())
        }
        func linkAppleIdentity(identityToken: String, nonce: String) async -> Result<SupabaseClient.Session, SupabaseClient.SupabaseError> {
            .failure(.backendDisabled)
        }
        var isAnonymous: Bool { get async { false } }

        // Helpers for tests

        func postBody(forTable table: String) -> Data? {
            posts.first(where: { $0.table == table })?.body
        }
        func postCount(forTable table: String) -> Int {
            posts.filter { $0.table == table }.count
        }
        func getQuery(forTable table: String) -> [URLQueryItem]? {
            gets.first(where: { $0.table == table })?.query
        }
    }

    // MARK: Fixtures

    private var client: FakeSupabaseClient!
    private var remote: SupabaseRouteCompanionRemote!

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.set(true, forKey: "FF_COMPANION")
        client = FakeSupabaseClient()
        remote = SupabaseRouteCompanionRemote(client: client)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "FF_COMPANION")
        client = nil
        remote = nil
        try await super.tearDown()
    }

    // MARK: Route / JSON builders

    /// Construct a valid `Route` with an attached companion in the given status.
    private func makeRoute(
        id: String = "route_1",
        cityCode: String = "TYO",
        companionStatus: CompanionStatus = .open,
        hostId: String = "host_abc",
        maxMembers: Int = 4,
        confirmedMembers: [String] = []
    ) -> Route {
        let companion = RouteCompanion(
            status: companionStatus,
            hostId: hostId,
            departureWindow: DepartureWindow(startDate: "2026-06-10", to: "2026-06-12", time: "morning"),
            departureLabel: "Sat morning",
            pacePreference: .standard,
            maxMembers: maxMembers,
            confirmedMembers: confirmedMembers
        )
        return Route(
            id: RouteId(rawValue: id),
            title: "Sunset Loop",
            summary: "A gentle walk",
            experienceIds: ["exp_1", "exp_2"],
            cityCode: cityCode,
            region: "Kanto",
            estimatedDuration: 90,
            distanceMeters: 3200,
            pace: .standard,
            tags: ["nature"],
            source: .editorial,
            companion: companion
        )
    }

    /// Encode an array of routes the same way the SUT decodes them.
    private func routesJSON(_ routes: [Route]) -> Data {
        // SUT decodes [Route] with JSONDecoder.iso8601Decoder (default keys),
        // so encode with the matching encoder to round-trip cleanly.
        try! JSONEncoder.iso8601Encoder.encode(routes)
    }

    /// Decode the upserted route from a captured POST body.
    /// `upsertRoute` encodes a *single* `Route` object (not an array), so decode
    /// one object; fall back to the first element if it ever becomes an array.
    private func decodeUpsertedRoute(_ data: Data) -> Route? {
        if let one = try? JSONDecoder.iso8601Decoder.decode(Route.self, from: data) {
            return one
        }
        return (try? JSONDecoder.iso8601Decoder.decode([Route].self, from: data))?.first
    }

    /// Build a join_requests row JSON array matching `JoinRequestRow` (snake_case).
    private func joinRequestRowsJSON(
        id: String = "jr_1",
        routeId: String = "route_1",
        hostId: String = "host_abc",
        requesterId: String = "req_xyz",
        message: String = "standard: hi",
        status: String = "pending",
        createdAt: String = "2026-06-01T12:00:00Z"
    ) -> Data {
        let json = """
        [{
          "id": "\(id)",
          "route_id": "\(routeId)",
          "host_id": "\(hostId)",
          "requester_id": "\(requesterId)",
          "message": "\(message)",
          "status": "\(status)",
          "created_at": "\(createdAt)"
        }]
        """
        return Data(json.utf8)
    }

    private func makeJoinRequest(
        id: String = "jr_1",
        requesterId: String = "req_xyz",
        message: String = "standard: hi",
        status: JoinRequestStatus = .pending,
        createdAt: String = "2026-06-01T12:00:00Z"
    ) -> JoinRequest {
        JoinRequest(
            id: JoinRequestId(rawValue: id),
            requesterId: requesterId,
            message: message,
            status: status,
            createdAt: createdAt
        )
    }

    // MARK: - fetchRecruitingRoutes

    func testFetchRecruitingRoutesReturnsOnlyOpenOrForming() async throws {
        let routes = [
            makeRoute(id: "r_open", companionStatus: .open),
            makeRoute(id: "r_forming", companionStatus: .forming),
            makeRoute(id: "r_closed", companionStatus: .closed),
            makeRoute(id: "r_completed", companionStatus: .completed),
        ]
        client.getResponses["routes"] = .success(routesJSON(routes))

        let result = try await remote.fetchRecruitingRoutes(cityCode: "TYO")

        let ids = Set(result.map { $0.id.rawValue })
        XCTAssertEqual(ids, ["r_open", "r_forming"],
            "Only open/forming routes survive the client-side filter")
        // GET hit the routes table with a city_code filter.
        let query = client.getQuery(forTable: "routes")
        XCTAssertEqual(query?.first?.name, "city_code")
        XCTAssertEqual(query?.first?.value, "eq.TYO")
    }

    func testFetchRecruitingRoutesEmptyDataReturnsEmpty() async throws {
        client.getResponses["routes"] = .success(Data())
        let result = try await remote.fetchRecruitingRoutes(cityCode: "TYO")
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - sendJoinRequest

    func testSendJoinRequestPostsPacePrefixedMessageToJoinRequests() async throws {
        // fetchRoute → returns the route so hostId is resolvable.
        client.getResponses["routes"] = .success(routesJSON([makeRoute(id: "route_1", hostId: "host_abc")]))

        try await remote.sendJoinRequest(routeId: RouteId(rawValue: "route_1"),
                                         message: "want to join",
                                         pace: "relaxed")

        // POST went to join_requests exactly once.
        XCTAssertEqual(client.postCount(forTable: "join_requests"), 1)
        let body = try XCTUnwrap(client.postBody(forTable: "join_requests"))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(obj["message"] as? String, "relaxed: want to join",
            "Message must be prefixed with the pace preference")
        XCTAssertEqual(obj["route_id"] as? String, "route_1")
        XCTAssertEqual(obj["host_id"] as? String, "host_abc")
        XCTAssertEqual(obj["status"] as? String, "pending")
    }

    func testSendJoinRequestNoRouteIsNoop() async throws {
        // fetchRoute returns empty → no host → no POST.
        client.getResponses["routes"] = .success(Data())
        try await remote.sendJoinRequest(routeId: RouteId(rawValue: "missing"),
                                         message: "hi", pace: "standard")
        XCTAssertEqual(client.postCount(forTable: "join_requests"), 0)
    }

    // MARK: - fetchInbox

    func testFetchInboxUsesHostIdAndPendingStatusQuery() async throws {
        client.getResponses["join_requests"] = .success(joinRequestRowsJSON(message: "standard: yo"))

        let inbox = try await remote.fetchInbox()

        XCTAssertEqual(inbox.count, 1)
        XCTAssertEqual(inbox.first?.message, "standard: yo")
        XCTAssertEqual(inbox.first?.status, .pending)

        let query = try XCTUnwrap(client.getQuery(forTable: "join_requests"))
        // host_id filter uses the device's id.
        let expectedHostId = DeviceIdentityService.shared.deviceID
        let hostItem = query.first { $0.name == "host_id" }
        XCTAssertEqual(hostItem?.value, "eq.\(expectedHostId)")
        // status pending.
        let statusItem = query.first { $0.name == "status" }
        XCTAssertEqual(statusItem?.value, "eq.pending")
        // ordered.
        XCTAssertTrue(query.contains { $0.name == "order" && $0.value == "created_at.desc" })
    }

    func testFetchInboxEmptyReturnsEmpty() async throws {
        client.getResponses["join_requests"] = .success(Data())
        let inbox = try await remote.fetchInbox()
        XCTAssertTrue(inbox.isEmpty)
    }

    // MARK: - accept

    func testAcceptAddsRequesterToConfirmedMembersAndUpsertsRoute() async throws {
        let route = makeRoute(id: "route_1", companionStatus: .open, hostId: "host_abc")
        client.getResponses["routes"] = .success(routesJSON([route]))
        let request = makeJoinRequest(id: "jr_1", requesterId: "req_xyz")

        try await remote.accept(request, route: route)

        // 1) join_requests row upserted with accepted status.
        let jrBody = try XCTUnwrap(client.postBody(forTable: "join_requests"))
        let jr = try XCTUnwrap(JSONSerialization.jsonObject(with: jrBody) as? [String: Any])
        XCTAssertEqual(jr["status"] as? String, "accepted")

        // 2) route upserted with requester added to confirmedMembers.
        let routeBody = try XCTUnwrap(client.postBody(forTable: "routes"))
        let upserted = try XCTUnwrap(decodeUpsertedRoute(routeBody))
        XCTAssertTrue(upserted.companion?.confirmedMembers.contains("req_xyz") ?? false,
            "Accepting must add the requester to confirmedMembers")
        // open → forming after first accept.
        XCTAssertEqual(upserted.companion?.status, .forming)
    }

    func testDeclineUpdatesRequestStatusOnlyNoRouteUpsert() async throws {
        let route = makeRoute(id: "route_1", companionStatus: .open, hostId: "host_abc")
        client.getResponses["routes"] = .success(routesJSON([route]))
        let request = makeJoinRequest(id: "jr_1", requesterId: "req_xyz")

        try await remote.decline(request, route: route)

        let jrBody = try XCTUnwrap(client.postBody(forTable: "join_requests"))
        let jr = try XCTUnwrap(JSONSerialization.jsonObject(with: jrBody) as? [String: Any])
        XCTAssertEqual(jr["status"] as? String, "declined")
        // Decline must NOT touch the route (no member changes).
        XCTAssertEqual(client.postCount(forTable: "routes"), 0,
            "Decline must not upsert the route")
    }

    func testWithdrawUpdatesRequestStatusOnlyNoRouteUpsert() async throws {
        let route = makeRoute(id: "route_1", companionStatus: .open, hostId: "host_abc")
        client.getResponses["routes"] = .success(routesJSON([route]))
        let request = makeJoinRequest(id: "jr_1", requesterId: "req_xyz")

        try await remote.withdraw(request, route: route)

        let jrBody = try XCTUnwrap(client.postBody(forTable: "join_requests"))
        let jr = try XCTUnwrap(JSONSerialization.jsonObject(with: jrBody) as? [String: Any])
        XCTAssertEqual(jr["status"] as? String, "withdrawn")
        XCTAssertEqual(client.postCount(forTable: "routes"), 0,
            "Withdraw must not upsert the route")
    }

    // MARK: - markCompleted

    func testMarkCompletedAdvancesStatusAndVerifies() async throws {
        // State machine only allows .closed → .completed, so seed a closed route
        // with confirmed members to credit as walkers.
        let route = makeRoute(
            id: "route_1",
            companionStatus: .closed,
            hostId: "host_abc",
            confirmedMembers: ["m1", "m2"]
        )
        client.getResponses["routes"] = .success(routesJSON([route]))

        try await remote.markCompleted(routeId: RouteId(rawValue: "route_1"))

        let routeBody = try XCTUnwrap(client.postBody(forTable: "routes"))
        let upserted = try XCTUnwrap(decodeUpsertedRoute(routeBody))
        XCTAssertEqual(upserted.companion?.status, .completed,
            "Companion must advance to completed")
        XCTAssertEqual(upserted.verification.status, .verified,
            "Verification must flip to verified")
        XCTAssertEqual(upserted.verification.walkedByCount, 2,
            "Confirmed members are credited as walkers")
        XCTAssertEqual(Set(upserted.verification.walkedBy), ["m1", "m2"])
    }

    func testMarkCompletedThrowsOnIllegalTransition() async throws {
        // open → markCompleted is not a legal transition; SUT must rethrow.
        let route = makeRoute(id: "route_1", companionStatus: .open)
        client.getResponses["routes"] = .success(routesJSON([route]))

        do {
            try await remote.markCompleted(routeId: RouteId(rawValue: "route_1"))
            XCTFail("markCompleted from .open must throw IllegalTransition")
        } catch is RouteCompanionStateMachine.IllegalTransition {
            // expected
        }
        // No route upsert should have happened.
        XCTAssertEqual(client.postCount(forTable: "routes"), 0)
    }

    // MARK: - Network failure propagation (never silently swallowed)

    func testFetchRecruitingRoutesThrowsOnNetworkFailure() async {
        client.getResponses["routes"] = .failure(.requestFailed(status: 500, body: "boom"))
        await assertThrowsSupabaseError {
            _ = try await self.remote.fetchRecruitingRoutes(cityCode: "TYO")
        }
    }

    func testFetchInboxThrowsOnNetworkFailure() async {
        client.getResponses["join_requests"] = .failure(.requestFailed(status: 503, body: "down"))
        await assertThrowsSupabaseError {
            _ = try await self.remote.fetchInbox()
        }
    }

    func testSendJoinRequestThrowsWhenPostFails() async {
        client.getResponses["routes"] = .success(routesJSON([makeRoute(id: "route_1", hostId: "host_abc")]))
        client.postResponses["join_requests"] = .failure(.requestFailed(status: 500, body: "no"))
        await assertThrowsSupabaseError {
            try await self.remote.sendJoinRequest(routeId: RouteId(rawValue: "route_1"),
                                                  message: "hi", pace: "standard")
        }
    }

    func testAcceptThrowsWhenRouteUpsertFails() async {
        let route = makeRoute(id: "route_1", companionStatus: .open, hostId: "host_abc")
        client.getResponses["routes"] = .success(routesJSON([route]))
        client.postResponses["routes"] = .failure(.requestFailed(status: 500, body: "no"))
        await assertThrowsSupabaseError {
            try await self.remote.accept(self.makeJoinRequest(), route: route)
        }
    }

    // MARK: - FeatureFlags.companion gate (no-op when off)

    func testMethodsAreNoopWhenCompanionFlagOff() async throws {
        UserDefaults.standard.set(false, forKey: "FF_COMPANION")
        defer { UserDefaults.standard.set(true, forKey: "FF_COMPANION") }

        // Even with a failing backend configured, an off flag short-circuits
        // before any network call, so nothing should throw or hit the client.
        client.getResponses["routes"] = .failure(.requestFailed(status: 500, body: "should-not-run"))
        client.getResponses["join_requests"] = .failure(.requestFailed(status: 500, body: "should-not-run"))

        let routes = try await remote.fetchRecruitingRoutes(cityCode: "TYO")
        XCTAssertTrue(routes.isEmpty)

        let inbox = try await remote.fetchInbox()
        XCTAssertTrue(inbox.isEmpty)

        try await remote.sendJoinRequest(routeId: RouteId(rawValue: "route_1"),
                                         message: "hi", pace: "standard")
        try await remote.markCompleted(routeId: RouteId(rawValue: "route_1"))
        try await remote.accept(makeJoinRequest(), route: makeRoute())
        try await remote.decline(makeJoinRequest(), route: makeRoute())
        try await remote.withdraw(makeJoinRequest(), route: makeRoute())

        XCTAssertTrue(client.posts.isEmpty, "No POSTs when companion flag is off")
        XCTAssertTrue(client.gets.isEmpty, "No GETs when companion flag is off")
    }

    // MARK: - Helpers

    /// Assert the async body throws a `SupabaseClient.SupabaseError` (not a silent swallow).
    private func assertThrowsSupabaseError(
        _ body: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await body()
            XCTFail("Expected SupabaseError to be thrown", file: file, line: line)
        } catch is SupabaseClient.SupabaseError {
            // expected
        } catch {
            XCTFail("Expected SupabaseError, got \(error)", file: file, line: line)
        }
    }
}
