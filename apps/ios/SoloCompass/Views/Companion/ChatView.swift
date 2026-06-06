import SwiftData
import SwiftUI

/// Full-screen chat view for a companion conversation (US-013).
///
/// Shows message bubbles sorted by `sent_at`. Subscribes to Supabase
/// Realtime via `ChatService` so new messages appear without polling.
/// Only conversation participants can read/write — enforced by RLS.
///
/// When `conversation.type == .groupRoute`: renders a sticky pinned RouteCard
/// at the top (US-037) and shows sender avatar + handle beside each bubble.
public struct ChatView: View {
    let conversation: Conversation

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var service: ChatService
    @State private var inputText = ""
    /// Draft attachments staged in the Instagram-style input bar before send.
    @State private var draftAttachments: [LocalAttachment] = []
    @State private var showingReportSheet = false
    @State private var pinnedRoute: Route?

    private let currentUserId: String?
    /// The other participant's user ID (used for report/block in one-on-one).
    private let otherUserId: String?

    private var isGroupRoute: Bool { conversation.type == .groupRoute }

    public init(conversation: Conversation, currentUserId: String? = nil) {
        self.conversation = conversation
        self.currentUserId = currentUserId
        self.otherUserId = conversation.participantIds.first { $0 != currentUserId }
        _service = State(
            initialValue: ChatService(conversationId: conversation.id)
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            if isGroupRoute, let route = pinnedRoute {
                pinnedRouteHeader(route: route)
                Divider()
            }
            messageList
            Divider()
            inputBar
        }
        .navigationTitle(NSLocalizedString("companion.chat.title", comment: "Chat nav title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isGroupRoute, let otherId = otherUserId {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            showingReportSheet = true
                        } label: {
                            Label(
                                NSLocalizedString("companion.report.block.menu", comment: "Report or block"),
                                systemImage: "flag"
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(NSLocalizedString("companion.report.block.menu", comment: "Report or block"))
                }
            }
        }
        .sheet(isPresented: $showingReportSheet) {
            if let otherId = otherUserId {
                ReportBlockSheet(
                    targetUserId: otherId,
                    targetLabel: NSLocalizedString("companion.chat.title", comment: "Chat")
                ) {
                    // Conversation frozen — dismiss chat on block.
                    dismiss()
                }
            }
        }
        .task {
            await service.start()
            if isGroupRoute, let routeId = conversation.routeId {
                pinnedRoute = RouteStore(context: modelContext).get(RouteId(rawValue: routeId))
            }
        }
        .onDisappear {
            service.stop()
        }
        .alert(
            NSLocalizedString("companion.chat.error.title", comment: "Chat error title"),
            isPresented: Binding(
                get: { service.lastError != nil },
                set: { if !$0 { service.lastError = nil } }
            )
        ) {
            Button(NSLocalizedString("action.ok", comment: "OK")) {
                service.lastError = nil
            }
        } message: {
            Text(service.lastError ?? "")
        }
    }

    // MARK: - Pinned route header (groupRoute only)

    @ViewBuilder
    private func pinnedRouteHeader(route: Route) -> some View {
        NavigationLink {
            RouteDetailView(route: route)
        } label: {
            HStack(spacing: 0) {
                Image(systemName: "pin.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
                    .padding(.trailing, 6)
                RouteCard(route: route)
            }
            .background(Color(.secondarySystemBackground))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            NSLocalizedString("companion.chat.pinnedRoute.a11y", comment: "Pinned route header")
            + ": " + route.title
        )
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(service.messages) { msg in
                        ChatMessageRow(
                            message: msg,
                            isFromMe: msg.senderId == currentUserId,
                            isGroupRoute: isGroupRoute,
                            resolveURL: resolveAttachmentURL
                        )
                        .id(msg.id.rawValue)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: service.messages.count) { _, _ in
                if let last = service.messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id.rawValue, anchor: .bottom)
                    }
                }
            }
        }
    }

    /// Instagram-DM-style input bar — "+" attachment menu (photos / camera /
    /// files) + rounded text field + inline send. No mic (that's Voice Agent
    /// only). Shared with the Voice-Agent bar's picker plumbing via
    /// `AttachmentInputBar`; staged drafts live in `draftAttachments`.
    private var inputBar: some View {
        AttachmentInputBar(
            draftText: $inputText,
            attachments: $draftAttachments,
            isSending: service.isSending,
            placeholder: NSLocalizedString(
                "companion.chat.input.placeholder",
                comment: "Message input placeholder"
            )
        ) { trimmed in
            // Read staged drafts here (the bar clears them after this returns).
            let staged = draftAttachments
            Task { await service.send(trimmed, attachments: staged) }
        }
    }

    // MARK: - Helpers

    /// Resolve a persisted attachment to a signed download URL, delegating to
    /// the conversation's `ChatService`. Returns `nil` (placeholder) when the
    /// storage backend isn't deployed.
    private func resolveAttachmentURL(_ attachment: ChatAttachment) async -> URL? {
        await service.resolveAttachmentURL(attachment)
    }
}

// MARK: - ChatMessageRow

private struct ChatMessageRow: View {
    let message: ChatMessage
    let isFromMe: Bool
    var isGroupRoute: Bool = false
    /// Resolves a persisted attachment to a signed download URL (Phase D).
    let resolveURL: (ChatAttachment) async -> URL?

    @Environment(\.colorScheme) private var colorScheme

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private var showAvatar: Bool { isGroupRoute && !isFromMe }

    private var hasText: Bool {
        !message.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var attachments: [ChatAttachment] { message.attachments ?? [] }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isFromMe { Spacer(minLength: 60) }

            if showAvatar {
                avatarColumn
                    .padding(.trailing, 6)
            }

            VStack(alignment: isFromMe ? .trailing : .leading, spacing: 4) {
                if showAvatar {
                    Text(message.senderId)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                }

                // Text bubble — shown only when there's body text. Attachment-only
                // messages skip the empty bubble and render just the media.
                if hasText {
                    textBubble
                }

                if !attachments.isEmpty {
                    AttachmentBubble(attachments: attachments, resolveURL: resolveURL)
                }

                Text(formattedTime(message.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
            }

            if !isFromMe { Spacer(minLength: 60) }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isFromMe
                ? String(
                    format: NSLocalizedString("companion.chat.bubble.me.a11y", comment: "My message"),
                    message.body, formattedTime(message.createdAt)
                  )
                : String(
                    format: NSLocalizedString("companion.chat.bubble.them.a11y", comment: "Their message"),
                    message.body, formattedTime(message.createdAt)
                  )
        )
    }

    // MARK: - Bubble (unified Voice-Agent design language)

    /// Plain-text bubble matching `MessageBubble`'s tokens: 18pt continuous
    /// corners, 14×9 padding, CT.accent fill for my messages (white text) /
    /// surface fill for others (dark-aware), 0.5pt border, soft shadow.
    /// DM is human-to-human, so this stays plain `Text` (no Markdown).
    private var textBubble: some View {
        Text(message.body)
            .font(.body)
            .foregroundStyle(isFromMe ? Color.white : Color.primary)
            .textSelection(.enabled)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(bubbleFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(bubbleBorder, lineWidth: 0.5)
            )
            .shadow(
                color: Color.black.opacity(isFromMe ? 0.10 : 0.06),
                radius: isFromMe ? 6 : 4,
                x: 0,
                y: isFromMe ? 2 : 1
            )
    }

    /// User bubble = warm accent; other = white (light) / dark AI fill (dark),
    /// mirroring `MessageBubble.assistantFill`.
    private var bubbleFill: Color {
        if isFromMe { return CT.accent }
        return colorScheme == .dark ? CT.chatAIBubbleBgDark : CT.surfaceWhite
    }

    private var bubbleBorder: Color {
        if isFromMe { return CT.accentBorder }
        return colorScheme == .dark ? Color(.separator) : CT.borderSubtle
    }

    @ViewBuilder
    private var avatarColumn: some View {
        Circle()
            .fill(UserDirectory.color(forId: message.senderId))
            .frame(width: 22, height: 22)
            .overlay(
                Text(avatarInitial)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .alignmentGuide(.bottom) { $0[.bottom] }
    }

    /// First letter of the sender id, falling back to "?" so an empty/unknown
    /// id never renders a blank avatar.
    private var avatarInitial: String {
        let first = String(message.senderId.prefix(1)).uppercased()
        return first.isEmpty ? "?" : first
    }

    private func formattedTime(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: iso) {
            return Self.timeFormatter.string(from: date)
        }
        // Fallback without fractional seconds
        let f2 = ISO8601DateFormatter()
        guard let date = f2.date(from: iso) else { return "" }
        return Self.timeFormatter.string(from: date)
    }
}

// MARK: - Preview

#Preview("Chat — one-on-one") {
    let conv = Conversation.sample
    let service = ChatService(conversationId: conv.id)
    service.messages = [
        ChatMessage(
            id: ChatMessageId(rawValue: "m1"),
            conversationId: conv.id,
            senderId: "user_preview",
            body: "Hey! Excited to explore Tokyo together.",
            createdAt: "2026-02-05T14:00:00Z"
        ),
        ChatMessage(
            id: ChatMessageId(rawValue: "m2"),
            conversationId: conv.id,
            senderId: "user_preview_b",
            body: "Same! Any hidden coffee spots on your list?",
            createdAt: "2026-02-05T14:01:00Z"
        ),
        ChatMessage(
            id: ChatMessageId(rawValue: "m3"),
            conversationId: conv.id,
            senderId: "user_preview",
            body: "Definitely. I have a few marked — let's compare notes.",
            createdAt: "2026-02-05T14:02:00Z"
        ),
        ChatMessage(
            id: ChatMessageId(rawValue: "m4"),
            conversationId: conv.id,
            senderId: "user_preview",
            body: "Here's my shortlist.",
            attachments: [
                ChatAttachment(
                    id: "att_preview_1",
                    kind: .file,
                    fileName: "tokyo-coffee.pdf",
                    mimeType: "application/pdf",
                    fileSizeBytes: 820_000,
                    storagePath: "conv/m4/att_preview_1-tokyo-coffee.pdf"
                )
            ],
            createdAt: "2026-02-05T14:03:00Z"
        ),
    ]
    return NavigationStack {
        ChatView(conversation: conv, currentUserId: "user_preview")
    }
}

#Preview("Chat — group route") {
    let conv = Conversation.groupRouteSample
    let service = ChatService(conversationId: conv.id)
    service.messages = [
        ChatMessage(
            id: ChatMessageId(rawValue: "gm1"),
            conversationId: conv.id,
            senderId: "maya",
            body: "Everyone good to meet at 7am by the river?",
            createdAt: "2026-02-06T09:00:00Z"
        ),
        ChatMessage(
            id: ChatMessageId(rawValue: "gm2"),
            conversationId: conv.id,
            senderId: "user_preview",
            body: "Works for me!",
            createdAt: "2026-02-06T09:01:00Z"
        ),
        ChatMessage(
            id: ChatMessageId(rawValue: "gm3"),
            conversationId: conv.id,
            senderId: "user_preview_c",
            body: "Same. Should I bring the portable speaker?",
            createdAt: "2026-02-06T09:02:00Z"
        ),
    ]
    return NavigationStack {
        ChatView(conversation: conv, currentUserId: "user_preview")
    }
}

#Preview("Empty") {
    NavigationStack {
        ChatView(conversation: .sample, currentUserId: "user_preview")
    }
}
