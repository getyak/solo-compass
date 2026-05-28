import Foundation
import SwiftData

/// SwiftData-backed CRUD for `Conversation` values.
///
/// `@MainActor` because SwiftData `ModelContext` is single-actor. Pass a context
/// from `SoloCompassModelContainer.makeInMemory()` in tests.
@MainActor
public final class ConversationStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: - CRUD

    /// Persist a conversation. Replaces any existing record with the same id.
    public func save(_ conversation: Conversation) {
        deleteRecord(id: conversation.id.rawValue)
        context.insert(ConversationRecord.fromValue(conversation))
        do {
            try context.save()
        } catch {
            assertionFailure("ConversationStore.save failed: \(error)")
        }
    }

    /// Stage a conversation insert without calling `context.save()`. Pair with
    /// the shared `RouteStore.commitContext()` for atomic multi-record saves.
    public func saveWithContext(_ conversation: Conversation) {
        deleteRecord(id: conversation.id.rawValue)
        context.insert(ConversationRecord.fromValue(conversation))
    }

    /// Fetch a conversation by id. Returns nil if not found.
    public func get(_ id: ConversationId) -> Conversation? {
        record(for: id.rawValue)?.asValue
    }

    /// All stored conversations.
    public func all() -> [Conversation] {
        let descriptor = FetchDescriptor<ConversationRecord>()
        return (try? context.fetch(descriptor))?.map(\.asValue) ?? []
    }

    // MARK: - Private helpers

    private func record(for id: String) -> ConversationRecord? {
        let descriptor = FetchDescriptor<ConversationRecord>(
            predicate: #Predicate { $0.id == id }
        )
        return (try? context.fetch(descriptor))?.first
    }

    private func deleteRecord(id: String) {
        guard let existing = record(for: id) else { return }
        context.delete(existing)
    }
}
