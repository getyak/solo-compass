import XCTest
import SwiftData
import UserNotifications
@testable import SoloCompass

/// P2/P3 skeleton coverage: exercises the deterministic paths of every
/// new service we've introduced this pass. Real APNs / MusicKit /
/// StoreKit live behind test-only guards; here we hit the contract.
@MainActor
final class V_NEXT_ServiceSkeletonTests: XCTestCase {

    // MARK: - OmenComposeService (#301)

    func test_omen_deterministic_perDay() {
        let svc = OmenComposeService()
        let day = Date(timeIntervalSince1970: 1_780_000_000)
        let a = svc.compose(for: day, tasteDescriptors: ["quiet", "sunlit"])
        let b = svc.compose(for: day, tasteDescriptors: ["quiet", "sunlit"])
        XCTAssertEqual(a, b, "same day + same taste must produce identical omen")
    }

    func test_omen_differsAcrossDays() {
        let svc = OmenComposeService()
        let cal = Calendar(identifier: .gregorian)
        let day1 = cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        let day2 = cal.date(from: DateComponents(year: 2026, month: 7, day: 2))!
        let a = svc.compose(for: day1, tasteDescriptors: ["quiet"])
        let b = svc.compose(for: day2, tasteDescriptors: ["quiet"])
        XCTAssertNotEqual(a, b)
    }

    // MARK: - MusicService (#310/#311)

    func test_music_deterministicPlaylist() {
        let svc = MusicService()
        let v1 = VisitRecord(experienceId: "cmi-kalare-market", dwellSeconds: 300)
        let v2 = VisitRecord(experienceId: "cmi-kalare-market", dwellSeconds: 300)
        let a = svc.composeOst(for: [v1, v2], style: .ambient)
        let b = svc.composeOst(for: [v1, v2], style: .ambient)
        XCTAssertEqual(a.trackIDs, b.trackIDs)
        XCTAssertEqual(a.style, .ambient)
    }

    // MARK: - BragCardComposer (#321)

    func test_brag_countsAndHeadlineDeterministic() {
        let visits = [
            VisitRecord(experienceId: "a", visitedAt: Date().addingTimeInterval(-3600 * 48), dwellSeconds: 300),
            VisitRecord(experienceId: "a", visitedAt: Date().addingTimeInterval(-3600 * 24), dwellSeconds: 400),
            VisitRecord(experienceId: "b", visitedAt: Date(), dwellSeconds: 500),
        ]
        let svc = BragCardComposer()
        let card = svc.compose(cityCode: "cmi", visits: visits, experiences: [])
        XCTAssertEqual(card.distinctExperienceCount, 2)
        XCTAssertGreaterThanOrEqual(card.dayCount, 2)
        XCTAssertFalse(card.headline.isEmpty)
    }

    // MARK: - MonthlyInsightService (#330)

    func test_monthly_bucketsVisitsByMonth() {
        let cal = Calendar(identifier: .gregorian)
        let july1 = cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        let aug1  = cal.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let visits = [
            VisitRecord(experienceId: "a", visitedAt: july1, dwellSeconds: 300),
            VisitRecord(experienceId: "b", visitedAt: aug1,  dwellSeconds: 300),
        ]
        let svc = MonthlyInsightService()
        let julyData = svc.compose(for: july1, visits: visits, experiences: [], calendar: cal)
        XCTAssertEqual(julyData.visitCount, 1, "August visit must not leak into July insight")
    }

    // MARK: - BookComposeService (#341)

    func test_book_weeklyChapters() {
        let cal = Calendar(identifier: .gregorian)
        let visits: [VisitRecord] = (0..<4).map { i in
            let d = cal.date(byAdding: .weekOfYear, value: i, to: cal.date(from: DateComponents(year: 2026, month: 1, day: 5))!)!
            return VisitRecord(experienceId: "e-\(i)", visitedAt: d, dwellSeconds: 300)
        }
        let svc = BookComposeService()
        let manifest = svc.compose(forYear: 2026, visits: visits, experiences: [], calendar: cal)
        XCTAssertEqual(manifest.chapters.count, 4)
    }

    // MARK: - AnalyticsService (#X20)

    func test_analytics_bufferHonoursOptOut() {
        let svc = AnalyticsService()
        svc.enabled = true
        UserDefaults.standard.removeObject(forKey: "com.solocompass.analytics.buffer.v1")
        svc.track(.paywallShown, properties: ["source": .string("blindbox")])
        XCTAssertGreaterThanOrEqual(svc.pendingCount, 1)
        svc.enabled = false
        XCTAssertEqual(svc.pendingCount, 0, "opt-out must drain the buffer")
    }

    // MARK: - CapsuleStore (#243)

    func test_capsuleStore_buriesAndFindsRipe() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: TimeCapsule.self, VisitRecord.self, TasteProfile.self, AgentMemorySnapshot.self,
            configurations: config
        )
        let store = CapsuleStore(modelContainer: container)
        let now = Date()
        let ripeAt = now.addingTimeInterval(-3600)
        let context = ModelContext(container)
        let row = TimeCapsule(
            experienceId: "cmi-market",
            createdAt: ripeAt.addingTimeInterval(-3600 * 24 * 30),
            scheduledFor: ripeAt,
            contentType: "text",
            contentBlob: "hello future".data(using: .utf8)!
        )
        context.insert(row)
        try context.save()
        XCTAssertEqual(store.ripeCapsules(now: now).count, 1)
        XCTAssertTrue(store.markOpened(row.id))
        XCTAssertEqual(store.ripeCapsules(now: now).count, 0)
    }

    // MARK: - ProactiveNudgeScheduler (#260/#261, #X42)

    func test_nudge_dailyBudgetLimits() {
        let sut = ProactiveNudgeScheduler()
        sut.dailyBudget = 2
        UserDefaults.standard.removeObject(forKey: ProactiveNudgeScheduler.budgetKey(for: Date(), calendar: .current))
        XCTAssertTrue(sut.consumeDailyBudget())
        XCTAssertTrue(sut.consumeDailyBudget())
        XCTAssertFalse(sut.consumeDailyBudget(), "third consume must be denied")
    }
}
