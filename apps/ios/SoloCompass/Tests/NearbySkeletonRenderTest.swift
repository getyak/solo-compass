import XCTest
import SwiftUI
@testable import SoloCompass

final class NearbySkeletonRenderTest: XCTestCase {

    @MainActor
    func testSkeletonListRenders() throws {
        let view = NearbyRowSkeletonList()
            .frame(width: 390, height: 300)
            .background(CT.surfaceWhite)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        let image = renderer.uiImage
        XCTAssertNotNil(image, "Skeleton list should render")

        if let data = image?.pngData() {
            try data.write(to: URL(fileURLWithPath: "/tmp/nearby_skeleton.png"))
        }
    }
}
