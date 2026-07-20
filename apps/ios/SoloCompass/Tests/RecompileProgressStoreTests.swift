import XCTest
@testable import SoloCompass

// MARK: - Deep cross-compile live feed

/// The feed store is the contract between the enrichment agent loop and the
/// sheet: it must present *immediately* on begin, accumulate every stage the
/// agent emits (including failures, which used to be silent no-ops), and reach
/// exactly one terminal state that says whether the card was upgraded.
@MainActor
final class RecompileProgressStoreTests: XCTestCase {

    func testBeginSeedsRunningStartEvent() {
        let store = RecompileProgressStore()
        store.begin(placeName: "Giang Cafe")

        XCTAssertEqual(store.placeName, "Giang Cafe")
        XCTAssertTrue(store.isRunning)
        XCTAssertNil(store.didUpgrade)
        // A start row exists at once so the sheet is never blank on present.
        XCTAssertEqual(store.events.count, 1)
        XCTAssertEqual(store.events.first?.stage, .start)
        XCTAssertEqual(store.events.first?.status, .running)
    }

    func testEmitAppendsInOrder() {
        let store = RecompileProgressStore()
        store.begin(placeName: "Test")
        store.emit(.amap, .running)
        store.emit(.amap, .success, "12 places found")
        store.emit(.foursquare, .skipped, "No API key")

        XCTAssertEqual(store.events.map(\.stage), [.start, .amap, .amap, .foursquare])
        XCTAssertEqual(store.events.last?.status, .skipped)
        XCTAssertEqual(store.events.last?.detail, "No API key")
    }

    func testFinishUpgradedFlipsStartAndAppendsDone() {
        let store = RecompileProgressStore()
        store.begin(placeName: "Test")
        store.emit(.synthesis, .success)
        store.finish(upgraded: true, detail: "Upgraded")

        XCTAssertFalse(store.isRunning)
        XCTAssertEqual(store.didUpgrade, true)
        // The leading running spinner must resolve so no orphan spinner remains.
        XCTAssertEqual(store.events.first?.status, .success)
        XCTAssertEqual(store.events.last?.stage, .done)
        XCTAssertEqual(store.events.last?.status, .success)
    }

    func testFinishNoUpgradeIsAFailureTerminal() {
        let store = RecompileProgressStore()
        store.begin(placeName: "Test")
        // The old silent path: a rejected adopt produced no feedback at all.
        store.emit(.adopt, .failure, "Different venue")
        store.finish(upgraded: false, detail: "Nothing richer found")

        XCTAssertFalse(store.isRunning)
        XCTAssertEqual(store.didUpgrade, false)
        XCTAssertEqual(store.events.last?.stage, .failed)
        XCTAssertEqual(store.events.last?.status, .failure)
        // The failing stage line survives so the user sees WHY, not just "done".
        XCTAssertTrue(store.events.contains { $0.stage == .adopt && $0.status == .failure })
    }

    func testBeginResetsPriorFeed() {
        let store = RecompileProgressStore()
        store.begin(placeName: "First")
        store.emit(.amap, .success)
        store.finish(upgraded: true)

        store.begin(placeName: "Second")
        XCTAssertEqual(store.placeName, "Second")
        XCTAssertEqual(store.events.count, 1)
        XCTAssertTrue(store.isRunning)
        XCTAssertNil(store.didUpgrade)
    }
}
