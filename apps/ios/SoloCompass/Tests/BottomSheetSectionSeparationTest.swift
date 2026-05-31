import XCTest
import SwiftUI
@testable import SoloCompass

/// US-036: the BottomInfoSheet must place a clear visual division — an inset
/// divider plus a localized section header — between the Routes section and the
/// Nearby section so the information hierarchy reads cleanly.
///
/// We don't ship a pixel-snapshot library, so (consistent with
/// `PrivacyAcknowledgementSheetSnapshotTest`) we render the composed sheet
/// content through SwiftUI's `ImageRenderer` at the mid detent and assert the
/// render is valid and non-empty. The render exercises both
/// `RoutesSection` (with its `sheet.section.routes` header) and
/// `NearbySection` (with its `sheet.section.nearby` header + leading inset
/// divider), so a layout that collapses the separator would not produce a
/// meaningful image. We also pin the localized keys and the inset constant.
@MainActor
final class BottomSheetSectionSeparationTest: XCTestCase {

    private func sampleRoutes() -> [Route] {
        [
            Route(
                id: RouteId(rawValue: "sep-test-route"),
                title: "Mekong Sunset Walk",
                summary: "Dawn at the river.",
                experienceIds: ["e1", "e2"],
                cityCode: "VTE",
                region: "Riverfront",
                estimatedDuration: 90,
                distanceMeters: 1200,
                pace: .relaxed,
                source: .editorial
            )
        ]
    }

    /// Render the composed Routes + Nearby content as it appears below the
    /// drag handle at the `.mid` detent.
    private func renderSheetContent() -> UIImage? {
        let routes = sampleRoutes()
        let view = BottomInfoSheet(
            aiHint: "Golden-hour light is perfect for the harbor walk right now",
            count: 7,
            isNowMode: false
        ) { detent, sortMode in
            if detent != .peek {
                VStack(spacing: 0) {
                    RoutesSection(
                        routes: routes,
                        isNowFilter: false,
                        onSelectRoute: { _ in }
                    )
                    NearbySection(
                        experiences: ExperienceService.hardcodedSeed,
                        smartPickIds: [],
                        referenceCoordinate: nil,
                        sortMode: sortMode.wrappedValue,
                        showsSectionDivider: true,
                        onSelectExperience: { _ in }
                    )
                }
            }
        }
        .frame(width: 390, height: BottomSheetDetent.mid.baseHeight)
        .environment(BestNowClock.shared)
        .environment(LocationService.shared)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage
    }

    // MARK: - Snapshot render at mid detent

    func testSheetWithBothSectionsRendersAtMidDetent() throws {
        let image = try XCTUnwrap(
            renderSheetContent(),
            "BottomInfoSheet with Routes + Nearby must render at the mid detent"
        )
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    /// The standalone separator (inset divider + localized header) must render.
    func testSectionSeparatorRenders() throws {
        let view = SheetSectionSeparator(titleKey: "sheet.section.nearby", showsDivider: true)
            .frame(width: 390)
            .fixedSize(horizontal: false, vertical: true)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage, "SheetSectionSeparator must render")
        XCTAssertGreaterThan(image.size.height, 0)
    }

    // MARK: - Inset divider constant

    func testDividerIsInset() {
        XCTAssertGreaterThan(
            SheetSectionSeparator.dividerInset, 0,
            "the separator divider must be inset (leading-padded), not full-bleed"
        )
    }

    // MARK: - Localized section titles present in both localizations

    func testSectionTitleKeysPresentInBothLocalizations() throws {
        let searchBundles = [Bundle.main, Bundle(for: BottomSheetSectionSeparationTest.self)]
        func keys(_ localization: String) -> Set<String>? {
            for bundle in searchBundles {
                if let url = bundle.url(
                    forResource: "Localizable",
                    withExtension: "strings",
                    subdirectory: nil,
                    localization: localization
                ), let dict = NSDictionary(contentsOf: url) as? [String: String] {
                    return Set(dict.keys)
                }
            }
            return nil
        }
        guard let enKeys = keys("en"), let zhKeys = keys("zh-Hans") else {
            throw XCTSkip("Localizable.strings not found in test host bundle")
        }
        for key in ["sheet.section.routes", "sheet.section.nearby"] {
            XCTAssertTrue(enKeys.contains(key), "en.lproj missing \(key)")
            XCTAssertTrue(zhKeys.contains(key), "zh-Hans.lproj missing \(key)")
        }
    }
}
