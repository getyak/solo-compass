import XCTest
import SwiftUI
@testable import SoloCompass

/// Visual verification for the aesthetic-audit remediation. Renders the new
/// warm-amber surfaces (SoloEmptyState, skeleton) in BOTH light and dark and
/// dumps PNGs to /tmp for eyeballing, then asserts the dark render is actually
/// dark — the whole point of the color-01 / skeleton-01 fixes was that these
/// surfaces stop being a light-locked white page in dark mode.
@MainActor
final class DesignSystemVisualTest: XCTestCase {
    private static let windowSize = CGSize(width: 390, height: 700)

    func testSoloEmptyStateLightAndDark() throws {
        let view = SoloEmptyState(
            systemImage: "figure.walk",
            title: "No saved places yet",
            message: "The places you save gather here for your next wander.",
            actionTitle: "Explore the map",
            action: {}
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CT.pageAdaptive)

        let light = try render(view, scheme: .light)
        let dark = try render(view, scheme: .dark)
        dump(light, "solo_empty_light")
        dump(dark, "solo_empty_dark")

        // The dark render's average luminance must be clearly dark; a regressed
        // light-locked page would come back bright.
        let darkLum = averageLuminance(dark)
        XCTAssertLessThan(darkLum, 0.30, "SoloEmptyState dark render should be dark, got luminance \(darkLum)")
        let lightLum = averageLuminance(light)
        XCTAssertGreaterThan(lightLum, 0.80, "SoloEmptyState light render should be warm-bright, got \(lightLum)")
    }

    func testSkeletonWarmInLightAndDark() throws {
        let view = CompanionSkeletonList(rows: 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CT.pageAdaptive)

        let light = try render(view, scheme: .light)
        let dark = try render(view, scheme: .dark)
        dump(light, "skeleton_light")
        dump(dark, "skeleton_dark")

        XCTAssertLessThan(averageLuminance(dark), 0.35, "Skeleton dark render should be warm-charcoal, not gray-bright")
    }

    // MARK: - Helpers

    private func render<Content: View>(_ content: Content, scheme: ColorScheme) throws -> UIImage {
        let host = UIHostingController(rootView: content.environment(\.colorScheme, scheme))
        host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        let window = UIWindow(frame: CGRect(origin: .zero, size: Self.windowSize))
        window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))

        let bounds = CGRect(origin: .zero, size: Self.windowSize)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        return renderer.image { _ in
            host.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
    }

    private func dump(_ image: UIImage, _ name: String) {
        if let data = image.pngData() {
            try? data.write(to: URL(fileURLWithPath: "/tmp/\(name).png"))
        }
    }

    /// Mean perceptual luminance (0…1) sampled across the image.
    private func averageLuminance(_ image: UIImage) -> Double {
        guard let cg = image.cgImage else { return 1 }
        let width = cg.width, height = cg.height
        guard width > 0, height > 0 else { return 1 }
        let bpp = 4, bpr = width * bpp
        var px = [UInt8](repeating: 0, count: height * bpr)
        guard let ctx = CGContext(
            data: &px, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 1 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        var sum = 0.0
        var count = 0
        // Sample every 16th pixel — plenty for an average.
        for y in stride(from: 0, to: height, by: 16) {
            for x in stride(from: 0, to: width, by: 16) {
                let i = y * bpr + x * bpp
                let r = Double(px[i]) / 255, g = Double(px[i + 1]) / 255, b = Double(px[i + 2]) / 255
                sum += 0.2126 * r + 0.7152 * g + 0.0722 * b
                count += 1
            }
        }
        return count > 0 ? sum / Double(count) : 1
    }
}
