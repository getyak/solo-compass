import Foundation
import Observation
import SwiftData

/// Friend service: the persistent relationship layer.
///
/// Orchestrates friend requests and friendships against the Supabase backend
/// (REST) plus a local SwiftData mirror for offline reads. Mirrors the
/// `CompanionService` shape (@Observable @MainActor, REST via SupabaseClient,
/// gated by `FeatureFlags.companion` — friends reuse the companion flag).
///
/// All relationship decisions defer to the pure `FriendshipStateMachine`, so
/// the business rules (mutual-pending fold, already-friends no-op, blocked
/// silent-drop) are unit-tested independently of I/O.
@Observable
@MainActor
public final class FriendService {
    public static let shared = FriendService()

    /// Confirmed friendships involving the current user.
    public var friends: [Friendship] = []
    /// Pending requests addressed *to* the current user.
    public var incomingRequests: [FriendRequest] = []
    /// Pending requests *sent by* the current user.
    public var outgoingRequests: [FriendRequest] = []
    public var isLoading = false
    public var lastError: String?

    private let client: SupabaseClientProtocol
    /// Days a pending request lives before auto-expiring (FR-6).
    private static let requestTTLDays = 14

    public init(client: SupabaseClientProtocol = SupabaseClient.shared) {
        self.client = client
    }

    // MARK: - Identity helpers

    private var currentUserId: String {
        client.currentSession?.userId ?? "local"
    }

    private func nowISO() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func expiryISO() -> String {
        let expiry = Calendar.current.date(
            byAdding: .day, value: Self.requestTTLDays, to: Date()
        ) ?? Date()
        return ISO8601DateFormatter().string(from: expiry)
    }

    // MARK: - FRD-005: Send request

    /// Send a friend request. Resolves the relationship via the state machine
    /// first: a mutual-pending request auto-accepts, an existing friendship is
    /// a no-op, and a blocked pair silently drops (never leaking block status).
    ///
    /// - Returns: the resolved `SendRequestOutcome`, or a failure when the
    ///   feature is off or the network write fails.
    @discardableResult
    public func sendRequest(
        to recipientId: String,
        source: FriendRequestSource,
        note: String? = nil
    ) async -> Result<SendRequestOutcome, Error> {
        guard FeatureFlags.companion else {
            return .failure(FriendServiceError.featureDisabled)
        }
        guard recipientId != currentUserId else {
            return .failure(FriendServiceError.cannotFriendSelf)
        }

        let currentState = relationState(with: recipientId)
        let hasInbound = incomingRequests.contains {
            $0.requesterId == recipientId && $0.status == .pending
        }
        let outcome = FriendshipStateMachine.resolveSendRequest(
            currentState: currentState,
            hasInboundPending: hasInbound,
            isBlockedEitherWay: isBlocked(recipientId)
        )

        switch outcome {
        case .alreadyFriends, .silentlyDropped:
            // No-op (or silent drop). Report success to avoid leaking state.
            return .success(outcome)

        case .autoAccepted:
            // The reverse request already exists → accept it.
            if let inbound = incomingRequests.first(where: {
                $0.requesterId == recipientId && $0.status == .pending
            }) {
                let res = await accept(inbound)
                return res.map { _ in .autoAccepted }
            }
            return .success(.autoAccepted)

        case .createdPending:
            let trimmedNote = note.map { String($0.prefix(120)) }
            let now = nowISO()
            let request = FriendRequest(
                id: FriendRequestId(rawValue: "freq_\(UUID().uuidString)"),
                requesterId: currentUserId,
                recipientId: recipientId,
                status: .pending,
                source: source,
                note: trimmedNote,
                expiresAt: expiryISO(),
                createdAt: now,
                updatedAt: now
            )
            guard let data = try? JSONEncoder.iso8601Encoder.encode(request) else {
                return .failure(FriendServiceError.encodingFailed)
            }
            let result = await client.post(table: "friend_requests", body: data)
            switch result {
            case .success:
                outgoingRequests.append(request)
                persistRequest(request)
                return .success(.createdPending)
            case .failure(let err):
                return .failure(err)
            }
        }
    }

    // MARK: - FRD-005: Accept / Decline / Withdraw

    /// Accept a pending request → materialises a `Friendship` (ordered pair).
    @discardableResult
    public func accept(_ request: FriendRequest) async -> Result<Friendship, Error> {
        guard FeatureFlags.companion else {
            return .failure(FriendServiceError.featureDisabled)
        }
        // 1. Mark request accepted.
        let updateResult = await updateRequestStatus(request, status: .accepted)
        if case .failure(let err) = updateResult { return .failure(err) }

        // 2. Create the ordered-pair friendship.
        let pair = Friendship.orderedPair(request.requesterId, request.recipientId)
        let now = nowISO()
        let friendship = Friendship(
            id: FriendshipId(rawValue: "fnd_\(UUID().uuidString)"),
            userLowId: pair.low,
            userHighId: pair.high,
            initiatedBy: request.requesterId,
            conversationId: nil,
            acceptedAt: now,
            createdAt: now,
            updatedAt: now
        )
        guard let data = try? JSONEncoder.iso8601Encoder.encode(friendship) else {
            return .failure(FriendServiceError.encodingFailed)
        }
        let result = await client.post(table: "friendships", body: data)
        switch result {
        case .success:
            friends.append(friendship)
            persistFriendship(friendship)
            removeFromInbox(request.id)
            return .success(friendship)
        case .failure(let err):
            return .failure(err)
        }
    }

    /// Decline a pending request. No friendship is created.
    public func decline(_ request: FriendRequest) async {
        guard FeatureFlags.companion else { return }
        await updateRequestStatus(request, status: .declined)
        removeFromInbox(request.id)
    }

    /// Withdraw a request the current user sent.
    public func withdraw(_ request: FriendRequest) async {
        guard FeatureFlags.companion else { return }
        await updateRequestStatus(request, status: .withdrawn)
        outgoingRequests.removeAll { $0.id == request.id }
    }

    // MARK: - FRD-005: Unfriend / block

    /// Remove a friendship. When `block` is true, also records a CompanionBlock
    /// so the pair can no longer see or reach each other (shared with the
    /// companion system's block table).
    public func unfriend(_ friendship: Friendship, block: Bool = false) async {
        guard FeatureFlags.companion else { return }
        _ = await client.delete(table: "friendships", id: friendship.id.rawValue)
        friends.removeAll { $0.id == friendship.id }
        deleteFriendshipRecord(friendship.id.rawValue)

        if block {
            let other = friendship.otherUserId(viewer: currentUserId)
            let blockBody: [String: String] = [
                "blocker_id": currentUserId,
                "blocked_id": other,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: blockBody) {
                _ = await client.post(table: "companion_blocks", body: data)
            }
        }
    }

    // MARK: - FRD-005: Fetch

    /// Load friendships + incoming/outgoing pending requests for the current user.
    public func refresh() async {
        guard FeatureFlags.companion else {
            friends = []
            incomingRequests = []
            outgoingRequests = []
            return
        }
        guard let userId = client.currentSession?.userId else {
            // Offline: fall back to the local SwiftData mirror.
            loadFromLocal()
            return
        }
        isLoading = true
        defer { isLoading = false }

        // Friendships where the user is either side of the ordered pair.
        let lowRes = await client.get(
            table: "friendships",
            query: [URLQueryItem(name: "user_low_id", value: "eq.\(userId)")]
        )
        let highRes = await client.get(
            table: "friendships",
            query: [URLQueryItem(name: "user_high_id", value: "eq.\(userId)")]
        )
        var collected: [Friendship] = []
        for res in [lowRes, highRes] {
            if case .success(let data) = res, !data.isEmpty,
               let rows = try? JSONDecoder.iso8601Decoder.decode([Friendship].self, from: data) {
                collected.append(contentsOf: rows)
            }
        }
        friends = collected

        // Incoming pending.
        let inboxRes = await client.get(
            table: "friend_requests",
            query: [
                URLQueryItem(name: "recipient_id", value: "eq.\(userId)"),
                URLQueryItem(name: "status", value: "eq.pending"),
                URLQueryItem(name: "order", value: "created_at.desc"),
            ]
        )
        if case .success(let data) = inboxRes, !data.isEmpty,
           let rows = try? JSONDecoder.iso8601Decoder.decode([FriendRequest].self, from: data) {
            incomingRequests = rows
        } else if case .success(let data) = inboxRes, data.isEmpty {
            incomingRequests = []
        }

        // Outgoing pending.
        let sentRes = await client.get(
            table: "friend_requests",
            query: [
                URLQueryItem(name: "requester_id", value: "eq.\(userId)"),
                URLQueryItem(name: "status", value: "eq.pending"),
                URLQueryItem(name: "order", value: "created_at.desc"),
            ]
        )
        if case .success(let data) = sentRes, !data.isEmpty,
           let rows = try? JSONDecoder.iso8601Decoder.decode([FriendRequest].self, from: data) {
            outgoingRequests = rows
        } else if case .success(let data) = sentRes, data.isEmpty {
            outgoingRequests = []
        }

        // Mirror to local store for offline reads.
        friends.forEach(persistFriendship)
    }

    // MARK: - Queries

    /// Whether the current user is already friends with `userId`.
    public func isFriend(_ userId: String) -> Bool {
        friends.contains {
            $0.userLowId == userId || $0.userHighId == userId
        }
    }

    /// The relationship state between the current user and `userId`.
    public func relationState(with userId: String) -> FriendRelationState {
        if isFriend(userId) { return .accepted }
        let pending = outgoingRequests.contains {
            $0.recipientId == userId && $0.status == .pending
        } || incomingRequests.contains {
            $0.requesterId == userId && $0.status == .pending
        }
        return pending ? .pending : .none
    }

    /// The friendship row for `userId`, if any.
    public func friendship(with userId: String) -> Friendship? {
        friends.first { $0.userLowId == userId || $0.userHighId == userId }
    }

    /// Friend count for the current user (used by profile stat rows).
    public var friendCount: Int { friends.count }

    private func isBlocked(_ userId: String) -> Bool {
        // Local check only; the backend RLS / Edge enforces the canonical rule.
        // Without a loaded block list we conservatively return false and let
        // the server silently drop.
        false
    }

    // MARK: - Private: request status update

    @discardableResult
    private func updateRequestStatus(
        _ request: FriendRequest,
        status: FriendRequestStatus
    ) async -> Result<FriendRequest, Error> {
        let now = nowISO()
        let updated = FriendRequest(
            id: request.id,
            requesterId: request.requesterId,
            recipientId: request.recipientId,
            status: status,
            source: request.source,
            note: request.note,
            expiresAt: request.expiresAt,
            createdAt: request.createdAt,
            updatedAt: now
        )
        guard let data = try? JSONEncoder.iso8601Encoder.encode(updated) else {
            return .failure(FriendServiceError.encodingFailed)
        }
        // PostgREST upsert via POST with merge-duplicates (client sets the
        // Prefer header). Reuses the same pattern as companion requests.
        let result = await client.post(table: "friend_requests", body: data)
        switch result {
        case .success:
            persistRequest(updated)
            return .success(updated)
        case .failure(let err):
            return .failure(err)
        }
    }

    private func removeFromInbox(_ id: FriendRequestId) {
        incomingRequests.removeAll { $0.id == id }
    }

    // MARK: - Private: local SwiftData mirror

    private var context: ModelContext { ModelContext(SoloCompassModelContainer.shared) }

    private func persistRequest(_ request: FriendRequest) {
        let ctx = context
        let rec = FriendRequestRecord(from: request)
        ctx.insert(rec)
        try? ctx.save()
    }

    private func persistFriendship(_ friendship: Friendship) {
        let ctx = context
        let rec = FriendshipRecord(from: friendship)
        ctx.insert(rec)
        try? ctx.save()
    }

    private func deleteFriendshipRecord(_ id: String) {
        let ctx = context
        let descriptor = FetchDescriptor<FriendshipRecord>(
            predicate: #Predicate { $0.id == id }
        )
        if let rows = try? ctx.fetch(descriptor) {
            rows.forEach(ctx.delete)
            try? ctx.save()
        }
    }

    private func loadFromLocal() {
        let ctx = context
        if let reqs = try? ctx.fetch(FetchDescriptor<FriendRequestRecord>()) {
            let values = reqs.map(\.asValue)
            incomingRequests = values.filter {
                $0.recipientId == currentUserId && $0.status == .pending
            }
            outgoingRequests = values.filter {
                $0.requesterId == currentUserId && $0.status == .pending
            }
        }
        if let fnds = try? ctx.fetch(FetchDescriptor<FriendshipRecord>()) {
            friends = fnds.map(\.asValue).filter {
                $0.userLowId == currentUserId || $0.userHighId == currentUserId
            }
        }
    }
}

// MARK: - Errors

public enum FriendServiceError: LocalizedError {
    case featureDisabled
    case encodingFailed
    case cannotFriendSelf

    public var errorDescription: String? {
        switch self {
        case .featureDisabled:
            return NSLocalizedString("friend.error.disabled", comment: "Friends feature disabled")
        case .encodingFailed:
            return NSLocalizedString("friend.error.encoding", comment: "Failed to encode friend payload")
        case .cannotFriendSelf:
            return NSLocalizedString("friend.error.self", comment: "Cannot friend yourself")
        }
    }
}
