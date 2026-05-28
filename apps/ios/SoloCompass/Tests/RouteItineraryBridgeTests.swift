import XCTest
@testable import SoloCompass

final class RouteItineraryBridgeTests: XCTestCase {

    // MARK: - Itinerary -> Route

    func testItineraryToRouteSetsExpectedDefaults() {
        let itinerary = makeItinerary()
        let route = Route(itinerary: itinerary)

        XCTAssertEqual(route.source, .userCreated)
        XCTAssertNil(route.companion)
        XCTAssertEqual(route.verification.status, .proposed)
        XCTAssertEqual(route.verification.walkedByCount, 0)
        XCTAssertTrue(route.verification.walkedBy.isEmpty)
    }

    func testItineraryToRoutePreservesCoreFields() {
        let itinerary = makeItinerary(
            experienceIds: ["exp-1", "exp-2", "exp-3"]
        )
        let route = Route(itinerary: itinerary)

        XCTAssertEqual(route.id.rawValue, itinerary.id.rawValue)
        XCTAssertEqual(route.title, itinerary.title)
        XCTAssertEqual(route.cityCode, itinerary.cityCode)
        XCTAssertEqual(route.authorId, itinerary.ownerId)
        XCTAssertEqual(route.experienceIds, itinerary.experienceIds)
    }

    // MARK: - Round-trip equality

    func testItineraryRouteRoundTripPreservesAllFields() {
        let original = makeItinerary(
            experienceIds: ["exp-alpha", "exp-beta", "exp-gamma"],
            note: "Focus on quiet cafes in the morning.",
            openToCompanions: true
        )

        let route = Route(itinerary: original)
        guard let recovered = Itinerary(route: route) else {
            return XCTFail("Expected Itinerary(route:) to succeed for source=.userCreated")
        }

        XCTAssertEqual(recovered.id.rawValue, original.id.rawValue)
        XCTAssertEqual(recovered.ownerId, original.ownerId)
        XCTAssertEqual(recovered.title, original.title)
        XCTAssertEqual(recovered.cityCode, original.cityCode)
        XCTAssertEqual(recovered.startDate, original.startDate)
        XCTAssertEqual(recovered.endDate, original.endDate)
        XCTAssertEqual(recovered.experienceIds, original.experienceIds)
        XCTAssertEqual(recovered.note, original.note)
        XCTAssertEqual(recovered.openToCompanions, original.openToCompanions)
        XCTAssertEqual(recovered.createdAt, original.createdAt)
        XCTAssertEqual(recovered.updatedAt, original.updatedAt)
    }

    func testRoundTripPreservesNilNote() {
        let original = makeItinerary(note: nil)
        let route = Route(itinerary: original)
        guard let recovered = Itinerary(route: route) else {
            return XCTFail("Expected Itinerary(route:) to succeed")
        }
        XCTAssertNil(recovered.note)
    }

    func testRoundTripPreservesEmptyButNonNilNote() {
        let original = makeItinerary(note: "")
        let route = Route(itinerary: original)
        guard let recovered = Itinerary(route: route) else {
            return XCTFail("Expected Itinerary(route:) to succeed")
        }
        XCTAssertEqual(recovered.note, "")
    }

    func testRoundTripPreservesOpenToCompanionsFalse() {
        let original = makeItinerary(openToCompanions: false)
        let route = Route(itinerary: original)
        guard let recovered = Itinerary(route: route) else {
            return XCTFail("Expected Itinerary(route:) to succeed")
        }
        XCTAssertEqual(recovered.openToCompanions, false)
    }

    // MARK: - Ordering

    func testRoundTripPreservesExperienceOrder() {
        let order = ["zeta", "alpha", "mu", "beta", "omega"]
        let original = makeItinerary(experienceIds: order)
        let route = Route(itinerary: original)
        XCTAssertEqual(route.experienceIds, order)
        guard let recovered = Itinerary(route: route) else {
            return XCTFail("Expected Itinerary(route:) to succeed")
        }
        XCTAssertEqual(recovered.experienceIds, order)
    }

    // MARK: - Companion stays nil

    func testCompanionIsNilAfterRoundTrip() {
        let original = makeItinerary()
        let route = Route(itinerary: original)
        XCTAssertNil(route.companion)
        let recovered = Itinerary(route: route)
        XCTAssertNotNil(recovered)
        XCTAssertNil(route.companion)
    }

    // MARK: - Route -> Itinerary failure cases

    func testItineraryFromRouteFailsWhenSourceIsNotUserCreated() {
        for source in RouteSource.allCases where source != .userCreated {
            let itinerary = makeItinerary()
            var route = Route(itinerary: itinerary)
            route.source = source
            XCTAssertNil(
                Itinerary(route: route),
                "Itinerary(route:) should return nil for source=\(source)"
            )
        }
    }

    func testItineraryFromRouteSucceedsWhenSourceIsUserCreated() {
        let route = Route(itinerary: makeItinerary())
        XCTAssertEqual(route.source, .userCreated)
        XCTAssertNotNil(Itinerary(route: route))
    }

    // MARK: - Helpers

    private func makeItinerary(
        id: String = "itin-test",
        ownerId: String = "user-42",
        title: String = "Tokyo Spring 2026",
        cityCode: String = "TYO",
        startDate: String = "2026-04-01",
        endDate: String = "2026-04-10",
        experienceIds: [String] = ["exp-1", "exp-2"],
        note: String? = "Focus on cherry blossoms.",
        openToCompanions: Bool = true,
        createdAt: String = "2026-01-15T09:00:00Z",
        updatedAt: String = "2026-01-15T09:00:00Z"
    ) -> Itinerary {
        Itinerary(
            id: ItineraryId(rawValue: id),
            ownerId: ownerId,
            title: title,
            cityCode: cityCode,
            startDate: startDate,
            endDate: endDate,
            experienceIds: experienceIds,
            note: note,
            openToCompanions: openToCompanions,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
