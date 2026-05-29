
// MARK: - CompanionEvent

public enum CompanionEvent: String, Sendable {
    case acceptFirst
    case acceptAdditional
    case reachMax
    case closeEarly
    case markCompleted
}

// MARK: - RouteCompanionStateMachine

public enum RouteCompanionStateMachine {

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
