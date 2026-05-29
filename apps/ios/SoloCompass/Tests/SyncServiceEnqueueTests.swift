import XCTest
import SwiftData
@testable import SoloCompass

/// US-002: `SyncService.enqueue` must report encode/persist failures to Sentry
/// instead of silently dropping the user's action.
@MainActor
final class SyncServiceEnqueueTests: XCTestCase {

    /// Records `capture` calls so the test can assert the failure was reported.
    /// `@unchecked Sendable` is safe: every call originates on the MainActor.
    final class MockSyncErrorReporter: SyncErrorReporting, @unchecked Sendable {
        struct Captured: Equatable {
            let context: String
            let payload: String?
        }
        private(set) var captures: [Captured] = []

        func capture(_ error: Error, context: String, payload: String?) {
            captures.append(Captured(context: context, payload: payload))
        }
    }

    /// A payload whose `encode(to:)` deterministically throws, forcing the
    /// `JSONEncoder` path in `enqueue` to fail.
    private struct AlwaysFailsEncoding: Encodable {
        struct EncodeError: Error {}
        func encode(to encoder: Encoder) throws {
            throw EncodeError()
        }
    }

    /// A trivially-encodable payload for the success path.
    private struct GoodPayload: Encodable {
        let value: String
    }

    private func makeContext() -> ModelContext {
        ModelContext(SoloCompassModelContainer.makeInMemory())
    }

    func testEnqueueReportsEncodeFailureToSentry() {
        let mock = MockSyncErrorReporter()
        let service = SyncService()
        service.reporter = mock

        service.enqueue(
            tableName: "user_favorites",
            operation: "upsert",
            payload: AlwaysFailsEncoding(),
            context: makeContext()
        )

        XCTAssertEqual(mock.captures.count, 1, "encode failure must be reported exactly once")
        XCTAssertEqual(mock.captures.first?.context, "SyncService.enqueue")
        XCTAssertEqual(mock.captures.first?.payload, "user_favorites")
    }

    func testEnqueueDoesNotReportWhenEncodeSucceeds() {
        let mock = MockSyncErrorReporter()
        let service = SyncService()
        service.reporter = mock

        service.enqueue(
            tableName: "user_completions",
            operation: "upsert",
            payload: GoodPayload(value: "exp_123"),
            context: makeContext()
        )

        XCTAssertTrue(mock.captures.isEmpty, "successful enqueue must not report to Sentry")
    }
}
