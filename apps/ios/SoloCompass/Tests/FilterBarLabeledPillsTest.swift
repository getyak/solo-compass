import XCTest
import SwiftUI
@testable import SoloCompass

final class FilterBarLabeledPillsTest: XCTestCase {

    @MainActor
    func testFilterBarRendersWithLabels() throws {
        let bar = FilterBarView(
            selectedCategory: nil,
            isNowSelected: false,
            onSelectNow: {},
            onSelectAll: {},
            onSelectCategory: { _ in },
            resultCount: 5
        )
        .frame(width: 402, height: 60)
        .environment(UserPreferences())
        .environment(BestNowClock())

        let renderer = ImageRenderer(content: bar)
        renderer.scale = 2.0
        let image = renderer.uiImage
        XCTAssertNotNil(image, "FilterBar with labeled category pills should render")

        if let data = image?.pngData() {
            try data.write(to: URL(fileURLWithPath: "/tmp/filterbar_labeled_pills.png"))
        }
    }

    @MainActor
    func testFilterBarWithSelectedCategory() throws {
        let bar = FilterBarView(
            selectedCategory: .food,
            isNowSelected: false,
            onSelectNow: {},
            onSelectAll: {},
            onSelectCategory: { _ in },
            resultCount: 3
        )
        .frame(width: 402, height: 60)
        .environment(UserPreferences())
        .environment(BestNowClock())

        let renderer = ImageRenderer(content: bar)
        renderer.scale = 2.0
        let image = renderer.uiImage
        XCTAssertNotNil(image, "FilterBar with food selected should render")

        if let data = image?.pngData() {
            try data.write(to: URL(fileURLWithPath: "/tmp/filterbar_food_selected.png"))
        }
    }
}
