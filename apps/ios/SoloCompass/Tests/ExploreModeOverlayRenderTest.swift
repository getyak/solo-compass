import XCTest
import SwiftUI
import CoreLocation
@testable import SoloCompass

/// Visual smoke test for the Explore-Mode overlay: render three
/// representative states to PNGs in /tmp, then assert (a) the write
/// actually happened and (b) the image has enough non-background pixels
/// somewhere in the frame to have "drawn something". Pixel diffing
/// lives out-of-band — the dev opens /tmp/exploreOverlay_*.png to
/// eye-check the render.
///
/// Why not a strict pixel-count assertion? `regularMaterial` and other
/// blur styles are frequently rasterized to fully-transparent in an
/// offscreen UIHostingController, so a "count non-background pixels in a
/// sparse grid" heuristic would false-alarm on real, working overlays.
/// We validate two invariants instead: the PNG file exists on disk and
/// its byte size is well above the "blank canvas" floor.
///
/// Companion to `ExploreSessionStateTests` (pure-derivation) and the
/// device rubric step (real motion + material blur + typography sizes).
final class ExploreModeOverlayRenderTest: XCTestCase {

    /// Empirically a solid-color 402×874 PNG is ~2–8 KB. Anything above
    /// this floor implies non-uniform content (the pill, text, or FAB
    /// rendered SOMETHING). Below → the render dropped everything.
    private static let minSensibleBytes = 12_000

    static let size = CGSize(width: 402, height: 874)   // iPhone 15 Pro

    func testScanningStateRendersNonBlank() throws {
        let img = try render(overlay(
            phase: .scanning,
            radiusMeters: 3000,
            city: "Futian",
            added: 7, verified: 3
        ))
        try assertNonTrivialPNG(img, name: "exploreOverlay_scanning")
    }

    func testSynthesizingStateRendersNonBlank() throws {
        let img = try render(overlay(
            phase: .synthesizing,
            radiusMeters: 6000,
            city: "深圳",
            added: 12, verified: 5
        ))
        try assertNonTrivialPNG(img, name: "exploreOverlay_synthesizing")
    }

    func testWideningStateRendersNonBlank() throws {
        let img = try render(overlay(
            phase: .widening,
            radiusMeters: 25_000,
            city: nil,
            added: 0, verified: 0
        ))
        try assertNonTrivialPNG(img, name: "exploreOverlay_widening")
    }

    func testHandoffCardRendersNonBlank() throws {
        let card = ExploreHandoffCard(
            result: .init(
                addedCount: 7, verifiedCount: 3, finalRadiusKm: 3,
                cityName: "Futian", addedIds: [], canExpand: true
            ),
            onAskSolo: {}, onSaveWalk: {}, onExpand: {}, onClear: {}, onDismiss: {}
        )
        let img = try render(
            ZStack {
                Color(red: 0.18, green: 0.32, blue: 0.28).ignoresSafeArea()
                card
            }
        )
        try assertNonTrivialPNG(img, name: "exploreOverlay_handoff")
    }

    // MARK: - Helpers

    private func overlay(
        phase: ExploreSession.Phase,
        radiusMeters: Double,
        city: String?,
        added: Int,
        verified: Int
    ) -> some View {
        ZStack {
            Color(red: 0.18, green: 0.32, blue: 0.28).ignoresSafeArea()
            ExploreModeOverlay(
                session: ExploreSession(state: .active(
                    phase: phase,
                    radiusMeters: radiusMeters,
                    anchor: CLLocationCoordinate2D(latitude: 22.5, longitude: 114.0),
                    addedCount: added,
                    verifiedCount: verified
                )),
                cityDisplayName: city,
                onCancel: {}
            )
        }
    }

    private func dump(_ image: UIImage, to name: String) {
        guard let data = image.pngData() else { return }
        try? data.write(to: URL(fileURLWithPath: "/tmp/\(name).png"))
    }

    /// Write the PNG and assert its byte length crosses the "not a
    /// solid-color canvas" threshold. See `minSensibleBytes` for the
    /// rationale (material blurs mangle pixel-count heuristics).
    private func assertNonTrivialPNG(_ image: UIImage, name: String) throws {
        guard let data = image.pngData() else {
            XCTFail("PNG encoding failed for \(name)")
            return
        }
        let url = URL(fileURLWithPath: "/tmp/\(name).png")
        try data.write(to: url)
        XCTAssertTrue(
            data.count >= Self.minSensibleBytes,
            "PNG \(name) is only \(data.count) B — likely a blank canvas"
        )
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

}
