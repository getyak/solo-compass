import XCTest
import SwiftUI
@testable import SoloCompass

final class LocationBannerActionTest: XCTestCase {

    @MainActor
    func testBannerWithOpenSettingsButton() throws {
        let banner = DismissibleBanner(
            systemImage: "location.slash.fill",
            text: NSLocalizedString("location.error.banner", comment: ""),
            color: .orange,
            actionLabel: NSLocalizedString("location.banner.openSettings", comment: ""),
            onAction: {},
            onDismiss: {}
        )
        .frame(width: 390)
        .padding(.vertical, 8)
        .background(Color(UIColor.systemBackground))

        let renderer = ImageRenderer(content: banner)
        renderer.scale = 2.0
        let image = renderer.uiImage
        XCTAssertNotNil(image, "Banner with Open Settings button should render")

        if let data = image?.pngData() {
            try data.write(to: URL(fileURLWithPath: "/tmp/location_banner_settings.png"))
        }
    }

    @MainActor
    func testBannerWithoutAction() throws {
        let banner = DismissibleBanner(
            systemImage: "clock.badge.exclamationmark",
            text: "Quota info banner",
            color: Color(red: 0.8, green: 0.6, blue: 0),
            onDismiss: {}
        )
        .frame(width: 390)
        .padding(.vertical, 8)
        .background(Color(UIColor.systemBackground))

        let renderer = ImageRenderer(content: banner)
        renderer.scale = 2.0
        let image = renderer.uiImage
        XCTAssertNotNil(image, "Banner without action should still render")

        if let data = image?.pngData() {
            try data.write(to: URL(fileURLWithPath: "/tmp/location_banner_no_action.png"))
        }
    }
}
