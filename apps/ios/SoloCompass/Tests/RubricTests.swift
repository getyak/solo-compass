import XCTest
@testable import SoloCompass

/// ④ Self-eval Rubric — unit coverage for the three pieces:
/// - `RubricReport` value semantics (clamp, overall, verdict, weakest)
/// - `RubricScorer` heuristics against the concrete failure modes it
///   was tuned to catch (skeleton, pretend-tool, wall-of-text on a
///   simple ask, ignored scoped experience, missing card on a "recommend
///   me" turn)
/// - `RubricStore` ring-buffer bounds + rolling average
///
/// These tests are deterministic and pure — no network, no simulator
/// interaction. The live orchestrator wiring is covered separately in
/// `RubricOrchestratorWiringTests`.
@MainActor
final class RubricTests: XCTestCase {

    // MARK: - RubricReport

    func testClampBelowZeroToZero() {
        let r = RubricReport(
            turnIndex: 0,
            relevance: -5,
            factuality: 10,
            conciseness: 10,
            contextUsage: 10,
            toolHonesty: 10,
            cardCoverage: 10
        )
        XCTAssertEqual(r.relevance, 0)
    }

    func testClampAboveTenToTen() {
        let r = RubricReport(
            turnIndex: 0,
            relevance: 42,
            factuality: 10,
            conciseness: 10,
            contextUsage: 10,
            toolHonesty: 10,
            cardCoverage: 10
        )
        XCTAssertEqual(r.relevance, 10)
    }

    func testOverallAllTensIsHundred() {
        let r = RubricReport(
            turnIndex: 0,
            relevance: 10,
            factuality: 10,
            conciseness: 10,
            contextUsage: 10,
            toolHonesty: 10,
            cardCoverage: 10
        )
        XCTAssertEqual(r.overall, 100)
        XCTAssertEqual(r.verdict, .pass)
    }

    func testOverallAllZerosIsZero() {
        let r = RubricReport(
            turnIndex: 0,
            relevance: 0,
            factuality: 0,
            conciseness: 0,
            contextUsage: 0,
            toolHonesty: 0,
            cardCoverage: 0
        )
        XCTAssertEqual(r.overall, 0)
        XCTAssertEqual(r.verdict, .fail)
    }

    func testVerdictBorderlineAtEighty() {
        // Pick values that land in [70, 84]. 8 across the board *
        // weight-sum 10 = 80 exactly.
        let r = RubricReport(
            turnIndex: 0,
            relevance: 8,
            factuality: 8,
            conciseness: 8,
            contextUsage: 8,
            toolHonesty: 8,
            cardCoverage: 8
        )
        XCTAssertEqual(r.overall, 80)
        XCTAssertEqual(r.verdict, .borderline)
    }

    func testWeakestDimensionPicksTheLowest() {
        let r = RubricReport(
            turnIndex: 0,
            relevance: 10,
            factuality: 10,
            conciseness: 3,   // lowest
            contextUsage: 10,
            toolHonesty: 10,
            cardCoverage: 10
        )
        XCTAssertEqual(r.weakestDimension, "conciseness")
    }

    // MARK: - RubricScorer

    private func input(
        user: String = "推荐个附近安静的咖啡馆",
        assistant: String,
        tools: [String] = [],
        cards: Int = 1,
        quality: AIService.AISynthesisQuality = .real,
        scoped: Bool = false
    ) -> RubricScorer.TurnInput {
        RubricScorer.TurnInput(
            turnIndex: 1,
            userText: user,
            assistantText: assistant,
            toolCallsInvoked: tools,
            cardsAppended: cards,
            synthesisQuality: quality,
            hasScopedExperience: scoped
        )
    }

    /// Happy path: real synthesis + a card + concise answer + user asked
    /// for places + card is present → should ship (≥85).
    func testHappyPathScoresPass() {
        let scorer = RubricScorer()
        let report = scorer.score(input(
            assistant: "附近这家咖啡馆很安静，适合独自阅读。",
            tools: ["searchPlaces"],
            cards: 1,
            quality: .real
        ))
        XCTAssertGreaterThanOrEqual(report.overall, 85)
        XCTAssertEqual(report.verdict, .pass)
    }

    /// Skeleton fallback should visibly drop factuality.
    func testSkeletonFallbackTanksFactuality() {
        let scorer = RubricScorer()
        let report = scorer.score(input(
            assistant: "这里有一家咖啡馆可以试试。",
            tools: [],
            cards: 0,
            quality: .skeleton
        ))
        // Skeleton = 5 base, no card bonus → factuality ≤ 6
        XCTAssertLessThanOrEqual(report.factuality, 6)
    }

    /// "Let me check…" text without a real tool call → both toolHonesty
    /// and factuality take the hit.
    func testPretendToolTanksHonesty() {
        let scorer = RubricScorer()
        let report = scorer.score(input(
            user: "How's the weather in Shenzhen?",
            assistant: "Let me check the weather for you...",
            tools: [],
            cards: 0,
            quality: .real
        ))
        XCTAssertLessThanOrEqual(report.toolHonesty, 2)
    }

    /// Scoped experience bound but the reply never references it → drop.
    func testIgnoringScopedExperienceDropsContextUsage() {
        let scorer = RubricScorer()
        let report = scorer.score(input(
            user: "早上人多吗",
            assistant: "早上的人流一般，但也要看具体情况。",
            tools: [],
            cards: 0,
            quality: .real,
            scoped: true
        ))
        XCTAssertLessThanOrEqual(report.contextUsage, 5)
    }

    /// User asks for places, no card appended, no explicit list → drop
    /// cardCoverage.
    func testAskingForPlacesWithoutCardsDropsCoverage() {
        let scorer = RubricScorer()
        let report = scorer.score(input(
            user: "附近有什么推荐的",
            assistant: "附近有很多不错的地方哦。",
            tools: [],
            cards: 0,
            quality: .real
        ))
        XCTAssertLessThanOrEqual(report.cardCoverage, 5)
    }

    /// Wall of text on a short prompt with a card doing the work → drop
    /// conciseness. Card coverage is fine because a card exists.
    func testWallOfTextDropsConciseness() {
        let scorer = RubricScorer()
        let wall = String(repeating: "这家咖啡馆非常安静适合独自阅读。", count: 40)
        let report = scorer.score(input(
            assistant: wall,
            tools: ["searchPlaces"],
            cards: 1,
            quality: .real
        ))
        XCTAssertLessThan(report.conciseness, 10)
    }

    /// Notes field carries the diagnostic string for the weakest dim.
    func testNotesReflectWeakestDimension() {
        let scorer = RubricScorer()
        let report = scorer.score(input(
            user: "How's the weather?",
            assistant: "Let me check the weather for you...",
            tools: [],
            cards: 0,
            quality: .real
        ))
        XCTAssertFalse(report.notes.isEmpty)
        XCTAssertEqual(report.weakestDimension, "toolHonesty")
    }

    // MARK: - RubricStore

    func testStoreRecordsInOrder() {
        let store = RubricStore(capacity: 3)
        for i in 0..<3 {
            store.record(RubricReport(
                turnIndex: i,
                relevance: 10, factuality: 10, conciseness: 10,
                contextUsage: 10, toolHonesty: 10, cardCoverage: 10
            ))
        }
        XCTAssertEqual(store.reports.map(\.turnIndex), [0, 1, 2])
    }

    func testStoreDropsOldestOnOverflow() {
        let store = RubricStore(capacity: 2)
        for i in 0..<4 {
            store.record(RubricReport(
                turnIndex: i,
                relevance: 10, factuality: 10, conciseness: 10,
                contextUsage: 10, toolHonesty: 10, cardCoverage: 10
            ))
        }
        XCTAssertEqual(store.reports.map(\.turnIndex), [2, 3])
    }

    func testStoreZeroCapacityCoercesToOne() {
        let store = RubricStore(capacity: 0)
        store.record(RubricReport(
            turnIndex: 5,
            relevance: 5, factuality: 5, conciseness: 5,
            contextUsage: 5, toolHonesty: 5, cardCoverage: 5
        ))
        XCTAssertEqual(store.reports.count, 1)
    }

    func testLatestReturnsMostRecent() {
        let store = RubricStore(capacity: 5)
        store.record(RubricReport(
            turnIndex: 1,
            relevance: 5, factuality: 5, conciseness: 5,
            contextUsage: 5, toolHonesty: 5, cardCoverage: 5
        ))
        store.record(RubricReport(
            turnIndex: 2,
            relevance: 10, factuality: 10, conciseness: 10,
            contextUsage: 10, toolHonesty: 10, cardCoverage: 10
        ))
        XCTAssertEqual(store.latest?.turnIndex, 2)
    }

    func testRollingOverallAveragesBuffer() {
        let store = RubricStore(capacity: 2)
        // overall = 50 (all 5s)
        store.record(RubricReport(
            turnIndex: 1,
            relevance: 5, factuality: 5, conciseness: 5,
            contextUsage: 5, toolHonesty: 5, cardCoverage: 5
        ))
        // overall = 100
        store.record(RubricReport(
            turnIndex: 2,
            relevance: 10, factuality: 10, conciseness: 10,
            contextUsage: 10, toolHonesty: 10, cardCoverage: 10
        ))
        XCTAssertEqual(store.rollingOverall, 75, accuracy: 0.5)
    }

    func testFailingReportsFilter() {
        let store = RubricStore(capacity: 5)
        // overall = 30 → fail
        store.record(RubricReport(
            turnIndex: 1,
            relevance: 3, factuality: 3, conciseness: 3,
            contextUsage: 3, toolHonesty: 3, cardCoverage: 3
        ))
        // overall = 100 → pass
        store.record(RubricReport(
            turnIndex: 2,
            relevance: 10, factuality: 10, conciseness: 10,
            contextUsage: 10, toolHonesty: 10, cardCoverage: 10
        ))
        XCTAssertEqual(store.failingReports.count, 1)
        XCTAssertEqual(store.failingReports.first?.turnIndex, 1)
    }

    func testClearEmptiesTheStore() {
        let store = RubricStore(capacity: 3)
        store.record(RubricReport(
            turnIndex: 1,
            relevance: 8, factuality: 8, conciseness: 8,
            contextUsage: 8, toolHonesty: 8, cardCoverage: 8
        ))
        store.clear()
        XCTAssertTrue(store.reports.isEmpty)
        XCTAssertNil(store.latest)
    }
}
