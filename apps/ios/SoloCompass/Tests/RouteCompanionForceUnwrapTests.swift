import XCTest
import SwiftData
@testable import SoloCompass

// MARK: - US-001: route.companion force-unwrap safety
//
// Verifies every mutation path in `LocalRouteCompanionRemote` no-ops cleanly
// (no crash, no data mutation) when the persisted route has `companion == nil`.
// These paths previously force-unwrapped `route.companion!` and would trap.

@MainActor
final class RouteCompanionForceUnwrapTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var routeStore: RouteStore!
    private var remote: LocalRouteCompanionRemote!

    override func setUp() async throws {
        try await super.setUp()
        container = SoloCompassModelContainer.makeInMemory()
        context = ModelContext(container)
        routeStore = RouteStore(context: context)
        remote = LocalRouteCompanionRemote(store: routeStore)
    }

    override func tearDown() async throws {
        remote = nil
        routeStore = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// A solo route with no companion data — the nil case under test.
    private func makeSoloRoute() -> Route {
        Route(
            id: RouteId(rawValue: "solo-walk"),
            title: "Solo Walk",
            summary: "A quiet stroll, no companions.",
            experienceIds: ["exp_solo_001"],
            cityCode: "VTE",
            region: "Riverfront",
            estimatedDuration: 60,
            distanceMeters: 800,
            pace: .relaxed,
            tags: ["quiet"],
            source: .editorial,
            companion: nil
        )
    }

    private func makeRequest() -> JoinRequest {
        JoinRequest(
            id: JoinRequestId(rawValue: "jr_solo_001"),
            requesterId: "tomas",
            message: "matching: mind if I join?",
            status: .pending,
            createdAt: "2026-05-28T08:00:00Z"
        )
    }

    // MARK: - sendJoinRequest

    func testSendJoinRequestNoOpsWhenCompanionNil() async throws {
        let route = makeSoloRoute()
        routeStore.save(route)

        try await remote.sendJoinRequest(routeId: route.id, message: "hi", pace: "relaxed")

        let updated = try XCTUnwrap(routeStore.get(route.id))
        XCTAssertNil(updated.companion, "companion must remain nil — no mutation on the nil path")
    }

    // MARK: - accept

    func testAcceptNoOpsWhenCompanionNil() async throws {
        let route = makeSoloRoute()
        routeStore.save(route)

        try await remote.accept(makeRequest(), route: route)

        let updated = try XCTUnwrap(routeStore.get(route.id))
        XCTAssertNil(updated.companion, "companion must remain nil on accept's nil path")
    }

    // MARK: - decline

    func testDeclineNoOpsWhenCompanionNil() async throws {
        let route = makeSoloRoute()
        routeStore.save(route)

        try await remote.decline(makeRequest(), route: route)

        let updated = try XCTUnwrap(routeStore.get(route.id))
        XCTAssertNil(updated.companion, "companion must remain nil on decline's nil path")
    }

    // MARK: - withdraw

    func testWithdrawNoOpsWhenCompanionNil() async throws {
        let route = makeSoloRoute()
        routeStore.save(route)

        try await remote.withdraw(makeRequest(), route: route)

        let updated = try XCTUnwrap(routeStore.get(route.id))
        XCTAssertNil(updated.companion, "companion must remain nil on withdraw's nil path")
    }

    // MARK: - markCompleted

    func testMarkCompletedNoOpsWhenCompanionNil() async throws {
        let route = makeSoloRoute()
        routeStore.save(route)

        // Must not throw and must not crash when companion is nil.
        try await remote.markCompleted(routeId: route.id)

        let updated = try XCTUnwrap(routeStore.get(route.id))
        XCTAssertNil(updated.companion, "companion must remain nil on markCompleted's nil path")
        XCTAssertEqual(updated.verification.status, route.verification.status,
            "verification must be untouched when the safety path triggers")
    }
}
