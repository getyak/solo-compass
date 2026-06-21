import Foundation
import SwiftData

/// SwiftData-backed persistence for chat conversations so history survives app
/// restarts and the user can reopen a past conversation.
///
/// `@MainActor` because SwiftData's `ModelContext` is single-actor, matching
/// `RouteStore` / `ItineraryStore`. A conversation is stored as one
/// `ChatSessionRecord` plus N `ChatMessageRecord` rows linked by `sessionId`.
/// `saveSession` is an idempotent upsert: it replaces the session's existing
/// message rows so the latest snapshot always wins (a turn-by-turn save just
/// overwrites the prior partial conversation under the same id).
@MainActor
public final class ChatHistoryStore {
    /// Posted after any successful mutation so observers can refresh the
    /// history list without holding a strong reference to the store.
    public static let didChange = Notification.Name("SoloCompass.ChatHistoryStore.didChange")

    let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Convenience init using the shared on-disk container.
    public convenience init() {
        self.init(context: ModelContext(SoloCompassModelContainer.shared))
    }

    private static func nowISO() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    // MARK: - Save

    /// Persist (upsert) a whole conversation under `sessionId`. Skips sessions
    /// that have no real user content yet so an opened-but-unused chat doesn't
    /// litter history. Returns true when something was written.
    @discardableResult
    public func saveSession(
        id sessionId: String,
        messages: [VoiceAgentSession.Message],
        scopedExperienceId: String?,
        createdAt: String? = nil
    ) -> Bool {
        // Only persist conversations the user actually had — at least one user
        // message present.
        let conversational = messages.filter { $0.role == .user || $0.role == .assistant }
        guard conversational.contains(where: { $0.role == .user }) else { return false }

        let now = Self.nowISO()
        let created = createdAt ?? existingSession(sessionId)?.createdAt ?? now

        // Replace any prior rows for this session (idempotent upsert).
        deleteRows(sessionId: sessionId)

        let title = Self.deriveTitle(from: messages)
        let session = ChatSessionRecord(
            id: sessionId,
            scopedExperienceId: scopedExperienceId,
            title: title,
            createdAt: created,
            updatedAt: now,
            messageCount: conversational.count
        )
        context.insert(session)

        for (index, message) in messages.enumerated() {
            // Don't persist the system prompt — it's rebuilt fresh on restore
            // and would otherwise bloat every stored conversation.
            guard message.role != .system else { continue }
            context.insert(
                ChatMessageRecord.fromMessage(
                    message,
                    sessionId: sessionId,
                    orderIndex: index,
                    createdAt: now
                )
            )
        }

        do {
            try context.save()
        } catch {
            assertionFailure("ChatHistoryStore.saveSession failed: \(error)")
            return false
        }
        postChange()
        return true
    }

    // MARK: - Fetch

    /// Saved sessions, most-recently-updated first, capped at `limit`.
    public func recentSessions(limit: Int = 30) -> [ChatSessionRecord] {
        guard limit > 0 else { return [] }
        var descriptor = FetchDescriptor<ChatSessionRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    /// All non-system messages for a session, in stored order, as domain values
    /// ready to seed back into a `VoiceAgentSession`.
    public func messages(sessionId: String) -> [VoiceAgentSession.Message] {
        let descriptor = FetchDescriptor<ChatMessageRecord>(
            predicate: #Predicate { $0.sessionId == sessionId },
            // #85: secondary sort on createdAt so two messages that ended up
            // with the same orderIndex (rare — only possible after a crash
            // during a turn commit) still render in a deterministic order
            // instead of shuffling between launches. SwiftData's sort is
            // otherwise unstable for equal keys.
            sortBy: [SortDescriptor(\.orderIndex), SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor))?.map(\.asMessage) ?? []
    }

    // MARK: - Delete

    /// Delete one session and all of its messages. No-op if not found.
    public func delete(sessionId: String) {
        deleteRows(sessionId: sessionId)
        if let session = existingSession(sessionId) {
            context.delete(session)
        }
        do {
            try context.save()
        } catch {
            assertionFailure("ChatHistoryStore.delete failed: \(error)")
        }
        postChange()
    }

    // MARK: - Private helpers

    private func existingSession(_ id: String) -> ChatSessionRecord? {
        let descriptor = FetchDescriptor<ChatSessionRecord>(
            predicate: #Predicate { $0.id == id }
        )
        return (try? context.fetch(descriptor))?.first
    }

    private func deleteRows(sessionId: String) {
        let descriptor = FetchDescriptor<ChatMessageRecord>(
            predicate: #Predicate { $0.sessionId == sessionId }
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        for row in rows { context.delete(row) }
    }

    private func postChange() {
        NotificationCenter.default.post(name: ChatHistoryStore.didChange, object: self)
    }

    /// Derive a short title from the first user message (trimmed to one line,
    /// capped). Falls back to nil so the list can show a default.
    static func deriveTitle(from messages: [VoiceAgentSession.Message]) -> String? {
        guard let firstUser = messages.first(where: { $0.role == .user })?.content else {
            return nil
        }
        let oneLine = firstUser
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oneLine.isEmpty else { return nil }
        return oneLine.count > 40 ? String(oneLine.prefix(40)) + "…" : oneLine
    }
}
