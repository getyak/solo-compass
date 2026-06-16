import XCTest
import SwiftUI
@testable import SoloCompass

final class NowEmptyStateTest: XCTestCase {

    @MainActor
    func testNowFilterEmptyState() throws {
        let view = EmptySheetListView(isNowFilter: true)
            .frame(width: 390, height: 300)
            .background(CT.surfaceWhite)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        let image = renderer.uiImage
        XCTAssertNotNil(image, "Now filter empty state should render")

        if let data = image?.pngData() {
            try data.write(to: URL(fileURLWithPath: "/tmp/now_empty_state.png"))
        }
    }

    @MainActor
    func testRegularEmptyState() throws {
        let view = EmptySheetListView(isNowFilter: false)
            .frame(width: 390, height: 300)
            .background(CT.surfaceWhite)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        let image = renderer.uiImage
        XCTAssertNotNil(image, "Regular empty state should render")

        if let data = image?.pngData() {
            try data.write(to: URL(fileURLWithPath: "/tmp/regular_empty_state.png"))
        }
    }

    func testIsLateNightLogic() {
        let hour = Calendar.current.component(.hour, from: Date())
        let expected = hour >= 23 || hour < 6
        XCTAssertEqual(EmptySheetListView.isLateNight, expected)
    }
}
