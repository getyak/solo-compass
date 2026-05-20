import SwiftUI

/// Multi-turn voice agent conversation surface.
///
/// Renders the session message history with streaming text and tool-call
/// chips. The orchestrator drives the session; this view only emits
/// `onClose` and `onSubmitText(_:)` intents.
public struct ConversationSheet: View {
    @Environment(VoiceAgentSession.self) private var session

    public var onClose: () -> Void
    public var onSubmitText: (String) -> Void
    public var voiceService: VoiceService?
    public var onVoiceTranscript: (String) -> Void

    /// Optional — when provided, streaming text and thinking step are
    /// shown inline so the user sees word-by-word output.
    public var orchestrator: VoiceAgentOrchestrator?

    @State private var textDraft: String = ""
    @State private var isRecording = false
    @State private var liveTranscript: String = ""
    @State private var voiceStreamTask: Task<Void, Never>?

    public init(
        onClose: @escaping () -> Void = {},
        onSubmitText: @escaping (String) -> Void = { _ in },
        voiceService: VoiceService? = nil,
        onVoiceTranscript: @escaping (String) -> Void = { _ in },
        orchestrator: VoiceAgentOrchestrator? = nil
    ) {
        self.onClose = onClose
        self.onSubmitText = onSubmitText
        self.voiceService = voiceService
        self.onVoiceTranscript = onVoiceTranscript
        self.orchestrator = orchestrator
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
        case .thinking:
            let step = orchestrator?.thinkingStep ?? ""
            return step.isEmpty ? NSLocalizedString("conversation.state.thinking", comment: "") : step
        case .toolExecuting:
            let step = orchestrator?.thinkingStep ?? ""
            return step.isEmpty ? NSLocalizedString("conversation.state.toolExecuting", comment: "") : step
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

    // MARK: - Helpers

    private var isAgentActive: Bool {
        switch session.state {
        case .thinking, .toolExecuting: return true
        default: return false
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

                    // Thinking step chip shown while model is working
                    if let step = orchestrator?.thinkingStep, !step.isEmpty, isAgentActive {
                        thinkingChip(step)
                            .id("thinkingChip")
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.9, anchor: .leading)),
                                removal: .opacity
                            ))
                    } else if session.state == .thinking && orchestrator == nil {
                        thinkingBubble.id("thinking")
                            .transition(.opacity)
                    }

                    // Streaming assistant response word-by-word
                    if let content = orchestrator?.streamingContent, !content.isEmpty {
                        HStack {
                            streamingBubble(content)
                            Spacer(minLength: 40)
                        }
                        .id("streaming")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .onChange(of: session.messages.count) {
                withAnimation(.easeOut(duration: 0.18)) {
                    if let last = session.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: orchestrator?.thinkingStep) { _, _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    proxy.scrollTo("thinkingChip", anchor: .bottom)
                }
            }
            .onChange(of: orchestrator?.streamingContent) { _, _ in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo("streaming", anchor: .bottom)
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

    private func streamingBubble(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground).opacity(0.85),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .bottomTrailing) {
                // Blinking cursor indicator
                Rectangle()
                    .fill(Color.primary.opacity(0.5))
                    .frame(width: 2, height: 12)
                    .padding(.trailing, 10)
                    .padding(.bottom, 10)
            }
            .accessibilityIdentifier("streamingBubble")
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

    private func thinkingChip(_ label: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemBackground), in: Capsule())
        .transition(.opacity)
    }

    private var thinkingBubble: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(NSLocalizedString("conversation.state.thinking", comment: ""))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

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
            Image(systemName: isRecording ? "waveform" : "mic.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(isRecording ? Color.red : Color.accentColor)
                .symbolEffect(.variableColor.iterative, isActive: isRecording)
                .accessibilityIdentifier("conversationMicButton")
                .accessibilityLabel(NSLocalizedString("conversation.input.mic.a11y", comment: ""))
                .gesture(
                    LongPressGesture(minimumDuration: 0.2)
                        .onEnded { _ in startVoiceRecording() }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { _ in if isRecording { stopVoiceRecording() } }
                )

            VStack(alignment: .leading, spacing: 2) {
                if isRecording, !liveTranscript.isEmpty {
                    Text(liveTranscript)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .transition(.opacity)
                }
                TextField(
                    NSLocalizedString("conversation.input.placeholder", comment: ""),
                    text: $textDraft,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .submitLabel(.send)
                .onSubmit { submitText() }
            }

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

    // MARK: - Voice recording

    private func startVoiceRecording() {
        guard let svc = voiceService, !isRecording else { return }
        Task {
            let granted = await svc.requestPermission()
            guard granted else { return }
            do {
                isRecording = true
                liveTranscript = ""
                let stream = try svc.startListening()
                voiceStreamTask = Task {
                    do {
                        for try await text in stream {
                            await MainActor.run { liveTranscript = text }
                        }
                    } catch {
                        await MainActor.run { isRecording = false }
                    }
                }
            } catch {
                isRecording = false
            }
        }
    }

    private func stopVoiceRecording() {
        guard let svc = voiceService, isRecording else { return }
        svc.stopListening()
        isRecording = false
        voiceStreamTask?.cancel()
        voiceStreamTask = nil
        let final = liveTranscript
        liveTranscript = ""
        if !final.isEmpty {
            onVoiceTranscript(final)
        }
    }

    private func submitText() {
        let trimmed = textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmitText(trimmed)
        textDraft = ""
    }
}

// MARK: - Previews

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
