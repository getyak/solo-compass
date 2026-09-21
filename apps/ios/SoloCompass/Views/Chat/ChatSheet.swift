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
    /// User tapped a place card in the chat — reveal it on the map. The chat is
    /// the only thing that moves the map here; the agent never does it for them.
    public let onSelectExperience: (Experience) -> Void
    /// User tapped "采用这条路线" on a proposed-route card — persist + open it.
    public let onAdoptRoute: (RouteProposal) -> Void
    /// City OS v2: user tapped "在地图上看" on an event card — dismiss the chat,
    /// recenter the map on the event, and highlight its marker.
    public let onShowEventOnMap: (CityEvent) -> Void

    /// The shared workspace state. Owns the panel detent, the draft, staged
    /// attachments and scroll intent, so collapsing to the map or opening
    /// discovery never drops the user's in-progress work. Injected — never
    /// defaulted — so the chat keeps one stable identity for the root's
    /// lifetime instead of being recreated per presentation.
    @Bindable public var workspace: ConversationWorkspaceState

    /// True when the chat lives inside the root conversation panel rather than
    /// its own modal sheet. Embedded chats swap the close glyph for a collapse
    /// chevron and are never asked to tear the orchestrator down.
    private let embedded: Bool

    /// Embedded mode: tapping the collapse chevron hands control back to the
    /// root, which drops the panel back onto the map.
    private let onCollapse: (() -> Void)?

    /// Optional history store. When wired, the header shows a clock button that
    /// opens saved conversations the user can reopen.
    private let historyStore: ChatHistoryStore?

    /// Resolves a persisted `scopedExperienceId` back to an `Experience` so a
    /// restored conversation reopens under the exact scope it was saved with.
    private let resolveExperience: ((String) -> Experience?)?

    /// True when the traveler has neither a city nor a GPS fix. Renders a modest
    /// "choose a city" chip in the empty conversation so location-dependent
    /// asks guide them to pick a city instead of guessing one.
    private let needsCitySelection: Bool
    private let onChooseCity: (() -> Void)?

    /// Optional first-turn seed. When non-nil, the sheet submits this string as
    /// the user's first message once the orchestrator finishes seeding. Used
    /// by the startup self-diagnostics bubble so the AI opens the conversation
    /// by explaining the detected issues instead of showing an empty state.
    private let initialUserPrompt: String?

    /// Guards against re-sending `initialUserPrompt` if `isSeeded` flips more
    /// than once in a session's lifetime.
    @State private var didSeedInitialPrompt: Bool = false

    @State private var showHistory: Bool = false
    @State private var liveTranscript: String = ""
    @State private var voiceStreamTask: Task<Void, Never>? = nil
    /// The in-flight microphone permission request. Cancelled (and its result
    /// ignored via `voiceGeneration`) if the panel hides, the app backgrounds,
    /// or the user releases before it resolves — so a late grant can never
    /// start a hidden recording.
    @State private var permissionTask: Task<Void, Never>? = nil
    /// Monotonic token guarding every async voice start against a teardown.
    @State private var voiceGeneration: Int = 0
    /// Bounded throttle for streaming scroll-follow. One scheduled trailing
    /// action per window — never a per-token debounce.
    @State private var followThrottle = ScrollFollowThrottle()
    /// Height of the message viewport, used to turn the bottom marker's content
    /// offset into a real "distance from the bottom".
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var scrollAnchor: UUID?
    /// Latest bottom-marker offset, re-evaluated when the viewport height changes.
    @State private var lastBottomMaxY: CGFloat = 0
    /// The keyboard's restore point: which detent to return to and the manual
    /// revision at the moment focus arrived. Captured once per focus session.
    @State private var keyboardRestore: ConversationWorkspaceState.KeyboardSnapshot?
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
    /// Drives the sun-gold pulse dot on the live-transcript bubble while the
    /// mic is hot. Toggled in begin/endPushToTalk; reduceMotion-guarded.
    @State private var recordingPulse: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Backgrounding the app must stop the mic + speech without discarding the
    /// conversation; this observes the transition.
    @Environment(\.scenePhase) private var scenePhase

    private static let starterPrompts: [String] = [
        NSLocalizedString("chat.empty.prompt.nearby",  comment: "Starter chip — what's good around me"),
        NSLocalizedString("chat.empty.prompt.coffee",  comment: "Starter chip — find a quiet café"),
        NSLocalizedString("chat.empty.prompt.events",  comment: "Starter chip — what's on this week"),
        NSLocalizedString("chat.empty.prompt.evening", comment: "Starter chip — plan my evening"),
    ]

    public init(
        orchestrator: VoiceAgentOrchestrator,
        voiceService: VoiceService,
        startInVoiceMode: Bool,
        onDismiss: @escaping () -> Void,
        onSelectExperience: @escaping (Experience) -> Void = { _ in },
        onAdoptRoute: @escaping (RouteProposal) -> Void = { _ in },
        onShowEventOnMap: @escaping (CityEvent) -> Void = { _ in },
        workspace: ConversationWorkspaceState,
        embedded: Bool = false,
        onCollapse: (() -> Void)? = nil,
        historyStore: ChatHistoryStore? = nil,
        resolveExperience: ((String) -> Experience?)? = nil,
        needsCitySelection: Bool = false,
        onChooseCity: (() -> Void)? = nil,
        initialUserPrompt: String? = nil
    ) {
        self.orchestrator = orchestrator
        self.voiceService = voiceService
        self.startInVoiceMode = startInVoiceMode
        self.onDismiss = onDismiss
        self.onSelectExperience = onSelectExperience
        self.onAdoptRoute = onAdoptRoute
        self.onShowEventOnMap = onShowEventOnMap
        self.workspace = workspace
        self.embedded = embedded
        self.onCollapse = onCollapse
        self.historyStore = historyStore
        self.resolveExperience = resolveExperience
        self.needsCitySelection = needsCitySelection
        self.onChooseCity = onChooseCity
        self.initialUserPrompt = initialUserPrompt
    }

    public var body: some View {
        VStack(spacing: 0) {
            // The chat is the whole surface — no titled header bar, no divider.
            // The old "Solo Compass" title + hairline read as a settings panel
            // grafted onto a conversation; the user asked for "全部都是聊天主体".
            // What remains is a chromeless control row: just the history +
            // collapse glyphs floating in the top corners over the message
            // stream. At the compact doorway height the controls ride anyway —
            // the composer below provides the sole input.
            if embedded || !workspace.isCompactConversation {
                minimalControls
            }

            if permissionDenied {
                permissionDeniedBanner
            }

            if let toast = voiceInterruptionToast {
                voiceInterruptionBanner(toast)
            }

            mainContent
        }
        .background(Color(.systemBackground))
        .accessibilityIdentifier(WorkspaceAccessibility.chat)
        .onAppear {
            applyStartModeIfNeeded()
            deliverPendingPromptIfNeeded()
            // A voice request raised before this chat mounted must still arm the
            // mic (the token change happened while the view was absent).
            if workspace.consumeVoiceStart() {
                showVoiceSurface = true
                beginPushToTalk()
            }
        }
        // Disappearing is the authoritative teardown: the surface-change
        // onChange may not fire before the subtree is removed, so this stops the
        // mic, the pending permission request, speech and the scroll jobs.
        .onDisappear { hibernateVoiceAndSpeech() }
        .onChange(of: orchestrator.session.transcript.count) { _, _ in
            handleMessageCountChange()
        }
        .onChange(of: orchestrator.uiState) { _, newState in
            handleUIStateChange(newState)
        }
        // Explicit asks (diagnostics seed, FilterBar "Ask Solo", place ask)
        // raised via the workspace token are delivered even when this chat was
        // already mounted — no duplicate submission, no missed event.
        .onChange(of: workspace.promptToken) { _, _ in
            deliverPendingPromptIfNeeded()
        }
        // Dock long-press: open the voice surface even though this chat may be
        // already mounted (startInVoiceMode is only read on first appear).
        .onChange(of: workspace.voiceStartToken) { _, _ in
            if workspace.consumeVoiceStart() {
                showVoiceSurface = true
                beginPushToTalk()
            }
        }
        // Collapsing onto the map, a real background transition, or a modal
        // covering the chat must stop the microphone and any speech output
        // immediately — never keep collecting audio behind a hidden panel. The
        // conversation and draft stay on the orchestrator/workspace.
        .onChange(of: workspace.showsConversation) { _, visible in
            if visible { resumeVoiceIfVisible() } else { hibernateVoiceAndSpeech() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { resumeVoiceIfVisible() } else { hibernateVoiceAndSpeech() }
        }
        // Modals (history, settings, detail, routes, profile) raised by the root
        // ask the chat to hibernate without ending it.
        .onChange(of: workspace.hibernationToken) { _, _ in
            hibernateVoiceAndSpeech()
        }
        .onChange(of: showHistory) { _, shown in
            if shown {
                hibernateVoiceAndSpeech()
            } else {
                // Closing history restores eligibility to speak but must not
                // start any audio on its own.
                resumeVoiceIfVisible()
            }
        }
        // A truthful keyboard signal: while the software keyboard is on screen
        // the panel drops the dock so the composer sits just above the keyboard.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            workspace.setSoftwareKeyboardVisible(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            workspace.setSoftwareKeyboardVisible(false)
        }
        .sheet(isPresented: $showHistory) {
            if let historyStore {
                ChatHistoryListView(
                    store: historyStore,
                    onSelect: { sessionId, messages, scopedExperienceId in
                        restoreConversation(
                            id: sessionId,
                            messages: messages,
                            scopedExperienceId: scopedExperienceId
                        )
                    },
                    onDismiss: { showHistory = false }
                )
            }
        }
    }

    /// Reopen a saved conversation in the live orchestrator, then close the
    /// history sheet. Persist the current (possibly in-progress) conversation
    /// first so switching away doesn't lose it. The orchestrator owns the
    /// re-seed + replay so ordering stays [system, ...restored], and receives
    /// the record's own scope so a place chat reopens as a place chat.
    private func restoreConversation(
        id: String,
        messages: [VoiceAgentSession.Message],
        scopedExperienceId: String?
    ) {
        orchestrator.persistConversation()
        let scoped = scopedExperienceId.flatMap { resolveExperience?($0) }
        orchestrator.restoreConversation(
            id: id,
            messages: messages,
            scopedExperience: scoped
        )
        // A restored conversation opens at its latest turn and drops any anchor
        // from the previous conversation.
        workspace.beginFollowing()
        showHistory = false
        showVoiceSurface = false
    }

    /// While the agent is thinking or streaming a reply, offer the panel more
    /// room — but only when the user is already in the chat and has not pinned a
    /// detent. This must never yank someone back from the map or from a
    /// deliberately chosen half height, and it must not fight a drag.
    private func handleUIStateChange(_ state: ChatUIState) {
        switch state {
        case .processing, .responding:
            workspace.autoExpandWhileWorking()
        default:
            break
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
            draftText: $workspace.draftText,
            attachments: $workspace.attachments,
            micState: micState,
            errorMessage: orchestrator.errorMessage,
            // When the chat was opened from a place's "Ask Solo", surface that
            // anchor visibly: a dismissable "Asking about <name>" pill rides
            // above the composer and the field placeholder shifts to the place.
            // The orchestrator already injects the place into its system scope;
            // this is the UI making that scope legible (handoff `.ai-ctx-chip`).
            placeContextName: scopedPlaceName,
            placeContextColor: orchestrator.scopedExperience?.category.color,
            onFocusChange: handleComposerFocusChange,
            resignFocus: workspace.surface != .ask,
            onSend: handleSend,
            onMicToggle: handleMicToggle,
            onMicPress: handleMicPress,
            onRetry: handleRetry,
            // Clearing the pill drops the anchor back to a global chat. We route
            // through the orchestrator so the system scope and the UI fall back
            // together, then animate the pill/placeholder back to generic copy.
            onClearContext: scopedPlaceName == nil ? nil : {
                withAnimation(.easeInOut(duration: 0.22)) {
                    orchestrator.clearContext()
                }
            }
        )
        .accessibilityIdentifier(WorkspaceAccessibility.composer)
    }

    /// Short display name of the place this chat is anchored to, or `nil` for
    /// the global "+" chat. Drives the composer context pill, the placeholder,
    /// and the hero card title. Prefers a real place name (romanized / local
    /// script) over the experience's long descriptive `title` so the pill reads
    /// "Asking about Wat Suandok", not a truncated sentence.
    private var scopedPlaceName: String? {
        orchestrator.scopedExperience.map(\.shortName)
    }

    static func shortName(_ place: Experience) -> String {
        place.shortName
    }

    /// Inline card surfaced when the orchestrator started in the
    /// `.unconfigured` state (no DeepSeek key and no Edge proxy). Without it
    /// the user can type, hit send, and get no reaction at all.
    private var unconfiguredBanner: some View {
        InlineBanner(
            tone: .permission,
            title: NSLocalizedString(
                "chat.unconfigured.title",
                comment: "Title shown when no AI key is configured"
            ),
            subtitle: NSLocalizedString(
                "chat.unconfigured.subtitle",
                comment: "Subtitle explaining the user needs to add a key"
            ),
            icon: "key.fill"
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    /// Slim transient banner used to surface non-fatal send failures (e.g.
    /// the orchestrator is still seeding the system prompt). Pinned above
    /// the input bar so the user sees it without losing the text field.
    private func sendHintBanner(_ message: String) -> some View {
        InlineBanner(tone: .info, title: message)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
    }

    /// First real user/assistant message → drop the voice surface so the
    /// chat history takes over. Tool-only messages don't count.
    private func handleMessageCountChange() {
        guard showVoiceSurface else { return }
        let hasConversation = orchestrator.session.transcript.contains { msg in
            let role = msg.role
            return role == .user || role == .assistant
        }
        guard hasConversation else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            showVoiceSurface = false
        }
    }

    // MARK: - Subviews

    /// Chromeless control row that replaces the old titled header. No "Solo
    /// Compass" label, no divider — just the history glyph on the leading edge
    /// and the close glyph on the trailing edge, floating over the chat so the
    /// conversation is the whole surface. The buttons keep their soft circular
    /// fill so they stay tappable against message bubbles.
    private var minimalControls: some View {
        HStack {
            if historyStore != nil {
                Button { showHistory = true } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(closeButtonFill, in: Circle())
                        // Keep the visible glyph 30×30 but expand the tappable
                        // region to the 44pt HIG minimum (a11y-02).
                        .frame(minWidth: HitTargetMetrics.minimum, minHeight: HitTargetMetrics.minimum)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(NSLocalizedString("chat.history.open.a11y", comment: "Open chat history")))
            }
            Spacer()
            if embedded, let onCollapse {
                Button(action: {
                    teardownVoiceStream()
                    onCollapse()
                }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(closeButtonFill, in: Circle())
                        .frame(minWidth: HitTargetMetrics.minimum, minHeight: HitTargetMetrics.minimum)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(WorkspaceAccessibility.collapseChat)
                .accessibilityLabel(Text(NSLocalizedString("workspace.collapseChat", comment: "Collapse the chat back onto the map")))
            } else {
                Button(action: closeSheet) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(closeButtonFill, in: Circle())
                        // Keep the visible glyph 30×30 but expand the tappable
                        // region to the 44pt HIG minimum (a11y-02).
                        .frame(minWidth: HitTargetMetrics.minimum, minHeight: HitTargetMetrics.minimum)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(NSLocalizedString("common.close", comment: "Close")))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private var permissionDeniedBanner: some View {
        InlineBanner(
            tone: .permission,
            title: NSLocalizedString("voiceAgent.permissionDenied", comment: "Microphone access needed — enable in Settings"),
            icon: "mic.slash.fill",
            ctaLabel: NSLocalizedString("common.settings", comment: "Settings"),
            onCTA: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    /// US-027: dismissible toast surfaced when the live voice stream ends via an
    /// error instead of being silently dropped. Tappable / has an explicit
    /// close affordance, and auto-dismisses after a few seconds.
    private func voiceInterruptionBanner(_ message: String) -> some View {
        InlineBanner(
            tone: .warning,
            title: message,
            icon: "waveform.slash",
            onDismiss: dismissVoiceInterruptionToast
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .accessibilityAddTraits(.isStaticText)
    }

    @ViewBuilder
    private var messageList: some View {
        if visibleMessages.isEmpty && orchestrator.streamingContent.isEmpty {
            // The elegant compact invitation stays through panel-height changes
            // (focus / expanded). A taller panel just gets more breathing room —
            // it does not swap in a different, giant empty state. A place-scoped
            // chat still leads with its place hero.
            ScrollView {
                emptyState
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(emptyStateBackground)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    // The bottom marker sits OUTSIDE the LazyVStack: a lazy
                    // container may not instantiate it when scrolled far up,
                    // which would drop the preference and falsely read as
                    // "at the bottom".
                    VStack(spacing: 0) {
                        // Editorial rhythm: 18pt between turns reads as paragraphs,
                        // not chat-density. Serif assistant text and bubble-less
                        // replies need the breathing room (Claude.ai / GPT-5
                        // standard ~16-20pt).
                        LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(visibleMessages) { msg in
                            if let findings = Self.extractDiagnosticsFindings(msg.content ?? "") {
                                // Startup-diagnostics user turn: render as a
                                // compact card instead of the raw JSON dump
                                // that ended up in the message body so the
                                // LLM could parse it.
                                DiagnosticsRequestCard(findings: findings)
                                    .id(msg.id)
                            } else {
                                MessageBubble(
                                    role: msg.role,
                                    text: Self.sanitizeForDisplay(msg.content ?? "", stripReferences: msg.role == .assistant),
                                    toolName: msg.name,
                                    isStreaming: false
                                )
                                .id(msg.id)
                            }

                            // Inline cards (places / proposed route) produced by
                            // this assistant turn's tools — rendered as tappable
                            // cards under the bubble instead of jumping the map.
                            if let cards = orchestrator.cardsByMessageId[msg.id], !cards.isEmpty {
                                ChatCardStack(
                                    cards: cards,
                                    onSelectExperience: handleSelectExperience,
                                    onAdoptRoute: handleAdoptRoute,
                                    onShowEventOnMap: handleShowEventOnMap,
                                    // Slice B: hand the ledger-state
                                    // projection down so each provisional
                                    // card gets a countdown + undo pill.
                                    // Absent when the ledger's projection
                                    // hasn't landed for this message yet
                                    // (ChatCardStack degrades gracefully).
                                    entries: orchestrator.entriesByMessageId[msg.id],
                                    onUndoCard: { entryId in
                                        orchestrator.undoCard(id: entryId)
                                    }
                                )
                                .id("cards-\(msg.id)")
                            }

                            // This turn's reasoning, collapsed into one
                            // expandable chip pinned under the reply — calm in
                            // the moment, auditable after the fact.
                            if msg.role == .assistant,
                               let summary = orchestrator.reasoningSummaryByMessageId[msg.id] {
                                ReasoningSummaryChip(summary: summary)
                                    .id("reasoning-\(msg.id)")
                            }
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
                            // captured in real time, with a small sun-gold
                            // pulse dot marking that the mic is still hot.
                            // Slight transparency reads as "not yet committed".
                            MessageBubble(
                                role: .user,
                                text: liveTranscript
                            )
                            .id(Self.liveTranscriptID)
                            .opacity(0.82)
                            .overlay(alignment: .topLeading) {
                                recordingPulseDot
                            }
                            .transition(.opacity)
                        }

                        if isAgentWorking {
                            // ONE quiet thinking indicator: a single spinner +
                            // cycling phrase. When the turn finishes this line
                            // vanishes and its reasoning collapses into a
                            // `ReasoningSummaryChip` pinned under the reply (see
                            // `reasoningSummaryByMessageId` below). This replaces
                            // the old always-on ReasoningTracePanel + typing dots
                            // that competed for attention on screen at once.
                            AgentStatusLine(label: orchestrator.thinkingStep)
                                .id(Self.typingIndicatorID)
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.2), value: isAgentWorking)
                        }

                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)

                    // The bottom marker sits OUTSIDE the LazyVStack so a lazy
                    // container can never drop it (which would make the
                    // preference default to 0 and falsely read as "at bottom").
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchorID)
                        // Real viewport geometry, not lazy-prefetch visibility:
                        // the marker's maxY in the scroll's named space minus
                        // the viewport height is the true distance from the
                        // bottom. This drives the follow intent.
                        .background(alignment: .top) {
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: ChatBottomOffsetKey.self,
                                    value: geo.frame(in: .named(Self.scrollSpace)).maxY
                                )
                            }
                        }
                    }
                }
                .coordinateSpace(name: Self.scrollSpace)
                    // Restore/record the reading anchor across surface remounts.
                    .scrollPosition(id: $scrollAnchor, anchor: .top)
                    .scrollContentBackground(.hidden)
                    .background(messageListBackground)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ChatViewportHeightKey.self,
                                value: geo.size.height
                            )
                        }
                    )
                    .scrollDismissesKeyboard(.interactively)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 6).onChanged { _ in
                            // Only a reader gesture releases explicit follow;
                            // a growing reply/card must not look like scrolling up.
                            workspace.noteScrolledAwayFromBottom()
                            followThrottle.cancel()
                        }
                    )
                    .overlay(alignment: .bottom) {
                        returnToLatestButton(proxy: proxy)
                    }
                    .onPreferenceChange(ChatViewportHeightKey.self) { height in
                        scrollViewportHeight = height
                        if #unavailable(iOS 18) {
                            noteScrollPosition(bottomMaxY: lastBottomMaxY)
                        }
                    }
                    .onPreferenceChange(ChatBottomOffsetKey.self) { bottomMaxY in
                        lastBottomMaxY = bottomMaxY
                        if #unavailable(iOS 18) {
                            noteScrollPosition(bottomMaxY: bottomMaxY)
                        }
                    }
                    .modifier(ChatScrollPositionObserver { nearBottom in
                        noteNearBottom(nearBottom)
                    })
                    .onChange(of: visibleMessages.count) { _, _ in
                        handleMessagesChanged(proxy: proxy)
                    }
                    // Streaming tokens are throttled: the scroll follows at most a
                    // few times per second, and only when the reader was already at
                    // the bottom — never yanking someone reading history.
                    .onChange(of: orchestrator.streamingContent) { _, _ in
                        scheduleFollowScroll(proxy: proxy)
                    }
                    .onChange(of: liveTranscript) { _, _ in
                        scheduleFollowScroll(proxy: proxy)
                    }
                    .onChange(of: orchestrator.session.state) { _, _ in
                        scheduleFollowScroll(proxy: proxy)
                    }
                    .onChange(of: orchestrator.reasoningSummaryByMessageId.count) { _, _ in
                        scheduleFollowScroll(proxy: proxy)
                    }
                    .onChange(of: orchestrator.reasoningTrace.count) { _, _ in
                        scheduleFollowScroll(proxy: proxy)
                    }
                    .onChange(of: totalCardCount) { _, _ in
                        scheduleFollowScroll(proxy: proxy)
                    }
                    .onChange(of: scrollAnchor) { _, id in
                        workspace.noteVisibleAnchor(id)
                    }
                    .onChange(of: orchestrator.persistedConversationId) { _, id in
                        // New / restored conversation: drop any stale anchor.
                        workspace.syncAnchorConversation(id: id)
                        scrollAnchor = workspace.visibleAnchorId
                    }
                    .onAppear {
                        // Scope the anchor to this conversation, then either
                        // follow the bottom or restore the row the reader left.
                        workspace.syncAnchorConversation(id: orchestrator.persistedConversationId)
                        scrollAnchor = workspace.visibleAnchorId
                        if workspace.shouldFollowScroll || workspace.visibleAnchorId == nil {
                            scrollToBottom(proxy: proxy, animated: false)
                        }
                    }
            }
        }
    }

    /// A new turn landed. A user turn always follows (they just sent it); an
    /// assistant/tool turn follows only when the reader was at the bottom.
    private func handleMessagesChanged(proxy: ScrollViewProxy) {
        if visibleMessages.last?.role == .user {
            workspace.beginFollowing()
            scrollToBottom(proxy: proxy)
            return
        }
        scheduleFollowScroll(proxy: proxy)
    }

    /// Translate the bottom marker's geometry into follow intent. Only writes
    /// the workspace when the state actually flips, so ordinary scrolling does
    /// not churn observation.
    private func noteScrollPosition(bottomMaxY: CGFloat) {
        guard scrollViewportHeight > 0 else { return }
        let distanceFromBottom = bottomMaxY - scrollViewportHeight
        noteNearBottom(distanceFromBottom <= 80)
    }

    private func noteNearBottom(_ nearBottom: Bool) {
        if nearBottom {
            if !workspace.isNearBottom { workspace.noteReachedBottom() }
        } else if !workspace.followStreaming {
            if workspace.isNearBottom { workspace.noteScrolledAwayFromBottom() }
        }
    }

    /// Bounded throttle for streaming/tool updates: at most one scheduled
    /// trailing scroll per 120ms window. The intent is re-checked at execution
    /// time, so a token that lands while the reader scrolls up will not drag
    /// them back to the bottom.
    private func scheduleFollowScroll(proxy: ScrollViewProxy) {
        guard workspace.shouldFollowScroll else {
            workspace.noteContentArrivedWhileAway()
            return
        }
        followThrottle.request(
            shouldFollow: { [workspace] in workspace.shouldFollowScroll },
            action: { [workspace] in
                guard workspace.shouldFollowScroll else { return }
                scrollToBottom(proxy: proxy, animated: false)
            }
        )
    }

    /// Accessible return-to-latest pill, shown only when a reply arrived while
    /// the reader was scrolled up in history.
    @ViewBuilder
    private func returnToLatestButton(proxy: ScrollViewProxy) -> some View {
        if workspace.showsReturnToLatest {
            Button {
                #if canImport(UIKit)
                Haptics.selection()
                #endif
                workspace.beginFollowing()
                scrollToBottom(proxy: proxy)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 11, weight: .bold))
                    Text(NSLocalizedString("chat.returnToLatest", comment: "Return to the latest message"))
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(CT.accent))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityIdentifier(WorkspaceAccessibility.returnToLatest)
            .accessibilityLabel(Text(NSLocalizedString("chat.returnToLatest.a11y", comment: "New reply — jump to the latest message")))
            .padding(.bottom, 10)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
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
                    .foregroundStyle(CT.accent)
            }
            .padding(.bottom, 24)

            if let err = orchestrator.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(CT.savedRed)
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

    /// Empty state forks on whether the chat is anchored to a place. The global
    /// "+" chat gets the hour-aware "ask me anything" canvas; a chat opened from
    /// a place's detail gets a focused canvas that *leads with that place* — a
    /// compact hero card + place-specific openers — so the anchor reads at a
    /// glance, not just as a line of copy. (Handoff: `ctx ? 'Ask about X' : …`.)
    @ViewBuilder
    private var emptyState: some View {
        if let place = orchestrator.scopedExperience {
            placeEmptyState(place)
        } else {
            compactEmptyCanvas
        }
    }

    /// The minimal compact layout. Wires `starterPrompts` into the
    /// `HalfExpandedEmptyState` pills so taps still produce the same full
    /// question the large state would have sent. The standalone mic handle is
    /// suppressed because the composer below (with its own text field + mic)
    /// is the single input surface now — stacking both created two competing
    /// entry points.
    private var compactEmptyCanvas: some View {
        VStack(spacing: 14) {
            HalfExpandedEmptyState(
                nowChipText: Self.nowContextCopy(hour: nowHour),
                suggestions: Self.halfExpandedSuggestions,
                onSendPrompt: { _ = handleSend($0) },
                onMicPress: handleMicPress,
                isMicListening: voiceService.isListening,
                showsMicHandle: false
            )

            if needsCitySelection, let onChooseCity {
                Button {
                    #if canImport(UIKit)
                    Haptics.selection()
                    #endif
                    onChooseCity()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 12, weight: .semibold))
                        Text(NSLocalizedString(
                            "workspace.chooseCity",
                            comment: "Choose a city before asking for nearby places"
                        ))
                        .font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundStyle(CT.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(CT.accentSoft))
                }
                .buttonStyle(PressableButtonStyle(pressedScale: 0.94))
                .accessibilityIdentifier("workspace.chooseCity")
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// Punchy 2-4 char tags + the full sentence they expand to on tap. The
    /// short tag is what reads on the pill; the full sentence is what the
    /// orchestrator receives, so the answer quality matches the large state.
    private static let halfExpandedSuggestions: [HalfExpandedEmptyState.Suggestion] = [
        .init(
            label: NSLocalizedString("chat.empty.half.tag.nearby", comment: "Nearby short tag"),
            icon: "mappin.and.ellipse",
            tint: CT.accent,
            fullPrompt: NSLocalizedString("chat.empty.prompt.nearby", comment: "Starter chip — what's good around me")
        ),
        .init(
            label: NSLocalizedString("chat.empty.half.tag.coffee", comment: "Coffee short tag"),
            icon: "cup.and.saucer.fill",
            tint: CT.sunGoldDeep,
            fullPrompt: NSLocalizedString("chat.empty.prompt.coffee", comment: "Starter chip — find a quiet café")
        ),
        .init(
            label: NSLocalizedString("chat.empty.half.tag.sunset", comment: "Sunset short tag"),
            icon: "sun.horizon.fill",
            tint: CT.sunGoldDeep,
            fullPrompt: NSLocalizedString("chat.empty.half.prompt.sunset", comment: "Where to watch the sunset")
        ),
        .init(
            label: NSLocalizedString("chat.empty.half.tag.evening", comment: "Evening short tag"),
            icon: "moon.stars.fill",
            tint: Color(.sRGB, red: 0x6B / 255, green: 0x4E / 255, blue: 0x7D / 255, opacity: 1),
            fullPrompt: NSLocalizedString("chat.empty.prompt.evening", comment: "Starter chip — plan my evening")
        ),
    ]

    /// Hour-aware global empty state (the "+" entry). Sequence: hero glyph →
    /// title → subtitle → NOW banner → starter cards. Rebuilt for a single warm
    /// identity in both schemes — the cold systemGray fallback is gone; every
    /// surface here sits on the amber ladder (`warm*Dark` / `CT.surface*`) with
    /// a deliberate vertical rhythm instead of evenly-spaced rows.
    private var genericEmptyState: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            heroGlyph
                .padding(.bottom, 20)

            Text(NSLocalizedString("chat.empty.title", comment: "Ask me anything about places near you"))
                .ctDisplay(22, .bold)
                .foregroundStyle(emptyTitleColor)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.bottom, 7)

            Text(NSLocalizedString("chat.empty.subtitle", comment: "Try ‘what’s good around me?’ or hold the mic to talk."))
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(emptySubtitleColor)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 36)
                .padding(.bottom, 18)

            nowContextBanner
                .padding(.bottom, 22)

            starterPromptChips

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity)
        .opacity(starterPromptsAppeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.45).delay(0.1)) {
                starterPromptsAppeared = true
            }
        }
    }

    /// Hero glyph for the global empty state — a layered, breathing badge rather
    /// than a flat disc. Two soft amber halos radiate behind a gradient-filled
    /// inner circle so the mark reads as warm and dimensional on the dark sheet,
    /// not a hard米白 cutout. The faint outer ring + inner highlight give it the
    /// "lit from within" quality the detail page hero has.
    private var heroGlyph: some View {
        ZStack {
            // Outer ambient halo — barely-there bloom that softens the edge
            // against the near-black sheet.
            Circle()
                .fill(CT.accent.opacity(colorScheme == .dark ? 0.16 : 0.10))
                .frame(width: 108, height: 108)
                .blur(radius: 14)

            // Mid ring — a thin warm border floating just outside the core.
            Circle()
                .strokeBorder(CT.sunGold.opacity(colorScheme == .dark ? 0.30 : 0.40), lineWidth: 1)
                .frame(width: 82, height: 82)

            // Core — gradient amber fill with a top highlight, white glyph.
            Circle()
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [CT.accent, CT.accentHover]
                            : [CT.sunGoldSoft, CT.accentSoft],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 68, height: 68)
                .overlay(
                    Circle().strokeBorder(
                        Color.white.opacity(colorScheme == .dark ? 0.10 : 0.55),
                        lineWidth: 0.75
                    )
                )
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? Color.white : CT.accent)
                )
                .shadow(color: CT.accent.opacity(colorScheme == .dark ? 0.45 : 0.18), radius: 12, y: 5)
        }
        .scaleEffect(starterPromptsAppeared ? 1 : 0.88)
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.7), value: starterPromptsAppeared)
        .accessibilityHidden(true)
    }

    private var emptyTitleColor: Color {
        colorScheme == .dark ? CT.fgPrimaryDark : CT.fgPrimary
    }

    private var emptySubtitleColor: Color {
        colorScheme == .dark ? CT.fgMutedDark : CT.fgMuted
    }

    /// Place-anchored empty state. Leads with a compact hero of the place the
    /// chat is bound to (so "I'm asking about *this*" is felt, not just read),
    /// then a tight stack of place-specific openers. The whole thing is
    /// vertically centered and scrolls if a small device can't fit it.
    private func placeEmptyState(_ place: Experience) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer(minLength: 8)
                placeHeroCard(place)
                Text(NSLocalizedString("chat.empty.place.subtitle", comment: "I'll answer with this place's live context."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                placeIntentChips(place)
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.15)) {
                starterPromptsAppeared = true
            }
        }
    }

    /// Compact mini-hero for the anchored place — the chat's answer to the
    /// handoff's plain "Ask about X" heading, lifted into a tactile card. A
    /// category-tinted disc, the place name (+ its local-script name), a Solo
    /// score chip, and a NOW/hours meta line, all on a soft surface that floats
    /// on the warm sheet. This is the deliberate "exceed the mock" beat for the
    /// detail-page entry.
    private func placeHeroCard(_ place: Experience) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(place.category.color.opacity(0.16))
                    .frame(width: 70, height: 70)
                Image(systemName: place.category.symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(
                        Circle().fill(
                            LinearGradient(
                                colors: [place.category.color, place.category.color.opacity(0.78)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    )
                    .shadow(color: place.category.color.opacity(0.4), radius: 7, y: 3)
            }

            VStack(spacing: 3) {
                Text(NSLocalizedString("chat.empty.place.eyebrow", comment: "ASKING ABOUT eyebrow"))
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(CT.accent.opacity(0.65))
                Text(Self.shortName(place))
                    .ctDisplay(20, .bold)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let secondary = placeSecondaryName(place) {
                    Text(secondary)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(CT.fgMuted)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 18)

            HStack(spacing: 7) {
                heroSoloChip(place)
                heroNowChip(place)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(heroCardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(CT.borderSubtle, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        .padding(.horizontal, 22)
        .opacity(starterPromptsAppeared ? 1 : 0)
        .scaleEffect(starterPromptsAppeared ? 1 : 0.96)
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82), value: starterPromptsAppeared)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(String(
            format: NSLocalizedString("chat.empty.place.title", comment: "Ask about %@"),
            place.title
        )))
    }

    /// Solo-score chip — "person · 8.4" in the warm verified-green system, the
    /// same chip language the place cards use, so the hero reads as one family.
    private func heroSoloChip(_ place: Experience) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "person.fill")
                .font(.system(size: 9.5, weight: .semibold))
            Text(String(
                format: NSLocalizedString("chat.card.solo", comment: "Solo %@"),
                String(format: "%.1f", place.soloScore.overall)
            ))
            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(CT.verifiedGreen)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(CT.successSoft))
    }

    /// NOW / hours chip — sun-gold "good right now" when the place is in its
    /// window this hour, else a quieter category label. Grounds the hero in
    /// *this moment* the same way the map's "AI · NOW" framing does.
    @ViewBuilder
    private func heroNowChip(_ place: Experience) -> some View {
        if place.isBestNow() {
            HStack(spacing: 5) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 9.5, weight: .semibold))
                Text(NSLocalizedString("chat.empty.place.goodNow", comment: "Good right now"))
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(CT.sunGoldDeep)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(CT.sunGoldSoft))
        } else {
            Text(place.category.localizedTitle)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(CT.fgMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(CT.surfaceSunken))
        }
    }

    /// Secondary line under the hero title. Prefers the local-script place name
    /// (the native flavor the detail page carries) when it differs from the
    /// shown short name; otherwise falls back to the experience one-liner so the
    /// hero still says *what this place is*, never an empty or duplicate line.
    private func placeSecondaryName(_ place: Experience) -> String? {
        let shown = Self.shortName(place)
        if let local = place.location.placeNameLocal, !local.isEmpty, local != shown {
            return local
        }
        let oneLiner = place.oneLiner.trimmingCharacters(in: .whitespacesAndNewlines)
        return oneLiner.isEmpty ? nil : oneLiner
    }

    /// Four place-grounded openers (busy / solo / route / nearby). Tapping one
    /// sends its question; the orchestrator's place scope makes the answer land
    /// on *this* place. Mirrors the handoff `PLACE_INTENTS`.
    private func placeIntentChips(_ place: Experience) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(Self.placeIntents.enumerated()), id: \.offset) { index, intent in
                Button {
                    Haptics.impact(.light)
                    _ = handleSend(NSLocalizedString(intent.promptKey, comment: "Place opener"))
                } label: {
                    starterCardRow(icon: intent.icon, iconColor: CT.accent, label: NSLocalizedString(intent.promptKey, comment: "Place opener"))
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(Text(NSLocalizedString(intent.promptKey, comment: "Place opener")))
                .opacity(starterPromptsAppeared ? 1 : 0)
                .offset(y: starterPromptsAppeared ? 0 : 8)
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.35).delay(0.1 + Double(index) * 0.07),
                    value: starterPromptsAppeared
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 2)
    }

    /// Static descriptor for the four place openers. Pure data so the chips
    /// stay declarative and the copy lives entirely in the strings table.
    private struct PlaceIntent {
        let icon: String
        let promptKey: String
    }

    private static let placeIntents: [PlaceIntent] = [
        PlaceIntent(icon: "person.2.fill",            promptKey: "chat.empty.place.busy"),
        PlaceIntent(icon: "figure.stand",             promptKey: "chat.empty.place.solo"),
        PlaceIntent(icon: "location.north.line.fill", promptKey: "chat.empty.place.route"),
        PlaceIntent(icon: "mappin.and.ellipse",       promptKey: "chat.empty.place.nearby"),
    ]

    private var heroCardFill: Color {
        colorScheme == .dark ? Color(.secondarySystemBackground) : CT.surfaceWhite
    }

    private var starterPromptChips: some View {
        VStack(spacing: 11) {
            ForEach(Array(Self.starterPrompts.enumerated()), id: \.offset) { index, prompt in
                Button {
                    Haptics.impact(.light)
                    _ = handleSend(prompt)
                } label: {
                    starterCardRow(
                        icon: promptIcon(for: index),
                        iconColor: promptIconColor(for: index),
                        label: prompt
                    )
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(prompt)
                .opacity(starterPromptsAppeared ? 1 : 0)
                .offset(y: starterPromptsAppeared ? 0 : 10)
                .animation(
                    reduceMotion
                        ? nil
                        : .spring(response: 0.42, dampingFraction: 0.8).delay(0.18 + Double(index) * 0.07),
                    value: starterPromptsAppeared
                )
            }
        }
        .padding(.horizontal, 24)
    }

    /// One opener row — shared by the global starter prompts and the
    /// place-anchored intents so the two empty states read as one family.
    /// The icon sits in a tinted rounded square (the handoff `.sugg .ic` chip),
    /// a step up in tactility from a bare glyph, and the chevron is the quiet
    /// "go" cue on the trailing edge.
    private func starterCardRow(icon: String, iconColor: Color, label: String) -> some View {
        HStack(spacing: 13) {
            // Gradient-filled rounded tile — a tactile chip, not a flat tint.
            // The diagonal gradient + hairline highlight give each icon a small
            // bit of dimension so the row reads as a card, not a list cell.
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [iconColor, iconColor.opacity(0.82)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                )
                .shadow(color: iconColor.opacity(0.35), radius: 5, y: 2)

            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(starterCardTextColor)
                .multilineTextAlignment(.leading)
                .lineLimit(2)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(starterCardChevronColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(starterCardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(starterCardBorder, lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.05), radius: 10, y: 4)
    }

    private var starterCardTextColor: Color {
        colorScheme == .dark ? CT.fgPrimaryDark : CT.fgPrimary
    }

    private var starterCardChevronColor: Color {
        colorScheme == .dark ? CT.fgMutedDark.opacity(0.7) : CT.fgSubtle
    }

    private func promptIcon(for index: Int) -> String {
        switch index {
        case 0:  return "mappin.and.ellipse"
        case 1:  return "cup.and.saucer.fill"
        case 2:  return "calendar"
        default: return "moon.stars.fill"
        }
    }

    /// Warm-family icon tints for the starter cards. Deep-amber accent →
    /// sun-gold → verified green (the events card borrows the Live sheet's
    /// solo-chip green so "what's on" reads as the same City-OS surface) →
    /// a dusk plum that still lives next to the amber palette (not a cold
    /// `.indigo` that fights the warm sheet). All four read as one family.
    private func promptIconColor(for index: Int) -> Color {
        switch index {
        case 0:  return CT.accent
        case 1:  return CT.sunGoldDeep
        case 2:  return CT.verifiedGreenDot
        default: return Color(.sRGB, red: 0x6B / 255, green: 0x4E / 255, blue: 0x7D / 255, opacity: 1) // dusk plum #6B4E7D
        }
    }

    // MARK: - Contextual NOW banner

    /// A single sun-gold pill on the empty chat that shifts copy with the hour —
    /// the chat's equivalent of the map's "AI · NOW" framing. It grounds the
    /// blank state in *this moment* ("Golden light soon · the river bank is
    /// calling") instead of a generic prompt, nudging the right question.
    private var nowContextBanner: some View {
        let copy = Self.nowContextCopy(hour: nowHour)
        return HStack(spacing: 7) {
            Image(systemName: nowContextIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CT.sunGoldDeep)
            Text(copy)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(nowBannerTextColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(nowBannerFill)
        )
        .overlay(
            Capsule().strokeBorder(CT.sunGold.opacity(colorScheme == .dark ? 0.30 : 0.0), lineWidth: 0.75)
        )
        .padding(.horizontal, 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(
            format: NSLocalizedString("chat.empty.now.a11y", comment: "NOW banner a11y prefix"),
            copy
        )))
    }

    /// NOW pill fill — warm-translucent gold on the dark sheet (so it reads as
    /// "lit, belongs here" not a pasted-on bright yellow chip), the original
    /// soft-gold parchment in light mode.
    private var nowBannerFill: Color {
        colorScheme == .dark
            ? CT.sunGold.opacity(0.14)
            : CT.sunGoldSoft
    }

    private var nowBannerTextColor: Color {
        colorScheme == .dark ? CT.fgPrimaryDark : CT.sunGoldDeep
    }

    /// Current local hour (0–23). A computed property so the banner reflects the
    /// hour the sheet was opened.
    private var nowHour: Int {
        Calendar.current.component(.hour, from: Date())
    }

    private var nowContextIcon: String {
        switch nowHour {
        case 5..<8:   return "sunrise.fill"
        case 8..<11:  return "cup.and.saucer.fill"
        case 11..<15: return "sun.max.fill"
        case 15..<17: return "sun.haze.fill"
        case 17..<19: return "sunset.fill"
        case 19..<22: return "moon.stars.fill"
        default:      return "moon.fill"
        }
    }

    /// Map an hour to a contextual one-liner. Static + pure so it's trivially
    /// unit-testable without constructing the whole sheet.
    static func nowContextCopy(hour: Int) -> String {
        let key: String
        switch hour {
        case 5..<8:   key = "chat.empty.now.dawn"
        case 8..<11:  key = "chat.empty.now.morning"
        case 11..<15: key = "chat.empty.now.midday"
        case 15..<17: key = "chat.empty.now.afternoon"
        case 17..<19: key = "chat.empty.now.goldenHour"
        case 19..<22: key = "chat.empty.now.evening"
        default:      key = "chat.empty.now.night"
        }
        return NSLocalizedString(key, comment: "Contextual NOW banner copy for the hour")
    }

    // MARK: - Visual helpers (dark-mode aware)

    /// Warm parchment in light mode; system grouped background in dark so the
    /// CT tint doesn't glow on a near-black sheet.
    private var messageListBackground: Color {
        colorScheme == .dark ? Color(.systemBackground) : CT.bgWarm
    }

    /// Empty-state canvas — a faint warm vertical wash so the starter cards
    /// float on an amber-tinted ground in both schemes, rather than a flat
    /// cold-black (dark) or plain white (light) plane. The gradient is whisper-
    /// quiet: just enough to make the surface feel lit from the top.
    private var emptyStateBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [CT.warmSheetDark, Color(.systemBackground)]
                : [CT.bgWarm, CT.surfaceWhite],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea(edges: .bottom)
    }

    private var closeButtonFill: Color {
        colorScheme == .dark ? Color(.secondarySystemBackground) : CT.surfaceSunken
    }

    private var starterCardFill: Color {
        colorScheme == .dark ? CT.warmCardDark : CT.surfaceWhite
    }

    private var starterCardBorder: Color {
        colorScheme == .dark ? CT.warmBorderDark : CT.borderSubtle
    }

    /// Small sun-gold pulse marking that the mic is hot while the tentative
    /// live-transcript bubble is shown. reduceMotion drops the pulse to a
    /// static dot.
    private var recordingPulseDot: some View {
        Circle()
            .fill(CT.sunGold)
            .frame(width: 8, height: 8)
            .scaleEffect(recordingPulse ? 1.4 : 1.0)
            .opacity(recordingPulse ? 0.4 : 1.0)
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                value: recordingPulse
            )
            .offset(x: -2, y: -2)
            .accessibilityHidden(true)
    }

    // MARK: - Derived state

    /// Messages with the system row hidden. Tool rows are kept so the user
    /// can see "Searched nearby" indicators inline with the conversation.
    private var visibleMessages: [VoiceAgentSession.Message] {
        orchestrator.session.transcript.filter { $0.role != .system }
    }

    /// Total inline cards across all messages — drives a scroll-to-bottom when a
    /// new place/route card lands so the user sees it without scrolling.
    private var totalCardCount: Int {
        orchestrator.cardsByMessageId.values.reduce(0) { $0 + $1.count }
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

    @discardableResult
    private func handleSend(_ text: String) -> Bool {
        // The agent pipeline accepts text only. Staged attachments must never be
        // silently discarded, so keep the draft and say so honestly instead of
        // pretending the file was sent.
        guard workspace.attachments.isEmpty else {
            showSendHint(NSLocalizedString(
                "chat.send.hint.attachmentsUnsupported",
                comment: "Hint shown when a staged attachment cannot be sent in the agent chat"
            ))
            return false
        }
        lastUserTranscript = text
        let outcome = orchestrator.handleTextInput(text)
        switch outcome {
        case .accepted:
            // A deliberate send always follows the reply, even if the reader
            // had scrolled up in an earlier turn.
            workspace.beginFollowing()
            clearSendHint()
            Haptics.impact(.light)
            return true
        case .empty:
            // The input bar already guards on empty; nothing to do.
            return false
        case .unconfigured:
            showSendHint(NSLocalizedString(
                "chat.send.hint.unconfigured",
                comment: "Hint shown when the user tries to send but no API key is configured"
            ))
            return false
        case .notReady:
            // Orchestrator is mid-seed (start() is async). The bar keeps the
            // draft; prompt the user to try again.
            showSendHint(NSLocalizedString(
                "chat.send.hint.notReady",
                comment: "Hint shown when the user sends before the agent finished waking up"
            ))
            return false
        case .sessionEnded:
            // The previous turn ended (timeout/error). Soft-restart and
            // re-submit transparently so the user sees their message land.
            if orchestrator.restartIfNeeded(),
               orchestrator.handleTextInput(text) == .accepted {
                workspace.beginFollowing()
                clearSendHint()
                Haptics.impact(.light)
                return true
            } else {
                showSendHint(NSLocalizedString(
                    "chat.send.hint.sessionEnded",
                    comment: "Hint shown when the chat session ended and a new turn couldn't be started"
                ))
                return false
            }
        }
    }

    private func showSendHint(_ message: String) {
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

    /// Push-to-talk path driven by `ChatInputBar`'s unified mic gesture: a real
    /// hold sends `true` on begin and `false` on release; a tap goes through
    /// `handleMicToggle` instead.
    private func handleMicPress(_ pressing: Bool) {
        if pressing {
            if !voiceService.isListening {
                beginPushToTalk()
            }
        } else {
            // Release always invalidates a pending permission grant, even if the
            // stream has not started yet — otherwise a late grant could begin
            // recording after the finger lifted.
            cancelPendingVoiceStart()
            if voiceService.isListening {
                endPushToTalk(send: true)
            }
        }
    }

    private func handleRetry() {
        // Read the active conversation: view-local text is lost on a map round
        // trip and can belong to a different conversation after history restore.
        let raw = orchestrator.session.transcript.last(where: { $0.role == .user })?.content ?? ""
        let transcript = ChatDisplayText.removingContextEnvelopes(raw)
        guard !transcript.isEmpty else { return }
        // The previous turn may have ended (timeout/network error). Re-arm
        // the orchestrator first so the retry isn't silently dropped by the
        // `session.isEnded` guard in handleTextInput.
        _ = orchestrator.restartIfNeeded()
        _ = handleSend(transcript)
    }

    private func closeSheet() {
        teardownVoiceStream()
        onDismiss()
    }

    // MARK: - Card actions

    /// User tapped a place card → dismiss the chat so the reveal is visible on
    /// the map underneath, then hand the place up to the host.
    private func handleSelectExperience(_ experience: Experience) {
        Haptics.impact(.light)
        teardownVoiceStream()
        onDismiss()
        onSelectExperience(experience)
    }

    /// User adopted a proposed route → dismiss the chat, persist + open it.
    private func handleAdoptRoute(_ proposal: RouteProposal) {
        Haptics.impact(.medium)
        teardownVoiceStream()
        onDismiss()
        onAdoptRoute(proposal)
    }

    /// City OS v2: user tapped "在地图上看" on an event card → dismiss the chat
    /// so the map is visible, then hand the event up to recenter + highlight it.
    private func handleShowEventOnMap(_ event: CityEvent) {
        Haptics.impact(.light)
        teardownVoiceStream()
        onDismiss()
        onShowEventOnMap(event)
    }

    // MARK: - Voice handling

    private func applyStartModeIfNeeded() {
        guard !didApplyStartMode else { return }
        didApplyStartMode = true
        resumeVoiceIfVisible()
        if startInVoiceMode {
            showVoiceSurface = true
            beginPushToTalk()
        }
        seedInitialPromptIfNeeded()
        #if DEBUG
        seedRubricScenarioPromptIfNeeded()
        #endif
    }

    #if DEBUG
    /// Rubric harness fires `-openChatMedium` on launch so the sheet peeks open
    /// at .medium detent. Without an auto-seeded first turn the sheet lands
    /// forever on an empty "Ask me where to go" placeholder — s02 lost 3 rubric
    /// dimensions to it. This hook synthesises the persona's implicit query
    /// based on -scenarioHour so ChatCards render before screenshot.
    private func seedRubricScenarioPromptIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-openChatMedium") else { return }
        guard initialUserPrompt == nil else { return }
        let hour = Calendar.current.component(.hour, from: AppClock.now())
        let prompt: String
        switch hour {
        case 23, 0, 1, 2, 3, 4:
            prompt = "现在附近有什么开着的能坐下吃一碗热的?粥、面、大排档都行,一个人。"
        case 5, 6, 7, 8, 9:
            prompt = "凌晨/清早我一个人,附近有什么开门了的安静小店?"
        case 10, 11, 12, 13:
            prompt = "附近 45 分钟能坐下吃个午饭的地方,有空调、不用排队。"
        case 14, 15, 16:
            prompt = "下午一个人想找一个安静能待久的地方,附近有什么?"
        case 17, 18, 19:
            prompt = "日落前后附近能坐下来看看风景的地方,一个人。"
        default:
            prompt = "晚上一个人,附近有什么灯亮、能坐、离街不远的小店?"
        }
        Task { @MainActor in
            for _ in 0..<20 {
                switch orchestrator.handleTextInput(prompt) {
                case .accepted, .empty, .sessionEnded, .unconfigured:
                    return
                case .notReady:
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
            }
        }
    }
    #endif

    /// If the caller passed an `initialUserPrompt` (used by the startup
    /// self-diagnostics bubble), submit it as the first user turn once the
    /// orchestrator finishes seeding. Retries for up to ~5s to cover the
    /// cold-start `start()` → `buildSystemPrompt` async gap; gives up quietly
    /// if the orchestrator ends up unconfigured (no API key), because the
    /// bubble itself already surfaced the "no key" finding.
    private func seedInitialPromptIfNeeded() {
        guard !didSeedInitialPrompt, let prompt = initialUserPrompt else { return }
        didSeedInitialPrompt = true
        submitPrompt(prompt)
    }

    /// Deliver an explicit ask raised through the workspace channel. Because the
    /// chat may already be mounted, this is event-driven (promptToken) rather
    /// than tied to `.onAppear`. Consuming clears the pending value, so a single
    /// request can never be submitted twice.
    private func deliverPendingPromptIfNeeded() {
        guard let request = workspace.consumePendingPrompt() else { return }
        didSeedInitialPrompt = true
        if request.startInVoice {
            showVoiceSurface = true
            beginPushToTalk()
        }
        submitPrompt(request.text)
    }

    /// Submit a prompt once the orchestrator has finished seeding. Retries for
    /// ~5s to cover the cold-start `start()` → `buildSystemPrompt` async gap.
    /// If the prompt still cannot be delivered (unconfigured key, ended
    /// session), it is kept in the composer instead of being silently dropped.
    private func submitPrompt(_ prompt: String) {
        Task { @MainActor in
            for _ in 0..<20 {
                switch orchestrator.handleTextInput(prompt) {
                case .accepted:
                    lastUserTranscript = prompt
                    workspace.beginFollowing()
                    return
                case .notReady:
                    try? await Task.sleep(nanoseconds: 250_000_000)
                case .empty:
                    return
                case .unconfigured:
                    if workspace.draftText.isEmpty { workspace.draftText = prompt }
                    showSendHint(NSLocalizedString(
                        "chat.send.hint.unconfigured",
                        comment: "Hint shown when the user tries to send but no API key is configured"
                    ))
                    return
                case .sessionEnded:
                    if workspace.draftText.isEmpty { workspace.draftText = prompt }
                    return
                }
            }
            // Retry budget exhausted: preserve the ask rather than lose it.
            if workspace.draftText.isEmpty { workspace.draftText = prompt }
        }
    }

    /// Keyboard focus expands the panel so the composer is never covered; on
    /// blur we restore the reader's chosen state, unless they changed it while
    /// typing. The snapshot is captured once per focus session (a non-nil value
    /// means we're already tracking it) so repeated focus callbacks can't
    /// overwrite the restore point with the already-expanded detent.
    private func handleComposerFocusChange(_ focused: Bool) {
        if focused {
            if keyboardRestore == nil {
                keyboardRestore = workspace.expandForKeyboard()
            }
        } else if let restore = keyboardRestore {
            keyboardRestore = nil
            withAnimation(reduceMotion ? nil : Motion.settle) {
                workspace.restoreAfterKeyboard(restore)
            }
        }
    }

    /// Stop capturing audio and stop any speech output without touching the
    /// conversation. Called when the panel collapses, the surface switches, a
    /// modal covers the chat, or the app backgrounds. Speech is suppressed so a
    /// late assistant completion can't speak while hidden.
    private func hibernateVoiceAndSpeech() {
        orchestrator.isSpeechSuppressed = true
        teardownVoiceStream()
        followThrottle.cancel()
        // The keyboard is dismissed with the subtree; clear the signal here so a
        // later map/discovery surface never renders with the dock hidden.
        workspace.setSoftwareKeyboardVisible(false)
        orchestrator.stopSpeaking()
    }

    /// Re-enable speech once the chat is visible and the app is active again.
    private func resumeVoiceIfVisible() {
        guard workspace.showsConversation, scenePhase == .active else { return }
        orchestrator.isSpeechSuppressed = false
    }

    private func beginPushToTalk() {
        guard !voiceService.isListening else { return }
        voiceGeneration &+= 1
        let generation = voiceGeneration
        permissionTask?.cancel()
        permissionTask = Task { @MainActor [generation] in
            let granted = await voiceService.requestPermission()
            // A late grant must never start a hidden recording: the generation
            // changed (teardown/collapse) or the chat is no longer visible.
            // Denial remains useful feedback even if the system permission
            // dialog temporarily made the scene inactive. A late grant still
            // cannot start recording after that lifecycle cancellation.
            guard granted else {
                if workspace.showsConversation { permissionDenied = true }
                return
            }
            guard generation == voiceGeneration, !Task.isCancelled else { return }
            guard workspace.showsConversation, scenePhase == .active else { return }
            withAnimation { permissionDenied = false }
            do {
                liveTranscript = ""
                let stream = try voiceService.startListening()
                if !reduceMotion { recordingPulse = true }
                // US-026: surface the capture as a Live Activity (录制语音 signal)
                // with a live waveform sampled from VoiceService.amplitude.
                LiveActivityService.shared.beginRecordingSession(
                    locality: ""
                ) { voiceService.amplitude }
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
        // A release must also invalidate an in-flight permission request.
        cancelPendingVoiceStart()
        voiceService.stopListening()
        Task { await LiveActivityService.shared.endRecordingSession() }
        recordingPulse = false
        voiceStreamTask?.cancel()
        voiceStreamTask = nil
        let final = liveTranscript
        liveTranscript = ""
        guard send, !final.isEmpty else { return }
        lastUserTranscript = final
        workspace.beginFollowing()
        orchestrator.handleTranscript(final)
        Haptics.impact(.light)
    }

    /// Invalidate a pending `requestPermission()` result so a late grant can
    /// never start a recording after the user released or left.
    private func cancelPendingVoiceStart() {
        voiceGeneration &+= 1
        permissionTask?.cancel()
        permissionTask = nil
    }

    private func teardownVoiceStream() {
        // Invalidate any in-flight permission request so its late completion
        // cannot start the mic after this teardown.
        voiceGeneration &+= 1
        permissionTask?.cancel()
        permissionTask = nil
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
        Task { await LiveActivityService.shared.endRecordingSession() }
        recordingPulse = false
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
    /// Named coordinate space of the message ScrollView, used to measure the
    /// true distance from the bottom instead of lazy-prefetch visibility.
    private static let scrollSpace = "chat.scroll"

    /// Removes machine-readable envelope blocks — `<latest_context>` (added
    /// by `VoiceAgentOrchestrator` for hour/timezone/coord refresh) and
    /// `<solo:diagnostics>` (added by `StartupDiagnosticsService` when the
    /// traveler taps the diagnostics banner) — before the message text
    /// lands in a `MessageBubble`. LLM payload stays identical; the human
    /// reader gets a clean sentence.
    ///
    /// Uses `dotMatchesLineSeparators` so `.` also spans `\n` — without it
    /// the `[\s\S]*?` trick worked in offline swift tests but failed at
    /// iOS runtime for reasons that resisted diagnosis. `dotMatchesLineSeparators`
    /// is the intent-revealing option and just works.
    static func sanitizeForDisplay(_ raw: String, stripReferences: Bool = true) -> String {
        var out = ChatDisplayText.removingContextEnvelopes(raw)
        if stripReferences { out = Self.stripInternalReferenceMarkers(out) }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Remove the model's internal Experience reference markers — `[exp:<id>]`
    /// and `[exp_<id>]` — **together with the arrow separators that chain
    /// them**, so an observed reply like
    /// `**route title** [exp:a] → [exp_b] → [exp_c].` collapses to
    /// `**route title**.` rather than the dangling `**route title** → → .`.
    ///
    /// Only these exact internal shapes are touched: ordinary user bracketed
    /// text (e.g. `[the quiet one]`) and prose arrows are preserved, and the
    /// persisted/raw provider output is never modified (display layer only).
    static func stripInternalReferenceMarkers(_ text: String) -> String {
        guard text.contains("[exp") else { return text }
        var out = text
        let colonMarker = "\\[exp:[A-Za-z0-9._\\-]+\\]"
        let underscoreMarker = "\\[exp_[A-Za-z0-9._\\-]+\\]"
        let arrow = "(?:→|->|⇒|—|–)"
        // Marker joined to a following arrow, and arrow joined to a following
        // marker — applied a few times to unwind a whole chain.
        let chainPatterns = [
            "\\s*" + arrow + "\\s*" + colonMarker,
            "\\s*" + arrow + "\\s*" + underscoreMarker,
            colonMarker + "\\s*" + arrow + "\\s*",
            underscoreMarker + "\\s*" + arrow + "\\s*"
        ]
        for _ in 0..<3 {
            for pattern in chainPatterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let range = NSRange(out.startIndex..., in: out)
                out = regex.stringByReplacingMatches(in: out, range: range, withTemplate: "")
            }
        }
        // Any standalone markers left behind.
        for pattern in [colonMarker, underscoreMarker] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(out.startIndex..., in: out)
            out = regex.stringByReplacingMatches(in: out, range: range, withTemplate: "")
        }
        // Tidy the residue: no space before sentence punctuation, no runs of
        // spaces, and no line that is now only arrows/commas.
        out = out.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        out = out.replacingOccurrences(of: "[ \\t]+([.,;:!?。，、；：！？])", with: "$1", options: .regularExpression)
        let keptLines = out.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("→") || trimmed.contains("->") else { return true }
            let residue = trimmed
                .replacingOccurrences(of: "→", with: "")
                .replacingOccurrences(of: "->", with: "")
                .replacingOccurrences(of: "⇒", with: "")
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespaces)
            return !residue.isEmpty
        }
        return keptLines.joined(separator: "\n")
    }

    /// Extracts the diagnostics payload from a message body when the user
    /// tapped the startup-diagnostics banner. Returns the parsed findings
    /// so the chat surface can render a `DiagnosticsRequestCard` instead of
    /// a raw MessageBubble. Any parse failure returns nil — the message
    /// then falls back to the sanitized MessageBubble render.
    static func extractDiagnosticsFindings(_ raw: String) -> [DiagnosticsRequestCard.Finding]? {
        guard raw.contains("<solo:diagnostics>") else { return nil }
        let pattern = "<solo:diagnostics>(.*?)</solo:diagnostics>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              match.numberOfRanges >= 2,
              let jsonRange = Range(match.range(at: 1), in: raw)
        else { return nil }
        let json = String(raw[jsonRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else { return nil }
        return arr.compactMap { dict in
            guard let severity = dict["severity"],
                  let title = dict["title"],
                  let fix = dict["fix"]
            else { return nil }
            return DiagnosticsRequestCard.Finding(
                severity: severity,
                title: title,
                suggestedFix: fix
            )
        }
    }

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
                // `Color.black.opacity(0.85)` made the idle mic button nearly
                // invisible against the dark-mode sheet. `Color(.systemGray)`
                // stays clearly separated from the background in both schemes
                // while keeping the white icon legible.
                .fill(isListening ? Color.accentColor : Color(.systemGray))
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
        onDismiss: {},
        workspace: ConversationWorkspaceState()
    )
}

#Preview("Unconfigured") {
    let orch = previewOrchestrator()
    orch.previewSetUnconfigured()
    return ChatSheet(
        orchestrator: orch,
        voiceService: VoiceService(),
        startInVoiceMode: false,
        onDismiss: {},
        workspace: ConversationWorkspaceState()
    )
}

#Preview("With history") {
    let orch = previewOrchestrator(seeded: true)
    return ChatSheet(
        orchestrator: orch,
        voiceService: VoiceService(),
        startInVoiceMode: false,
        onDismiss: {},
        workspace: ConversationWorkspaceState()
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

// MARK: - Scroll geometry preferences

/// The bottom marker's maxY in the message scroll's named coordinate space.
/// Combined with the viewport height this is the true distance from the bottom
/// — unlike lazy-container `onAppear`/`onDisappear`, which fire on prefetch.
private struct ChatBottomOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Height of the message viewport.
private struct ChatViewportHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// iOS 18+ supplies the actual scroll geometry, including lazy-content estimates.
/// Older systems retain the named-coordinate-space marker above.
private struct ChatScrollPositionObserver: ViewModifier {
    let onChange: (Bool) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height - geometry.visibleRect.maxY <= 80
            } action: { _, nearBottom in
                onChange(nearBottom)
            }
        } else {
            content
        }
    }
}
