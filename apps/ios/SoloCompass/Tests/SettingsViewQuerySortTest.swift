import XCTest
import SwiftData
@testable import SoloCompass

// MARK: - US-010: SwiftData @Query sort stays clean under strict concurrency
//
// `CompanionConversationsListView` (SettingsView.swift) lists group-route
// conversations newest-first. The view's @Query was migrated off the bare
// KeyPath + `order:` overload — which trips a "sending KeyPath risks data
// races" warning under SWIFT_STRICT_CONCURRENCY=complete — onto an explicit
// `[SortDescriptor]`. This test pins the resulting ordering so the migration
// preserves behavior: groupRoute records, sorted by createdAt descending.
@MainActor
final class SettingsViewQuerySortTest: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = SoloCompassModelContainer.makeInMemory()
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        context = nil
        container = nil
        try await super.tearDown()
    }

    private func makeRecord(id: String, createdAt: String, type: String = "groupRoute") -> ConversationRecord {
        ConversationRecord(
            id: id,
            requestId: "req_\(id)",
            participantIdsBlob: (try? JSONEncoder().encode(["maya", "lin"])) ?? Data(),
            type: type,
            routeId: "route_\(id)",
            lastMessageAt: nil,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    /// Mirrors the exact predicate + sort used by `CompanionConversationsListView`.
    func testGroupRouteRecordsReturnedNewestFirst() throws {
        // Insert out of order to prove the sort, not insertion order, drives output.
        context.insert(makeRecord(id: "b", createdAt: "2026-05-02T10:00:00Z"))
        context.insert(makeRecord(id: "a", createdAt: "2026-05-01T10:00:00Z"))
        context.insert(makeRecord(id: "c", createdAt: "2026-05-03T10:00:00Z"))
        // A non-groupRoute record must be filtered out.
        context.insert(makeRecord(id: "x", createdAt: "2026-05-04T10:00:00Z", type: "oneOnOne"))
        try context.save()

        let descriptor = FetchDescriptor<ConversationRecord>(
            predicate: #Predicate<ConversationRecord> { $0.type == "groupRoute" },
            sortBy: [SortDescriptor(\ConversationRecord.createdAt, order: .reverse)]
        )
        let records = try context.fetch(descriptor)

        XCTAssertEqual(records.map(\.id), ["c", "b", "a"],
            "Group-route records must be sorted by createdAt descending; non-groupRoute excluded")
    }
}
