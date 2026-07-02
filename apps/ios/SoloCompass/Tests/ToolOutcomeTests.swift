import XCTest
@testable import SoloCompass

/// Wire-format + retry-ledger tests for `ToolOutcome`.
///
/// The point of this suite is not to prove the enum compiles (Swift already
/// does that), it's to lock the JSON shape and the retry semantics that the
/// model reads and reacts to. Any regression here changes the contract with
/// the LLM and must be intentional.
@MainActor
final class ToolOutcomeTests: XCTestCase {

    // MARK: - Wire format

    struct DummyOK: Encodable { let count: Int; let ids: [String] }

    func testOkOutcomeShape() throws {
        let outcome: ToolOutcome<DummyOK> = .ok(
            payload: DummyOK(count: 3, ids: ["a", "b", "c"]),
            hint: "3 fresh coffee spots surfaced within 800m."
        )
        let json = outcome.encodeForModel()
        let dict = try parse(json)

        XCTAssertEqual(dict["ok"] as? Bool, true)
        XCTAssertEqual(dict["outcome"] as? String, "ok")
        XCTAssertEqual(dict["hint"] as? String, "3 fresh coffee spots surfaced within 800m.")

        let payload = try XCTUnwrap(dict["payload"] as? [String: Any])
        XCTAssertEqual(payload["count"] as? Int, 3)
        XCTAssertEqual(payload["ids"] as? [String], ["a", "b", "c"])

        // Absent fields
        XCTAssertNil(dict["reason"])
        XCTAssertNil(dict["retryable_with"])
        XCTAssertNil(dict["question"])
    }

    func testRetryableOutcomeCarriesHintAndOverride() throws {
        let outcome: ToolOutcome<DummyOK> = .retryable(
            reason: .emptyResult,
            hint: "No coffee shops in 800m. Widen to 3000m or drop the category filter.",
            retryableWith: [
                "radius_meters": .int(3000),
                "categories": .string("[]")
            ]
        )
        let json = outcome.encodeForModel()
        let dict = try parse(json)

        XCTAssertEqual(dict["ok"] as? Bool, false)
        XCTAssertEqual(dict["outcome"] as? String, "retryable")
        XCTAssertEqual(dict["reason"] as? String, "empty_result")
        XCTAssertTrue((dict["hint"] as? String ?? "").contains("3000m"))

        let ov = try XCTUnwrap(dict["retryable_with"] as? [String: Any])
        XCTAssertEqual(ov["radius_meters"] as? Int, 3000)
    }

    func testFatalOutcomeNeverEmitsRetryHooks() throws {
        let outcome: ToolOutcome<DummyOK> = .fatal(
            reason: .mapUnavailable,
            hint: "Ask the user to reopen the map — the tool cannot recover this turn."
        )
        let json = outcome.encodeForModel()
        let dict = try parse(json)

        XCTAssertEqual(dict["outcome"] as? String, "fatal")
        XCTAssertEqual(dict["reason"] as? String, "map_unavailable")
        XCTAssertNil(dict["retryable_with"], "fatal must not present retry hooks — otherwise the model may loop.")
        XCTAssertNil(dict["payload"])
    }

    func testNeedsConfirmationCarriesQuestion() throws {
        let outcome: ToolOutcome<DummyOK> = .needsConfirmation(
            reason: .paywallRequired,
            question: "Blindbox needs Pro — want me to open the paywall?"
        )
        let json = outcome.encodeForModel()
        let dict = try parse(json)

        XCTAssertEqual(dict["outcome"] as? String, "needs_confirmation")
        XCTAssertEqual(dict["reason"] as? String, "paywall_required")
        XCTAssertEqual(dict["question"] as? String, "Blindbox needs Pro — want me to open the paywall?")
    }

    func testEnvelopeIsDeterministicallyOrdered() throws {
        // Snapshotting the LLM contract needs stable key order.
        let outcome1: ToolOutcome<DummyOK> = .ok(payload: DummyOK(count: 1, ids: ["a"]))
        let outcome2: ToolOutcome<DummyOK> = .ok(payload: DummyOK(count: 1, ids: ["a"]))
        XCTAssertEqual(outcome1.encodeForModel(), outcome2.encodeForModel())
    }

    // MARK: - Retry ledger

    func testLedgerRecordsAndReports() {
        let ledger = ToolRetryLedger()
        XCTAssertFalse(ledger.isExhausted(tool: "explore_nearby", reason: "empty_result"))

        _ = ledger.record(tool: "explore_nearby", reason: "empty_result")
        _ = ledger.record(tool: "explore_nearby", reason: "empty_result")
        XCTAssertFalse(ledger.isExhausted(tool: "explore_nearby", reason: "empty_result"),
                       "retryCap=2 → after 2 retries the model still gets one more legitimate try")

        _ = ledger.record(tool: "explore_nearby", reason: "empty_result")
        XCTAssertTrue(ledger.isExhausted(tool: "explore_nearby", reason: "empty_result"),
                      "3rd occurrence of same (tool, reason) → exhausted, router must return .fatal(.retryBudgetExhausted)")
    }

    func testLedgerIsolatesByToolAndReason() {
        let ledger = ToolRetryLedger()
        _ = ledger.record(tool: "explore_nearby", reason: "empty_result")
        _ = ledger.record(tool: "explore_nearby", reason: "empty_result")
        _ = ledger.record(tool: "explore_nearby", reason: "empty_result")

        // Different reason → independent budget.
        XCTAssertFalse(ledger.isExhausted(tool: "explore_nearby", reason: "invalid_args"))
        // Different tool → independent budget.
        XCTAssertFalse(ledger.isExhausted(tool: "search_places", reason: "empty_result"))
    }

    func testLedgerResetsPerTurn() {
        let ledger = ToolRetryLedger()
        _ = ledger.record(tool: "explore_nearby", reason: "empty_result")
        _ = ledger.record(tool: "explore_nearby", reason: "empty_result")
        _ = ledger.record(tool: "explore_nearby", reason: "empty_result")
        XCTAssertTrue(ledger.isExhausted(tool: "explore_nearby", reason: "empty_result"))

        ledger.resetForNewTurn()
        XCTAssertFalse(ledger.isExhausted(tool: "explore_nearby", reason: "empty_result"),
                       "fresh user turn = fresh retry budget")
    }

    // MARK: - Helpers

    private func parse(_ json: String) throws -> [String: Any] {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
