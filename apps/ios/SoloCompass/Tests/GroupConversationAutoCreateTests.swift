import XCTest
import SwiftData
@testable import SoloCompass

// MARK: - US-036: Auto-create group conversation on first accept (open → forming)

@MainActor
final class GroupConversationAutoCreateTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var routeStore: RouteStore!
    private var convStore: ConversationStore!
    private var remote: LocalRouteCompanionRemote!

    override func setUp() async throws {
        try await super.setUp()
        container = SoloCompassModelContainer.makeInMemory()
        context = ModelContext(container)
        routeStore = RouteStore(context: context)
        convStore = ConversationStore(context: context)
        remote = LocalRouteCompanionRemote(store: routeStore)
    }

    override func tearDown() async throws {
        remote = nil
        convStore = nil
        routeStore = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeMekongSunset() -> Route {
        let window = DepartureWindow(startDate: "2026-06-01", to: "2026-06-03", time: "17:00")
        let companion = RouteCompanion(
            status: .open,
            hostId: "maya",
            departureWindow: window,
            departureLabel: "Early June evenings",
            pacePreference: .relaxed,
            maxMembers: 5,
            confirmedMembers: ["maya", "lin"],
            joinRequests: [
                JoinRequest(
                    id: JoinRequestId(rawValue: "jr_mekong_001"),
                    requesterId: "tomas",
                    message: "matching: Would love to catch the sunset!",
                    status: .pending,
                    createdAt: "2026-05-28T08:00:00Z"
                ),
                JoinRequest(
                    id: JoinRequestId(rawValue: "jr_mekong_002"),
                    requesterId: "ren",
                    message: "matching: Sounds magical, count me in",
                    status: .pending,
                    createdAt: "2026-05-28T08:01:00Z"
                ),
            ],
            visibility: .public,
            groupConversationId: nil,
            hostMessage: "Bringing a speaker, come as you are."
        )
        return Route(
            id: RouteId(rawValue: "mekong-sunset"),
            title: "Mekong Sunset",
            summary: "A 45-minute promenade walk.",
            experienceIds: ["exp_vte_mekong_riverside_sunset"],
            cityCode: "VTE",
            region: "Riverfront",
            estimatedDuration: 90,
            distanceMeters: 1200,
            pace: .relaxed,
            tags: ["sunset", "river"],
            source: .editorial,
            companion: companion
        )
    }

    // MARK: - First accept: open → forming

    func testFirstAcceptCreatesGroupConversation() async throws {
        let route = makeMekongSunset()
        routeStore.save(route)

        let request = route.companion!.joinRequests[0] // tomas, pending
        try await remote.accept(request, route: route)

        let updated = try XCTUnwrap(routeStore.get(route.id))
        let companion = try XCTUnwrap(updated.companion)

        XCTAssertEqual(companion.status, .forming, "Status must transition open → forming on first accept")
        XCTAssertNotNil(companion.groupConversationId, "groupConversationId must be set after first accept")

        let convId = try XCTUnwrap(companion.groupConversationId)
        let conversation = try XCTUnwrap(convStore.get(ConversationId(rawValue: convId)))

        XCTAssertEqual(conversation.type, .groupRoute)
        XCTAssertEqual(conversation.routeId, route.id.rawValue)
        XCTAssertTrue(conversation.participantIds.contains("maya"), "Host must be in participants")
        XCTAssertTrue(conversation.participantIds.contains("tomas"), "Accepted requester must be in participants")
    }

    // MARK: - Subsequent accept: stays forming, appends to conversation

    func testSubsequentAcceptAppendsToExistingConversation() async throws {
        let route = makeMekongSunset()
        routeStore.save(route)

        // Accept first request (tomas) → creates conversation, open → forming
        let firstRequest = route.companion!.joinRequests[0]
        try await remote.accept(firstRequest, route: route)

        let afterFirst = try XCTUnwrap(routeStore.get(route.id))
        let convIdStr = try XCTUnwrap(afterFirst.companion?.groupConversationId)
        let convAfterFirst = try XCTUnwrap(convStore.get(ConversationId(rawValue: convIdStr)))
        XCTAssertEqual(convAfterFirst.participantIds.count, 2)

        // Accept second request (ren) → stays forming, appends to conversation
        let secondRequest = try XCTUnwrap(
            afterFirst.companion?.joinRequests.first(where: { $0.requesterId == "ren" })
        )
        try await remote.accept(secondRequest, route: afterFirst)

        let afterSecond = try XCTUnwrap(routeStore.get(route.id))
        XCTAssertEqual(afterSecond.companion?.status, .forming)
        XCTAssertEqual(afterSecond.companion?.groupConversationId, convIdStr,
            "groupConversationId must not change on subsequent accepts")

        let convAfterSecond = try XCTUnwrap(convStore.get(ConversationId(rawValue: convIdStr)))
        XCTAssertTrue(convAfterSecond.participantIds.contains("ren"),
            "Second requester must be added to existing conversation")
        XCTAssertEqual(convAfterSecond.participantIds.count, 3,
            "Conversation must have host + both accepted requesters")
    }

    // MARK: - groupConversationId not set for declined requests

    func testDeclinedRequestDoesNotCreateConversation() async throws {
        let route = makeMekongSunset()
        routeStore.save(route)

        let request = route.companion!.joinRequests[0]
        try await remote.decline(request, route: route)

        let updated = try XCTUnwrap(routeStore.get(route.id))
        XCTAssertNil(updated.companion?.groupConversationId,
            "Declining must not create a group conversation")
        XCTAssertEqual(updated.companion?.status, .open)
    }
}
