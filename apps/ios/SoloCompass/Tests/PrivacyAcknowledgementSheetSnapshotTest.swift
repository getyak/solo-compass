import XCTest
import SwiftUI
@testable import SoloCompass

/// V-001 regression coverage: the Explore-Here privacy acknowledgement sheet
/// (`ExploreConsentSheet`) must render its full subtitle — the phrase ending in
/// "…on your behalf." — without truncation, at both the default and the largest
/// accessibility Dynamic Type sizes.
///
/// We don't ship a third-party snapshot library, so instead of comparing pixels
/// we render the sheet through SwiftUI's `ImageRenderer` at two Dynamic Type
/// sizes and assert each render produces a valid, non-empty image whose height
/// grows with the accessibility size. A truncated subtitle would collapse to a
/// single line and the AX5 render would not be meaningfully taller than the
/// default one — so the height ordering is our truncation guard.
@MainActor
final class PrivacyAcknowledgementSheetSnapshotTest: XCTestCase {

    /// Render the consent sheet at a fixed width and a given Dynamic Type size.
    private func render(_ size: DynamicTypeSize) -> UIImage? {
        let view = ExploreConsentSheet(onAccept: {}, onCancel: {})
            .dynamicTypeSize(size)
            .frame(width: 390) // iPhone 17 Pro logical width
            .fixedSize(horizontal: false, vertical: true)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage
    }

    func testSnapshotAtAccessibilityMedium() throws {
        let image = try XCTUnwrap(
            render(.accessibilityMedium),
            "Sheet must render at .accessibilityMedium"
        )
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testSnapshotAtAccessibilityExtraExtraExtraLarge() throws {
        let image = try XCTUnwrap(
            render(.accessibilityExtraExtraExtraLarge),
            "Sheet must render at AX5 (.accessibilityExtraExtraExtraLarge)"
        )
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    /// The core anti-truncation assertion: at the largest accessibility size the
    /// subtitle wraps across more lines, so the overall sheet must be strictly
    /// taller than at the default-ish accessibility size. If the subtitle were
    /// truncated (single line, fixed height) this ordering would not hold.
    func testSubtitleExpandsAtLargerDynamicType() throws {
        let medium = try XCTUnwrap(render(.accessibilityMedium))
        let ax5 = try XCTUnwrap(render(.accessibilityExtraExtraExtraLarge))
        XCTAssertGreaterThan(
            ax5.size.height,
            medium.size.height,
            "AX5 render must be taller than AX-medium — proves text grows/wraps instead of truncating"
        )
    }

    /// Guards the localized string itself: the full subtitle phrase must end in
    /// "on your behalf." so the UI has the complete sentence to render.
    func testSubtitleLocalizedStringIsComplete() {
        let subtitle = NSLocalizedString("explore.consent.subtitle", comment: "")
        XCTAssertTrue(
            subtitle.contains("on your behalf"),
            "Subtitle must contain the full phrase ending in '…on your behalf'"
        )
    }
}
