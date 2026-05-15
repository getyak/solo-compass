import SwiftUI

/// Multi-turn voice agent conversation surface (US-VA-04).
///
/// Bound to a `VoiceAgentSession` from the environment. Renders:
/// - top status bar with turn count + close button
/// - scrollable message list (user right, assistant left, tool muted)
/// - bottom input row (mic + text field) — text input is wired here
///   but the mic gesture lands in US-VA-05.
///
/// The orchestrator (US-VA-06) drives the session; this view is read-only
/// for state and only emits two intents: `onClose` and `onSubmitText(_:)`.
public struct ConversationSheet: View {
    @Environment(VoiceAgentSession.self) private var session

    /// Called when the user dismisses the sheet (× button or down-drag).
    public var onClose: () -> Void

    /// Called when the user submits a typed message (the fallback path
    /// when voice isn't available or for accessibility).
    public var onSubmitText: (String) -> Void

    @State private var textDraft: String = ""

    public init(
        onClose: @escaping () -> Void = {},
        onSubmitText: @escaping (String) -> Void = { _ in }
    ) {
        self.onClose = onClose
        self.onSubmitText = onSubmitText
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messageList
            Divider()
            inputBar
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            statusDot
            VStack(alignment: .leading, spacing: 0) {
                Text(headerTitle)
                    .font(.subheadline.weight(.semibold))
                Text(stateLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("conversationStateLabel")
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(NSLocalizedString("common.close", comment: "Close"))
            .accessibilityIdentifier("conversationCloseButton")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var headerTitle: String {
        String(
            format: NSLocalizedString("conversation.header.turn", comment: "Conversation · turn %d"),
            max(session.turnCount, 1)
        )
    }

    private var stateLabel: String {
        switch session.state {
        case .idle:          return NSLocalizedString("conversation.state.idle", comment: "")
        case .listening:     return NSLocalizedString("conversation.state.listening", comment: "")
        case .transcribing:  return NSLocalizedString("conversation.state.transcribing", comment: "")
        case .thinking:      return NSLocalizedString("conversation.state.thinking", comment: "")
        case .toolExecuting: return NSLocalizedString("conversation.state.toolExecuting", comment: "")
        case .speaking:      return NSLocalizedString("conversation.state.speaking", comment: "")
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        switch session.state {
        case .idle:
            Image(systemName: "circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary.opacity(0.5))
        case .listening:
            Image(systemName: "mic.fill")
                .font(.system(size: 14))
                .foregroundStyle(.red)
        case .transcribing, .thinking:
            ProgressView().controlSize(.small)
        case .toolExecuting:
            Image(systemName: "gearshape.fill")
                .font(.system(size: 14))
                .foregroundStyle(.blue)
        case .speaking:
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 14))
                .foregroundStyle(.green)
        }
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(session.messages.filter { $0.role != .system }) { message in
                        messageRow(message)
                            .id(message.id)
                    }
                    if session.state == .thinking {
                        thinkingBubble.id("thinking")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .onChange(of: session.messages.count) {
                // Pin the most recent bubble in view as new content lands.
                if let last = session.messages.last {
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ msg: VoiceAgentSession.Message) -> some View {
        switch msg.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                userBubble(msg.content ?? "")
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                if let content = msg.content, !content.isEmpty {
                    HStack {
                        assistantBubble(content)
                        Spacer(minLength: 40)
                    }
                }
                ForEach(msg.toolCalls) { call in
                    toolCallChip(call)
                }
            }
        case .tool:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal")
                    .font(.caption2)
                Text(toolResultSummary(msg))
                    .font(.caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .padding(.leading, 8)
        case .system:
            EmptyView()
        }
    }

    private func userBubble(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
            .accessibilityIdentifier("userBubble")
    }

    private func assistantBubble(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("assistantBubble")
    }

    private func toolCallChip(_ call: VoiceAgentSession.ToolCall) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "gearshape.fill")
                .font(.caption2)
            Text(call.name)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemBackground), in: Capsule())
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("toolCallChip")
    }

    private var thinkingBubble: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(NSLocalizedString("conversation.state.thinking", comment: ""))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Short label for a tool-result row — we don't want to dump full
    /// JSON in the conversation view, so we strip to the most useful
    /// hint: either the tool's `name` field if present, or a count.
    private func toolResultSummary(_ msg: VoiceAgentSession.Message) -> String {
        let name = msg.name ?? "tool"
        if let content = msg.content,
           let data = content.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let ok = obj["ok"] as? Bool, !ok, let err = obj["error"] as? String {
                return "\(name): \(err)"
            }
            return name
        }
        return name
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            // Mic button — long-press gesture wiring lands in US-VA-05.
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
                .accessibilityIdentifier("conversationMicButton")
                .accessibilityLabel(NSLocalizedString("conversation.input.mic.a11y", comment: ""))

            TextField(
                NSLocalizedString("conversation.input.placeholder", comment: ""),
                text: $textDraft,
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...3)
            .submitLabel(.send)
            .onSubmit { submitText() }

            Button {
                submitText()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(textDraft.isEmpty ? Color.secondary : Color.accentColor)
            }
            .disabled(textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(NSLocalizedString("conversation.input.send.a11y", comment: ""))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func submitText() {
        let trimmed = textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmitText(trimmed)
        textDraft = ""
    }
}

// MARK: - Preview helpers
//
// PRD US-VA-04 DoD: three #Preview states (thinking, tool_executing, idle).

#Preview("idle (empty)") {
    let session = VoiceAgentSession()
    return ConversationSheet()
        .environment(session)
}

#Preview("thinking") {
    let session = VoiceAgentSession()
    session.seedSystem("system prompt")
    session.beginUserTurn(transcript: "Find me a quiet café in the old quarter.")
    return ConversationSheet()
        .environment(session)
}

#Preview("tool_executing") {
    let session = VoiceAgentSession()
    session.seedSystem("system prompt")
    session.beginUserTurn(transcript: "Filter to coffee, then show details for the closest one.")
    session.appendAssistantTurn(content: nil, toolCalls: [
        .init(id: "c1", name: "filter_by_category",
              argumentsJSON: #"{"category":"coffee"}"#),
        .init(id: "c2", name: "show_details",
              argumentsJSON: #"{"experience_id":"exp_demo"}"#),
    ])
    session.appendToolResult(toolCallId: "c1", name: "filter_by_category",
                             resultJSON: #"{"ok":true}"#)
    return ConversationSheet()
        .environment(session)
}
