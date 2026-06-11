import Foundation
import Observation

/// Platform moderation client. Wraps the three things a moderator / admin
/// needs from the backend:
///
///   1. the current user's platform `role` (drives whether the moderation
///      entry point appears at all),
///   2. the full moderation queue (companion_reports — readable only by
///      moderators/admins thanks to the 0012 RLS policy),
///   3. moderation actions (ban / unban / setRole / resolveReport), all routed
///      through the `moderate-action` Edge Function so the privilege-guard
///      trigger permits the write.
///
/// Everything degrades to a no-op / empty result when `FF_BACKEND_SYNC` is off
/// (the underlying `SupabaseClient` short-circuits), preserving the local-first
/// invariant: a moderator simply sees an empty queue offline rather than an
/// error.
@Observable
@MainActor
public final class AdminService {
    public static let shared = AdminService()

    private let client: SupabaseClientProtocol

    /// The current user's platform role. `.user` until `refreshRole()` lands a
    /// value from the backend. Drives the admin-gated UI.
    public private(set) var currentRole: UserRole = .user

    /// The moderation queue (unresolved reports first). Empty until loaded.
    public private(set) var reports: [CompanionReport] = []

    public private(set) var isLoading: Bool = false
    public private(set) var lastError: String?

    public init(client: SupabaseClientProtocol = SupabaseClient.shared) {
        self.client = client
    }

    /// True when the current user can open the moderation tools.
    public var canModerate: Bool { currentRole.canModerate }

    /// True when the current user can change roles (admin only).
    public var canManageRoles: Bool { currentRole == .admin }

    private var currentUserId: String { client.currentSession?.userId ?? "local" }

    // MARK: - Role

    /// Fetch the current user's `role` from `companion_profiles`. Falls back to
    /// `.user` on any miss (no row, backend off, decode failure).
    public func refreshRole() async {
        let query = [
            URLQueryItem(name: "select", value: "role,is_banned"),
            URLQueryItem(name: "user_id", value: "eq.\(currentUserId)"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        let result = await client.get(table: "companion_profiles", query: query)
        guard case .success(let data) = result, !data.isEmpty else {
            currentRole = .user
            return
        }
        struct Row: Decodable { let role: String?; let is_banned: Bool? }
        let rows = (try? JSONDecoder().decode([Row].self, from: data)) ?? []
        guard let row = rows.first, row.is_banned != true,
              let raw = row.role, let parsed = UserRole(rawValue: raw) else {
            currentRole = .user
            return
        }
        currentRole = parsed
    }

    // MARK: - Queue

    /// Load the moderation queue. The 0012 `companion_reports moderator-select`
    /// policy returns the full table for moderators/admins; for a plain user it
    /// returns only their own reports, so guard on `canModerate` first.
    public func refreshReports() async {
        guard canModerate else { reports = []; return }
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let query = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "resolved_at.asc.nullsfirst,created_at.desc"),
            URLQueryItem(name: "limit", value: "200"),
        ]
        let result = await client.get(table: "companion_reports", query: query)
        switch result {
        case .success(let data):
            guard !data.isEmpty else { reports = []; return }
            reports = (try? JSONDecoder().decode([CompanionReport].self, from: data)) ?? []
        case .failure(let err):
            lastError = err.localizedDescription
        }
    }

    // MARK: - Actions

    public enum ModerationAction {
        case ban(targetUserId: String)
        case unban(targetUserId: String)
        case resolveReport(reportId: String)
        case setRole(targetUserId: String, role: UserRole)

        var body: [String: String] {
            switch self {
            case .ban(let id):            return ["action": "ban", "targetUserId": id]
            case .unban(let id):          return ["action": "unban", "targetUserId": id]
            case .resolveReport(let id):  return ["action": "resolveReport", "reportId": id]
            case .setRole(let id, let r): return ["action": "setRole", "targetUserId": id, "role": r.rawValue]
            }
        }
    }

    /// Perform a moderation action via the Edge Function. Returns true on
    /// success. On success the local queue is refreshed so resolved/handled
    /// rows update immediately.
    @discardableResult
    public func perform(_ action: ModerationAction) async -> Bool {
        guard canModerate else { lastError = "forbidden"; return false }
        guard let body = try? JSONSerialization.data(withJSONObject: action.body) else {
            lastError = "could not encode action"
            return false
        }
        let result = await client.invoke(function: "moderate-action", body: body)
        switch result {
        case .success(let data):
            // Edge function returns { ok: true } / { error }. A backend-off
            // no-op returns empty Data — treat as success (nothing to do).
            if data.isEmpty { return true }
            struct Resp: Decodable { let ok: Bool?; let error: String? }
            let resp = try? JSONDecoder().decode(Resp.self, from: data)
            if let err = resp?.error { lastError = err; return false }
            await refreshReports()
            return resp?.ok ?? true
        case .failure(let err):
            lastError = err.localizedDescription
            return false
        }
    }
}
