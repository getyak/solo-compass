import SwiftUI

/// History of saved chat conversations. Presented from the chat header's clock
/// button; tapping a row reopens that conversation, swipe deletes it. Reads from
/// `ChatHistoryStore` and refreshes on appear.
@MainActor
public struct ChatHistoryListView: View {
    let store: ChatHistoryStore
    /// Called with a chosen session's id, restored messages, and the stored
    /// `scopedExperienceId` so the host can restore the conversation under the
    /// exact scope it was saved with (a place chat must not reopen as global).
    let onSelect: (_ sessionId: String, _ messages: [VoiceAgentSession.Message], _ scopedExperienceId: String?) -> Void
    let onDismiss: () -> Void

    @State private var sessions: [ChatSessionRecord] = []
    @State private var displayTitles: [String: String] = [:]
    @Environment(\.colorScheme) private var colorScheme

    public init(
        store: ChatHistoryStore,
        onSelect: @escaping (_ sessionId: String, _ messages: [VoiceAgentSession.Message], _ scopedExperienceId: String?) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.store = store
        self.onSelect = onSelect
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle(Text(NSLocalizedString("chat.history.title", comment: "History")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "Done"), action: onDismiss)
                }
            }
            .background(backgroundColor)
        }
        .onAppear(perform: reload)
    }

    private var list: some View {
        List {
            ForEach(sessions, id: \.id) { session in
                Button {
                    let restored = store.messages(sessionId: session.id)
                    onSelect(session.id, restored, session.scopedExperienceId)
                } label: {
                    row(for: session)
                }
                .listRowBackground(rowBackground)
            }
            .onDelete(perform: deleteRows)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(for session: ChatSessionRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayTitles[session.id] ?? NSLocalizedString("chat.history.untitled", comment: "Untitled chat"))
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            HStack(spacing: 8) {
                Text(Self.relativeDate(session.updatedAt))
                Text("·")
                Text(String(
                    format: NSLocalizedString("chat.history.messageCount", comment: "%d messages"),
                    session.messageCount
                ))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        SoloEmptyState(
            systemImage: "clock.arrow.circlepath",
            title: NSLocalizedString("chat.history.empty.title", comment: "No conversations yet"),
            message: NSLocalizedString("chat.history.empty", comment: "Hint to start a conversation")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func reload() {
        sessions = store.recentSessions()
        // Legacy titles may have been truncated inside a context envelope.
        // Recover from the full first message without mutating stored history.
        displayTitles = Dictionary(uniqueKeysWithValues: sessions.map { session in
            let title = session.title ?? ""
            let recovered: String?
            if title.hasPrefix("<latest_context>") || title.hasPrefix("<solo:diagnostics>") {
                recovered = ChatHistoryStore.deriveTitle(from: store.messages(sessionId: session.id))
            } else {
                recovered = session.title
            }
            return (session.id, recovered ?? NSLocalizedString("chat.history.untitled", comment: "Untitled chat"))
        })
    }

    private func deleteRows(_ offsets: IndexSet) {
        let ids = offsets.map { sessions[$0].id }
        for id in ids { store.delete(sessionId: id) }
        reload()
        #if canImport(UIKit)
        Haptics.impact(.soft)
        #endif
    }

    // MARK: - Helpers

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(.systemBackground) : CT.bgWarm
    }

    private var rowBackground: Color {
        colorScheme == .dark ? Color(.secondarySystemBackground) : CT.surfaceWhite
    }

    /// Format an ISO 8601 stamp as a short relative description ("2h ago").
    /// Falls back to the raw date if parsing fails.
    static func relativeDate(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return iso }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
