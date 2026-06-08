import SwiftUI

/// History of saved chat conversations. Presented from the chat header's clock
/// button; tapping a row reopens that conversation, swipe deletes it. Reads from
/// `ChatHistoryStore` and refreshes on appear.
@MainActor
public struct ChatHistoryListView: View {
    let store: ChatHistoryStore
    /// Called with a chosen session's id + restored messages so the host can
    /// rebind the live orchestrator to that conversation.
    let onSelect: (_ sessionId: String, _ messages: [VoiceAgentSession.Message]) -> Void
    let onDismiss: () -> Void

    @State private var sessions: [ChatSessionRecord] = []
    @Environment(\.colorScheme) private var colorScheme

    public init(
        store: ChatHistoryStore,
        onSelect: @escaping (_ sessionId: String, _ messages: [VoiceAgentSession.Message]) -> Void,
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
                    onSelect(session.id, restored)
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
            Text(session.title ?? NSLocalizedString("chat.history.untitled", comment: "Untitled chat"))
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
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("chat.history.empty.title", comment: "No conversations yet"))
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text(NSLocalizedString("chat.history.empty", comment: "Hint to start a conversation"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    // MARK: - Actions

    private func reload() {
        sessions = store.recentSessions()
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
