import XCTest
import SwiftData
@testable import SoloCompass

/// Tests for `ArchiveViewModel` (P1.1 #113).
///
/// Each test rebuilds an in-memory ModelContainer with the two tables the
/// view model joins: `VisitRecord` + `ExperienceRecord`. Setup helpers
/// keep visit-creation noise out of the test bodies.
@MainActor
final class ArchiveViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration("ArchiveVMTests", isStoredInMemoryOnly: true)
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
        let rec = ExperienceRecord(
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
        )
        ctx.insert(rec)
        try ctx.save()
    }

    private func seedVisit(
        in container: ModelContainer,
        experienceId: String,
        visitedAt: Date,
        dwellSeconds: Int = 600
    ) throws {
        let ctx = ModelContext(container)
        let v = VisitRecord(
            experienceId: experienceId,
            visitedAt: visitedAt,
            dwellSeconds: dwellSeconds
        )
        ctx.insert(v)
        try ctx.save()
    }

    // MARK: - Empty state

    func testRefreshOnEmptyStoreYieldsEmptyState() throws {
        let container = try makeContainer()
        let vm = ArchiveViewModel(modelContainer: container)

        vm.refresh()

        XCTAssertTrue(vm.isEmpty)
        XCTAssertEqual(vm.groups.count, 0)
        XCTAssertNil(vm.currentTrip)
        XCTAssertEqual(vm.totalVisitCount, 0)
    }

    // MARK: - City grouping

    func testVisitsAreGroupedByCity() throws {
        let container = try makeContainer()
        try seedExperience(in: container, id: "exp_arch_bkk_a", title: "Rama Café", cityCode: "BKK")
        try seedExperience(in: container, id: "exp_arch_bkk_b", title: "River Books", cityCode: "BKK")
        try seedExperience(in: container, id: "exp_arch_kyo_a", title: "Kamogawa Bench", cityCode: "KYO")

        let now = Date()
        try seedVisit(in: container, experienceId: "exp_arch_bkk_a", visitedAt: now)
        try seedVisit(in: container, experienceId: "exp_arch_bkk_b", visitedAt: now.addingTimeInterval(-3600))
        try seedVisit(in: container, experienceId: "exp_arch_kyo_a", visitedAt: now.addingTimeInterval(-86_400))

        let vm = ArchiveViewModel(modelContainer: container)
        vm.refresh()

        XCTAssertFalse(vm.isEmpty)
        XCTAssertEqual(vm.groups.count, 2, "two distinct cityCodes must produce two groups")

        let bkk = vm.groups.first { $0.cityCode == "BKK" }
        let kyo = vm.groups.first { $0.cityCode == "KYO" }
        XCTAssertEqual(bkk?.visits.count, 2)
        XCTAssertEqual(kyo?.visits.count, 1)
    }

    // MARK: - Multi-visit dedup

    func testSameExperienceRevisitsCountAsOneDistinctPlace() throws {
        let container = try makeContainer()
        try seedExperience(in: container, id: "exp_arch_revisit", title: "Daily Bench", cityCode: "BKK")

        let now = Date()
        try seedVisit(in: container, experienceId: "exp_arch_revisit", visitedAt: now)
        try seedVisit(in: container, experienceId: "exp_arch_revisit", visitedAt: now.addingTimeInterval(-86_400))
        try seedVisit(in: container, experienceId: "exp_arch_revisit", visitedAt: now.addingTimeInterval(-2 * 86_400))

        let vm = ArchiveViewModel(modelContainer: container, activeCityCode: "BKK")
        vm.refresh()

        XCTAssertEqual(vm.totalVisitCount, 3, "raw visit count keeps every visit")
        let bkk = vm.groups.first { $0.cityCode == "BKK" }
        XCTAssertEqual(bkk?.visits.count, 3, "the group shows every visit row")
        XCTAssertEqual(bkk?.distinctExperienceCount, 1, "distinct places collapses revisits")
        XCTAssertEqual(vm.currentTrip?.distinctExperienceCount, 1)
    }

    // MARK: - Trip summary

    func testCurrentTripPicksTheMostRecentCityByDefault() throws {
        let container = try makeContainer()
        try seedExperience(in: container, id: "exp_arch_old", title: "Stale", cityCode: "OSA")
        try seedExperience(in: container, id: "exp_arch_new", title: "Fresh", cityCode: "TYO")

        let now = Date()
        try seedVisit(in: container, experienceId: "exp_arch_old", visitedAt: now.addingTimeInterval(-7 * 86_400))
        try seedVisit(in: container, experienceId: "exp_arch_new", visitedAt: now)

        let vm = ArchiveViewModel(modelContainer: container)
        vm.refresh()

        XCTAssertEqual(vm.currentTrip?.cityCode, "TYO")
        XCTAssertEqual(vm.currentTrip?.distinctExperienceCount, 1)
    }

    func testActiveCityCodeOverridesMostRecentDefault() throws {
        let container = try makeContainer()
        try seedExperience(in: container, id: "exp_arch_old", title: "Stale", cityCode: "OSA")
        try seedExperience(in: container, id: "exp_arch_new", title: "Fresh", cityCode: "TYO")

        let now = Date()
        try seedVisit(in: container, experienceId: "exp_arch_old", visitedAt: now.addingTimeInterval(-7 * 86_400))
        try seedVisit(in: container, experienceId: "exp_arch_new", visitedAt: now)

        let vm = ArchiveViewModel(modelContainer: container, activeCityCode: "OSA")
        vm.refresh()

        XCTAssertEqual(vm.currentTrip?.cityCode, "OSA", "explicit active city wins over most-recent default")
    }

    /// Build a Date anchored in the *current* calendar's time zone so the
    /// dayCount math (which uses `Calendar.current.startOfDay`) is hermetic
    /// regardless of the test runner's locale.
    private func localDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.timeZone = Calendar.current.timeZone
        return Calendar.current.date(from: components)!
    }

    func testTripDayCountSpansFirstToLastInclusive() throws {
        let container = try makeContainer()
        try seedExperience(in: container, id: "exp_arch_d", title: "Bench", cityCode: "BKK")

        let day1 = localDate(year: 2026, month: 6, day: 1, hour: 9)
        let day3 = localDate(year: 2026, month: 6, day: 3, hour: 18)
        try seedVisit(in: container, experienceId: "exp_arch_d", visitedAt: day1)
        try seedVisit(in: container, experienceId: "exp_arch_d", visitedAt: day3)

        let vm = ArchiveViewModel(modelContainer: container, activeCityCode: "BKK")
        vm.refresh()

        XCTAssertEqual(vm.currentTrip?.dayCount, 3, "Jun 1 → Jun 3 spans 3 days inclusive")
    }

    func testSameDayTripIsOneDay() throws {
        let container = try makeContainer()
        try seedExperience(in: container, id: "exp_arch_same", title: "Cafe", cityCode: "BKK")

        let morning = localDate(year: 2026, month: 6, day: 1, hour: 9)
        let evening = localDate(year: 2026, month: 6, day: 1, hour: 20)
        try seedVisit(in: container, experienceId: "exp_arch_same", visitedAt: morning)
        try seedVisit(in: container, experienceId: "exp_arch_same", visitedAt: evening)

        let vm = ArchiveViewModel(modelContainer: container, activeCityCode: "BKK")
        vm.refresh()

        XCTAssertEqual(vm.currentTrip?.dayCount, 1, "two visits on the same day must report 1 day")
    }

    // MARK: - Orphan handling

    func testVisitsToDeletedExperiencesAreSilentlyDropped() throws {
        let container = try makeContainer()
        // Seed a visit but never create the matching ExperienceRecord.
        try seedVisit(in: container, experienceId: "exp_arch_orphan", visitedAt: Date())
        // Also seed a valid pair so the view model has something to show.
        try seedExperience(in: container, id: "exp_arch_valid", title: "Real", cityCode: "BKK")
        try seedVisit(in: container, experienceId: "exp_arch_valid", visitedAt: Date())

        let vm = ArchiveViewModel(modelContainer: container)
        vm.refresh()

        XCTAssertEqual(vm.groups.count, 1)
        XCTAssertEqual(vm.groups.first?.visits.count, 1)
        XCTAssertEqual(vm.groups.first?.visits.first?.experienceId, "exp_arch_valid")
        // totalVisitCount counts raw rows, including orphans — that's the contract.
        XCTAssertEqual(vm.totalVisitCount, 2)
    }
}
