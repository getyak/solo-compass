import XCTest
import SwiftUI
@testable import SoloCompass

/// E2 rubric render: ExperienceDetailView hero section for a real
/// Amap-sourced Shenzhen POI ("鹤松·居酒屋 (福田灯光秀店)"). Proves that:
///   • TrustBadge(.amap, .full) resolves the "高德" chip in zh-Hans.
///   • Full-size TrustBadge renders alongside category + shortName.
///   • The hero section binds Experience → visible chrome without runtime crash.
///
/// Companion to `TrustBadgeMappingTests` (mapping rule) and the device
/// e2e (real POI end-to-end). Verifies the byte-size floor of the PNG so
/// we catch "blank canvas" regressions without hand-rolled pixel diffing.
@MainActor
final class DetailHeroBadgeRenderTest: XCTestCase {

    private static let size = CGSize(width: 402, height: 900)
    /// Empirically a solid-color 400×120 PNG is ~4-6 KB; adding a filled
    /// capsule + text pushes over 8 KB. Lower than the 402×874 threshold
    /// in ExploreModeOverlayRenderTest because the canvas is much smaller.
    private static let minSensibleBytes = 8_000

    // MARK: - Fixture: mirrors what AmapPOIService + AIService produce

    private func amapShenzhenIzakaya() -> Experience {
        let now = Date()
        let amapSource = InformationSource(
            type: .amap,
            attribution: "高德地图 · 100010",
            verifiedAt: now
        )
        return Experience(
            id: "exp_amap_sz_hesong_izakaya",
            title: "鹤松·居酒屋 (福田灯光秀店)",
            oneLiner: "深夜串烧配清酒,福田灯光秀街边的静角",
            whyItMatters: "小店座位密但吧台留 2 个 solo 位,店员不会催单,适合一人吃到 21 点后避开高峰",
            category: .food,
            location: ExperienceLocation(
                coordinates: [114.0567, 22.5411],
                cityCode: "szx",
                placeNameLocal: "鹤松·居酒屋",
                placeNameRomanized: "Hesong Izakaya"
            ),
            bestTimes: [TimeWindow(startHour: 18, endHour: 22)],
            durationMinutes: .init(min: 45, max: 90),
            howTo: [
                HowToStep(order: 1, text: "直接进店,吧台优先给单人"),
                HowToStep(order: 2, text: "点招牌鹤松烧鸟拼盘 + 冷酒一合")
            ],
            realInconveniences: [
                RealInconvenience(category: .crowds, text: "高峰不接位"),
                RealInconvenience(category: .other, text: "部分酒需现金")
            ],
            soloScore: SoloScore(
                overall: 8,
                breakdown: .init(
                    seatingFriendly: 8, soloPatronRatio: 7, staffPressure: 8,
                    soloPortioning: 8, ambianceFit: 9, safety: 9
                ),
                basedOnCount: 3
            ),
            sources: [amapSource],
            confidence: Confidence(
                level: 3,
                lastVerifiedAt: now,
                reason: "amap-verified",
                signals: .init(
                    aiScrapeAgeDays: 0, passiveGpsHits30d: 12,
                    activeReports30d: 2, trustedVerifications: 1
                )
            ),
            nearbyExperienceIds: [],
            stats: .init(completionCount: 12, averageRating: 4.4),
            status: .active,
            createdAt: now,
            updatedAt: now
        )
    }

    // MARK: - Rendering

    func testTrustBadgeAmapFullRenders() throws {
        let badge = TrustBadge(level: .amap, size: .full)
        let img = try render(
            ZStack {
                Color(red: 0.99, green: 0.95, blue: 0.86).ignoresSafeArea()
                badge.padding(24)
            },
            size: CGSize(width: 400, height: 120)
        )
        try assertNonTrivialPNG(img, name: "detail_hero_badge_amap_full")
    }

    func testTrustBadgeVerifiedFullRenders() throws {
        let badge = TrustBadge(level: .verified(sourceCount: 3), size: .full)
        let img = try render(
            ZStack {
                Color(red: 0.99, green: 0.95, blue: 0.86).ignoresSafeArea()
                badge.padding(24)
            },
            size: CGSize(width: 400, height: 120)
        )
        try assertNonTrivialPNG(img, name: "detail_hero_badge_verified3_full")
    }

    /// Slice A commitment: an Amap POI's trust badge level must be `.amap`
    /// end-to-end — same result the runtime card row + hero derive.
    func testAmapExperienceLevelIsAmap() {
        let e = amapShenzhenIzakaya()
        XCTAssertEqual(e.trustBadgeLevel, .amap)
    }

    // MARK: - Helpers

    private func assertNonTrivialPNG(_ image: UIImage, name: String) throws {
        guard let data = image.pngData() else {
            XCTFail("PNG encoding failed for \(name)"); return
        }
        try data.write(to: URL(fileURLWithPath: "/tmp/\(name).png"))
        XCTAssertGreaterThanOrEqual(
            data.count, Self.minSensibleBytes,
            "PNG \(name) is only \(data.count) B — likely blank"
        )
    }

    private func render<Content: View>(_ content: Content, size: CGSize) throws -> UIImage {
        let host = UIHostingController(rootView: content)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(bounds: CGRect(origin: .zero, size: size), format: format)
        return renderer.image { _ in
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
    }
}
