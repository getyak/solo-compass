import XCTest
import UserNotifications
@testable import SoloCompass

/// US-021: unit coverage for the deterministic, non-system parts of
/// `PushTokenService` — APNs token hex-encoding and local state transitions.
///
/// The authorization-prompt + `UIApplication.registerForRemoteNotifications`
/// paths are intentionally NOT exercised here: they touch live system services
/// (`UNUserNotificationCenter` prompt, UIKit registration) that a unit-test
/// bundle without a running host app cannot stub deterministically. Those are
/// verified by hand on-device. What is fully testable — and what actually
/// carries the token-upload contract — is the encoding of the raw device
/// token and the local `currentToken` / `isRegistered` bookkeeping.
@MainActor
final class PushTokenServiceTests: XCTestCase {

    /// Records the table + body of the most recent `post`, so we can assert the
    /// upsert targets `device_push_tokens` once backend sync is enabled.
    private final class SpySupabaseClient: SupabaseClientProtocol {
        private(set) var lastPostTable: String?
        private(set) var lastPostBody: Data?
        private(set) var lastDeleteTable: String?
        private(set) var lastDeleteId: String?

        var currentSession: SupabaseClient.Session? {
            SupabaseClient.Session(
                userId: "user-123",
                accessToken: "at",
                refreshToken: "rt",
                expiresAt: Date().addingTimeInterval(3600)
            )
        }

        func signInAnonymously() async -> Result<SupabaseClient.Session, SupabaseClient.SupabaseError> { .failure(.notSignedIn) }
        func refreshSession() async -> Result<SupabaseClient.Session, SupabaseClient.SupabaseError> { .failure(.notSignedIn) }
        func get(table: String, query: [URLQueryItem]) async -> Result<Data, SupabaseClient.SupabaseError> { .success(Data()) }
        func invoke(function: String, body: Data) async -> Result<Data, SupabaseClient.SupabaseError> { .success(Data()) }
        func linkAppleIdentity(identityToken: String, nonce: String) async -> Result<SupabaseClient.Session, SupabaseClient.SupabaseError> { .failure(.notSignedIn) }
        var isAnonymous: Bool { get async { false } }

        func post(table: String, body: Data) async -> Result<Data, SupabaseClient.SupabaseError> {
            lastPostTable = table
            lastPostBody = body
            return .success(Data())
        }

        func delete(table: String, id: String) async -> Result<Void, SupabaseClient.SupabaseError> {
            lastDeleteTable = table
            lastDeleteId = id
            return .success(())
        }
    }

    private func makeService(_ spy: SpySupabaseClient) -> PushTokenService {
        PushTokenService(client: spy, center: .current())
    }

    /// `handle(deviceToken:)` hex-encodes the raw bytes lowercase and stores them
    /// in `currentToken`. This encoding runs before the backend-sync gate, so it
    /// is deterministic regardless of `FeatureFlags.backendSync`.
    func testHandleHexEncodesDeviceToken() async {
        let spy = SpySupabaseClient()
        let service = makeService(spy)

        let raw = Data([0x00, 0xAB, 0xCD, 0xEF, 0x10, 0xFF])
        await service.handle(deviceToken: raw)

        XCTAssertEqual(service.currentToken, "00abcdef10ff")
    }

    /// An empty token still produces an empty (non-nil) hex string — the system
    /// never delivers one, but the encoder must not crash on the edge case.
    func testHandleEmptyTokenProducesEmptyString() async {
        let spy = SpySupabaseClient()
        let service = makeService(spy)

        await service.handle(deviceToken: Data())

        XCTAssertEqual(service.currentToken, "")
    }

    /// `invalidate()` clears local push state. The server-side delete is gated by
    /// `FeatureFlags.backendSync`; the local bookkeeping always resets so a
    /// signed-out device stops considering itself registered.
    func testInvalidateClearsLocalState() async {
        let spy = SpySupabaseClient()
        let service = makeService(spy)

        await service.handle(deviceToken: Data([0x01, 0x02]))
        XCTAssertEqual(service.currentToken, "0102")

        await service.invalidate()
        XCTAssertNil(service.currentToken)
        XCTAssertFalse(service.isRegistered)
    }
}
