
// MARK: - CompanionEvent

/// Actions that move a companion meetup through its lifecycle, such as someone joining or it closing.
public enum CompanionEvent: String, Sendable {
    case acceptFirst
    case acceptAdditional
    case reachMax
    case closeEarly
    case markCompleted
}

// MARK: - RouteCompanionStateMachine

/// Rules governing how a companion meetup progresses from open to forming to closed.
public enum RouteCompanionStateMachine {

    /// Raised when a companion event cannot be applied to the meetup's current state.
    public struct IllegalTransition: Error {
        public let state: CompanionStatus
        public let event: CompanionEvent
    }

    /// Pure transition function. Throws `IllegalTransition` for any disallowed (state, event) pair.
    public static func transition(
        state: CompanionStatus,
        event: CompanionEvent
    ) throws -> CompanionStatus {
        switch (state, event) {
        case (.open, .acceptFirst):       return .forming
        case (.forming, .acceptAdditional): return .forming
        case (.forming, .reachMax):       return .closed
        case (.forming, .closeEarly):     return .closed
        case (.closed, .markCompleted):   return .completed
        default:
            throw IllegalTransition(state: state, event: event)
        }
    }
}
