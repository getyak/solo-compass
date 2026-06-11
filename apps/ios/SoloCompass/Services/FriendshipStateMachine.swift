import Foundation

// MARK: - FriendRelationState

/// The relationship between two users from the perspective of a pending action.
public enum FriendRelationState: String, Sendable, Equatable {
    /// No relationship and no live request.
    case none
    /// A request is outstanding (someone sent, awaiting accept).
    case pending
    /// Confirmed friends.
    case accepted
    /// One side has blocked the other.
    case blocked
}

// MARK: - FriendEvent

/// Actions that move a friendship through its lifecycle.
public enum FriendEvent: Sendable, Equatable {
    /// Requester sends a friend request.
    case sendRequest
    /// Recipient accepts a pending request.
    case accept
    /// Recipient declines a pending request.
    case decline
    /// Requester withdraws their pending request.
    case withdraw
    /// A pending request ages out (14 days).
    case expire
    /// Either side blocks the other.
    case block
    /// The blocker unblocks.
    case unblock
}

// MARK: - SendRequestOutcome

/// The resolved effect of a `sendRequest`, accounting for the special rules
/// (mutual-pending fold, already-friends no-op, blocked silent-drop).
public enum SendRequestOutcome: Equatable, Sendable {
    /// A normal new pending request should be created.
    case createdPending
    /// The recipient already had a pending request to the requester → both
    /// want it, so auto-accept the *existing inbound* request.
    case autoAccepted
    /// An auto-accept policy applies (recipient is staff, a co-traveler, or the
    /// recipient opted into auto-accept) with NO inbound request → create the
    /// friendship directly, skipping the pending step.
    case autoAcceptedDirect
    /// Already friends → no-op, return the existing friendship.
    case alreadyFriends
    /// The requester is blocked by the recipient (or vice-versa) → silently
    /// drop. We never reveal block status, so this *looks* like success to the
    /// caller but enqueues nothing.
    case silentlyDropped
}

/// Why a `sendRequest` should bypass the pending step and become an immediate
/// friendship. Computed by the caller (which has the I/O to know these facts)
/// and handed to the pure resolver. `.none` = normal pending flow.
public enum AutoAcceptPolicy: Equatable, Sendable {
    /// No auto-accept — the recipient must approve the request.
    case none
    /// The recipient is a platform moderator/admin (staff are reachable
    /// directly so users can always get help).
    case staffRecipient
    /// Both users are confirmed members of the same route (co-travelers skip
    /// the approval friction — FRIENDS_DESIGN §4).
    case coTraveler
    /// The recipient has turned on "auto-accept friend requests".
    case recipientOptedIn

    /// True when this policy grants an immediate friendship.
    public var grantsImmediate: Bool { self != .none }
}

// MARK: - FriendshipStateMachine

/// Rules governing how a friendship progresses. Pure functions only — no I/O,
/// no persistence — so every transition is unit-testable. Mirrors the
/// `RouteCompanionStateMachine` style.
public enum FriendshipStateMachine {

    /// Raised when an event cannot be applied to the current relation state.
    public struct IllegalTransition: Error, Equatable {
        public let state: FriendRelationState
        public let event: FriendEvent
    }

    /// Pure transition function for the base lifecycle. Throws
    /// `IllegalTransition` for any disallowed (state, event) pair.
    ///
    /// Note: `sendRequest` from `.none` is handled here as the simple case
    /// (→ pending). The special rules (mutual-pending fold, already-friends,
    /// blocked) are resolved *before* calling this, by `resolveSendRequest`.
    public static func transition(
        state: FriendRelationState,
        event: FriendEvent
    ) throws -> FriendRelationState {
        switch (state, event) {
        case (.none, .sendRequest):    return .pending
        case (.pending, .accept):      return .accepted
        case (.pending, .decline):     return .none
        case (.pending, .withdraw):    return .none
        case (.pending, .expire):      return .none
        case (.accepted, .block):      return .blocked
        case (.pending, .block):       return .blocked
        case (.none, .block):          return .blocked
        case (.blocked, .unblock):     return .none
        default:
            throw IllegalTransition(state: state, event: event)
        }
    }

    /// Resolve a `sendRequest` against the *current* relationship, applying the
    /// three special rules from the design (§3 of FRIENDS_DESIGN):
    ///
    /// 1. **Mutual-pending fold** — if the recipient already has a pending
    ///    request *to the requester*, both want it → auto-accept.
    /// 2. **Already-friends no-op** — if already accepted, do nothing.
    /// 3. **Blocked silent-drop** — if either side blocked the other, succeed
    ///    silently without enqueuing (never leak block status).
    ///
    /// - Parameters:
    ///   - currentState: the (requester → recipient) relation state.
    ///   - hasInboundPending: true when the recipient already sent the
    ///     requester a still-pending request (the reverse direction).
    ///   - isBlockedEitherWay: true when either user has blocked the other.
    ///   - autoAcceptPolicy: a non-`.none` policy makes the request bypass the
    ///     pending step and become an immediate friendship (staff recipient,
    ///     co-traveler, or recipient opted-in). Block/already-friends/mutual
    ///     rules still take precedence over the policy.
    public static func resolveSendRequest(
        currentState: FriendRelationState,
        hasInboundPending: Bool,
        isBlockedEitherWay: Bool,
        autoAcceptPolicy: AutoAcceptPolicy = .none
    ) -> SendRequestOutcome {
        // Safety rules win over any auto-accept policy: never override a block,
        // never re-create an existing friendship.
        if isBlockedEitherWay || currentState == .blocked {
            return .silentlyDropped
        }
        if currentState == .accepted {
            return .alreadyFriends
        }
        if hasInboundPending {
            return .autoAccepted
        }
        // No inbound request, relationship is open → an auto-accept policy
        // creates the friendship directly; otherwise a normal pending request.
        if autoAcceptPolicy.grantsImmediate {
            return .autoAcceptedDirect
        }
        // currentState is .none or our own .pending (re-send) → pending.
        return .createdPending
    }
}
