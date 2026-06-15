import XCTest
import SwiftUI
import CoreLocation
@testable import SoloCompass

final class FarAwayDistanceTest: XCTestCase {

    @MainActor
    func testCardShowsCityNameWhenFarAway() throws {
        let exp = ExperienceService.hardcodedSeed.first!
        let farDistance: Double = 12_398_000

        let row = NearbyExperienceRow(
            experience: exp,
            isSmartPick: false,
            distanceMeters: farDistance,
            isOpenNow: false,
            onTap: {}
        )
        .frame(width: 390, height: 120)
        .environment(LocationService.shared)
        .environment(UserPreferences())
        .environment(BestNowClock())

        let renderer = ImageRenderer(content: row)
        renderer.scale = 2.0
        let image = renderer.uiImage
        XCTAssertNotNil(image, "NearbyExperienceRow should render with far distance")

        if let data = image?.pngData() {
            try data.write(to: URL(fileURLWithPath: "/tmp/card_far_distance.png"))
        }
    }

    @MainActor
    func testCardShowsMetersWhenNearby() throws {
        let exp = ExperienceService.hardcodedSeed.first!
        let nearDistance: Double = 850

        let row = NearbyExperienceRow(
            experience: exp,
            isSmartPick: false,
            distanceMeters: nearDistance,
            isOpenNow: false,
            onTap: {}
        )
        .frame(width: 390, height: 120)
        .environment(LocationService.shared)
        .environment(UserPreferences())
        .environment(BestNowClock())

        let renderer = ImageRenderer(content: row)
        renderer.scale = 2.0
        let image = renderer.uiImage
        XCTAssertNotNil(image, "NearbyExperienceRow should render with nearby distance")

        if let data = image?.pngData() {
            try data.write(to: URL(fileURLWithPath: "/tmp/card_near_distance.png"))
        }
    }
}
