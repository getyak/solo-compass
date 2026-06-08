import XCTest
@testable import SoloCompass

// MARK: - US-005: FriendshipStateMachine

/// Exhaustive coverage of the pure friendship transition rules:
/// every legal `(state, event)` pair, a sweep of the illegal pairs (which must
/// throw `IllegalTransition`), and the three special `resolveSendRequest` rules
/// (mutual-pending fold, already-friends no-op, blocked silent-drop).
final class FriendshipStateMachineTests: XCTestCase {

    // MARK: transition — legal pairs

    func testLegalTransitions() throws {
        let cases: [(FriendRelationState, FriendEvent, FriendRelationState)] = [
            (.none, .sendRequest, .pending),
            (.pending, .accept, .accepted),
            (.pending, .decline, .none),
            (.pending, .withdraw, .none),
            (.pending, .expire, .none),
            (.accepted, .block, .blocked),
            (.pending, .block, .blocked),
            (.none, .block, .blocked),
            (.blocked, .unblock, .none),
        ]
        for (state, event, expected) in cases {
            let result = try FriendshipStateMachine.transition(state: state, event: event)
            XCTAssertEqual(
                result, expected,
                "transition(\(state), \(event)) should be \(expected), got \(result)"
            )
        }
    }

    // MARK: transition — illegal pairs throw

    func testIllegalTransitionsThrow() {
        // A representative sweep of disallowed pairs across every state.
        let illegal: [(FriendRelationState, FriendEvent)] = [
            (.none, .accept),       // nothing pending to accept
            (.none, .decline),
            (.none, .withdraw),
            (.none, .expire),
            (.none, .unblock),      // not blocked
            (.pending, .sendRequest), // already pending (resend handled upstream)
            (.pending, .unblock),
            (.accepted, .accept),   // already friends
            (.accepted, .sendRequest),
            (.accepted, .decline),
            (.accepted, .withdraw),
            (.accepted, .expire),
            (.accepted, .unblock),
            (.blocked, .sendRequest),
            (.blocked, .accept),
            (.blocked, .decline),
            (.blocked, .withdraw),
            (.blocked, .expire),
            (.blocked, .block),     // already blocked
        ]
        for (state, event) in illegal {
            XCTAssertThrowsError(
                try FriendshipStateMachine.transition(state: state, event: event),
                "transition(\(state), \(event)) should throw IllegalTransition"
            ) { error in
                guard let illegal = error as? FriendshipStateMachine.IllegalTransition else {
                    return XCTFail("expected IllegalTransition, got \(error)")
                }
                XCTAssertEqual(illegal.state, state)
                XCTAssertEqual(illegal.event, event)
            }
        }
    }

    // MARK: resolveSendRequest — special rule 1: mutual-pending fold

    func testResolveSendRequest_mutualPending_autoAccepts() {
        // The recipient already sent us a still-pending request → both want it.
        let outcome = FriendshipStateMachine.resolveSendRequest(
            currentState: .pending,
            hasInboundPending: true,
            isBlockedEitherWay: false
        )
        XCTAssertEqual(outcome, .autoAccepted)
    }

    func testResolveSendRequest_inboundPendingFromNone_autoAccepts() {
        // Even from a .none outgoing view, an inbound pending folds to accept.
        let outcome = FriendshipStateMachine.resolveSendRequest(
            currentState: .none,
            hasInboundPending: true,
            isBlockedEitherWay: false
        )
        XCTAssertEqual(outcome, .autoAccepted)
    }

    // MARK: resolveSendRequest — special rule 2: already-friends no-op

    func testResolveSendRequest_alreadyFriends_isNoOp() {
        let outcome = FriendshipStateMachine.resolveSendRequest(
            currentState: .accepted,
            hasInboundPending: false,
            isBlockedEitherWay: false
        )
        XCTAssertEqual(outcome, .alreadyFriends)
    }

    func testResolveSendRequest_alreadyFriends_winsOverInboundPending() {
        // Accepted takes precedence even if an inbound pending somehow lingers.
        let outcome = FriendshipStateMachine.resolveSendRequest(
            currentState: .accepted,
            hasInboundPending: true,
            isBlockedEitherWay: false
        )
        XCTAssertEqual(outcome, .alreadyFriends)
    }

    // MARK: resolveSendRequest — special rule 3: blocked silent-drop

    func testResolveSendRequest_blockedFlag_silentlyDrops() {
        let outcome = FriendshipStateMachine.resolveSendRequest(
            currentState: .none,
            hasInboundPending: false,
            isBlockedEitherWay: true
        )
        XCTAssertEqual(outcome, .silentlyDropped)
    }

    func testResolveSendRequest_blockedState_silentlyDrops() {
        let outcome = FriendshipStateMachine.resolveSendRequest(
            currentState: .blocked,
            hasInboundPending: false,
            isBlockedEitherWay: false
        )
        XCTAssertEqual(outcome, .silentlyDropped)
    }

    func testResolveSendRequest_blocked_winsOverEverything() {
        // Block is the highest-priority rule: even a mutual pending is dropped.
        let outcome = FriendshipStateMachine.resolveSendRequest(
            currentState: .pending,
            hasInboundPending: true,
            isBlockedEitherWay: true
        )
        XCTAssertEqual(outcome, .silentlyDropped)
    }

    // MARK: resolveSendRequest — default path

    func testResolveSendRequest_none_createsPending() {
        let outcome = FriendshipStateMachine.resolveSendRequest(
            currentState: .none,
            hasInboundPending: false,
            isBlockedEitherWay: false
        )
        XCTAssertEqual(outcome, .createdPending)
    }

    func testResolveSendRequest_ownPendingResend_staysPending() {
        // Re-sending while our own request is pending (no inbound) → pending.
        let outcome = FriendshipStateMachine.resolveSendRequest(
            currentState: .pending,
            hasInboundPending: false,
            isBlockedEitherWay: false
        )
        XCTAssertEqual(outcome, .createdPending)
    }
}
