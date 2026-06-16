import XCTest
import SwiftUI
import CoreLocation
@testable import SoloCompass

final class PeekCardShortNameTest: XCTestCase {

    @MainActor
    func testPeekCardUsesShortName() throws {
        let exp = ExperienceService.hardcodedSeed.first!
        XCTAssertFalse(exp.shortName.isEmpty, "shortName should not be empty")

        let card = PeekSummaryCard(
            experience: exp,
            isSmartPick: true,
            referenceCoordinate: CLLocationCoordinate2D(latitude: 18.79, longitude: 98.98),
            onTap: {}
        )
        .frame(width: 390, height: 120)
        .environment(LocationService.shared)
        .environment(BestNowClock())

        let renderer = ImageRenderer(content: card)
        renderer.scale = 2.0
        let image = renderer.uiImage
        XCTAssertNotNil(image, "PeekSummaryCard with shortName should render")

        if let data = image?.pngData() {
            try data.write(to: URL(fileURLWithPath: "/tmp/peek_card_shortname_render.png"))
        }
    }

    func testShortNamePrefersRomanized() {
        let seed = ExperienceService.hardcodedSeed
        for exp in seed {
            let sn = exp.shortName
            if let rom = exp.location.placeNameRomanized, !rom.isEmpty {
                XCTAssertEqual(sn, rom, "shortName should prefer romanized for \(exp.id)")
            } else if let local = exp.location.placeNameLocal, !local.isEmpty {
                XCTAssertEqual(sn, local, "shortName should fall back to local for \(exp.id)")
            } else {
                XCTAssertEqual(sn, exp.title, "shortName should fall back to title for \(exp.id)")
            }
        }
    }
}
