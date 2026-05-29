import Foundation
import Observation

/// Anonymized post returned by the companion-discover Edge Function.
public struct DiscoverPost: Identifiable, Decodable, Sendable {
    public let id: String
    /// Emoji avatar — no real name or user ID exposed.
    public let handle: String
    public let blurb: String
    public let categories: [String]
    public let cityCode: String
    public let mode: String
    public let activeFrom: String?
    public let activeTo: String?
    /// Geohash precision-6 cell (~600m). Only present for mode=nearby posts.
    public let geohash6: String?
    /// ISO 8601 UTC expiry timestamp. Posts with expires_at ≤ now are stale
    /// and must not be shown (US-018).
    public let expiresAt: String?
    /// US-019: trust weight of the post's author (0.0–1.0).
    /// Default 1.0 when absent (pre-migration data / backwards compat).
    public let reporterWeight: Double

    public init(
        id: String,
        handle: String,
        blurb: String,
        categories: [String],
        cityCode: String,
        mode: String,
        activeFrom: String?,
        activeTo: String?,
        geohash6: String? = nil,
        expiresAt: String? = nil,
        reporterWeight: Double = 1.0
    ) {
        self.id = id
        self.handle = handle
        self.blurb = blurb
        self.categories = categories
        self.cityCode = cityCode
        self.mode = mode
        self.activeFrom = activeFrom
        self.activeTo = activeTo
        self.geohash6 = geohash6
        self.expiresAt = expiresAt
        self.reporterWeight = reporterWeight
    }

    enum CodingKeys: String, CodingKey {
        case id, handle, blurb, categories, mode
        case cityCode = "city_code"
        case activeFrom = "active_from"
        case activeTo = "active_to"
        case geohash6 = "geohash6"
        case expiresAt = "expires_at"
        case reporterWeight = "reporter_weight"
    }

    /// US-018: true when the post has an expires_at in the past.
    public var isExpired: Bool {
        guard let exp = expiresAt else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: exp) ?? ISO8601DateFormatter().date(from: exp) {
            return date <= Date()
        }
        return false
    }
}

// MARK: - US-019: reporter_weight helpers

/// Minimum reporter_weight for a user to appear in companion discovery.
public let companionReporterWeightThreshold: Double = 0.3

public extension Array where Element == DiscoverPost {
    /// Exclude posts from authors whose reporter_weight is below the discovery threshold.
    func aboveReporterWeightThreshold() -> [DiscoverPost] {
        filter { $0.reporterWeight >= companionReporterWeightThreshold }
    }

    /// Sort posts by author reporter_weight descending (highest-trust first).
    /// Uses stable sort so equal-weight items keep their relative order.
    func sortedByReporterWeight() -> [DiscoverPost] {
        sorted { $0.reporterWeight > $1.reporterWeight }
    }
}

/// Params for companion-discover Edge Function.
public struct CompanionDiscoverParams: Sendable {
    public let cityCode: String
    public let mode: CompanionPostMode?
    public let dateFrom: String?
    public let dateTo: String?
    public let categories: [ExperienceCategory]

    public init(
        cityCode: String,
        mode: CompanionPostMode? = nil,
        dateFrom: String? = nil,
        dateTo: String? = nil,
        categories: [ExperienceCategory] = []
    ) {
        self.cityCode = cityCode
        self.mode = mode
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.categories = categories
    }
}

/// Companion service: discovery and request management.
///
/// All network calls are gated by `FeatureFlags.companion`.
/// When the flag is off every method returns an empty success — the
/// local-first invariant (PRD G7) is preserved.
@Observable
@MainActor
public final class CompanionService {
    public static let shared = CompanionService()

    public var discoverPosts: [DiscoverPost] = []
    public var inboxRequests: [CompanionRequest] = []
    public var sentRequests: [CompanionRequest] = []
    public var isLoading = false
    public var lastError: String?

    private let client: SupabaseClientProtocol

    public init(client: SupabaseClientProtocol = SupabaseClient.shared) {
        self.client = client
    }

    // MARK: - US-011: Discovery

    /// Fetch anonymized companion posts from the companion-discover Edge Function.
    public func fetchDiscovery(params: CompanionDiscoverParams) async {
        guard FeatureFlags.companion else {
            discoverPosts = []
            return
        }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        var items: [URLQueryItem] = [
            URLQueryItem(name: "city_code", value: params.cityCode),
        ]
        if let mode = params.mode {
            items.append(URLQueryItem(name: "mode", value: mode.rawValue))
        }
        if let from = params.dateFrom {
            items.append(URLQueryItem(name: "date_from", value: from))
        }
        if let to = params.dateTo {
            items.append(URLQueryItem(name: "date_to", value: to))
        }
        if !params.categories.isEmpty {
            let joined = params.categories.map(\.rawValue).joined(separator: ",")
            items.append(URLQueryItem(name: "categories", value: joined))
        }

        // Build URL with query params and call the function via GET-style invoke
        // We encode params into the body as a JSON object for the Edge Function's
        // URL params since `invoke` sends a POST body.
        // Instead, build a query string and pass it as the function path.
        guard let cfg = supabaseConfig() else {
            lastError = NSLocalizedString("companion.discover.error.config", comment: "Config missing")
            return
        }

        var components = URLComponents(
            url: cfg.url.appendingPathComponent("/functions/v1/companion-discover"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = items

        guard let url = components?.url else {
            lastError = NSLocalizedString("companion.discover.error.config", comment: "Config missing")
            return
        }

        guard let token = client.currentSession?.accessToken else {
            lastError = NSLocalizedString("companion.discover.error.auth", comment: "Not signed in")
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                lastError = NSLocalizedString("companion.discover.error.server", comment: "Server error")
                return
            }
            struct DiscoverResponse: Decodable {
                let posts: [DiscoverPost]
            }
            let decoded = try JSONDecoder().decode(DiscoverResponse.self, from: data)
            // US-018: filter expired posts client-side (server filters too).
            // US-019: filter below-threshold authors and sort by reporter_weight.
            discoverPosts = decoded.posts
                .filter { !$0.isExpired }
                .aboveReporterWeightThreshold()
                .sortedByReporterWeight()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - US-012: Send request

    /// Send a companion request with an optional icebreaker note (≤200 chars).
    public func sendRequest(
        postId: CompanionPostId,
        recipientId: String,
        note: String?
    ) async -> Result<CompanionRequest, Error> {
        guard FeatureFlags.companion else {
            return .failure(CompanionServiceError.featureDisabled)
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let trimmedNote = note.map { String($0.prefix(200)) }

        let req = CompanionRequest(
            id: CompanionRequestId(rawValue: UUID().uuidString),
            postId: postId,
            requesterId: client.currentSession?.userId ?? "local",
            recipientId: recipientId,
            status: .pending,
            note: trimmedNote,
            createdAt: now,
            updatedAt: now
        )

        guard let data = try? JSONEncoder.iso8601Encoder.encode(req) else {
            return .failure(CompanionServiceError.encodingFailed)
        }

        let result = await client.post(table: "companion_requests", body: data)
        switch result {
        case .success:
            sentRequests.append(req)
            return .success(req)
        case .failure(let err):
            return .failure(err)
        }
    }

    // MARK: - US-012: Inbox

    /// Load pending companion requests addressed to the current user.
    public func fetchInbox() async {
        guard FeatureFlags.companion else {
            inboxRequests = []
            return
        }

        lastError = nil

        guard let userId = client.currentSession?.userId else { return }

        let result = await client.get(
            table: "companion_requests",
            query: [
                URLQueryItem(name: "recipient_id", value: "eq.\(userId)"),
                URLQueryItem(name: "status", value: "eq.pending"),
                URLQueryItem(name: "order", value: "created_at.desc"),
            ]
        )

        switch result {
        case .success(let data):
            if !data.isEmpty,
               let requests = try? JSONDecoder.iso8601Decoder.decode([CompanionRequest].self, from: data) {
                inboxRequests = requests
            } else if data.isEmpty {
                inboxRequests = []
            }
        case .failure:
            lastError = NSLocalizedString("companion.inbox.error.load", comment: "Inbox load error")
        }
    }

    // MARK: - US-012: Accept / Decline / Withdraw

    /// Accept a pending request. Creates a Conversation on success.
    @discardableResult
    public func acceptRequest(_ request: CompanionRequest) async -> Result<Conversation, Error> {
        guard FeatureFlags.companion else {
            return .failure(CompanionServiceError.featureDisabled)
        }
        let result = await updateRequestStatus(request, status: .accepted)
        switch result {
        case .failure(let err):
            return .failure(err)
        case .success(let updated):
            // Create conversation
            let now = ISO8601DateFormatter().string(from: Date())
            let conversation = Conversation(
                id: ConversationId(rawValue: UUID().uuidString),
                requestId: updated.id,
                participantIds: [updated.requesterId, updated.recipientId],
                createdAt: now,
                updatedAt: now
            )
            guard let convData = try? JSONEncoder.iso8601Encoder.encode(conversation) else {
                return .failure(CompanionServiceError.encodingFailed)
            }
            let convResult = await client.post(table: "conversations", body: convData)
            switch convResult {
            case .success:
                removeFromInbox(request.id)
                return .success(conversation)
            case .failure(let err):
                return .failure(err)
            }
        }
    }

    /// Decline a pending request. No conversation is created.
    public func declineRequest(_ request: CompanionRequest) async {
        guard FeatureFlags.companion else { return }
        await updateRequestStatus(request, status: .declined)
        removeFromInbox(request.id)
    }

    /// Withdraw a sent request (requester action).
    public func withdrawRequest(_ request: CompanionRequest) async {
        guard FeatureFlags.companion else { return }
        await updateRequestStatus(request, status: .withdrawn)
        sentRequests.removeAll { $0.id == request.id }
    }

    // MARK: - Internals

    @discardableResult
    private func updateRequestStatus(
        _ request: CompanionRequest,
        status: CompanionRequestStatus
    ) async -> Result<CompanionRequest, Error> {
        let now = ISO8601DateFormatter().string(from: Date())
        let updated = CompanionRequest(
            id: request.id,
            postId: request.postId,
            requesterId: request.requesterId,
            recipientId: request.recipientId,
            status: status,
            note: request.note,
            createdAt: request.createdAt,
            updatedAt: now
        )
        guard let data = try? JSONEncoder.iso8601Encoder.encode(updated) else {
            return .failure(CompanionServiceError.encodingFailed)
        }
        let result = await client.post(
            table: "companion_requests",
            body: data
        )
        switch result {
        case .success:
            return .success(updated)
        case .failure(let err):
            return .failure(err)
        }
    }

    private func removeFromInbox(_ id: CompanionRequestId) {
        inboxRequests.removeAll { $0.id == id }
    }

    private struct SupabaseConfig {
        let url: URL
        let anonKey: String
    }

    private func supabaseConfig() -> SupabaseConfig? {
        let envURL = ProcessInfo.processInfo.environment["SUPABASE_URL"]
        let envKey = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]
            ?? ProcessInfo.processInfo.environment["SUPABASE_KEY"]
        let urlString = envURL ?? secretsPlistValue("SUPABASE_URL")
        let key = envKey ?? secretsPlistValue("SUPABASE_ANON_KEY") ?? secretsPlistValue("SUPABASE_KEY")
        guard let urlString, let url = URL(string: urlString), let key, !key.isEmpty else {
            return nil
        }
        return SupabaseConfig(url: url, anonKey: key)
    }

    private func secretsPlistValue(_ key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist[key] as? String
    }

    // MARK: - US-014: Report

    /// File a safety report against a user. The report is write-only for the
    /// reporter — RLS forbids reading other users' reports. `details` is
    /// optional free-text; `reason` must be a valid `CompanionReportReason`.
    @discardableResult
    public func reportUser(
        targetUserId: String,
        reason: CompanionReportReason,
        details: String?
    ) async -> Result<Void, Error> {
        guard FeatureFlags.companion else {
            return .failure(CompanionServiceError.featureDisabled)
        }
        guard let reporterId = client.currentSession?.userId else {
            return .failure(CompanionServiceError.notSignedIn)
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let report = CompanionReport(
            id: CompanionReportId(rawValue: UUID().uuidString),
            reporterId: reporterId,
            targetUserId: targetUserId,
            reason: reason,
            details: details.flatMap { $0.isEmpty ? nil : String($0.prefix(500)) },
            createdAt: now
        )

        guard let data = try? JSONEncoder.iso8601Encoder.encode(report) else {
            return .failure(CompanionServiceError.encodingFailed)
        }

        let result = await client.post(table: "companion_reports", body: data)
        switch result {
        case .success: return .success(())
        case .failure(let err): return .failure(err)
        }
    }

    // MARK: - US-014: Block

    /// Block a user. After blocking:
    /// - The blocked user disappears from all discovery results (Edge Function
    ///   excludes both sides).
    /// - Existing conversations are effectively frozen (both sides can no longer
    ///   find each other in discovery; new requests are blocked by the Edge
    ///   Function).
    @discardableResult
    public func blockUser(blockedId: String) async -> Result<Void, Error> {
        guard FeatureFlags.companion else {
            return .failure(CompanionServiceError.featureDisabled)
        }
        guard let blockerId = client.currentSession?.userId else {
            return .failure(CompanionServiceError.notSignedIn)
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let block = CompanionBlock(blockerId: blockerId, blockedId: blockedId, createdAt: now)

        guard let data = try? JSONEncoder.iso8601Encoder.encode(block) else {
            return .failure(CompanionServiceError.encodingFailed)
        }

        let result = await client.post(table: "companion_blocks", body: data)
        switch result {
        case .success: return .success(())
        case .failure(let err): return .failure(err)
        }
    }

    // MARK: - US-018: Expiry and cleanup

    /// Delete companion_posts rows whose expires_at has passed.
    /// Called periodically — at app launch and after any discovery fetch.
    /// RLS already blocks reading expired rows; this hard-deletes them so
    /// the table stays lean.
    public func cleanupExpiredPosts() async {
        guard FeatureFlags.companion else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        // PostgREST: DELETE /rest/v1/companion_posts?expires_at=lt.<now>
        let result = await client.get(
            table: "companion_posts",
            query: [
                URLQueryItem(name: "expires_at", value: "lt.\(now)"),
                URLQueryItem(name: "select", value: "id"),
            ]
        )
        guard case .success(let data) = result, !data.isEmpty else { return }
        struct IDRow: Decodable { let id: String }
        guard let rows = try? JSONDecoder().decode([IDRow].self, from: data) else { return }
        for row in rows {
            _ = await client.delete(table: "companion_posts", id: row.id)
        }
    }

    /// Auto-expire pending companion_requests older than 7 days by marking
    /// them `.withdrawn` locally and deleting them server-side (US-018).
    public func cleanupStaleRequests() async {
        guard FeatureFlags.companion else { return }
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let cutoffString = ISO8601DateFormatter().string(from: cutoff)

        let result = await client.get(
            table: "companion_requests",
            query: [
                URLQueryItem(name: "status", value: "eq.pending"),
                URLQueryItem(name: "created_at", value: "lt.\(cutoffString)"),
                URLQueryItem(name: "select", value: "id"),
            ]
        )
        guard case .success(let data) = result, !data.isEmpty else { return }
        struct IDRow: Decodable { let id: String }
        guard let rows = try? JSONDecoder().decode([IDRow].self, from: data) else { return }
        for row in rows {
            _ = await client.delete(table: "companion_requests", id: row.id)
        }
        // Remove stale pending requests from local inbox / sent lists.
        let cutoffISO = cutoffString
        inboxRequests.removeAll { req in
            req.status == .pending && req.createdAt < cutoffISO
        }
        sentRequests.removeAll { req in
            req.status == .pending && req.createdAt < cutoffISO
        }
    }
}

// MARK: - Errors

/// Failures that can occur while creating or joining companion meetups.
public enum CompanionServiceError: LocalizedError {
    case featureDisabled
    case encodingFailed
    case notSignedIn

    public var errorDescription: String? {
        switch self {
        case .featureDisabled: return "Companion mode is not enabled."
        case .encodingFailed: return "Failed to encode request."
        case .notSignedIn: return "Sign in to use companion features."
        }
    }
}
