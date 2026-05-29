import XCTest
import SwiftUI
@testable import SoloCompass

/// V-006 regression coverage: the top region of the map must render street/tile
/// content — not a flat dark band (the cold-launch "NORTH BEACH band").
///
/// Root cause (documented in the PR): `CompassMapView.mapZStack` used to apply
/// `.ignoresSafeArea(edges: [.bottom, .horizontal])` to the `Map`, so the map
/// stopped at the top safe-area inset. That status-bar-height strip then showed
/// the flat theme background (`Color(.systemBackground)` — near-black in dark
/// mode), reading as a dark band above the streets. The fix lets the `Map`
/// ignore *all* safe-area edges so real tiles fill the top region; the overlay
/// content stays a sibling layer that keeps its own safe-area inset.
///
/// We can't drive MapKit's async tile server in a unit-test process, so we don't
/// assert specific street pixels. Instead we:
///   1. Snapshot the top 200pt of the installed view graph at ~T+5s and assert
///      the captured region is NOT a single uniform flat color band (which is
///      exactly what the regression produced). MapKit fills the map area with a
///      non-uniform base render (graticule / land-water shading) even before
///      network tiles arrive, so a passing fix yields varied pixels there.
///   2. Independently validate the uniformity detector against a synthetic flat
///      band so the assertion in (1) can never silently pass on an empty buffer.
@MainActor
final class MapTopOverlayRenderTest: XCTestCase {

    /// Logical size of an iPhone 17 Pro portrait window.
    private static let windowSize = CGSize(width: 402, height: 874)
    /// The top slice we inspect, per the acceptance criteria.
    private static let topRegionHeight: CGFloat = 200

    // MARK: - Real view graph

    /// Installs `CompassMapView` in a real window, pumps the run loop to ~T+5s
    /// so the map has time to lay out and render its base content, snapshots the
    /// top 200pt, and asserts the slice is not a flat uniform color band.
    func testMapTopRegionIsNotFlatBand() throws {
        let view = CompassMapView()
            .environment(LocationService())
            .environment(ExperienceService())
            .environment(AIService())
            .environment(UserPreferences())
            .environment(NotificationService.shared)
            .environment(SubscriptionService())
            .environment(CompanionService())
            .environment(PresenceService())

        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: Self.windowSize))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        // Acceptance criterion: snapshot at T+5s so the map has rendered.
        RunLoop.main.run(until: Date().addingTimeInterval(5.0))

        let topRect = CGRect(
            x: 0,
            y: 0,
            width: Self.windowSize.width,
            height: Self.topRegionHeight
        )
        let slice = try snapshot(host.view, region: topRect)

        // The slice must not be a single uniform flat color. A uniform slice is
        // the regression signature (theme background band). The fix puts the
        // map's non-uniform base render in this region.
        XCTAssertFalse(
            isUniformColor(slice),
            "Top 200pt of the map rendered as a flat uniform color band — the "
                + "map is not filling the top safe area (V-006 regression)."
        )
    }

    // MARK: - Detector self-check

    /// A deliberately flat band must be detected as uniform. This guards the
    /// detector so the real-view assertion can never pass on a degenerate
    /// (empty / all-one-color) buffer by accident.
    func testUniformDetectorFlagsFlatBand() throws {
        let band = Color(.systemBackground)
        let view = band
            .frame(width: Self.windowSize.width, height: Self.topRegionHeight)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage, "flat band must render")
        XCTAssertTrue(
            isUniformColor(image),
            "A solid color fill must be detected as a uniform band"
        )
    }

    /// A varied gradient must NOT be flagged as uniform — proves the detector
    /// reports non-uniform content for real (street-like) variation.
    func testUniformDetectorPassesVariedContent() throws {
        let view = LinearGradient(
            colors: [.black, .white],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: Self.windowSize.width, height: Self.topRegionHeight)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage, "gradient must render")
        XCTAssertFalse(
            isUniformColor(image),
            "A gradient has clearly varied pixels and must not be flagged uniform"
        )
    }

    // MARK: - Helpers

    /// Renders `view` into an image and crops it to `region` (points).
    private func snapshot(_ view: UIView, region: CGRect) throws -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(bounds: region, format: format)
        let image = renderer.image { _ in
            // afterScreenUpdates ensures MapKit's drawn layer is captured.
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        return image
    }

    /// True when every sampled pixel is (near) identical — i.e. a flat color
    /// band. Samples a grid across the image and compares each sample to the
    /// first; any channel differing by more than a small tolerance means the
    /// content is non-uniform.
    private func isUniformColor(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else {
            // No backing bitmap → treat as uniform so the real-view test fails
            // loudly rather than passing on an empty buffer.
            return true
        }
        let width = cg.width
        let height = cg.height
        guard width > 0, height > 0 else { return true }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return true
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        func sample(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
            let i = y * bytesPerRow + x * bytesPerPixel
            return (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
        }

        let steps = 16
        let first = sample(0, 0)
        let tolerance: Int = 6
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
