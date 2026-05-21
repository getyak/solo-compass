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

    /// True while showing the dedicated voice surface (large mic + live agent
    /// state). Set on appear when `startInVoiceMode`; user can opt into the
    /// classic chat list with a single tap.
    @State private var showVoiceSurface: Bool = false

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
        // US-013: Unconfigured state shows a guidance card instead of chat
        if orchestrator.uiState == .unconfigured {
            unconfiguredCard
        } else if showVoiceSurface {
            voiceSurface
        } else {
            messageList
            textInputBar
        }
    }

    private var unconfiguredCard: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "key.slash")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)
                Text(NSLocalizedString("chat.unconfigured.title", comment: "AI not configured title"))
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                Text(NSLocalizedString("chat.unconfigured.body", comment: "AI not configured body"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text(NSLocalizedString("chat.unconfigured.cta", comment: "Open Settings"))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            Text(NSLocalizedString("chat.empty.subtitle", comment: "Try ‘what's good around me?’ or hold the mic to talk."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Derived state

    /// Messages with the system row hidden. Tool rows are kept so the user
    /// can see "Searched nearby" indicators inline with the conversation.
    private var visibleMessages: [VoiceAgentSession.Message] {
        orchestrator.session.messages.filter { $0.role != .system }
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
        orchestrator.handleTextInput(text)
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
        // Orchestrator clears errorMessage on next successful run; nudge it.
        orchestrator.handleTextInput(lastUserTranscript)
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
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                voiceStreamTask = Task { @MainActor in
                    do {
                        for try await text in stream {
                            liveTranscript = text
                        }
                    } catch {
                        // Stream ended via error — drop transcript silently;
                        // user-facing errors surface through orchestrator.errorMessage.
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
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func teardownVoiceStream() {
        voiceStreamTask?.cancel()
        voiceStreamTask = nil
        if voiceService.isListening {
            voiceService.stopListening()
        }
        liveTranscript = ""
    }

    // MARK: - Scroll helpers

    private static let bottomAnchorID = "chat.bottom"
    private static let streamingBubbleID = "chat.streaming"
    private static let liveTranscriptID = "chat.liveTranscript"

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
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressed {
                        pressed = true
                        pulse = true
                        onPress()
                    }
                }
                .onEnded { _ in
                    pressed = false
                    pulse = false
                    onRelease()
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
