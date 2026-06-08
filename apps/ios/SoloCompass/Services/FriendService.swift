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

    /// The current user's active, shareable friend code (US-013). Lazily
    /// generated on first open of the AddFriendSheet, then cached here.
    public var myFriendCode: FriendCode?

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

    // MARK: - US-012: Lazy-create direct conversation

    /// Open the persistent 1:1 DM backing a friendship.
    ///
    /// If the friendship already has a `conversationId`, returns a lightweight
    /// `Conversation` value pointing at it (the messages themselves are loaded
    /// lazily by `ChatService` over Realtime). Otherwise this lazily creates a
    /// `.friendDirect` conversation, writes it to the backend, and patches the
    /// friendship's `conversation_id` back (locally + via a PostgREST upsert)
    /// so the next open reuses the same thread.
    ///
    /// - Returns: the existing-or-newly-created `Conversation`, or a failure
    ///   when the feature is off or the network write fails.
    @discardableResult
    public func openDirectConversation(
        with friendship: Friendship
    ) async -> Result<Conversation, Error> {
        guard FeatureFlags.companion else {
            return .failure(FriendServiceError.featureDisabled)
        }

        let participants = [friendship.userLowId, friendship.userHighId]
        let now = nowISO()

        // Already linked → return a value pointing at the existing thread.
        if let existing = friendship.conversationId {
            return .success(
                Conversation(
                    id: existing,
                    requestId: nil,
                    participantIds: participants,
                    type: .friendDirect,
                    createdAt: friendship.createdAt,
                    updatedAt: now
                )
            )
        }

        // Lazily create a friendDirect conversation.
        let conversation = Conversation(
            id: ConversationId(rawValue: "conv_\(UUID().uuidString)"),
            requestId: nil,
            participantIds: participants,
            type: .friendDirect,
            createdAt: now,
            updatedAt: now
        )
        guard let convData = try? JSONEncoder.iso8601Encoder.encode(conversation) else {
            return .failure(FriendServiceError.encodingFailed)
        }
        let convResult = await client.post(table: "conversations", body: convData)
        if case .failure(let err) = convResult { return .failure(err) }

        // Write the conversation id back onto the friendship (upsert the row,
        // same merge-duplicates POST pattern used for request status updates).
        let linked = Friendship(
            id: friendship.id,
            userLowId: friendship.userLowId,
            userHighId: friendship.userHighId,
            initiatedBy: friendship.initiatedBy,
            conversationId: conversation.id,
            acceptedAt: friendship.acceptedAt,
            createdAt: friendship.createdAt,
            updatedAt: now
        )
        if let data = try? JSONEncoder.iso8601Encoder.encode(linked) {
            _ = await client.post(table: "friendships", body: data)
        }

        // Reflect the link locally so a re-open reuses the same thread.
        if let idx = friends.firstIndex(where: { $0.id == friendship.id }) {
            friends[idx] = linked
        }
        persistFriendship(linked)

        return .success(conversation)
    }

    // MARK: - US-013: Shareable friend code (friend_codes)

    /// Load the current user's active friend code, lazily generating one the
    /// first time. Resolution rule: the newest non-revoked `friend_codes` row.
    /// If none exists, a fresh `SOLO-XXXX-XXXX` code is generated, written to the
    /// backend, and cached in `myFriendCode`.
    ///
    /// - Returns: the active `FriendCode`, or a failure when the feature is off
    ///   or the network write fails.
    @discardableResult
    public func loadOrCreateFriendCode() async -> Result<FriendCode, Error> {
        // Cache hit short-circuits before the feature gate so an already-issued
        // code stays viewable regardless of flag/network state.
        if let cached = myFriendCode { return .success(cached) }
        guard FeatureFlags.companion else {
            return .failure(FriendServiceError.featureDisabled)
        }

        let owner = currentUserId

        // Look for an existing active (non-revoked) row.
        let existing = await client.get(
            table: "friend_codes",
            query: [
                URLQueryItem(name: "owner_id", value: "eq.\(owner)"),
                URLQueryItem(name: "revoked_at", value: "is.null"),
                URLQueryItem(name: "order", value: "created_at.desc"),
            ]
        )
        if case .success(let data) = existing, !data.isEmpty,
           let rows = try? JSONDecoder.iso8601Decoder.decode([FriendCodeRow].self, from: data),
           let active = rows.first(where: { $0.isActive }) {
            myFriendCode = active.code
            return .success(active.code)
        }

        // None active → mint a fresh one.
        return await issueNewCode(owner: owner)
    }

    /// Rotate the friend code: revoke the active row (`revoked_at` stamped) and
    /// issue a brand-new code. The old code stops resolving immediately.
    ///
    /// - Returns: the newly-issued `FriendCode`, or a failure on the network write.
    @discardableResult
    public func rotateFriendCode() async -> Result<FriendCode, Error> {
        guard FeatureFlags.companion else {
            return .failure(FriendServiceError.featureDisabled)
        }
        let owner = currentUserId
        let now = nowISO()

        // 1. Revoke every currently-active row for this owner.
        let activeRes = await client.get(
            table: "friend_codes",
            query: [
                URLQueryItem(name: "owner_id", value: "eq.\(owner)"),
                URLQueryItem(name: "revoked_at", value: "is.null"),
            ]
        )
        if case .success(let data) = activeRes, !data.isEmpty,
           let rows = try? JSONDecoder.iso8601Decoder.decode([FriendCodeRow].self, from: data) {
            for row in rows where row.isActive {
                let revoked = FriendCodeRow(
                    id: row.id,
                    ownerId: row.ownerId,
                    code: row.code,
                    revokedAt: now,
                    createdAt: row.createdAt,
                    updatedAt: now
                )
                if let body = try? JSONEncoder.iso8601Encoder.encode(revoked) {
                    // PostgREST upsert (merge-duplicates) — same pattern as
                    // request status updates: re-POST the row by primary key.
                    _ = await client.post(table: "friend_codes", body: body)
                }
            }
        }

        // 2. Issue the replacement. Clear the cache first so a failure doesn't
        //    leave a stale code visible.
        myFriendCode = nil
        return await issueNewCode(owner: owner)
    }

    /// Mint, persist, and cache a fresh `SOLO-XXXX-XXXX` code for `owner`.
    private func issueNewCode(owner: String) async -> Result<FriendCode, Error> {
        let now = nowISO()
        let row = FriendCodeRow(
            id: FriendCodeId(rawValue: "fcode_\(UUID().uuidString)"),
            ownerId: owner,
            code: FriendCode.generate(),
            revokedAt: nil,
            createdAt: now,
            updatedAt: now
        )
        guard let body = try? JSONEncoder.iso8601Encoder.encode(row) else {
            return .failure(FriendServiceError.encodingFailed)
        }
        let result = await client.post(table: "friend_codes", body: body)
        switch result {
        case .success:
            myFriendCode = row.code
            return .success(row.code)
        case .failure(let err):
            return .failure(err)
        }
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
