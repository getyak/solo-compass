import XCTest
import UIKit
@testable import SoloCompass

/// City OS v2 §5.3: the 在地 event marker's category→icon mapping is pure and
/// every icon it can emit must be a real SF Symbol (a ghost symbol renders as a
/// blank glyph with no error). The rotating ring is gated by an `animatesRing`
/// init param defaulting to the environment's Reduce Motion, so the view can be
/// constructed in both states without an environment injection.
@MainActor
final class EventMarkerReduceMotionTest: XCTestCase {

    func testCategoryIconMappingIsStable() {
        XCTAssertEqual(EventMarkerView.categoryIcon(for: "culture"), "theatermasks")
        XCTAssertEqual(EventMarkerView.categoryIcon(for: "market"), "basket")
        XCTAssertEqual(EventMarkerView.categoryIcon(for: "wellness"), "figure.run")
        XCTAssertEqual(EventMarkerView.categoryIcon(for: "music"), "music.note")
        XCTAssertEqual(EventMarkerView.categoryIcon(for: "sports"), "sportscourt")
        XCTAssertEqual(EventMarkerView.categoryIcon(for: "food"), "fork.knife")
        XCTAssertEqual(EventMarkerView.categoryIcon(for: "notice"), "exclamationmark.triangle")
    }

    func testUnknownCategoryFallsBackToCalendar() {
        XCTAssertEqual(EventMarkerView.categoryIcon(for: "nonsense"), "calendar")
        XCTAssertEqual(EventMarkerView.categoryIcon(for: nil), "calendar")
    }

    func testEveryEmittedIconIsARealSFSymbol() {
        let categories = ["culture", "market", "wellness", "music", "sports", "food", "notice", nil, "??"]
        for c in categories {
            let name = EventMarkerView.categoryIcon(for: c)
            XCTAssertNotNil(
                UIImage(systemName: name),
                "EventMarkerView.categoryIcon(for: \(c ?? "nil")) → '\(name)' is not a real SF Symbol"
            )
        }
    }

    func testMarkerConstructsInBothMotionStates() {
        let event = CityEvent(
            id: "evt_test", cityCode: "vte", name: "夜市", whenLabel: "本周每晚",
            soloScore: 8.0, category: "market", sourceURL: nil
        )
        // Both explicit ring states must build without trapping.
        _ = EventMarkerView(event: event, animatesRing: true, onTap: {})
        _ = EventMarkerView(event: event, animatesRing: false, onTap: {})
    }
}
