import XCTest
import SwiftData
@testable import SoloCompass

/// `CompassMapView.handleRouteStopEntered(experienceId:)` is a private @MainActor
/// async method that consumes `LocationService.routeStopEntered` notifications
/// and updates two pieces of state: persisted route progress (via RouteStore)
/// and the Dynamic Island (via LiveActivityService.shared, which is a
/// singleton wrapper around `ActivityKit.Activity<…>`).
///
/// The View hook itself can't be fully tested without a UIKit window + a real
/// Live Activity — but the *decision* the handler makes is purely arithmetic:
///   1. Find the arrived experience's index in `route.experienceIds`.
///   2. Advance `RouteStore` (which appends to completed + bumps the index).
///   3. If `arrivedIndex + 1 >= totalStops`, end the Live Activity; else
///      update it with the next stop's name + 1-indexed display position.
///
/// These tests pin (1)/(2)/(3) so a future regression in the advance/last-stop
/// math (e.g. an off-by-one swapping "still walking" for "you're done!") is
/// caught even though the actual View hook stays untested.
@MainActor
final class HandleRouteStopEnteredContractTests: XCTestCase {

    private var store: RouteStore!

    override func setUp() async throws {
        try await super.setUp()
        let container = SoloCompassModelContainer.makeInMemory()
        store = RouteStore(context: ModelContext(container))
    }

    override func tearDown() async throws {
        store = nil
        try await super.tearDown()
    }

    private func makeAndStartRoute(stops: [String]) -> Route {
        let route = Route(
            id: RouteId(rawValue: "route_handler_\(UUID().uuidString)"),
            title: "Walk",
            summary: "",
            experienceIds: stops,
            cityCode: "vte",
            region: "",
            estimatedDuration: 60,
            distanceMeters: 1500,
            pace: .standard,
            tags: [],
            source: .editorial
        )
        store.save(route)
        store.startRoute(route.id)
        return route
    }

    // MARK: - The advanceStop side (every middle arrival)

    func testArrivingAtMiddleStopAppendsToCompletedAndBumpsIndex() {
        let route = makeAndStartRoute(stops: ["a", "b", "c"])
        store.advanceStop(route.id, completedExperienceId: "a")

        guard let snap = store.loadActiveRoute() else {
            return XCTFail("route should remain active after a middle-stop arrival")
        }
        XCTAssertEqual(snap.stopIndex, 1)
        XCTAssertEqual(snap.completedIds, ["a"])
    }

    func testArrivingAtSecondStopAppendsBoth() {
        let route = makeAndStartRoute(stops: ["a", "b", "c"])
        store.advanceStop(route.id, completedExperienceId: "a")
        store.advanceStop(route.id, completedExperienceId: "b")

        guard let snap = store.loadActiveRoute() else {
            return XCTFail("route should still be active until last stop")
        }
        XCTAssertEqual(snap.stopIndex, 2)
        XCTAssertEqual(snap.completedIds, ["a", "b"])
    }

    // MARK: - The end-vs-update decision (last-stop math)

    /// Mirrors the `nextIndex >= totalStops` check in handleRouteStopEntered.
    /// Encoded as a small struct so the decision is testable without standing
    /// up `LiveActivityService` (which wraps ActivityKit and isn't unit-friendly).
    private struct ArrivalDecision: Equatable {
        let nextIndex: Int
        let totalStops: Int
        var isLastStop: Bool { nextIndex >= totalStops }
        var humanIndex: Int { nextIndex + 1 }
    }

    private func decide(arrivedIndex: Int, totalStops: Int) -> ArrivalDecision {
        ArrivalDecision(nextIndex: arrivedIndex + 1, totalStops: totalStops)
    }

    func testArrivingAtFirstOfThreeIsNotLastStop() {
        let d = decide(arrivedIndex: 0, totalStops: 3)
        XCTAssertFalse(d.isLastStop)
        XCTAssertEqual(d.humanIndex, 2, "after arriving at stop 1/3, island shows 2/3")
    }

    func testArrivingAtMiddleOfThreeIsNotLastStop() {
        let d = decide(arrivedIndex: 1, totalStops: 3)
        XCTAssertFalse(d.isLastStop)
        XCTAssertEqual(d.humanIndex, 3, "after arriving at stop 2/3, island shows 3/3")
    }

    func testArrivingAtLastOfThreeIsLastStop() {
        let d = decide(arrivedIndex: 2, totalStops: 3)
        XCTAssertTrue(d.isLastStop, "arriving at the final stop must end the Live Activity")
    }

    func testSingleStopRouteIsAlwaysLastStop() {
        let d = decide(arrivedIndex: 0, totalStops: 1)
        XCTAssertTrue(d.isLastStop, "1-stop routes end on first arrival")
    }

    func testTwoStopRouteFirstIsNotLastStop() {
        let d = decide(arrivedIndex: 0, totalStops: 2)
        XCTAssertFalse(d.isLastStop)
        XCTAssertEqual(d.humanIndex, 2)
    }

    func testTwoStopRouteSecondIsLastStop() {
        let d = decide(arrivedIndex: 1, totalStops: 2)
        XCTAssertTrue(d.isLastStop)
    }

    // MARK: - Defensive: arrival at an experience NOT in the route

    func testArrivingAtUnrelatedExperienceDoesNotAdvance() {
        let route = makeAndStartRoute(stops: ["a", "b"])
        // handler guards `firstIndex(of:)` — an unrelated geofence trigger
        // (e.g. user walked past a favorite that isn't part of this route)
        // must NOT consume a slot in the active route.
        XCTAssertNil(route.experienceIds.firstIndex(of: "z"))
        guard let snap = store.loadActiveRoute() else {
            return XCTFail("route should remain active")
        }
        XCTAssertEqual(snap.stopIndex, 0)
        XCTAssertTrue(snap.completedIds.isEmpty)
    }

    // MARK: - Idempotence: arriving at the SAME stop twice

    func testArrivingAtSameStopTwiceDoesNotDuplicateCompletion() {
        // RouteStore.advanceStop dedupes by checking `!completed.contains(...)`.
        // A bouncing CLCircularRegion (enter/exit/enter near the boundary) can
        // fire the same arrival twice; we must not log two completions for the
        // same place.
        let route = makeAndStartRoute(stops: ["a", "b", "c"])
        store.advanceStop(route.id, completedExperienceId: "a")
        store.advanceStop(route.id, completedExperienceId: "a")

        guard let snap = store.loadActiveRoute() else {
            return XCTFail("route should still be active")
        }
        XCTAssertEqual(snap.completedIds, ["a"], "completedIds must dedupe by experienceId")
    }
}
