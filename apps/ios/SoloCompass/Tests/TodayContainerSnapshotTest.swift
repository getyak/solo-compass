import XCTest
import SwiftUI
@testable import SoloCompass

/// B1-a visual smoke: render the Today home scaffold's placeholder content to a
/// PNG so the shell can be eyeballed without fighting the simulator's cold-start
/// location alert. Writes to /tmp; DEBUG-only, asserts nothing about pixels.
@MainActor
final class TodayContainerSnapshotTest: XCTestCase {

    func testRenderTodayScaffoldPlaceholder() throws {
        // Render only the Today-home placeholder surface (no map layer, no
        // environment) — that's the B1-a deliverable to inspect.
        let view = VStack(spacing: 20) {
            Spacer(minLength: 32)
            VStack(spacing: 8) {
                Text("Today")
                    .ctDisplay(34, .bold, relativeTo: .largeTitle)
                    .foregroundStyle(CT.textPrimaryAdaptive)
                Text(NSLocalizedString("today.scaffold.placeholder", comment: ""))
                    .ctBody(15)
                    .foregroundStyle(CT.textMutedAdaptive)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Spacer()
        }
        .frame(width: 402, height: 874)
        .background(CT.pageAdaptive)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let uiImage = renderer.uiImage,
              let data = uiImage.pngData() else {
            throw XCTSkip("ImageRenderer produced no image")
        }
        let url = URL(fileURLWithPath: "/tmp/today_scaffold.png")
        try data.write(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
