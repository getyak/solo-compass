import SwiftUI

/// Pinned bottom input bar for `ChatSheet`. Combines:
///  * a multi-line text field (1–4 lines of growth)
///  * a send button
///  * a mic button with two interaction modes:
///     - tap = toggle voice mode (accessibility-friendly path)
///     - press-and-hold = push-to-talk (immediate touch-down feedback)
///  * an error banner pinned above the row when the orchestrator reports
///    a failure, with a Retry button.
///
/// State (listening / thinking / error) is rendered around the mic button
/// itself so the user always knows which mode the chat is in.
@MainActor
public struct ChatInputBar: View {
    /// Visible state of the input bar's mic affordance.
    public enum MicState: Equatable {
        case idle
        case listening
        case thinking
        case error
    }

    @Binding public var draftText: String
    public let micState: MicState
    public let errorMessage: String?

    /// Fires when the user taps the send button (or hits return) with a
    /// non-empty draft. The trimmed text is passed in; the input bar
    /// clears `draftText` after the closure runs.
    public let onSend: (String) -> Void

    /// Tap-to-toggle voice mode (accessibility path). `true` requests start,
    /// `false` requests stop.
    public let onMicToggle: (Bool) -> Void

    /// Push-to-talk press change. `true` on touch-down, `false` on release.
    /// Fires synchronously with the touch so the bar can begin streaming
    /// the live transcript immediately.
    public let onMicPress: (Bool) -> Void

    /// Retry the last action that errored. Caller decides what "retry" means
    /// (usually re-running the last user transcript).
    public let onRetry: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Drives the soft pulse on the "Listening" status dot.
    @State private var listeningPulse: Bool = false

    public init(
        draftText: Binding<String>,
        micState: MicState,
        errorMessage: String?,
        onSend: @escaping (String) -> Void,
        onMicToggle: @escaping (Bool) -> Void,
        onMicPress: @escaping (Bool) -> Void,
        onRetry: @escaping () -> Void
    ) {
        self._draftText = draftText
        self.micState = micState
        self.errorMessage = errorMessage
        self.onSend = onSend
        self.onMicToggle = onMicToggle
        self.onMicPress = onMicPress
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(spacing: 8) {
            if let errorMessage {
                InlineBanner(
                    tone: .error,
                    title: errorMessage,
                    ctaLabel: NSLocalizedString("chat.error.retry", comment: "Retry"),
                    onCTA: onRetry
                )
            }

            stateLabel

            HStack(alignment: .bottom, spacing: 8) {
                textField
                sendButton
                micButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(alignment: .top) {
            // Hairline top divider + opaque surface (replaces `.bar`).
            ZStack(alignment: .top) {
                Color(.systemBackground)
                Rectangle()
                    .fill(CT.borderDefault)
                    .frame(height: 0.5)
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var stateLabel: some View {
        switch micState {
        case .listening:
            HStack(spacing: 6) {
                Circle()
                    .fill(CT.sunGold)
                    .frame(width: 8, height: 8)
                    .scaleEffect(listeningPulse ? 1.35 : 1.0)
                    .opacity(listeningPulse ? 0.5 : 1.0)
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                        value: listeningPulse
                    )
                Text(NSLocalizedString("chat.state.listening", comment: "Listening — release to send"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CT.sunGoldDeep)
                Spacer()
            }
            .transition(.opacity)
            .onAppear { if !reduceMotion { listeningPulse = true } }
            .onDisappear { listeningPulse = false }
        case .thinking:
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text(NSLocalizedString("chat.state.thinking", comment: "Thinking…"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .transition(.opacity)
        case .idle, .error:
            EmptyView()
        }
    }

    /// Light mode uses the warm input fill; dark mode falls back to a system
    /// semantic surface so the parchment tint doesn't glow on black.
    private var inputFieldFill: Color {
        colorScheme == .dark ? Color(.secondarySystemBackground) : CT.chatInputBg
    }

    private var inputBorder: Color {
        colorScheme == .dark ? Color(.separator) : CT.borderSubtle
    }

    private var textField: some View {
        // Multi-line growth comes free with `axis: .vertical` + lineLimit range.
        TextField(
            NSLocalizedString("chat.input.placeholder", comment: "Type a message…"),
            text: $draftText,
            axis: .vertical
        )
        .lineLimit(1...4)
        .textFieldStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(inputFieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(inputBorder, lineWidth: 0.5)
        )
        .submitLabel(.send)
        .onSubmit(submitDraft)
        .accessibilityLabel(Text(NSLocalizedString("chat.input.placeholder", comment: "Type a message…")))
    }

    private var sendButton: some View {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let canSend = !trimmed.isEmpty
        return Button(action: submitDraft) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title2)
                .foregroundStyle(canSend ? CT.accent : Color.secondary.opacity(0.5))
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.88))
        .disabled(!canSend)
        .accessibilityLabel(Text(NSLocalizedString("chat.input.send.a11y", comment: "Send")))
    }

    private var micButton: some View {
        // `onPressingChanged` fires immediately on touch-down, giving us the
        // sub-frame feedback the redesign demands. `perform` is required by
        // the API but we don't use the long-press fire here — the tap
        // gesture below handles toggle mode.
        let micColor: Color = {
            switch micState {
            case .listening: return CT.sunGoldDeep
            case .thinking:  return CT.accent
            case .error:     return CT.bannerError
            case .idle:      return .primary
            }
        }()
        let isListening = micState == .listening
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        return ZStack {
            shape
                .fill(isListening ? CT.sunGoldSoft : Color(.tertiarySystemBackground))
                .frame(width: 40, height: 40)
                .overlay(
                    shape.strokeBorder(
                        isListening ? CT.sunGold : CT.borderSubtle,
                        lineWidth: isListening ? 1 : 0.5
                    )
                )
            Image(systemName: isListening ? "waveform" : "mic.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(micColor)
                .symbolEffect(
                    .variableColor.iterative,
                    isActive: micState == .listening || micState == .thinking
                )
        }
        .scaleEffect(isListening ? 1.08 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: micState)
        .contentShape(shape)
        .onLongPressGesture(
            minimumDuration: 0.0,
            maximumDistance: .infinity,
            perform: { /* no-op: tap is handled by the simultaneous gesture */ },
            onPressingChanged: { pressing in
                onMicPress(pressing)
            }
        )
        .simultaneousGesture(
            TapGesture().onEnded {
                let isStarting = micState != .listening
                onMicToggle(isStarting)
            }
        )
        .accessibilityLabel(Text(NSLocalizedString("chat.input.mic.a11y", comment: "Voice")))
        .accessibilityHint(Text(NSLocalizedString("chat.input.mic.hint", comment: "Tap to start or stop voice, hold to push-to-talk")))
        .accessibilityAddTraits(.startsMediaSession)
    }

    private func submitDraft() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSend(trimmed)
        draftText = ""
    }
}

#Preview("Idle") {
    StatefulPreviewWrapper(initial: "", micState: .idle, error: nil)
}

#Preview("Listening") {
    StatefulPreviewWrapper(initial: "", micState: .listening, error: nil)
}

#Preview("Thinking") {
    StatefulPreviewWrapper(initial: "Tell me more about that café", micState: .thinking, error: nil)
}

#Preview("Error") {
    StatefulPreviewWrapper(
        initial: "",
        micState: .idle,
        error: "Connection interrupted — please try again"
    )
}

/// Small helper so the previews can mutate `draftText` like the real parent.
private struct StatefulPreviewWrapper: View {
    @State var text: String
    let micState: ChatInputBar.MicState
    let error: String?

    init(initial: String, micState: ChatInputBar.MicState, error: String?) {
        self._text = State(initialValue: initial)
        self.micState = micState
        self.error = error
    }

    var body: some View {
        VStack {
            Spacer()
            ChatInputBar(
                draftText: $text,
                micState: micState,
                errorMessage: error,
                onSend: { _ in },
                onMicToggle: { _ in },
                onMicPress: { _ in },
                onRetry: {}
            )
        }
    }
}
