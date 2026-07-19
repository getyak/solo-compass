import XCTest
@testable import SoloCompass

/// Nomad OS B1-c: `TodayThreeThings.pick` chooses the work / now / tonight
/// cards from a city's experiences. These tests pin each lens, the cross-card
/// de-dup, and the empty-city contract — all against the pure `pick` function,
/// no view or store.
@MainActor
final class TodayThreeThingsTests: XCTestCase {

    // A fixed clock at 14:00 so "now" and "tonight" windows are deterministic.
    private var twoPM: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 19; c.hour = 14; c.minute = 0
        return Calendar.current.date(from: c)!
    }

    private func window(_ start: Int, _ end: Int) -> TimeWindow {
        TimeWindow(startHour: start, endHour: end, dayOfWeek: nil, season: nil, note: nil)
    }

    private func wifi() -> CategoryHighlight {
        CategoryHighlight(kind: .wifi, label: "Wi-Fi", value: "fast")
    }

    private func make(
        id: String,
        cityCode: String = "cmi",
        category: ExperienceCategory,
        score: Double = 5,
        bestTimes: [TimeWindow] = [],
        highlights: [CategoryHighlight] = []
    ) -> Experience {
        let now = Date()
        return Experience(
            id: id,
            title: "Fixture \(id)",
            oneLiner: "One liner \(id)",
            whyItMatters: "Why \(id).",
            category: category,
            location: ExperienceLocation(coordinates: [98.99, 18.78], cityCode: cityCode),
            bestTimes: bestTimes,
            durationMinutes: .init(min: 30, max: 60),
            howTo: [],
            realInconveniences: [],
            soloScore: SoloScore(
                overall: score,
                breakdown: .init(
                    seatingFriendly: 7, soloPatronRatio: 7, staffPressure: 7,
                    soloPortioning: 7, ambianceFit: 7, safety: 7
                ),
                basedOnCount: 1
            ),
            sources: [InformationSource(type: .user, attribution: "test", verifiedAt: now)],
            confidence: Confidence(
                level: 3, lastVerifiedAt: now, reason: "fixture",
                signals: .init(aiScrapeAgeDays: 1, passiveGpsHits30d: 0, activeReports30d: 0, trustedVerifications: 0)
            ),
            nearbyExperienceIds: [],
            stats: .init(completionCount: 0, averageRating: 0),
            status: .active,
            createdAt: now, updatedAt: now,
            categoryHighlights: highlights.isEmpty ? nil : highlights
        )
    }

    // MARK: Work lens

    /// The work card takes the highest-solo-score work-ready spot (a `.work`
    /// place, or a `.coffee` with wifi/power). A plain café without wifi is not
    /// work-ready.
    func testWorkPicksHighestScoringWorkReady() {
        let all = [
            make(id: "cowork-lo", category: .work, score: 7),
            make(id: "cowork-hi", category: .work, score: 9),
            make(id: "cafe-wifi", category: .coffee, score: 8, highlights: [wifi()]),
            make(id: "cafe-plain", category: .coffee, score: 9.5), // not work-ready
        ]
        let picks = TodayThreeThings.pick(from: all, cityCode: "cmi", now: twoPM)
        XCTAssertEqual(picks.work?.id, "cowork-hi",
                       "work must be the top-scoring work-ready spot, not the plain café")
    }

    // MARK: Now lens

    /// The now card takes the highest nowScore. An experience whose bestTimes
    /// contain the current hour scores highly; one that doesn't lags.
    func testNowPicksBestScoringForCurrentHour() {
        let all = [
            make(id: "open-now", category: .food, score: 8, bestTimes: [window(12, 16)]),  // covers 14:00
            make(id: "closed-now", category: .food, score: 8, bestTimes: [window(6, 9)]),  // morning only
        ]
        let picks = TodayThreeThings.pick(from: all, cityCode: "cmi", now: twoPM)
        XCTAssertEqual(picks.now?.id, "open-now",
                       "now must favour the experience whose best window covers the current hour")
    }

    // MARK: Tonight lens

    /// The tonight card requires an evening window (opens ≥18:00).
    func testTonightRequiresEveningWindow() {
        let all = [
            make(id: "daytime", category: .culture, score: 9, bestTimes: [window(9, 17)]),
            make(id: "evening", category: .nightlife, score: 7, bestTimes: [window(19, 23)]),
        ]
        let picks = TodayThreeThings.pick(from: all, cityCode: "cmi", now: twoPM)
        XCTAssertEqual(picks.tonight?.id, "evening",
                       "tonight must require a window opening at or after 18:00")
    }

    // MARK: De-dup

    /// One experience can win two lenses; the earlier lens (work→now→tonight)
    /// keeps it and the later lens falls to its runner-up, so no card repeats.
    func testNoDuplicateAcrossCards() {
        // A single evening work café that's also open now would otherwise win
        // all three; give each later lens a distinct runner-up.
        let all = [
            make(id: "super", category: .work, score: 9, bestTimes: [window(12, 23)], highlights: [wifi()]),
            make(id: "now-alt", category: .food, score: 8, bestTimes: [window(12, 16)]),
            make(id: "night-alt", category: .nightlife, score: 8, bestTimes: [window(20, 23)]),
        ]
        let picks = TodayThreeThings.pick(from: all, cityCode: "cmi", now: twoPM)
        XCTAssertEqual(picks.work?.id, "super", "work claims the super spot first")
        XCTAssertNotEqual(picks.now?.id, "super", "now must not repeat the work pick")
        XCTAssertNotEqual(picks.tonight?.id, "super", "tonight must not repeat the work pick")
        let ids = [picks.work?.id, picks.now?.id, picks.tonight?.id].compactMap { $0 }
        XCTAssertEqual(Set(ids).count, ids.count, "no experience may appear on two cards")
    }

    // MARK: City / empty contract

    /// Experiences in another city are ignored.
    func testFiltersToSelectedCity() {
        let all = [
            make(id: "here", category: .work, score: 9, highlights: [wifi()]),
            make(id: "elsewhere", cityCode: "lis", category: .work, score: 9.5, highlights: [wifi()]),
        ]
        let picks = TodayThreeThings.pick(from: all, cityCode: "cmi", now: twoPM)
        XCTAssertEqual(picks.work?.id, "here")
    }

    /// No city, empty list, or a city with no experiences → empty picks.
    func testEmptyContracts() {
        let some = [make(id: "x", category: .work, score: 9, highlights: [wifi()])]
        XCTAssertTrue(TodayThreeThings.pick(from: some, cityCode: nil, now: twoPM).isEmpty)
        XCTAssertTrue(TodayThreeThings.pick(from: [], cityCode: "cmi", now: twoPM).isEmpty)
        XCTAssertTrue(TodayThreeThings.pick(from: some, cityCode: "tyo", now: twoPM).isEmpty,
                      "a city with no matching experiences yields empty picks")
    }
}
