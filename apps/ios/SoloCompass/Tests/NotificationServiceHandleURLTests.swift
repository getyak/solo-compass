import XCTest
@testable import SoloCompass

/// `NotificationService.handleURL(_:)` is the single entry point for the
/// `solocompass://` custom scheme registered in `project.yml info.properties`.
/// It feeds the same `pendingDeepLink` mechanism APNs payloads use, so a
/// regression here silently breaks share-sheet → app navigation for every
/// path (experience / route / chat / friends).
///
/// These tests run on the shared singleton because `pendingDeepLink` is
/// observed by `CompassMapView` via that singleton — we reset it before each
/// test so cross-test bleed can't fake a pass.
@MainActor
final class NotificationServiceHandleURLTests: XCTestCase {

    private var service: NotificationService { NotificationService.shared }

    override func setUp() async throws {
        try await super.setUp()
        service.pendingDeepLink = nil
    }

    override func tearDown() async throws {
        service.pendingDeepLink = nil
        try await super.tearDown()
    }

    // MARK: - Scheme rejection

    func testRejectsForeignScheme() {
        let url = URL(string: "https://daypage.com/experience/abc")!
        XCTAssertFalse(service.handleURL(url))
        XCTAssertNil(service.pendingDeepLink, "non-solocompass scheme must NOT set a deep link")
    }

    func testAcceptsUppercaseScheme() {
        // URL schemes are case-insensitive per RFC 3986 §3.1; the handler
        // lowercases for comparison so SOLOCOMPASS://... still works.
        let url = URL(string: "SOLOCOMPASS://friends")!
        XCTAssertTrue(service.handleURL(url))
        XCTAssertEqual(service.pendingDeepLink, .friendRequestInbox(requestId: nil))
    }

    // MARK: - Each of the 4 recognized paths

    func testExperiencePathSetsExperienceDetailDeepLink() {
        let url = URL(string: "solocompass://experience/exp_vte_mekong_sunset")!
        XCTAssertTrue(service.handleURL(url))
        XCTAssertEqual(
            service.pendingDeepLink,
            .experienceDetail(experienceId: "exp_vte_mekong_sunset")
        )
    }

    func testRoutePathSetsRoutePreviewDeepLink() {
        let url = URL(string: "solocompass://route/mekong-sunset")!
        XCTAssertTrue(service.handleURL(url))
        XCTAssertEqual(
            service.pendingDeepLink,
            .routePreview(routeId: "mekong-sunset")
        )
    }

    func testChatPathSetsChatConversationDeepLink() {
        let url = URL(string: "solocompass://chat/conv_42")!
        XCTAssertTrue(service.handleURL(url))
        XCTAssertEqual(
            service.pendingDeepLink,
            .chatConversation(conversationId: "conv_42")
        )
    }

    func testFriendsPathSetsFriendRequestInboxDeepLink() {
        let url = URL(string: "solocompass://friends")!
        XCTAssertTrue(service.handleURL(url))
        XCTAssertEqual(
            service.pendingDeepLink,
            .friendRequestInbox(requestId: nil)
        )
    }

    // MARK: - Defensive: empty ids and unknown paths

    func testExperiencePathWithoutIdIsIgnored() {
        // `solocompass://experience` (no id) must NOT route to an empty
        // experienceDetail — that would crash detail-sheet lookup downstream.
        let url = URL(string: "solocompass://experience")!
        XCTAssertFalse(service.handleURL(url))
        XCTAssertNil(service.pendingDeepLink)
    }

    func testRoutePathWithoutIdIsIgnored() {
        let url = URL(string: "solocompass://route")!
        XCTAssertFalse(service.handleURL(url))
        XCTAssertNil(service.pendingDeepLink)
    }

    func testChatPathWithoutIdIsIgnored() {
        let url = URL(string: "solocompass://chat")!
        XCTAssertFalse(service.handleURL(url))
        XCTAssertNil(service.pendingDeepLink)
    }

    func testUnknownPathIsIgnored() {
        let url = URL(string: "solocompass://settings")!
        XCTAssertFalse(service.handleURL(url))
        XCTAssertNil(service.pendingDeepLink)
    }

    // MARK: - URL shape variations

    func testExperiencePathAcceptsNestedSegments() {
        // exp ids never contain '/' in production, but if a future id format
        // does, we should preserve the suffix rather than truncating it.
        let url = URL(string: "solocompass://experience/group/abc/123")!
        XCTAssertTrue(service.handleURL(url))
        XCTAssertEqual(
            service.pendingDeepLink,
            .experienceDetail(experienceId: "group/abc/123")
        )
    }
}
