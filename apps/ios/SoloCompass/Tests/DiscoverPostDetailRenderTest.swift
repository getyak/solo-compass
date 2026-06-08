import XCTest
import SwiftUI
@testable import SoloCompass

/// US-016 render coverage: the `DiscoverPostDetailView` is the dedicated
/// [Add Friend] entry point reached from a Discover post. It renders the post,
/// a note field (capped at 120 chars), and a prominent Add Friend button.
///
/// We install it in a real full-page window and dump a PNG to /tmp for the
/// "verify in Simulator" inspection step, asserting it laid out (non-uniform).
@MainActor
final class DiscoverPostDetailRenderTest: XCTestCase {

    private static let size = CGSize(width: 402, height: 874)

    private static func post(reporterWeight: Double = 0.9) -> DiscoverPost {
        DiscoverPost(
            id: "post_render",
            handle: "🦊",
            blurb: "Hiking the old town this weekend — looking for a walking buddy.",
            categories: ["hiking", "coffee"],
            cityCode: "TYO",
            mode: "city",
            activeFrom: "2026-06-10",
            activeTo: "2026-06-14",
            reporterWeight: reporterWeight
        )
    }

    // MARK: - Gate wiring (the detail's reporterWeight feeds the gate)

    func testHighTrustPostPassesGate() {
        let gate = DiscoverFriendGate()
        XCTAssertNil(gate.evaluate(reporterWeight: 0.9, recentAddTimestamps: []))
    }

    func testLowTrustPostFailsGate() {
        let gate = DiscoverFriendGate()
        XCTAssertEqual(
            gate.evaluate(reporterWeight: 0.2, recentAddTimestamps: []),
            .lowReporterWeight
        )
    }

    // MARK: - Render

    func testRendersDetail() throws {
        let image = try render(DiscoverPostDetailView(post: Self.post(), service: FriendService()))
        dump(image, to: "discover_post_detail")
        XCTAssertFalse(isUniformColor(image), "Detail rendered as a flat band.")
    }

    // MARK: - Helpers

    private func dump(_ image: UIImage, to name: String) {
        guard let data = image.pngData() else { return }
        try? data.write(to: URL(fileURLWithPath: "/tmp/\(name).png"))
    }

    private func render<Content: View>(_ content: Content) throws -> UIImage {
        let host = UIHostingController(rootView: content)
        let window = UIWindow(frame: CGRect(origin: .zero, size: Self.size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        let bounds = CGRect(origin: .zero, size: Self.size)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        return renderer.image { _ in
            host.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
    }

    private func isUniformColor(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return true }
        let width = cg.width, height = cg.height
        guard width > 0, height > 0 else { return true }
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return true }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        func sample(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
            let i = y * bytesPerRow + x * bytesPerPixel
            return (pixels[i], pixels[i + 1], pixels[i + 2])
        }
        let steps = 16
        let first = sample(0, 0)
        let tolerance = 6
        for sy in 0..<steps {
            for sx in 0..<steps {
                let x = min(width - 1, sx * width / steps)
                let y = min(height - 1, sy * height / steps)
                let p = sample(x, y)
                if abs(Int(p.0) - Int(first.0)) > tolerance
                    || abs(Int(p.1) - Int(first.1)) > tolerance
                    || abs(Int(p.2) - Int(first.2)) > tolerance {
                    return false
                }
            }
        }
        return true
    }
}
