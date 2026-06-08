import XCTest
@testable import SoloCompass

// MARK: - US-035: Conversation type + routeId

final class ConversationTests: XCTestCase {

    private let encoder = JSONEncoder.iso8601Encoder
    private let decoder = JSONDecoder.iso8601Decoder

    // MARK: - ConversationType round-trip

    func testConversationTypeOneOnOneRoundTrip() throws {
        let data = try encoder.encode(ConversationType.oneOnOne)
        let decoded = try decoder.decode(ConversationType.self, from: data)
        XCTAssertEqual(decoded, .oneOnOne)
    }

    func testConversationTypeGroupRouteRoundTrip() throws {
        let data = try encoder.encode(ConversationType.groupRoute)
        let decoded = try decoder.decode(ConversationType.self, from: data)
        XCTAssertEqual(decoded, .groupRoute)
    }

    // MARK: - Default type preserves existing behavior

    func testDefaultTypeIsOneOnOne() {
        let conv = Conversation(
            id: ConversationId(rawValue: "c1"),
            requestId: CompanionRequestId(rawValue: "r1"),
            participantIds: ["u1", "u2"],
            createdAt: "2026-05-28T00:00:00Z",
            updatedAt: "2026-05-28T00:00:00Z"
        )
        XCTAssertEqual(conv.type, .oneOnOne)
        XCTAssertNil(conv.routeId)
    }

    // MARK: - oneOnOne JSON round-trip

    func testOneOnOneConversationJSONRoundTrip() throws {
        let original = Conversation(
            id: ConversationId(rawValue: "conv_1"),
            requestId: CompanionRequestId(rawValue: "creq_1"),
            participantIds: ["user_a", "user_b"],
            type: .oneOnOne,
            routeId: nil,
            lastMessageAt: "2026-05-28T12:00:00Z",
            createdAt: "2026-05-28T09:00:00Z",
            updatedAt: "2026-05-28T12:00:00Z"
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Conversation.self, from: data)

        XCTAssertEqual(decoded.id.rawValue, original.id.rawValue)
        XCTAssertEqual(decoded.requestId?.rawValue, original.requestId?.rawValue)
        XCTAssertEqual(decoded.participantIds, original.participantIds)
        XCTAssertEqual(decoded.type, .oneOnOne)
        XCTAssertNil(decoded.routeId)
        XCTAssertEqual(decoded.lastMessageAt, original.lastMessageAt)
        XCTAssertEqual(decoded.createdAt, original.createdAt)
        XCTAssertEqual(decoded.updatedAt, original.updatedAt)
    }

    // MARK: - groupRoute JSON round-trip

    func testGroupRouteConversationJSONRoundTrip() throws {
        let original = Conversation(
            id: ConversationId(rawValue: "conv_group_1"),
            requestId: CompanionRequestId(rawValue: "creq_group_1"),
            participantIds: ["user_a", "user_b", "user_c"],
            type: .groupRoute,
            routeId: "route_123",
            lastMessageAt: "2026-05-28T15:00:00Z",
            createdAt: "2026-05-28T10:00:00Z",
            updatedAt: "2026-05-28T15:00:00Z"
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Conversation.self, from: data)

        XCTAssertEqual(decoded.id.rawValue, original.id.rawValue)
        XCTAssertEqual(decoded.requestId?.rawValue, original.requestId?.rawValue)
        XCTAssertEqual(decoded.participantIds, original.participantIds)
        XCTAssertEqual(decoded.type, .groupRoute)
        XCTAssertEqual(decoded.routeId, "route_123")
        XCTAssertEqual(decoded.lastMessageAt, original.lastMessageAt)
    }

    // MARK: - US-011: friendDirect — requestId optional, never read-only

    func testConversationTypeFriendDirectRoundTrip() throws {
        let data = try encoder.encode(ConversationType.friendDirect)
        let decoded = try decoder.decode(ConversationType.self, from: data)
        XCTAssertEqual(decoded, .friendDirect)
    }

    func testFriendDirectConversationHasNoRequestId() {
        // A friend DM is created from a Friendship, not a CompanionRequest.
        let conv = Conversation(
            id: ConversationId(rawValue: "conv_friend"),
            participantIds: ["user_a", "user_b"],
            type: .friendDirect,
            createdAt: "2026-06-01T00:00:00Z",
            updatedAt: "2026-06-01T00:00:00Z"
        )
        XCTAssertNil(conv.requestId)
        XCTAssertEqual(conv.type, .friendDirect)
    }

    func testFriendDirectIsNeverReadOnly() {
        // Even if a stale isReadOnly=true is passed, friendDirect forces false:
        // a friendship has no route to complete, so the DM never freezes.
        let conv = Conversation(
            id: ConversationId(rawValue: "conv_friend_ro"),
            participantIds: ["user_a", "user_b"],
            type: .friendDirect,
            createdAt: "2026-06-01T00:00:00Z",
            updatedAt: "2026-06-01T00:00:00Z",
            isReadOnly: true
        )
        XCTAssertFalse(conv.isReadOnly)
    }

    func testFriendDirectJSONRoundTripOmitsRequestId() throws {
        let original = Conversation(
            id: ConversationId(rawValue: "conv_friend_json"),
            participantIds: ["user_a", "user_b"],
            type: .friendDirect,
            lastMessageAt: "2026-06-02T12:00:00Z",
            createdAt: "2026-06-02T09:00:00Z",
            updatedAt: "2026-06-02T12:00:00Z"
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Conversation.self, from: data)

        XCTAssertEqual(decoded.id.rawValue, "conv_friend_json")
        XCTAssertNil(decoded.requestId)
        XCTAssertEqual(decoded.type, .friendDirect)
        XCTAssertFalse(decoded.isReadOnly)
        XCTAssertEqual(decoded.lastMessageAt, original.lastMessageAt)
    }

    func testDecodingFriendDirectWithReadOnlyTrueForcesFalse() throws {
        // Hand-craft a payload that (incorrectly) carries isReadOnly=true.
        let conv = Conversation(
            id: ConversationId(rawValue: "conv_friend_force"),
            participantIds: ["u1", "u2"],
            type: .friendDirect,
            createdAt: "2026-06-03T00:00:00Z",
            updatedAt: "2026-06-03T00:00:00Z"
        )
        let data = try encoder.encode(conv)
        var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        dict["isReadOnly"] = true
        let tampered = try JSONSerialization.data(withJSONObject: dict)

        let decoded = try decoder.decode(Conversation.self, from: tampered)
        XCTAssertEqual(decoded.type, .friendDirect)
        XCTAssertFalse(decoded.isReadOnly)
    }

    // MARK: - ConversationRecord round-trip preserves nil requestId (US-011)

    func testConversationRecordRoundTripWithNilRequestId() throws {
        let conv = Conversation(
            id: ConversationId(rawValue: "conv_rec_friend"),
            participantIds: ["u1", "u2"],
            type: .friendDirect,
            createdAt: "2026-06-04T00:00:00Z",
            updatedAt: "2026-06-04T00:00:00Z"
        )
        let record = ConversationRecord.fromValue(conv)
        XCTAssertNil(record.requestId)

        let restored = record.asValue
        XCTAssertNil(restored.requestId)
        XCTAssertEqual(restored.type, .friendDirect)
        XCTAssertFalse(restored.isReadOnly)
    }

    func testConversationRecordRoundTripPreservesRequestId() throws {
        let conv = Conversation(
            id: ConversationId(rawValue: "conv_rec_companion"),
            requestId: CompanionRequestId(rawValue: "creq_x"),
            participantIds: ["u1", "u2"],
            type: .oneOnOne,
            createdAt: "2026-06-04T00:00:00Z",
            updatedAt: "2026-06-04T00:00:00Z"
        )
        let record = ConversationRecord.fromValue(conv)
        XCTAssertEqual(record.requestId, "creq_x")

        let restored = record.asValue
        XCTAssertEqual(restored.requestId?.rawValue, "creq_x")
    }

    // MARK: - Legacy JSON (missing `type` field) decodes as oneOnOne

    func testLegacyJSONWithoutTypeFieldDecodesAsOneOnOne() throws {
        let conv = Conversation(
            id: ConversationId(rawValue: "conv_legacy"),
            requestId: CompanionRequestId(rawValue: "creq_legacy"),
            participantIds: ["u1", "u2"],
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z"
        )
        let data = try encoder.encode(conv)
        var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        dict.removeValue(forKey: "type")
        dict.removeValue(forKey: "routeId")
        let stripped = try JSONSerialization.data(withJSONObject: dict)

        // Custom init(from:) falls back to .oneOnOne when `type` is absent.
        let decoded = try decoder.decode(Conversation.self, from: stripped)
        XCTAssertEqual(decoded.type, .oneOnOne)
        XCTAssertNil(decoded.routeId)
        XCTAssertEqual(decoded.id.rawValue, "conv_legacy")
    }

    // MARK: - Sample data sanity

    func testSampleConversationIsOneOnOne() {
        XCTAssertEqual(Conversation.sample.type, .oneOnOne)
        XCTAssertNil(Conversation.sample.routeId)
    }

    func testGroupRouteSampleHasRouteId() {
        XCTAssertEqual(Conversation.groupRouteSample.type, .groupRoute)
        XCTAssertEqual(Conversation.groupRouteSample.routeId, "route_preview")
        XCTAssertGreaterThan(Conversation.groupRouteSample.participantIds.count, 2)
    }
}
