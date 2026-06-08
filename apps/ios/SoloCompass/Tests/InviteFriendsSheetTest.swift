import XCTest
import SwiftUI
import SwiftData
@testable import SoloCompass

/// US-020 verification: a host invites friends straight into a recruiting route
/// with NO approval step — they land directly in `confirmedMembers`, the group
/// conversation gets the new participants, and the companion status machine
/// advances. Also renders the sheet to /tmp for the simulator visual check.
@MainActor
final class InviteFriendsSheetTest: XCTestCase {

    private static let outDir = URL(fileURLWithPath: "/tmp/sc-invite-friends")

    private func makeRoute(in ctx: ModelContext, maxMembers: Int = 4) -> Route {
        let store = RouteStore(context: ctx)
        let companion = RouteCompanion(
            status: .open,
            hostId: "local",
            departureWindow: DepartureWindow(startDate: "2026-07-01", to: "2026-07-03", time: "morning"),
            departureLabel: "Jul 1–3 · morning",
            maxMembers: maxMembers
        )
        let route = Route(
            id: RouteId(rawValue: "mekong-sunset"),
            title: "Mekong Sunset Walk",
            summary: "Dawn at the river.",
            experienceIds: ["e1", "e2"],
            cityCode: "VTE",
            region: "Riverfront",
            estimatedDuration: 90,
            distanceMeters: 1200,
            pace: .relaxed,
            tags: [],
            source: .editorial,
            companion: companion
        )
        store.save(route)
        return route
    }

    // D-3: friends go straight into confirmedMembers — no JoinRequest created.
    func testInviteAddsFriendsDirectlyNoApproval() throws {
        let container = SoloCompassModelContainer.makeInMemory()
        let ctx = ModelContext(container)
        let route = makeRoute(in: ctx)

        let added = InviteFriendsSheet.confirmFriends(
            ["maya", "kenji"],
            into: route,
            contextProvider: { ctx }
        )

        XCTAssertEqual(Set(added), ["maya", "kenji"])

        let updated = try XCTUnwrap(RouteStore(context: ctx).get(route.id))
        let companion = try XCTUnwrap(updated.companion)
        // Directly confirmed, no pending request anywhere.
        XCTAssertEqual(Set(companion.confirmedMembers), ["maya", "kenji"])
        XCTAssertTrue(companion.joinRequests.isEmpty, "invite must not create join requests")
        // First accept opened the group → status advanced to forming.
        XCTAssertEqual(companion.status, .forming)

        // Group conversation carries host + both invited friends (Realtime sync).
        let convId = try XCTUnwrap(companion.groupConversationId)
        let conv = try XCTUnwrap(
            ConversationStore(context: ctx).get(ConversationId(rawValue: convId))
        )
        XCTAssertEqual(conv.type, .groupRoute)
        XCTAssertEqual(Set(conv.participantIds), ["local", "maya", "kenji"])
    }

    // Host can never overfill past maxMembers.
    func testInviteRespectsCapacity() throws {
        let container = SoloCompassModelContainer.makeInMemory()
        let ctx = ModelContext(container)
        let route = makeRoute(in: ctx, maxMembers: 2)

        let added = InviteFriendsSheet.confirmFriends(
            ["a", "b", "c"],
            into: route,
            contextProvider: { ctx }
        )
        XCTAssertEqual(added.count, 2, "should stop at the 2-seat cap")

        let companion = try XCTUnwrap(RouteStore(context: ctx).get(route.id)?.companion)
        XCTAssertEqual(companion.confirmedMembers.count, 2)
        XCTAssertEqual(companion.status, .closed, "reaching max closes the slot")
    }

    // Visual: render the picker to /tmp for the simulator check.
    func testRenderSheet() throws {
        let container = SoloCompassModelContainer.makeInMemory()
        let ctx = ModelContext(container)
        let route = makeRoute(in: ctx)

        let service = FriendService()
        service.friends = [
            Friendship(
                id: FriendshipId(rawValue: "fnd_01"),
                userLowId: "local", userHighId: "maya", initiatedBy: "local",
                conversationId: nil, acceptedAt: "2026-05-01T10:00:00Z",
                createdAt: "2026-05-01T10:00:00Z", updatedAt: "2026-05-01T10:00:00Z"
            ),
            Friendship(
                id: FriendshipId(rawValue: "fnd_02"),
                userLowId: "kenji", userHighId: "local", initiatedBy: "kenji",
                conversationId: nil, acceptedAt: "2026-05-02T10:00:00Z",
                createdAt: "2026-05-02T10:00:00Z", updatedAt: "2026-05-02T10:00:00Z"
            ),
        ]

        let view = InviteFriendsSheet(
            route: route, contextProvider: { ctx }, friendService: service
        )
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = .light
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let window = UIWindow(frame: host.view.frame)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))

        let renderer = UIGraphicsImageRenderer(bounds: host.view.bounds)
        let img = renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
        let data = try XCTUnwrap(img.pngData())
        try data.write(to: Self.outDir.appendingPathComponent("invite-friends-sheet.png"))
        XCTAssertGreaterThan(img.size.width, 0)
    }
}
