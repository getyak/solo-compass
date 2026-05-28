import XCTest
import SwiftData
@testable import SoloCompass

// MARK: - US-038: CompletionMoment — state mutation tests (no UI)

@MainActor
final class CompletionMomentTests: XCTestCase {

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

    private func makeClosedRoute(
        confirmedMembers: [String] = ["user-a", "user-b", "user-c"],
        existingWalkedBy: [String] = ["maya", "leo"],
        existingWalkedByCount: Int = 15,
        groupConversationId: String? = nil
    ) -> Route {
        let companion = RouteCompanion(
            status: .closed,
            hostId: "host-preview",
            departureWindow: DepartureWindow(startDate: "2026-06-01", to: "2026-06-03", time: "morning"),
            departureLabel: "Early June",
            pacePreference: .relaxed,
            maxMembers: 4,
            confirmedMembers: confirmedMembers,
            joinRequests: [],
            visibility: .public,
            groupConversationId: groupConversationId,
            hostMessage: nil
        )
        return Route(
            id: RouteId(rawValue: "mekong-sunset"),
            title: "Mekong Sunset Walk",
            summary: "",
            experienceIds: [],
            cityCode: "VTE",
            region: "Riverfront",
            estimatedDuration: 90,
            distanceMeters: 1200,
            pace: .relaxed,
            source: .editorial,
            verification: RouteVerification(
                status: .walkedBy,
                walkedByCount: existingWalkedByCount,
                walkedBy: existingWalkedBy
            ),
            companion: companion
        )
    }

    // MARK: - State machine: closed → completed

    func testMarkCompletedTransitionsStatusToCompleted() async throws {
        let route = makeClosedRoute()
        routeStore.save(route)

        try await remote.markCompleted(routeId: route.id)

        let updated = try XCTUnwrap(routeStore.get(route.id))
        XCTAssertEqual(updated.companion?.status, .completed)
    }

    // MARK: - Verification fields updated atomically

    func testMarkCompletedSetsVerificationStatusToVerified() async throws {
        let route = makeClosedRoute()
        routeStore.save(route)

        try await remote.markCompleted(routeId: route.id)

        let updated = try XCTUnwrap(routeStore.get(route.id))
        XCTAssertEqual(updated.verification.status, .verified)
    }

    func testMarkCompletedIncrementsWalkedByCount() async throws {
        let confirmedMembers = ["user-a", "user-b", "user-c"]
        let route = makeClosedRoute(confirmedMembers: confirmedMembers, existingWalkedByCount: 15)
        routeStore.save(route)

        try await remote.markCompleted(routeId: route.id)

        let updated = try XCTUnwrap(routeStore.get(route.id))
        XCTAssertEqual(updated.verification.walkedByCount, 15 + confirmedMembers.count)
    }

    func testMarkCompletedAppendsNewMembersToWalkedBy() async throws {
        let confirmedMembers = ["user-a", "user-b", "user-c"]
        let route = makeClosedRoute(
            confirmedMembers: confirmedMembers,
            existingWalkedBy: ["maya", "leo"]
        )
        routeStore.save(route)

        try await remote.markCompleted(routeId: route.id)

        let updated = try XCTUnwrap(routeStore.get(route.id))
        XCTAssertTrue(updated.verification.walkedBy.contains("user-a"))
        XCTAssertTrue(updated.verification.walkedBy.contains("user-b"))
        XCTAssertTrue(updated.verification.walkedBy.contains("user-c"))
        XCTAssertTrue(updated.verification.walkedBy.contains("maya"))
        XCTAssertTrue(updated.verification.walkedBy.contains("leo"))
    }

    func testMarkCompletedDoesNotDuplicateExistingWalkedBy() async throws {
        // user-a is already in walkedBy — should not appear twice
        let route = makeClosedRoute(
            confirmedMembers: ["user-a", "user-b"],
            existingWalkedBy: ["user-a", "maya"]
        )
        routeStore.save(route)

        try await remote.markCompleted(routeId: route.id)

        let updated = try XCTUnwrap(routeStore.get(route.id))
        let count = updated.verification.walkedBy.filter { $0 == "user-a" }.count
        XCTAssertEqual(count, 1, "user-a must not be duplicated in walkedBy")
    }

    // MARK: - Group conversation marked readOnly

    func testMarkCompletedSetsGroupConversationReadOnly() async throws {
        let convId = ConversationId(rawValue: "conv-mekong-001")
        let now = ISO8601DateFormatter().string(from: Date())
        let conversation = Conversation(
            id: convId,
            requestId: CompanionRequestId(rawValue: "creq-001"),
            participantIds: ["host-preview", "user-a", "user-b", "user-c"],
            type: .groupRoute,
            routeId: "mekong-sunset",
            createdAt: now,
            updatedAt: now,
            isReadOnly: false
        )
        convStore.save(conversation)

        let route = makeClosedRoute(groupConversationId: convId.rawValue)
        routeStore.save(route)

        try await remote.markCompleted(routeId: route.id)

        let updatedConv = try XCTUnwrap(convStore.get(convId))
        XCTAssertTrue(updatedConv.isReadOnly, "Group conversation must be marked readOnly after completion")
    }

    // MARK: - Illegal transition guard

    func testMarkCompletedThrowsForOpenRoute() async throws {
        var companion = RouteCompanion()
        companion.status = .open
        var route = makeClosedRoute()
        route.companion!.status = .open
        routeStore.save(route)

        do {
            try await remote.markCompleted(routeId: route.id)
            XCTFail("Expected IllegalTransition to be thrown")
        } catch is RouteCompanionStateMachine.IllegalTransition {
            // expected
        }
    }
}
