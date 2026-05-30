import SwiftUI

/// Messenger-style chat sheet — single entry point for talking to the Solo
/// Compass agent. Replaces the legacy `PlusMenuSheet` + `VoiceAgentInlineOverlay`
/// two-mode mess.
///
/// Lifecycle:
///  1. Parent creates a `VoiceAgentOrchestrator`, calls `start()`, then
///     presents this view in a `.sheet`.
///  2. If `startInVoiceMode == true`, the input bar arms the mic on appear
///     (same path as long-press push-to-talk).
///  3. Closing the sheet calls `onDismiss`, which the parent uses to stop
///     and discard the orchestrator.
///
/// State (history, streaming text, error banner, mic state) is read directly
/// off the `@Observable` orchestrator — no duplicated mirror state.
@MainActor
public struct ChatSheet: View {
    @Bindable public var orchestrator: VoiceAgentOrchestrator
    public let voiceService: VoiceService
    public let startInVoiceMode: Bool
    public let onDismiss: () -> Void

    @State private var draftText: String = ""
    @State private var liveTranscript: String = ""
    @State private var voiceStreamTask: Task<Void, Never>? = nil
    @State private var permissionDenied: Bool = false
    @State private var lastUserTranscript: String = ""
    @State private var didApplyStartMode: Bool = false
    /// Transient hint shown above the input bar when a send was rejected
    /// (orchestrator not yet seeded, session ended, unconfigured key, …).
    /// Auto-clears on the next successful send or after a short delay.
    @State private var sendHint: String? = nil
    @State private var sendHintTask: Task<Void, Never>? = nil
    /// US-027: transient, dismissible toast surfaced when the voice recording
    /// stream ends via an error (mic revoked mid-record, audio session
    /// interruption, recognizer failure) instead of silently dropping the
    /// transcript. Carries the localized `voice.interrupted` copy interpolated
    /// with the underlying error description. Auto-clears after a short delay.
    @State private var voiceInterruptionToast: String? = nil
    @State private var voiceInterruptionTask: Task<Void, Never>? = nil

    /// True while showing the dedicated voice surface (large mic + live agent
    /// state). Set on appear when `startInVoiceMode`; user can opt into the
    /// classic chat list with a single tap.
    @State private var showVoiceSurface: Bool = false
    @State private var starterPromptsAppeared: Bool = false

    private static let starterPrompts: [String] = [
        NSLocalizedString("chat.empty.prompt.nearby",  comment: "Starter chip — what's good around me"),
        NSLocalizedString("chat.empty.prompt.coffee",  comment: "Starter chip — find a quiet café"),
        NSLocalizedString("chat.empty.prompt.evening", comment: "Starter chip — plan my evening"),
    ]

    public init(
        orchestrator: VoiceAgentOrchestrator,
        voiceService: VoiceService,
        startInVoiceMode: Bool,
        onDismiss: @escaping () -> Void
    ) {
        self.orchestrator = orchestrator
        self.voiceService = voiceService
        self.startInVoiceMode = startInVoiceMode
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)

            if permissionDenied {
                permissionDeniedBanner
            }

            if let toast = voiceInterruptionToast {
                voiceInterruptionBanner(toast)
            }

            mainContent
        }
        .background(Color(.systemBackground))
        .onAppear { applyStartModeIfNeeded() }
        .onDisappear { teardownVoiceStream() }
        .onChange(of: orchestrator.session.messages.count) { _, _ in
            handleMessageCountChange()
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if showVoiceSurface {
            voiceSurface
        } else {
            messageList
            VStack(spacing: 0) {
                if orchestrator.uiState == .unconfigured {
                    unconfiguredBanner
                }
                if let hint = sendHint {
                    sendHintBanner(hint)
                }
                textInputBar
            }
        }
    }

    private var textInputBar: some View {
        ChatInputBar(
            draftText: $draftText,
            micState: micState,
            errorMessage: orchestrator.errorMessage,
            onSend: handleSend,
            onMicToggle: handleMicToggle,
            onMicPress: handleMicPress,
            onRetry: handleRetry
        )
    }

    /// Inline amber card surfaced when the orchestrator started in the
    /// `.unconfigured` state (no DeepSeek key and no Edge proxy). Without it
    /// the user can type, hit send, and get no reaction at all.
    private var unconfiguredBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString(
                    "chat.unconfigured.title",
                    comment: "Title shown when no AI key is configured"
                ))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                Text(NSLocalizedString(
                    "chat.unconfigured.subtitle",
                    comment: "Subtitle explaining the user needs to add a key"
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Slim transient banner used to surface non-fatal send failures (e.g.
    /// the orchestrator is still seeding the system prompt). Pinned above
    /// the input bar so the user sees it without losing the text field.
    private func sendHintBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.tint)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// First real user/assistant message → drop the voice surface so the
    /// chat history takes over. Tool-only messages don't count.
    private func handleMessageCountChange() {
        guard showVoiceSurface else { return }
        let hasConversation = orchestrator.session.messages.contains { msg in
            let role = msg.role
            return role == .user || role == .assistant
        }
        guard hasConversation else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            showVoiceSurface = false
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Text(NSLocalizedString("chat.title", comment: "Chat title — Solo Compass"))
                .font(.headline)
            Spacer()
            Button(action: closeSheet) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(NSLocalizedString("common.close", comment: "Close")))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var permissionDeniedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.slash.fill")
                .foregroundStyle(.orange)
            Text(NSLocalizedString("voiceAgent.permissionDenied", comment: "Microphone access needed — enable in Settings"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
            Spacer()
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text(NSLocalizedString("common.settings", comment: "Settings"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// US-027: dismissible toast surfaced when the live voice stream ends via an
    /// error instead of being silently dropped. Tappable / has an explicit
    /// close affordance, and auto-dismisses after a few seconds.
    private func voiceInterruptionBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.slash")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(3)
            Spacer(minLength: 4)
            Button(action: dismissVoiceInterruptionToast) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(NSLocalizedString("common.dismiss", comment: "Dismiss")))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder
    private var messageList: some View {
        if visibleMessages.isEmpty && orchestrator.streamingContent.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(visibleMessages) { msg in
                            MessageBubble(
                                role: msg.role,
                                text: msg.content ?? "",
                                toolName: msg.name,
                                isStreaming: false
                            )
                            .id(msg.id)
                        }

                        if !orchestrator.streamingContent.isEmpty {
                            MessageBubble(
                                role: .assistant,
                                text: orchestrator.streamingContent,
                                isStreaming: true
                            )
                            .id(Self.streamingBubbleID)
                        }

                        if !liveTranscript.isEmpty {
                            // Mirror the live transcript as a tentative
                            // user bubble so the chat shows what's being
                            // captured in real time.
                            MessageBubble(
                                role: .user,
                                text: liveTranscript
                            )
                            .id(Self.liveTranscriptID)
                            .opacity(0.6)
                        }

                        if isAgentWorking {
                            TypingIndicatorBubble(
                                label: orchestrator.thinkingStep.isEmpty ? nil : orchestrator.thinkingStep
                            )
                            .id(Self.typingIndicatorID)
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.2), value: isAgentWorking)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomAnchorID)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: visibleMessages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: orchestrator.streamingContent) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: liveTranscript) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: orchestrator.session.state) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onAppear { scrollToBottom(proxy: proxy, animated: false) }
            }
        }
    }

    /// Voice-first surface shown when the user taps "+" (short-tap entry).
    /// Renders a large mic + live agent state so the user can see that mic,
    /// model, and tools are all really running.
    private var voiceSurface: some View {
        ZStack {
            // US-017: Live waveform background visible while listening
            if voiceService.isListening {
                VoiceWaveformView(amplitude: voiceService.amplitude)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: voiceService.isListening)
            }

            VStack(spacing: 22) {
            Spacer(minLength: 12)

            voiceStatusLabel
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)

            if !orchestrator.streamingContent.isEmpty {
                Text(orchestrator.streamingContent)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(.opacity)
            } else if !liveTranscript.isEmpty {
                Text(liveTranscript)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Spacer(minLength: 8)

            VoiceMicButton(
                isListening: voiceService.isListening,
                isBusy: micState == .thinking,
                onPress: { handleMicPress(true) },
                onRelease: { handleMicPress(false) }
            )
            .padding(.bottom, 12)

            Button(action: switchToTextMode) {
                Text(NSLocalizedString("chat.voice.tap.toType", comment: "Switch to typing"))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.tint)
            }
            .padding(.bottom, 24)

            if let err = orchestrator.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
            } // end inner VStack
        }   // end ZStack
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Big status label that mirrors the orchestrator's real-time progress.
    /// We prefer `thinkingStep` (already-localized strings the orchestrator
    /// publishes) so tool execution shows "🔍 Searching nearby…" etc.
    private var voiceStatusLabel: some View {
        let text: String = {
            if voiceService.isListening {
                return NSLocalizedString("chat.voice.listening", comment: "Listening")
            }
            if orchestrator.isExecutingTool {
                return orchestrator.thinkingStep.isEmpty
                    ? NSLocalizedString("chat.voice.toolRunning", comment: "Working on it")
                    : orchestrator.thinkingStep
            }
            switch orchestrator.session.state {
            case .thinking:
                return NSLocalizedString("chat.voice.thinking", comment: "Thinking")
            case .toolExecuting:
                return orchestrator.thinkingStep.isEmpty
                    ? NSLocalizedString("chat.voice.toolRunning", comment: "Working on it")
                    : orchestrator.thinkingStep
            default:
                if !orchestrator.streamingContent.isEmpty {
                    return NSLocalizedString("chat.voice.responding", comment: "Responding")
                }
                return NSLocalizedString("chat.voice.idle", comment: "Hold the mic to speak")
            }
        }()
        return Text(text)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .animation(.easeInOut(duration: 0.2), value: text)
    }

    private func switchToTextMode() {
        // Drop the voice stream cleanly before swapping surfaces so the
        // mic doesn't keep listening while the keyboard appears.
        teardownVoiceStream()
        withAnimation(.easeInOut(duration: 0.2)) {
            showVoiceSurface = false
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("chat.empty.title", comment: "Ask me anything about places near you"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text(NSLocalizedString("chat.empty.subtitle", comment: "Try ‘what’s good around me?’ or hold the mic to talk."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            starterPromptChips
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.15)) {
                starterPromptsAppeared = true
            }
        }
    }

    private var starterPromptChips: some View {
        VStack(spacing: 8) {
            ForEach(Array(Self.starterPrompts.enumerated()), id: \.offset) { index, prompt in
                Button {
                    Haptics.impact(.light)
                    handleSend(prompt)
                } label: {
                    Text(prompt)
                        .font(.body)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(prompt)
                .opacity(starterPromptsAppeared ? 1 : 0)
                .offset(y: starterPromptsAppeared ? 0 : 8)
                .animation(
                    .easeOut(duration: 0.35).delay(Double(index) * 0.08),
                    value: starterPromptsAppeared
                )
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 4)
    }

    // MARK: - Derived state

    /// Messages with the system row hidden. Tool rows are kept so the user
    /// can see "Searched nearby" indicators inline with the conversation.
    private var visibleMessages: [VoiceAgentSession.Message] {
        orchestrator.session.messages.filter { $0.role != .system }
    }

    /// True while the agent is thinking or executing a tool but no streamed
    /// text or live voice transcript has arrived yet.
    private var isAgentWorking: Bool {
        let state = orchestrator.session.state
        let agentBusy: Bool
        switch state {
        case .thinking, .toolExecuting:
            agentBusy = true
        default:
            agentBusy = orchestrator.isExecutingTool
        }
        return agentBusy
            && orchestrator.streamingContent.isEmpty
            && liveTranscript.isEmpty
    }

    private var micState: ChatInputBar.MicState {
        if orchestrator.errorMessage != nil {
            return .error
        }
        if voiceService.isListening {
            return .listening
        }
        switch orchestrator.session.state {
        case .thinking, .toolExecuting:
            return .thinking
        default:
            return orchestrator.isExecutingTool ? .thinking : .idle
        }
    }

    // MARK: - Actions

    private func handleSend(_ text: String) {
        lastUserTranscript = text
        let outcome = orchestrator.handleTextInput(text)
        switch outcome {
        case .accepted:
            clearSendHint()
            Haptics.impact(.light)
        case .empty:
            // The input bar already guards on empty; nothing to do.
            break
        case .unconfigured:
            showSendHint(
                NSLocalizedString(
                    "chat.send.hint.unconfigured",
                    comment: "Hint shown when the user tries to send but no API key is configured"
                ),
                restoreDraft: text
            )
        case .notReady:
            // Orchestrator is mid-seed (start() is async). Restore the draft
            // so the user doesn't lose it, and prompt them to try again.
            showSendHint(
                NSLocalizedString(
                    "chat.send.hint.notReady",
                    comment: "Hint shown when the user sends before the agent finished waking up"
                ),
                restoreDraft: text
            )
        case .sessionEnded:
            // The previous turn ended (timeout/error). Soft-restart and
            // re-submit transparently so the user sees their message land.
            if orchestrator.restartIfNeeded(),
               orchestrator.handleTextInput(text) == .accepted {
                clearSendHint()
                Haptics.impact(.light)
            } else {
                showSendHint(
                    NSLocalizedString(
                        "chat.send.hint.sessionEnded",
                        comment: "Hint shown when the chat session ended and a new turn couldn't be started"
                    ),
                    restoreDraft: text
                )
            }
        }
    }

    private func showSendHint(_ message: String, restoreDraft: String? = nil) {
        if let restoreDraft, draftText.isEmpty {
            draftText = restoreDraft
        }
        sendHint = message
        sendHintTask?.cancel()
        sendHintTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            if !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.2)) { sendHint = nil }
            }
        }
    }

    private func clearSendHint() {
        sendHintTask?.cancel()
        sendHintTask = nil
        if sendHint != nil {
            withAnimation(.easeOut(duration: 0.2)) { sendHint = nil }
        }
    }

    private func handleMicToggle(_ start: Bool) {
        if start {
            beginPushToTalk()
        } else {
            endPushToTalk(send: true)
        }
    }

    /// Push-to-talk path. `pressing == true` on touch-down, `false` on
    /// release. Starts/stops the voice stream immediately for sub-frame
    /// feedback.
    private func handleMicPress(_ pressing: Bool) {
        if pressing {
            // Only treat as PTT-start if not already listening (avoids
            // double-start with the simultaneous tap gesture).
            if !voiceService.isListening {
                beginPushToTalk()
            }
        } else {
            if voiceService.isListening {
                endPushToTalk(send: true)
            }
        }
    }

    private func handleRetry() {
        guard !lastUserTranscript.isEmpty else { return }
        // The previous turn may have ended (timeout/network error). Re-arm
        // the orchestrator first so the retry isn't silently dropped by the
        // `session.isEnded` guard in handleTextInput.
        _ = orchestrator.restartIfNeeded()
        handleSend(lastUserTranscript)
    }

    private func closeSheet() {
        teardownVoiceStream()
        onDismiss()
    }

    // MARK: - Voice handling

    private func applyStartModeIfNeeded() {
        guard !didApplyStartMode else { return }
        didApplyStartMode = true
        if startInVoiceMode {
            showVoiceSurface = true
            beginPushToTalk()
        }
    }

    private func beginPushToTalk() {
        guard !voiceService.isListening else { return }
        Task { @MainActor in
            let granted = await voiceService.requestPermission()
            guard granted else {
                withAnimation(.easeInOut(duration: 0.2)) { permissionDenied = true }
                return
            }
            withAnimation { permissionDenied = false }
            do {
                liveTranscript = ""
                let stream = try voiceService.startListening()
                Haptics.impact(.light)
                voiceStreamTask = Task { @MainActor in
                    do {
                        for try await text in stream {
                            liveTranscript = text
                        }
                    } catch is CancellationError {
                        // Deliberate stop (endPushToTalk / teardown cancels the
                        // task) — not an interruption, stay silent.
                    } catch {
                        // Stream ended via error (mic revoked mid-record, audio
                        // session interruption, recognizer failure). US-027:
                        // surface it as a dismissible toast instead of silently
                        // stopping, so the user knows recording was interrupted.
                        showVoiceInterruptionToast(for: error)
                    }
                }
            } catch {
                voiceService.stopListening()
            }
        }
    }

    private func endPushToTalk(send: Bool) {
        voiceService.stopListening()
        voiceStreamTask?.cancel()
        voiceStreamTask = nil
        let final = liveTranscript
        liveTranscript = ""
        guard send, !final.isEmpty else { return }
        lastUserTranscript = final
        orchestrator.handleTranscript(final)
        Haptics.impact(.light)
    }

    private func teardownVoiceStream() {
        voiceStreamTask?.cancel()
        voiceStreamTask = nil
        sendHintTask?.cancel()
        sendHintTask = nil
        sendHint = nil
        voiceInterruptionTask?.cancel()
        voiceInterruptionTask = nil
        voiceInterruptionToast = nil
        if voiceService.isListening {
            voiceService.stopListening()
        }
        liveTranscript = ""
    }

    // MARK: - Voice interruption toast (US-027)

    /// Localized toast copy for an interrupted voice recording. Pulled out as a
    /// pure static so it can be unit-tested without driving the live audio
    /// stream (mirrors `VoiceProcessingToast.localizedText(for:)`).
    static func voiceInterruptionToastText(for error: Error) -> String {
        let format = NSLocalizedString(
            "voice.interrupted",
            comment: "Toast shown when voice recording is interrupted; %@ is the underlying error"
        )
        return String(format: format, error.localizedDescription)
    }

    private func showVoiceInterruptionToast(for error: Error) {
        let text = Self.voiceInterruptionToastText(for: error)
        liveTranscript = ""
        withAnimation(.easeInOut(duration: 0.2)) {
            voiceInterruptionToast = text
        }
        voiceInterruptionTask?.cancel()
        voiceInterruptionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                voiceInterruptionToast = nil
            }
        }
    }

    private func dismissVoiceInterruptionToast() {
        voiceInterruptionTask?.cancel()
        voiceInterruptionTask = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            voiceInterruptionToast = nil
        }
    }

    // MARK: - Scroll helpers

    private static let bottomAnchorID = "chat.bottom"
    private static let streamingBubbleID = "chat.streaming"
    private static let liveTranscriptID = "chat.liveTranscript"
    private static let typingIndicatorID = "chat.typing"

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        let anchor = Self.bottomAnchorID
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(anchor, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(anchor, anchor: .bottom)
        }
    }
}

/// Large central mic for the voice-first surface. Holds-to-talk and shows a
/// pulsing ring while listening / a spinner while the agent is busy. Mirrors
/// the affordance of `PlusActionButton` but stays put inside the sheet.
@MainActor
private struct VoiceMicButton: View {
    let isListening: Bool
    let isBusy: Bool
    let onPress: () -> Void
    let onRelease: () -> Void

    @State private var pressed: Bool = false
    @State private var pulse: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.accentColor.opacity(isListening ? 0.55 : 0.0), lineWidth: 4)
                .frame(width: 132, height: 132)
                .scaleEffect(pulse ? 1.18 : 1.0)
                .opacity(pulse ? 0.0 : 1.0)
                .animation(
                    isListening
                        ? .easeOut(duration: 1.2).repeatForever(autoreverses: false)
                        : .default,
                    value: pulse
                )

            Circle()
                .fill(isListening ? Color.accentColor : Color.black.opacity(0.85))
                .frame(width: 108, height: 108)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                .scaleEffect(pressed ? 1.06 : 1.0)
                .overlay(
                    Group {
                        if isBusy {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 40, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                )
        }
        .contentShape(Circle())
        .onLongPressGesture(
            minimumDuration: 0,
            maximumDistance: .infinity,
            perform: { /* no-op: press/release handled by onPressingChanged */ },
            onPressingChanged: { pressing in
                if pressing {
                    pressed = true
                    pulse = true
                    onPress()
                } else {
                    pressed = false
                    pulse = false
                    onRelease()
                }
            }
        )
        .accessibilityLabel(Text(NSLocalizedString("voiceAgent.orb.a11y", comment: "Hold to speak to Solo Compass")))
        .accessibilityHint(Text(NSLocalizedString("voiceAgent.orb.hint", comment: "Double tap and hold to speak")))
    }
}

#Preview("Empty") {
    let orch = previewOrchestrator()
    return ChatSheet(
        orchestrator: orch,
        voiceService: VoiceService(),
        startInVoiceMode: false,
        onDismiss: {}
    )
}

#Preview("Unconfigured") {
    let orch = previewOrchestrator()
    orch.previewSetUnconfigured()
    return ChatSheet(
        orchestrator: orch,
        voiceService: VoiceService(),
        startInVoiceMode: false,
        onDismiss: {}
    )
}

#Preview("With history") {
    let orch = previewOrchestrator(seeded: true)
    return ChatSheet(
        orchestrator: orch,
        voiceService: VoiceService(),
        startInVoiceMode: false,
        onDismiss: {}
    )
}

@MainActor
private func previewOrchestrator(seeded: Bool = false) -> VoiceAgentOrchestrator {
    let orch = VoiceAgentOrchestrator(
        aiService: AIService(),
        voiceService: VoiceService(),
        mapViewModel: MapViewModel(
            locationService: LocationService.shared,
            experienceService: ExperienceService(),
            aiService: AIService(),
            preferences: UserPreferences()
        ),
        preferences: UserPreferences()
    )
    if seeded {
        orch.start()
        orch.handleTextInput("What's good around me?")
    }
    return orch
}
