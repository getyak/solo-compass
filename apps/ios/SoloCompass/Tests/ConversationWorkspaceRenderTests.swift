import XCTest
import SwiftUI
import UIKit
@testable import SoloCompass

/// Render-level checks for the two layout regressions the workspace touched:
/// the conversation panel's height must match its detent, and `InlineBanner`
/// must size to its content instead of stretching into a huge empty box.
///
/// These use `ImageRenderer` (no simulator window needed) so they run in the
/// normal unit-test process.
@MainActor
final class ConversationWorkspaceRenderTests: XCTestCase {

    private let size = CGSize(width: 390, height: 800)

    // MARK: - Panel height

    func testPanelRendersConversationHeight() throws {
        let top = try panelTop(detent: .conversation)
        XCTAssertEqual(Double(top), 176, accuracy: 10, "78% conversation panel leaves a clean map glimpse")
    }

    func testPanelRendersExpandedHeight() throws {
        let top = try panelTop(detent: .expanded)
        XCTAssertEqual(Double(top), 40, accuracy: 10, "Expanded panel covers 95% of the container")
    }

    func testPanelRendersCollapsedBar() throws {
        let top = try panelTop(detent: .collapsed)
        XCTAssertEqual(
            Double(top),
            Double(size.height - ConversationWorkspaceState.Metrics.collapsedHeight),
            accuracy: 10,
            "Collapsed map surface keeps only the slim handle + dock bar"
        )
    }

    // MARK: - InlineBanner sizing

    func testCompactBannerDoesNotStretchIntoEmptyBox() throws {
        // Host the banner in a flexible column with a Spacer, exactly the shape
        // that used to make its fixed-width Rectangle rail fill all remaining
        // height and stretch the banner into a huge empty box.
        let view = VStack(spacing: 0) {
            InlineBanner(
                tone: .info,
                title: "Waking up the agent…",
                subtitle: "Give it a second, then send again.",
                icon: "info.circle.fill"
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .frame(width: size.width, height: size.height)
        .background(Color.blue)
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.isOpaque = true
        let image = try XCTUnwrap(renderer.uiImage)

        // Far below the banner must still be the background — if the banner
        // stretched, this row would carry its surface fill instead.
        XCTAssertTrue(
            try isBackground(image, x: 195, y: 400),
            "Banner must not stretch down the whole column (unbounded Rectangle regression)"
        )

        let bannerBottom = try lastNonBackgroundRow(in: image, column: 195)
        XCTAssertLessThan(
            Double(bannerBottom), 140,
            "A title + subtitle banner should stay compact, not become a huge empty box"
        )
    }

    // MARK: - Helpers

    private func panelTop(detent: ConversationWorkspaceState.PanelDetent) throws -> Int {
        let state = ConversationWorkspaceState()
        state.selectDetent(detent)
        let view = ZStack(alignment: .bottom) {
            Color.blue
            ConversationPanel(workspace: state, containerHeight: size.height) {
                Color.clear
            } dock: {
                Color.clear.frame(height: 60)
            }
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.isOpaque = true
        let image = try XCTUnwrap(renderer.uiImage)
        return try XCTUnwrap(
            firstNonBackgroundRow(in: image, column: 195),
            "Panel never rendered a contrasting top edge"
        )
    }

    /// Euclidean RGB distance threshold. A soft drop shadow darkens the
    /// background by well under this; the panel border/interior is far beyond.
    private let backgroundTolerance: Double = 120

    private func firstNonBackgroundRow(in image: UIImage, column: Int) -> Int? {
        for y in 0..<image.pixelHeight {
            if (try? isBackground(image, x: column, y: y)) == false { return y }
        }
        return nil
    }

    private func lastNonBackgroundRow(in image: UIImage, column: Int) throws -> Int {
        var last = 0
        for y in 0..<image.pixelHeight {
            let background = try isBackground(image, x: column, y: y)
            if !background { last = y }
        }
        return last
    }

    private func isBackground(_ image: UIImage, x: Int, y: Int) throws -> Bool {
        let reference = try XCTUnwrap(pixel(image, x: 4, y: 4))
        let sample = try XCTUnwrap(pixel(image, x: x, y: y))
        let distance = sqrt(
            pow(Double(reference.0) - Double(sample.0), 2)
                + pow(Double(reference.1) - Double(sample.1), 2)
                + pow(Double(reference.2) - Double(sample.2), 2)
        )
        return distance < backgroundTolerance
    }

    private func pixel(_ image: UIImage, x: Int, y: Int) -> (Int, Int, Int)? {
        guard let cg = image.cgImage,
              x >= 0, y >= 0, x < cg.width, y < cg.height,
              let data = cg.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return nil }
        let bytesPerPixel = max(cg.bitsPerPixel / 8, 1)
        let offset = y * cg.bytesPerRow + x * bytesPerPixel
        // Byte order is irrelevant here: the reference pixel is read with the
        // same layout, so a channel-order difference cancels out.
        guard bytesPerPixel >= 3 else { return nil }
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }
}

private extension UIImage {
    var pixelHeight: Int { cgImage?.height ?? Int(size.height) }
}
