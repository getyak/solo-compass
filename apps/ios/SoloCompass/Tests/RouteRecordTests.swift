import XCTest
@testable import SoloCompass

final class RouteRecordTests: XCTestCase {

    func testRouteRecordRoundTripPreservesAllFields() {
        let original = Route(
            id: RouteId(rawValue: "route-rt-1"),
            title: "Morning Shibuya Loop",
            summary: "Coffee, river walk, sunrise rooftop",
            experienceIds: ["exp-a", "exp-b", "exp-c"],
            cityCode: "tyo",
            region: "Shibuya",
            estimatedDuration: 120,
            distanceMeters: 3400,
            pace: .relaxed,
            tags: ["scenic", "morning", "coffee"],
            source: .aiGenerated,
            authorId: "user-7",
            bestStartHour: 7.5,
            bestNow: true,
            verification: RouteVerification(
                status: .walkedBy,
                walkedByCount: 2,
                walkedBy: ["user-1", "user-2"]
            ),
            companion: RouteCompanion()
        )

        let record = RouteRecord.fromValue(original)
        let restored = record.asValue

        XCTAssertEqual(restored.id.rawValue, original.id.rawValue)
        XCTAssertEqual(restored.title, original.title)
        XCTAssertEqual(restored.summary, original.summary)
        XCTAssertEqual(restored.experienceIds, original.experienceIds)
        XCTAssertEqual(restored.cityCode, original.cityCode)
        XCTAssertEqual(restored.region, original.region)
        XCTAssertEqual(restored.estimatedDuration, original.estimatedDuration)
        XCTAssertEqual(restored.distanceMeters, original.distanceMeters)
        XCTAssertEqual(restored.pace, original.pace)
        XCTAssertEqual(restored.tags, original.tags)
        XCTAssertEqual(restored.source, original.source)
        XCTAssertEqual(restored.authorId, original.authorId)
        XCTAssertEqual(restored.bestStartHour, original.bestStartHour)
        XCTAssertEqual(restored.bestNow, original.bestNow)
        XCTAssertEqual(restored.verification.status, original.verification.status)
        XCTAssertEqual(restored.verification.walkedByCount, original.verification.walkedByCount)
        XCTAssertEqual(restored.verification.walkedBy, original.verification.walkedBy)
        XCTAssertNotNil(restored.companion)
    }

    func testRouteRecordRoundTripWithDefaultsAndNilCompanion() {
        let original = Route(
            id: RouteId(rawValue: "route-rt-2"),
            title: "Empty",
            summary: "",
            experienceIds: [],
            cityCode: "tyo",
            region: "Shinjuku",
            estimatedDuration: 0,
            distanceMeters: 0,
            pace: .standard,
            source: .editorial
        )

        let record = RouteRecord.fromValue(original)
        XCTAssertNil(record.companionBlob)
        XCTAssertNil(record.authorId)
        XCTAssertNil(record.bestStartHour)

        let restored = record.asValue
        XCTAssertEqual(restored.id.rawValue, "route-rt-2")
        XCTAssertTrue(restored.experienceIds.isEmpty)
        XCTAssertTrue(restored.tags.isEmpty)
        XCTAssertTrue(restored.verification.walkedBy.isEmpty)
        XCTAssertEqual(restored.verification.status, .proposed)
        XCTAssertEqual(restored.verification.walkedByCount, 0)
        XCTAssertFalse(restored.bestNow)
        XCTAssertNil(restored.companion)
        XCTAssertNil(restored.authorId)
        XCTAssertNil(restored.bestStartHour)
    }

    func testRouteRecordPreservesExperienceIdOrder() {
        let ordered = ["exp-delta", "exp-alpha", "exp-charlie", "exp-bravo"]
        let original = Route(
            id: RouteId(rawValue: "route-rt-3"),
            title: "Order test",
            summary: "",
            experienceIds: ordered,
            cityCode: "tyo",
            region: "Ginza",
            estimatedDuration: 60,
            distanceMeters: 1200,
            pace: .packed,
            source: .userCreated
        )

        let restored = RouteRecord.fromValue(original).asValue
        XCTAssertEqual(restored.experienceIds, ordered)
    }
}
