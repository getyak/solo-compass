import SwiftData
import SwiftUI

/// US-017: the unified inbox reachable from the Me hub's "Messages" row.
///
/// Lists every conversation the user is in — friend DMs (`friendDirect`),
/// one-on-one companion threads (`oneOnOne`), and route group chats
/// (`groupRoute`) — in a single list sorted by `lastMessageAt` descending.
///
/// Each row shows the other party's emoji + handle (or the route name for
/// groups), the last message preview, and an unread dot. Tapping a row pushes
/// the matching `ChatView`. Conversations and their previews are fetched from
/// the backend via `FriendService` / `SupabaseClient`; the chat itself streams
/// over Realtime once opened.
public struct ConversationListView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var service = FriendService.shared
    @State private var summaries: [ConversationSummary] = []
    @State private var isLoading = false
    @State private var didLoad = false
    /// US-024: when this list was opened from a tapped `message` push, the
    /// matching conversation is pushed onto the stack once it loads. Cleared
    /// after it routes so a re-render doesn't re-open it.
    @State private var autoOpenConversation: Conversation?

    /// US-024: conversation id from a `message` deep link; matched against the
    /// loaded summaries to auto-open the thread. `nil` for a normal open.
    private let deepLinkConversationId: String?

    private var currentUserId: String { service.resolvedUserId }

    public init() {
        self.deepLinkConversationId = nil
    }

    /// US-024: open the inbox and auto-push the conversation matching
    /// `deepLinkConversationId` (a tapped message push).
    init(deepLinkConversationId: String?) {
        self.deepLinkConversationId = deepLinkConversationId
    }

    /// Test/preview seam: preload summaries and skip the network reload so the
    /// populated layout (mixed thread types) can be rendered offline.
    init(previewSummaries: [ConversationSummary]) {
        self.deepLinkConversationId = nil
        _summaries = State(initialValue: previewSummaries)
        _didLoad = State(initialValue: true)
    }

    public var body: some View {
        List {
            if summaries.isEmpty {
                Section {
                    Text(NSLocalizedString("messages.empty", comment: "No conversations yet"))
                        .font(.subheadline)
                        .foregroundStyle(CT.fgSubtle)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                        .listRowBackground(Color.clear)
                }
            } else {
                ForEach(summaries) { summary in
                    NavigationLink {
                        ChatView(
                            conversation: summary.conversation,
                            currentUserId: currentUserId
                        )
                    } label: {
                        ConversationRow(summary: summary)
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("me.messages", comment: "Messages"))
        .navigationBarTitleDisplayMode(.inline)
        // US-024: a message deep link auto-pushes the matching ChatView once its
        // conversation appears in the loaded summaries.
        .navigationDestination(item: $autoOpenConversation) { conversation in
            ChatView(conversation: conversation, currentUserId: currentUserId)
        }
        .overlay {
            if isLoading && summaries.isEmpty {
                ProgressView()
            }
        }
        .task {
            // Load once on first appear; pull-to-refresh re-runs `reload`.
            guard !didLoad else { return }
            didLoad = true
            await reload()
            routeDeepLinkIfNeeded()
        }
        .onChange(of: summaries.map(\.id)) { _, _ in
            // Preloaded summaries (previewSummaries init) or a later reload —
            // re-attempt the deep-link match against the current list.
            routeDeepLinkIfNeeded()
        }
        .refreshable { await reload() }
    }

    /// US-024: if opened from a message push, push the matching ChatView once.
    /// No-op when there's no deep link, it already routed, or the conversation
    /// isn't in the user's list.
    private func routeDeepLinkIfNeeded() {
        guard let targetId = deepLinkConversationId, autoOpenConversation == nil else { return }
        guard let match = summaries.first(where: { $0.conversation.id.rawValue == targetId }) else {
            return
        }
        autoOpenConversation = match.conversation
    }

    // MARK: - Data

    /// Fetch conversations, then resolve each one's preview row (last message +
    /// unread) and the group route title where applicable.
    @MainActor
    private func reload() async {
        isLoading = true
        defer { isLoading = false }

        let result = await service.listConversations()
        guard case .success(let conversations) = result else {
            // Network/feature failure leaves the existing list untouched.
            return
        }

        var built: [ConversationSummary] = []
        built.reserveCapacity(conversations.count)
        for conversation in conversations {
            let last = await fetchLastMessage(for: conversation.id)
            built.append(
                ConversationSummary(
                    conversation: conversation,
                    title: title(for: conversation),
                    emoji: emoji(for: conversation),
                    preview: previewText(for: last),
                    hasUnread: isUnread(last)
                )
            )
        }
        summaries = built
    }

    /// The newest message in a conversation, used for the preview + unread dot.
    /// Returns nil for a brand-new thread with no messages.
    private func fetchLastMessage(for id: ConversationId) async -> ChatMessage? {
        let result = await SupabaseClient.shared.get(
            table: "chat_messages",
            query: [
                URLQueryItem(name: "conversation_id", value: "eq.\(id.rawValue)"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        guard case .success(let data) = result, !data.isEmpty,
              let rows = try? JSONDecoder.iso8601Decoder.decode([ChatMessage].self, from: data)
        else {
            return nil
        }
        return rows.first
    }

    // MARK: - Row content resolution

    /// Group chats show the anchored route's title; 1:1 threads show the other
    /// participant's handle (falls back to the raw id when unknown).
    private func title(for conversation: Conversation) -> String {
        if conversation.type == .groupRoute, let routeId = conversation.routeId {
            let route = RouteStore(context: modelContext).get(RouteId(rawValue: routeId))
            if let title = route?.title, !title.isEmpty {
                return title
            }
            return NSLocalizedString("messages.group.fallbackTitle", comment: "Group route fallback title")
        }
        return otherParticipant(in: conversation) ?? NSLocalizedString(
            "messages.unknownUser", comment: "Unknown participant"
        )
    }

    /// Avatar emoji: a people glyph for groups; 1:1 threads use a generic
    /// compass glyph (seed users carry no emoji — richer avatars arrive with
    /// real profiles in a later story).
    private func emoji(for conversation: Conversation) -> String {
        conversation.type == .groupRoute ? "👥" : "🧭"
    }

    /// Last message preview: the body text, or an attachment placeholder when
    /// the newest message is media-only, or a placeholder for an empty thread.
    private func previewText(for message: ChatMessage?) -> String {
        guard let message else {
            return NSLocalizedString("messages.preview.empty", comment: "No messages yet preview")
        }
        let trimmed = message.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if !(message.attachments ?? []).isEmpty {
            return NSLocalizedString("messages.preview.attachment", comment: "Attachment preview")
        }
        return "—"
    }

    /// Unread when the newest message is from the other party and unread by us.
    /// Our own outgoing messages never count as unread.
    private func isUnread(_ message: ChatMessage?) -> Bool {
        guard let message else { return false }
        return message.senderId != currentUserId && message.readAt == nil
    }

    /// First participant that isn't the current user (the 1:1 counterpart).
    private func otherParticipant(in conversation: Conversation) -> String? {
        conversation.participantIds.first { $0 != currentUserId }
    }
}

// MARK: - Summary model

/// A flattened, render-ready row for the unified conversation list. Carries the
/// underlying `Conversation` so a tap can open the matching `ChatView`.
struct ConversationSummary: Identifiable {
    let conversation: Conversation
    let title: String
    let emoji: String
    let preview: String
    let hasUnread: Bool

    var id: ConversationId { conversation.id }
}

// MARK: - Row

private struct ConversationRow: View {
    let summary: ConversationSummary

    var body: some View {
        HStack(spacing: 12) {
            Text(summary.emoji)
                .font(.system(size: 26))
                .frame(width: 44, height: 44)
                .background(Circle().fill(CT.accentSoft))

            VStack(alignment: .leading, spacing: 3) {
                // Semantic colors so the row stays legible against the system
                // List background in both light and dark mode (CT.* are fixed
                // light-surface tokens and would wash out on a dark background).
                Text(summary.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(summary.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if summary.hasUnread {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 10, height: 10)
                    .accessibilityLabel(
                        Text(NSLocalizedString("messages.unread.a11y", comment: "Unread"))
                    )
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

#Preview("Conversation list") {
    NavigationStack {
        ConversationListView()
    }
}
