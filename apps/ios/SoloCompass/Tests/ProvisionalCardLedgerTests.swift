import XCTest
import CoreLocation
@testable import SoloCompass

/// ⑩ Card 可反悔性 — slice A unit tests.
///
/// The ledger is a pure `(entries, now) -> projection` function. Every
/// test here feeds it a fixed `Date` so the transitions are deterministic
/// — no `XCTestExpectation`, no real 3-second wait. Slice B (UI wiring)
/// will pair a real clock with `nextDeadline()`.
@MainActor
final class ProvisionalCardLedgerTests: XCTestCase {

    // MARK: - Helpers

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeExperience(_ id: String = "szx_1") -> Experience {
        let now = t0
        return Experience(
            id: id,
            title: "Fixture \(id)",
            oneLiner: "Fixture \(id)",
            whyItMatters: "⑩ ledger fixture",
            category: .coffee,
            location: ExperienceLocation(coordinates: [114.05, 22.54], cityCode: "szx"),
            bestTimes: [],
            durationMinutes: .init(min: 30, max: 60),
            howTo: [],
            realInconveniences: [],
            soloScore: SoloScore(
                overall: 5,
                breakdown: .init(
                    seatingFriendly: 7, soloPatronRatio: 7, staffPressure: 7,
                    soloPortioning: 7, ambianceFit: 7, safety: 7
                ),
                basedOnCount: 1
            ),
            sources: [InformationSource(type: .user, attribution: "test", verifiedAt: now)],
            confidence: Confidence(
                level: 3,
                lastVerifiedAt: now,
                reason: "Test fixture",
                signals: .init(aiScrapeAgeDays: 1, passiveGpsHits30d: 0, activeReports30d: 0, trustedVerifications: 0)
            ),
            nearbyExperienceIds: [],
            stats: .init(completionCount: 0, averageRating: 0),
            status: .active,
            createdAt: now,
            updatedAt: now
        )
    }

    private func makeCard(_ id: String = "szx_1") -> ChatCard {
        .experiences(id: UUID(), [makeExperience(id)])
    }

    // MARK: - Append & initial state

    func testAppendedCardStartsProvisional() {
        let ledger = ProvisionalCardLedger(undoWindow: 3)
        let msg = UUID()
        _ = ledger.append(card: makeCard(), to: msg, at: t0)

        XCTAssertEqual(ledger.entries.count, 1)
        guard case .provisional(let deadline) = ledger.entries[0].state else {
            return XCTFail("must land as provisional, got \(ledger.entries[0].state)")
        }
        XCTAssertEqual(deadline, t0.addingTimeInterval(3))
    }

    func testCardsByMessageIdAtT0IncludesProvisional() {
        let ledger = ProvisionalCardLedger()
        let msg = UUID()
        _ = ledger.append(card: makeCard(), to: msg, at: t0)

        let map = ledger.cardsByMessageId(at: t0)
        XCTAssertEqual(map[msg]?.count, 1,
                       "provisional cards must still be visible in the projection")
    }

    // MARK: - Undo before deadline

    func testUndoLastBeforeDeadlineHidesCard() {
        let ledger = ProvisionalCardLedger(undoWindow: 3)
        let msg = UUID()
        _ = ledger.append(card: makeCard(), to: msg, at: t0)

        let didUndo = ledger.undoLast(at: t0.addingTimeInterval(1))
        XCTAssertTrue(didUndo)
        XCTAssertEqual(ledger.entries[0].state, .undone)
        XCTAssertTrue(ledger.cardsByMessageId(at: t0.addingTimeInterval(1)).isEmpty,
                      "undone cards must drop out of the projection")
    }

    func testUndoLastReturnsFalseWhenNothingProvisional() {
        let ledger = ProvisionalCardLedger()
        XCTAssertFalse(ledger.undoLast(at: t0),
                       "no-op undo on empty ledger must report false")
    }

    // MARK: - Auto-commit at deadline

    func testProvisionalAutoCommitsAtDeadline() {
        let ledger = ProvisionalCardLedger(undoWindow: 3)
        let msg = UUID()
        _ = ledger.append(card: makeCard(), to: msg, at: t0)

        // Read at exactly deadline: state must be `.committed`.
        let map = ledger.cardsByMessageId(at: t0.addingTimeInterval(3))
        XCTAssertEqual(map[msg]?.count, 1, "committed cards stay visible")

        ledger.promoteDueEntries(now: t0.addingTimeInterval(3))
        XCTAssertEqual(ledger.entries[0].state, .committed)
    }

    func testUndoAfterCommitIsNoOp() {
        let ledger = ProvisionalCardLedger(undoWindow: 3)
        let msg = UUID()
        _ = ledger.append(card: makeCard(), to: msg, at: t0)

        // Let it auto-commit.
        _ = ledger.cardsByMessageId(at: t0.addingTimeInterval(3))
        ledger.promoteDueEntries(now: t0.addingTimeInterval(3))

        // Now the user tries to undo — must be denied.
        XCTAssertFalse(ledger.undoLast(at: t0.addingTimeInterval(3.5)))
        XCTAssertEqual(ledger.entries[0].state, .committed,
                       "committed is irreversible")
    }

    // MARK: - Multi-card ordering

    func testUndoLastPullsMostRecentProvisional() {
        let ledger = ProvisionalCardLedger(undoWindow: 3)
        let msg = UUID()
        let a = ledger.append(card: makeCard("a"), to: msg, at: t0)
        let b = ledger.append(card: makeCard("b"), to: msg, at: t0.addingTimeInterval(0.5))
        let c = ledger.append(card: makeCard("c"), to: msg, at: t0.addingTimeInterval(1.0))

        let didUndo = ledger.undoLast(at: t0.addingTimeInterval(1.2))
        XCTAssertTrue(didUndo)

        XCTAssertEqual(ledger.entries.first(where: { $0.id == c })?.state, .undone,
                       "most recent must be the one undone")
        XCTAssertEqual(ledger.entries.first(where: { $0.id == a })?.state,
                       .provisional(deadline: t0.addingTimeInterval(3)))
        XCTAssertEqual(ledger.entries.first(where: { $0.id == b })?.state,
                       .provisional(deadline: t0.addingTimeInterval(3.5)))
    }

    func testUndoByIdTargetsSpecificEntry() {
        let ledger = ProvisionalCardLedger()
        let msg = UUID()
        let a = ledger.append(card: makeCard("a"), to: msg, at: t0)
        _ = ledger.append(card: makeCard("b"), to: msg, at: t0.addingTimeInterval(0.5))

        XCTAssertTrue(ledger.undo(id: a, at: t0.addingTimeInterval(1)))
        XCTAssertEqual(ledger.entries.first(where: { $0.id == a })?.state, .undone,
                       "targeted undo must hit `a`, not the more recent `b`")
    }

    // MARK: - Commit all + projections

    func testCommitAllProvisionalPromotesEverything() {
        let ledger = ProvisionalCardLedger(undoWindow: 30)
        let msg = UUID()
        _ = ledger.append(card: makeCard("a"), to: msg, at: t0)
        _ = ledger.append(card: makeCard("b"), to: msg, at: t0.addingTimeInterval(1))

        ledger.commitAllProvisional()

        XCTAssertTrue(ledger.entries.allSatisfy { $0.state == .committed },
                      "commitAll must settle every provisional entry, even before deadline")
    }

    func testCommitAllDoesNotResurrectUndoneEntries() {
        let ledger = ProvisionalCardLedger()
        let msg = UUID()
        let a = ledger.append(card: makeCard("a"), to: msg, at: t0)
        _ = ledger.undo(id: a, at: t0.addingTimeInterval(0.5))

        ledger.commitAllProvisional()

        XCTAssertEqual(ledger.entries.first(where: { $0.id == a })?.state, .undone,
                       "commitAll must not un-do an undo")
    }

    func testCardsByMessageIdPreservesInsertionOrder() {
        let ledger = ProvisionalCardLedger()
        let msg = UUID()
        _ = ledger.append(card: makeCard("first"), to: msg, at: t0)
        _ = ledger.append(card: makeCard("second"), to: msg, at: t0.addingTimeInterval(0.1))
        _ = ledger.append(card: makeCard("third"), to: msg, at: t0.addingTimeInterval(0.2))

        let cards = ledger.cardsByMessageId(at: t0.addingTimeInterval(0.3))[msg] ?? []
        guard cards.count == 3,
              case .experiences(_, let e0) = cards[0],
              case .experiences(_, let e1) = cards[1],
              case .experiences(_, let e2) = cards[2] else {
            return XCTFail("expected three experience cards in insertion order")
        }
        XCTAssertEqual(e0.first?.id, "first")
        XCTAssertEqual(e1.first?.id, "second")
        XCTAssertEqual(e2.first?.id, "third")
    }

    // MARK: - Next deadline scheduling

    func testNextDeadlineReturnsSoonest() {
        let ledger = ProvisionalCardLedger(undoWindow: 3)
        let msg = UUID()
        _ = ledger.append(card: makeCard("a"), to: msg, at: t0)                   // deadline t0+3
        _ = ledger.append(card: makeCard("b"), to: msg, at: t0.addingTimeInterval(1)) // deadline t0+4

        XCTAssertEqual(ledger.nextDeadline(), t0.addingTimeInterval(3))
    }

    func testNextDeadlineIsNilWhenNothingProvisional() {
        let ledger = ProvisionalCardLedger()
        XCTAssertNil(ledger.nextDeadline())

        let msg = UUID()
        _ = ledger.append(card: makeCard(), to: msg, at: t0)
        ledger.commitAllProvisional()
        XCTAssertNil(ledger.nextDeadline(),
                     "no deadlines to schedule once everything settled")
    }

    // MARK: - Reset

    func testRemoveAllDropsEverything() {
        let ledger = ProvisionalCardLedger()
        let msg = UUID()
        _ = ledger.append(card: makeCard(), to: msg, at: t0)
        ledger.removeAll()
        XCTAssertTrue(ledger.entries.isEmpty)
        XCTAssertTrue(ledger.cardsByMessageId(at: t0).isEmpty)
    }
}
