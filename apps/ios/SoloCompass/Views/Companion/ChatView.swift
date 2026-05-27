import SwiftUI

/// Full-screen chat view for a companion conversation (US-013).
///
/// Shows message bubbles sorted by `sent_at`. Subscribes to Supabase
/// Realtime via `ChatService` so new messages appear without polling.
/// Only conversation participants can read/write — enforced by RLS.
public struct ChatView: View {
    let conversation: Conversation

    @Environment(\.dismiss) private var dismiss
    @State private var service: ChatService
    @State private var inputText = ""
    @State private var showingReportSheet = false
    @FocusState private var inputFocused: Bool

    private let currentUserId: String?
    /// The other participant's user ID (used for report/block).
    private let otherUserId: String?

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
            messageList
            Divider()
            inputBar
        }
        .navigationTitle(NSLocalizedString("companion.chat.title", comment: "Chat nav title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let otherId = otherUserId {
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

    // MARK: - Subviews

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(service.messages) { msg in
                        ChatMessageRow(
                            message: msg,
                            isFromMe: msg.senderId == currentUserId
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

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(
                NSLocalizedString("companion.chat.input.placeholder", comment: "Message input placeholder"),
                text: $inputText,
                axis: .vertical
            )
            .lineLimit(1...5)
            .focused($inputFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemBackground))
            )
            .accessibilityLabel(NSLocalizedString("companion.chat.input.a11y", comment: "Message input accessibility"))

            Button {
                Task { await submitMessage() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
            }
            .disabled(!canSend)
            .accessibilityLabel(NSLocalizedString("companion.chat.send.a11y", comment: "Send message"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !service.isSending
    }

    private func submitMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        await service.send(text)
    }
}

// MARK: - ChatMessageRow

private struct ChatMessageRow: View {
    let message: ChatMessage
    let isFromMe: Bool

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            if isFromMe { Spacer(minLength: 60) }

            VStack(alignment: isFromMe ? .trailing : .leading, spacing: 2) {
                Text(message.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isFromMe ? Color.accentColor : Color(.secondarySystemBackground))
                    )
                    .foregroundStyle(isFromMe ? Color.white : Color.primary)
                    .textSelection(.enabled)

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

#Preview("Chat") {
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
