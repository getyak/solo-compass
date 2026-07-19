import XCTest
import SwiftUI
@testable import SoloCompass

/// US-029: at large Dynamic Type sizes (up to AX5) the `BottomInfoSheet` detent
/// heights (peek / mid / full) must scale so the enlarged content — handle,
/// AI-hint row, sort/count toolbar, nearby list — is not clipped.
///
/// The base detents (240 / 500 / 800 pt) are sized for the default content size
/// category. `BottomSheetDetent.scaledHeight(for:)` multiplies them by
/// `UIFontMetrics.default.scaledValue(for: 1.0)` for the active trait
/// collection. This test asserts:
///   1. each detent grows at AX5 vs. the default size, and
///   2. the sheet renders at all three detents at AX5 (no zero-height clip),
/// mirroring the `ImageRenderer` approach used by other snapshot tests in this
/// target (we ship no third-party pixel-diff library).
@MainActor
final class BottomSheetDetentDynamicTypeTest: XCTestCase {

    // MARK: - Trait collections

    private var defaultTraits: UITraitCollection {
        UITraitCollection(preferredContentSizeCategory: .large)
    }

    private var ax5Traits: UITraitCollection {
        UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
    }

    // MARK: - Scale factor

    func testScaleFactorIsOneAtDefaultSize() {
        XCTAssertEqual(
            BottomSheetDetentScale.factor(for: defaultTraits),
            1.0,
            accuracy: 0.0001,
            "At the default content size category the detent scale factor must be 1.0"
        )
    }

    func testScaleFactorGrowsAtAX5() {
        let factor = BottomSheetDetentScale.factor(for: ax5Traits)
        XCTAssertGreaterThan(
            factor, 1.0,
            "At AX5 the detent scale factor must exceed 1.0 so heights grow; got \(factor)"
        )
    }

    func testScaleFactorNeverShrinksBelowOne() {
        let xs = UITraitCollection(preferredContentSizeCategory: .extraSmall)
        XCTAssertGreaterThanOrEqual(
            BottomSheetDetentScale.factor(for: xs), 1.0,
            "Detents must never shrink below their base height, even at the smallest text size"
        )
    }

    // MARK: - Detent heights scale

    func testAllThreeDetentsGrowAtAX5() {
        for detent in BottomSheetDetent.allCases {
            let base = detent.scaledHeight(for: defaultTraits)
            let ax5 = detent.scaledHeight(for: ax5Traits)
            XCTAssertGreaterThan(
                ax5, base,
                "\(detent) detent must be taller at AX5 (\(ax5)) than at the default size (\(base))"
            )
        }
    }

    func testBaseDetentHeightsMatchSpec() {
        // The base (unscaled) ladder is 272 / 500 / 800. Peek grew 170 → 240 (to
        // fit the "best for right now" summary card) → 272 (north-star peek card
        // gained its NowScore line + confidence-facts + 带我去/换一个 action row).
        // This spec test tracks the current peek height so the ladder stays pinned
        // to intent; keep it in step with `basePeekHeight` in BottomInfoSheet.
        XCTAssertEqual(BottomSheetDetent.peek.scaledHeight(for: defaultTraits), 272, accuracy: 0.5)
        XCTAssertEqual(BottomSheetDetent.mid.scaledHeight(for: defaultTraits), 500, accuracy: 0.5)
        XCTAssertEqual(BottomSheetDetent.full.scaledHeight(for: defaultTraits), 800, accuracy: 0.5)
    }

    func testDetentLadderOrderingPreservedAtAX5() {
        let peek = BottomSheetDetent.peek.scaledHeight(for: ax5Traits)
        let mid = BottomSheetDetent.mid.scaledHeight(for: ax5Traits)
        let full = BottomSheetDetent.full.scaledHeight(for: ax5Traits)
        XCTAssertLessThan(peek, mid, "peek < mid must hold after scaling")
        XCTAssertLessThan(mid, full, "mid < full must hold after scaling")
    }

    // MARK: - Snapshot render (no clipping → valid, non-zero image)

    /// Render the full sheet content at a given detent and Dynamic Type size.
    /// A clipped / zero-height layout would produce a degenerate image; a valid
    /// non-empty render at each detent is the no-clip guard, consistent with
    /// `PrivacyAcknowledgementSheetSnapshotTest`.
    private func render(detent: BottomSheetDetent, size: DynamicTypeSize) -> UIImage? {
        let view = BottomInfoSheet(
            aiHint: "Golden-hour light is perfect for the harbor walk right now",
            count: 7,
            isNowMode: false
        ) { activeDetent, sortMode in
            if activeDetent != .peek {
                NearbySection(
                    experiences: ExperienceService.hardcodedSeed,
                    smartPickIds: [],
                    referenceCoordinate: nil,
                    sortMode: sortMode.wrappedValue,
                    onSelectExperience: { _ in }
                )
            }
        }
        .frame(width: 390, height: detent.scaledHeight(for: UITraitCollection(preferredContentSizeCategory: size.uiContentSizeCategory)))
        .dynamicTypeSize(size)
        .environment(BestNowClock.shared)
        .environment(LocationService.shared)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage
    }

    func testSheetRendersAtAllDetentsAtAX5() throws {
        for detent in BottomSheetDetent.allCases {
            let image = try XCTUnwrap(
                render(detent: detent, size: .accessibility5),
                "BottomInfoSheet must render at \(detent) detent at AX5"
            )
            XCTAssertGreaterThan(image.size.width, 0, "\(detent) render width must be > 0")
            XCTAssertGreaterThan(image.size.height, 0, "\(detent) render height must be > 0 (no clip-to-zero)")
        }
    }

    /// At AX5 the rendered sheet at the `full` detent must be meaningfully taller
    /// than at the default size — proving the detent (and thus its content area)
    /// scaled up rather than clamping content into the base height.
    func testFullDetentRenderTallerAtAX5ThanDefault() throws {
        let base = try XCTUnwrap(render(detent: .full, size: .large))
        let ax5 = try XCTUnwrap(render(detent: .full, size: .accessibility5))
        XCTAssertGreaterThan(
            ax5.size.height,
            base.size.height,
            "Full detent at AX5 must render taller than at the default size"
        )
    }
}
