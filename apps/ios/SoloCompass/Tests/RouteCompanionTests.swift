import XCTest
@testable import SoloCompass

final class RouteCompanionTests: XCTestCase {

    // MARK: - JoinRequest encode/decode round-trip

    func testJoinRequestRoundTrip() throws {
        let original = JoinRequest(
            id: JoinRequestId(rawValue: "jr-001"),
            requesterId: "user-42",
            message: "Looking forward to exploring together!",
            status: .pending,
            createdAt: "2026-05-28T09:00:00Z"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JoinRequest.self, from: data)

        XCTAssertEqual(decoded.id.rawValue, original.id.rawValue)
        XCTAssertEqual(decoded.requesterId, original.requesterId)
        XCTAssertEqual(decoded.message, original.message)
        XCTAssertEqual(decoded.status, original.status)
        XCTAssertEqual(decoded.createdAt, original.createdAt)
    }

    func testJoinRequestStatusCodability() throws {
        for status in JoinRequestStatus.allCases {
            let data = try JSONEncoder().encode([status])
            let decoded = try JSONDecoder().decode([JoinRequestStatus].self, from: data)
            XCTAssertEqual(decoded.first, status)
        }
    }

    // MARK: - RouteCompanion encode/decode round-trip

    func testRouteCompanionRoundTrip() throws {
        let joinRequest = JoinRequest(
            id: JoinRequestId(rawValue: "jr-002"),
            requesterId: "user-99",
            message: "Can I join?",
            status: .accepted,
            createdAt: "2026-05-27T14:30:00Z"
        )
        let window = DepartureWindow(from: "2026-06-01", to: "2026-06-03", time: "morning")
        let original = RouteCompanion(
            status: .forming,
            hostId: "user-host-1",
            departureWindow: window,
            departureLabel: "Early June",
            pacePreference: .relaxed,
            maxMembers: 3,
            confirmedMembers: ["user-host-1", "user-99"],
            joinRequests: [joinRequest],
            visibility: .linkOnly,
            groupConversationId: "conv-abc",
            hostMessage: "Easygoing walk, bring snacks."
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RouteCompanion.self, from: data)

        XCTAssertEqual(decoded.status, original.status)
        XCTAssertEqual(decoded.hostId, original.hostId)
        XCTAssertEqual(decoded.departureWindow.from, original.departureWindow.from)
        XCTAssertEqual(decoded.departureWindow.to, original.departureWindow.to)
        XCTAssertEqual(decoded.departureWindow.time, original.departureWindow.time)
        XCTAssertEqual(decoded.departureLabel, original.departureLabel)
        XCTAssertEqual(decoded.pacePreference, original.pacePreference)
        XCTAssertEqual(decoded.maxMembers, original.maxMembers)
        XCTAssertEqual(decoded.confirmedMembers, original.confirmedMembers)
        XCTAssertEqual(decoded.joinRequests.count, 1)
        XCTAssertEqual(decoded.joinRequests[0].id.rawValue, joinRequest.id.rawValue)
        XCTAssertEqual(decoded.joinRequests[0].status, joinRequest.status)
        XCTAssertEqual(decoded.visibility, original.visibility)
        XCTAssertEqual(decoded.groupConversationId, original.groupConversationId)
        XCTAssertEqual(decoded.hostMessage, original.hostMessage)
    }

    func testRouteCompanionRoundTripWithNilOptionals() throws {
        let window = DepartureWindow(from: "2026-07-10", to: "2026-07-12", time: "flexible")
        let original = RouteCompanion(
            status: .open,
            hostId: "user-solo",
            departureWindow: window,
            departureLabel: "Mid July",
            pacePreference: .flexible,
            maxMembers: 2,
            confirmedMembers: [],
            joinRequests: [],
            visibility: .public,
            groupConversationId: nil,
            hostMessage: nil
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RouteCompanion.self, from: data)

        XCTAssertEqual(decoded.status, .open)
        XCTAssertEqual(decoded.hostId, "user-solo")
        XCTAssertTrue(decoded.confirmedMembers.isEmpty)
        XCTAssertTrue(decoded.joinRequests.isEmpty)
        XCTAssertEqual(decoded.visibility, .public)
        XCTAssertNil(decoded.groupConversationId)
        XCTAssertNil(decoded.hostMessage)
    }

    func testRouteCompanionDefaultInit() throws {
        let companion = RouteCompanion()
        XCTAssertEqual(companion.status, .open)
        XCTAssertEqual(companion.pacePreference, .standard)
        XCTAssertEqual(companion.maxMembers, 4)
        XCTAssertEqual(companion.visibility, .public)
        XCTAssertTrue(companion.confirmedMembers.isEmpty)
        XCTAssertTrue(companion.joinRequests.isEmpty)
        XCTAssertNil(companion.groupConversationId)
        XCTAssertNil(companion.hostMessage)

        let data = try JSONEncoder().encode(companion)
        let decoded = try JSONDecoder().decode(RouteCompanion.self, from: data)
        XCTAssertEqual(decoded.status, companion.status)
        XCTAssertEqual(decoded.pacePreference, companion.pacePreference)
    }

    // MARK: - Enum codability

    func testCompanionStatusCodability() throws {
        for status in CompanionStatus.allCases {
            let data = try JSONEncoder().encode([status])
            let decoded = try JSONDecoder().decode([CompanionStatus].self, from: data)
            XCTAssertEqual(decoded.first, status)
        }
    }

    func testPacePreferenceCodability() throws {
        for pref in PacePreference.allCases {
            let data = try JSONEncoder().encode([pref])
            let decoded = try JSONDecoder().decode([PacePreference].self, from: data)
            XCTAssertEqual(decoded.first, pref)
        }
    }

    func testRouteCompanionVisibilityCodability() throws {
        for vis in RouteCompanionVisibility.allCases {
            let data = try JSONEncoder().encode([vis])
            let decoded = try JSONDecoder().decode([RouteCompanionVisibility].self, from: data)
            XCTAssertEqual(decoded.first, vis)
        }
    }
}
