import XCTest
import SwiftUI
import SwiftData
@testable import SoloCompass

/// Visual snapshot tests for the Archive tab (P1.4 #192).
///
/// Per the project's iOS visual-verify pattern (memory
/// `project_ios_visual_verify`), we render the view through SwiftUI's
/// `ImageRenderer` and dump the PNG to /tmp so a human can eyeball it.
/// The asserts here only guard that we *can* render — non-zero PNG bytes —
/// because pixel-perfect snapshot diffing would be flaky across iOS / Xcode
/// upgrades on this surface. The PNGs are the actual artifact.
@MainActor
final class ArchiveSnapshotTests: XCTestCase {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration("ArchiveSnapshot", isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: VisitRecord.self, ExperienceRecord.self,
            configurations: config
        )
    }

    private func seedExperience(
        in container: ModelContainer,
        id: String,
        title: String,
        cityCode: String
    ) throws {
        let ctx = ModelContext(container)
        ctx.insert(ExperienceRecord(
            id: id,
            title: title,
            oneLiner: "",
            whyItMatters: "",
            category: "cafe",
            longitude: 100.5,
            latitude: 13.7,
            cityCode: cityCode,
            addressHint: nil,
            placeNameLocal: nil,
            placeNameRomanized: nil,
            durationMin: 30,
            durationMax: 90,
            status: "active",
            createdAt: Date(),
            updatedAt: Date(),
            bestTimesBlob: Data(),
            howToBlob: Data(),
            realInconveniencesBlob: Data(),
            sourcesBlob: Data(),
            soloScoreBlob: Data(),
            confidenceBlob: Data(),
            statsBlob: Data(),
            nearbyExperienceIdsBlob: Data()
        ))
        try ctx.save()
    }

    private func seedVisit(
        in container: ModelContainer,
        experienceId: String,
        visitedAt: Date,
        dwellSeconds: Int = 1_800
    ) throws {
        let ctx = ModelContext(container)
        ctx.insert(VisitRecord(
            experienceId: experienceId,
            visitedAt: visitedAt,
            dwellSeconds: dwellSeconds
        ))
        try ctx.save()
    }

    private func renderPNG(_ view: some View, named: String) throws -> Data {
        let renderer = ImageRenderer(content:
            view
                .frame(width: 402, height: 874) // iPhone 17 Pro logical
                .background(Color.white)
        )
        renderer.scale = 2
        let uiImage = try XCTUnwrap(renderer.uiImage, "ImageRenderer must produce a UIImage")
        let png = try XCTUnwrap(uiImage.pngData(), "UIImage must encode to PNG bytes")
        let path = "/tmp/archive_snapshot_\(named).png"
        try png.write(to: URL(fileURLWithPath: path))
        return png
    }

    // MARK: - Populated state

    func testPopulatedArchiveSnapshot() throws {
        let container = try makeContainer()
        try seedExperience(in: container, id: "exp_snap_bkk_1", title: "Rama Café", cityCode: "BKK")
        try seedExperience(in: container, id: "exp_snap_bkk_2", title: "River Books", cityCode: "BKK")
        try seedExperience(in: container, id: "exp_snap_kyo_1", title: "Kamogawa Bench", cityCode: "KYO")

        let base = Date(timeIntervalSince1970: 1_780_000_000)
        try seedVisit(in: container, experienceId: "exp_snap_bkk_1", visitedAt: base)
        try seedVisit(in: container, experienceId: "exp_snap_bkk_2", visitedAt: base.addingTimeInterval(-3_600))
        try seedVisit(in: container, experienceId: "exp_snap_kyo_1", visitedAt: base.addingTimeInterval(-86_400))

        let view = NavigationStack {
            ArchiveView(modelContainer: container, activeCityCode: "BKK")
        }

        let png = try renderPNG(view, named: "populated")
        XCTAssertGreaterThan(png.count, 1_000, "rendered Archive PNG must be a substantial image, not an empty render")
    }

    // MARK: - Empty state

    func testEmptyArchiveSnapshot() throws {
        let container = try makeContainer()
        let view = NavigationStack {
            ArchiveView(modelContainer: container)
        }

        let png = try renderPNG(view, named: "empty")
        XCTAssertGreaterThan(png.count, 1_000, "empty-state PNG must still render the placeholder hero")
    }
}
