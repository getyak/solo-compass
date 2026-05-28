import XCTest
@testable import SoloCompass

final class RouteCompanionStateMachineTests: XCTestCase {

    // MARK: - Legal transitions

    func testOpenAcceptFirstFormsGroup() throws {
        let next = try RouteCompanionStateMachine.transition(state: .open, event: .acceptFirst)
        XCTAssertEqual(next, .forming)
    }

    func testFormingAcceptAdditionalStaysForming() throws {
        let next = try RouteCompanionStateMachine.transition(state: .forming, event: .acceptAdditional)
        XCTAssertEqual(next, .forming)
    }

    func testFormingReachMaxCloses() throws {
        let next = try RouteCompanionStateMachine.transition(state: .forming, event: .reachMax)
        XCTAssertEqual(next, .closed)
    }

    func testFormingCloseEarlyCloses() throws {
        let next = try RouteCompanionStateMachine.transition(state: .forming, event: .closeEarly)
        XCTAssertEqual(next, .closed)
    }

    func testClosedMarkCompletedCompletes() throws {
        let next = try RouteCompanionStateMachine.transition(state: .closed, event: .markCompleted)
        XCTAssertEqual(next, .completed)
    }

    // MARK: - Illegal transitions

    private func assertIllegal(state: CompanionStatus, event: CompanionEvent, file: StaticString = #file, line: UInt = #line) {
        XCTAssertThrowsError(
            try RouteCompanionStateMachine.transition(state: state, event: event),
            "Expected IllegalTransition for \(state)+\(event)",
            file: file, line: line
        ) { error in
            XCTAssertTrue(error is RouteCompanionStateMachine.IllegalTransition, file: file, line: line)
        }
    }

    func testOpenToClosedIsIllegal() {
        assertIllegal(state: .open, event: .reachMax)
    }

    func testOpenMarkCompletedIsIllegal() {
        assertIllegal(state: .open, event: .markCompleted)
    }

    func testCompletedToOpenIsIllegal() {
        assertIllegal(state: .completed, event: .acceptFirst)
    }

    func testClosedAcceptFirstIsIllegal() {
        assertIllegal(state: .closed, event: .acceptFirst)
    }

    func testClosedAcceptAdditionalIsIllegal() {
        assertIllegal(state: .closed, event: .acceptAdditional)
    }

    func testCompletedMarkCompletedIsIllegal() {
        assertIllegal(state: .completed, event: .markCompleted)
    }

    func testOpenCloseEarlyIsIllegal() {
        assertIllegal(state: .open, event: .closeEarly)
    }
}
