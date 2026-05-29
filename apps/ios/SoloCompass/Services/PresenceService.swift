import Foundation
import Observation
import UIKit

/// Foreground-only presence broadcaster for Companion Mode (US-015).
///
/// Privacy contract:
/// - Precise coordinates **never** leave the device. Only a geohash-6 cell
///   (~600 m × 600 m) is computed on-device and posted to the backend.
/// - Broadcasting starts **only** when the user explicitly calls `enable()`.
/// - Stops immediately when the user calls `disable()` or the app enters the
///   background. The backend row (`companion_posts` mode=nearby) is deleted on
///   stop so there is no stale presence after the user leaves.
/// - WhenInUse location authorization is sufficient — Always is never requested.
@Observable
@MainActor
public final class PresenceService {
    public static let shared = PresenceService()

    /// Whether presence broadcasting is currently active.
    public private(set) var isActive: Bool = false

    /// Last known error string (nil when everything is fine).
    public private(set) var lastError: String?

    /// The companion_post id for the active nearby post (used for cleanup).
    private var activePostId: String?

    private let locationService: LocationService
    private let client: SupabaseClientProtocol
    private var broadcastTask: Task<Void, Never>?
    private var backgroundObserverTask: Task<Void, Never>?

    /// How often to refresh the nearby post (keeps `expires_at` rolling forward).
    private static let broadcastInterval: TimeInterval = 5 * 60 // 5 minutes

    public init(
        locationService: LocationService = .shared,
        client: SupabaseClientProtocol = SupabaseClient.shared
    ) {
        self.locationService = locationService
        self.client = client
        observeBackground()
    }

    // MARK: - Public API

    /// Activate presence broadcasting. Requires the user to opt in explicitly from the UI.
    /// A companion_posts row with mode=nearby and a 2-hour expires_at is upserted each
    /// broadcast cycle. Precise location is never sent — only geohash6.
    public func enable() async {
        guard FeatureFlags.companion else { return }
        guard !isActive else { return }
        isActive = true
        lastError = nil
        broadcastTask = Task { await broadcastLoop() }
    }

    /// Deactivate presence. Immediately stops broadcasting and removes the nearby post.
    public func disable() async {
        await stopAndCleanup()
    }

    // MARK: - Background observation

    private func observeBackground() {
        backgroundObserverTask = Task { @MainActor [weak self] in
            let nc = NotificationCenter.default
            for await _ in nc.notifications(named: UIApplication.didEnterBackgroundNotification) {
                await self?.stopAndCleanup()
            }
        }
    }

    // MARK: - Broadcast loop

    private func broadcastLoop() async {
        // Broadcast immediately, then on interval.
        await broadcastOnce()
        while !Task.isCancelled && isActive {
            try? await Task.sleep(for: .seconds(Self.broadcastInterval))
            if Task.isCancelled || !isActive { break }
            await broadcastOnce()
        }
    }

    private func broadcastOnce() async {
        guard let geohash = locationService.coarseGeohash6 else { return }
        guard let userId = client.currentSession?.userId else { return }

        let now = ISO8601DateFormatter().string(from: Date())
        // expires_at ≤ 2 h from now (US-018).
        let expiresAt = ISO8601DateFormatter().string(
            from: Date().addingTimeInterval(2 * 60 * 60)
        )

        let postId = activePostId ?? "pres_\(userId)"
        activePostId = postId

        let payload: [String: Any] = [
            "id": postId,
            "author_id": userId,
            "mode": "nearby",
            "geohash6": geohash,
            "blurb": "",
            "categories": [],
            "city_code": "",
            "expires_at": expiresAt,
            "created_at": now,
            "updated_at": now,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let result = await client.post(table: "companion_posts", body: data)
        if case .failure(let err) = result {
            lastError = err.localizedDescription
        }
    }

    // MARK: - Cleanup

    @discardableResult
    private func stopAndCleanup() async -> Bool {
        guard isActive else { return false }
        isActive = false
        broadcastTask?.cancel()
        broadcastTask = nil
        await deleteNearbyPost()
        return true
    }

    private func deleteNearbyPost() async {
        guard let postId = activePostId else { return }
        let result = await client.delete(table: "companion_posts", id: postId)
        if case .failure(let err) = result {
            lastError = err.localizedDescription
        }
        activePostId = nil
    }
}
