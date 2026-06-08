import Foundation
import UIKit
import UserNotifications

/// US-021: APNs remote-push registration + device-token upload.
///
/// Solo Compass uses **local** notifications for geofence check-ins
/// (`NotificationService`), but friend-graph features (friend requests,
/// meetup invites, route joins) need server-pushed notifications even when
/// the app is closed. That requires registering with APNs and persisting the
/// device token server-side so an Edge Function can target the device.
///
/// Lifecycle:
///   1. `requestAuthorizationAndRegister()` — asks for push permission at an
///      appropriate (non-cold-start) moment, then calls
///      `registerForRemoteNotifications()` when granted.
///   2. The system calls back into the `AppDelegate`, which forwards the raw
///      `Data` token to `handle(deviceToken:)`.
///   3. We hex-encode the token and **upsert** it into `device_push_tokens`
///      keyed by device id — so re-registration (token rotation) overwrites
///      the stale row rather than creating duplicates.
///   4. `invalidate()` removes the local row when APNs reports the token is no
///      longer valid (`didFailToRegister` / feedback), so we stop targeting it.
///
/// Every backend call is gated by `FeatureFlags.backendSync`; when the flag is
/// off (default in beta) the whole service is a quiet no-op, preserving the
/// local-first invariant.
@MainActor
@Observable
public final class PushTokenService {
    public static let shared = PushTokenService()

    /// The most recently registered APNs token, hex-encoded. `nil` until the
    /// system delivers one. Surfaced for diagnostics / tests.
    public private(set) var currentToken: String?

    /// Whether the user granted push authorization in this process.
    public private(set) var isRegistered: Bool = false

    private let client: any SupabaseClientProtocol
    private let center: UNUserNotificationCenter

    /// PostgREST table the token rows live in. Primary key is `device_id`
    /// so upserts (merge-duplicates) rotate the token in place.
    private static let tokenTable = "device_push_tokens"

    private convenience init() {
        self.init(client: SupabaseClient.shared, center: .current())
    }

    /// Dependency-injected initialiser for unit tests.
    init(client: any SupabaseClientProtocol, center: UNUserNotificationCenter) {
        self.client = client
        self.center = center
    }

    // MARK: - Registration

    /// Request push authorization, then register for remote notifications when
    /// granted. Call this from a **non-cold-start** moment (e.g. when the user
    /// first opens a social surface) so the system prompt has context.
    ///
    /// Safe to call repeatedly — if already authorized it re-registers, which
    /// refreshes a possibly-rotated token.
    public func requestAuthorizationAndRegister() async {
        let granted: Bool
        do {
            granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            isRegistered = false
            return
        }
        isRegistered = granted
        guard granted else { return }
        registerForRemoteNotifications()
    }

    /// Re-register for remote notifications when authorization already exists
    /// (e.g. on a warm launch). No prompt is shown if the user previously
    /// granted permission. Does nothing when push is not authorized.
    public func registerIfAuthorized() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        isRegistered = true
        registerForRemoteNotifications()
    }

    /// Triggers the APNs handshake. The OS responds asynchronously via the
    /// `AppDelegate` callbacks below. Must run on the main thread (UIKit rule).
    public func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    // MARK: - AppDelegate callbacks

    /// Called from `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    /// Hex-encodes the raw token and upserts it server-side. Token rotation is
    /// handled implicitly: a new token for the same device overwrites the row.
    public func handle(deviceToken: Data) async {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        currentToken = hex
        await uploadToken(hex)
    }

    /// Called from `application(_:didFailToRegisterForRemoteNotificationsWithError:)`.
    /// Registration failed (no entitlement, no network, simulator) — clear local
    /// state. We deliberately do NOT delete the server row here, because a
    /// transient failure shouldn't drop a still-valid token.
    public func handleRegistrationFailure(_ error: Error) {
        isRegistered = false
    }

    // MARK: - Token persistence

    /// Upsert the device token into `device_push_tokens`. Keyed by `device_id`
    /// with `resolution=merge-duplicates` (SupabaseClient.post default) so a
    /// rotated token replaces the stale one instead of inserting a duplicate.
    private func uploadToken(_ token: String) async {
        guard FeatureFlags.backendSync else { return }
        guard let userId = client.currentSession?.userId else { return }

        let payload: [String: Any] = [
            "device_id": DeviceIdentityService.shared.deviceID,
            "user_id": userId,
            "token": token,
            "platform": "ios",
            "updated_at": ISO8601DateFormatter().string(from: Date()),
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        _ = await client.post(table: Self.tokenTable, body: body)
    }

    /// US-021: token invalidation. Remove the device's row from
    /// `device_push_tokens` when APNs feedback reports the token is stale, or
    /// when the user signs out. After this the device is no longer targeted.
    public func invalidate() async {
        currentToken = nil
        isRegistered = false
        guard FeatureFlags.backendSync else { return }
        _ = await client.delete(table: Self.tokenTable, id: DeviceIdentityService.shared.deviceID)
    }
}
