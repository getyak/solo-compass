import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// One conversational row inside `ChatSheet`. Renders user, assistant, and
/// tool messages with Messenger-style alignment. Tool rows collapse to a
/// subtle inline indicator (e.g. "🔍 Searched nearby") rather than a full
/// bubble — the user doesn't need to read raw JSON.
///
/// Use `isStreaming = true` for the live assistant bubble whose text is
/// updating word-by-word from `orchestrator.streamingContent`.
@MainActor
public struct MessageBubble: View {
    public let role: VoiceAgentSession.Role
    public let text: String
    /// For tool rows: the tool name (e.g. "explore_nearby"). Ignored for
    /// user/assistant rows.
    public let toolName: String?
    /// When true, renders a blinking caret on the trailing edge to signal that
    /// content is still arriving from the model.
    public let isStreaming: Bool
    /// For voice-transcribed user messages: the recording length (e.g. "0:03").
    /// When set, a small mono "VOICE · 0:03" badge floats above the bubble —
    /// mirrors the design-handoff `voice-chip` so a spoken turn reads differently
    /// from a typed one. Nil (the default) hides the badge.
    public let voiceDuration: String?

    @Environment(\.colorScheme) private var colorScheme
    /// User-turn long-text collapse state. WeChat-style: >240 chars or
    /// multi-line content clips to a preview until the traveler taps to
    /// expand. Assistant / streaming bubbles are unaffected.
    @State private var isExpanded: Bool = false

    /// Threshold above which a user bubble collapses. 240 chars ≈ 6 lines
    /// on iPhone width — enough to write a real sentence but small enough
    /// to spare the scroll view a paragraph dump.
    private static let collapseThreshold: Int = 240

    public init(
        role: VoiceAgentSession.Role,
        text: String,
        toolName: String? = nil,
        isStreaming: Bool = false,
        voiceDuration: String? = nil
    ) {
        self.role = role
        self.text = text
        self.toolName = toolName
        self.isStreaming = isStreaming
        self.voiceDuration = voiceDuration
    }

    private var isLongUserText: Bool {
        role == .user && text.count > Self.collapseThreshold
    }

    public var body: some View {
        switch role {
        case .user:
            userBubble
        case .assistant:
            assistantBubble
        case .tool:
            toolIndicator
        case .system:
            // System prompts are internal — never rendered.
            EmptyView()
        }
    }

    // MARK: - Bubbles

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 64)
            VStack(alignment: .trailing, spacing: 6) {
                if let voiceDuration {
                    voiceBadge(voiceDuration)
                }
                if isLongUserText && !isExpanded {
                    collapsedUserBubble
                } else {
                    expandedUserBubble
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isExpanded)
    }

    /// Collapsed WeChat-style preview: first ~3 lines with a fade + tap
    /// affordance. Tapping the bubble expands to the full text.
    private var collapsedUserBubble: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(text)
                .font(.system(size: 15, weight: .regular, design: .default))
                .lineSpacing(4)
                .foregroundStyle(.white)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: 260, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(CT.accent, in: userBubbleShape)
                .shadow(color: CT.accent.opacity(0.14), radius: 8, y: 3)

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    isExpanded = true
                }
            } label: {
                HStack(spacing: 3) {
                    Text(NSLocalizedString(
                        "chat.bubble.expand",
                        value: "查看原文",
                        comment: "Expand a collapsed long user message"
                    ))
                    .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(CT.accent.opacity(0.75))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(CT.accentSoft)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chat.bubble.expand")
        }
    }

    /// Full-text bubble (default for short messages, and for long ones after
    /// expansion). Typography aligns to SF Pro Text with generous line
    /// spacing + rounded corners tuned to iMessage/Claude-style aesthetics.
    private var expandedUserBubble: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(text)
                .font(.system(size: 15, weight: .regular, design: .default))
                .lineSpacing(4)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .background(CT.accent, in: userBubbleShape)
                .shadow(color: CT.accent.opacity(0.14), radius: 8, y: 3)
                .accessibilityLabel(Text(String(
                    format: NSLocalizedString("chat.bubble.user.a11y", comment: "You said: %@"),
                    text
                )))
                .accessibilityAction(named: Text(NSLocalizedString("chat.bubble.copy", comment: "Copy bubble text"))) {
                    copyText()
                }
                .contextMenu {
                    if !text.isEmpty && !isStreaming {
                        Button {
                            copyText()
                        } label: {
                            Label(
                                NSLocalizedString("chat.bubble.copy", comment: "Copy bubble text"),
                                systemImage: "doc.on.doc"
                            )
                        }
                    }
                }

            if isLongUserText && isExpanded {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        isExpanded = false
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(NSLocalizedString(
                            "chat.bubble.collapse",
                            value: "收起",
                            comment: "Collapse an expanded long user message"
                        ))
                        .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(CT.accent.opacity(0.75))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(CT.accentSoft))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .accessibilityIdentifier("chat.bubble.collapse")
            }
        }
    }

    /// Mono "VOICE · 0:03" chip above a spoken user turn (design `voice-chip`).
    private func voiceBadge(_ duration: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "mic.fill")
                .font(.system(size: 8, weight: .semibold))
            Text(String(
                format: NSLocalizedString("chat.input.voiceBadge", comment: "VOICE · %@"),
                duration
            ))
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            .tracking(0.6)
        }
        .foregroundStyle(CT.fgSubtle)
        .padding(.trailing, 4)
        .accessibilityHidden(true)
    }

    private var assistantBubble: some View {
        // Editorial voice — no bubble, no border. The assistant reply sits
        // directly on the warm sheet in a serif body face with generous
        // leading, so a long answer reads like a letter rather than a chat
        // chrome block. Tokens fade in (handled in ChatSheet via .transition);
        // no blinking caret — the cursor was visual noise at scale.
        HStack(spacing: 0) {
            MarkdownMessageText(
                text: MessageBubble.renderCitations(text.isEmpty ? " " : text),
                bodyFont: .system(size: 16, design: .serif),
                bodyLineSpacing: 6
            )
                .foregroundStyle(MessageBubble.assistantTextColor(colorScheme))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(isStreaming ? "streaming-\(text.count)" : "final")
                .transition(.opacity)
                .animation(.easeOut(duration: 0.18), value: text)
                .contextMenu {
                    if !text.isEmpty && !isStreaming {
                        Button {
                            copyText()
                        } label: {
                            Label(
                                NSLocalizedString("chat.bubble.copy", comment: "Copy bubble text"),
                                systemImage: "doc.on.doc"
                            )
                        }
                    }
                }
            Spacer(minLength: 24)
        }
        .accessibilityLabel(Text(String(
            format: NSLocalizedString("chat.bubble.assistant.a11y", comment: "Solo said: %@"),
            text
        )))
        .accessibilityAction(named: Text(NSLocalizedString("chat.bubble.copy", comment: "Copy bubble text"))) {
            copyText()
        }
    }

    /// AI bubble fill — kept for `TypingIndicatorBubble` compatibility. The main
    /// assistant message no longer uses a bubble; it sits directly on the warm
    /// sheet in serif body text.
    static func assistantFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? CT.chatAIBubbleBgDark : CT.surfaceWhite
    }

    /// Editorial body color for the bubble-less assistant text. Slightly softer
    /// than pure primary so long passages read like newsprint instead of headlines.
    static func assistantTextColor(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? CT.fgPrimaryDark : CT.fgPrimary
    }

    private var toolIndicator: some View {
        // Intentional terminology — see project anti-pattern policy.
        HStack(spacing: 6) {
            Image(systemName: toolIconName)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(toolLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.leading, 40) // align under assistant avatar (32 + 8 spacing)
        .padding(.trailing, 16)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// User bubble: even 18pt rounded rectangle. The old tucked corner pointed
    /// toward the sender, but top-tier chat apps (Claude / ChatGPT / iMessage
    /// 2025) settled on symmetric rounded rects — the alignment + color already
    /// signal authorship, no tail required.
    private var userBubbleShape: some InsettableShape {
        // 20pt matches iMessage 2024 / Claude iOS chat bubble radius — the
        // sweet spot between iOS 6 pill (too playful) and Material Design
        // sharp corners (too utilitarian) for a warm, editorial tone.
        RoundedRectangle(cornerRadius: 20, style: .continuous)
    }

    // MARK: - Actions

    private func copyText() {
        guard !text.isEmpty, !isStreaming else { return }
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        Haptics.notify(.success)
        #endif
    }

    // MARK: - Tool helpers

    private var toolLabel: String {
        switch toolName ?? "" {
        case "explore_nearby":
            return NSLocalizedString("chat.tool.exploreNearby", comment: "Searched nearby")
        case "filter_by_category":
            return NSLocalizedString("chat.tool.filter", comment: "Filtered the map")
        case "show_details":
            return NSLocalizedString("chat.tool.showDetails", comment: "Opened a place")
        case "save_to_favorites":
            return NSLocalizedString("chat.tool.save", comment: "Saved to favorites")
        case "dismiss_recommendation":
            return NSLocalizedString("chat.tool.dismiss", comment: "Hid a place")
        case "search_places":
            return NSLocalizedString("chat.tool.search", comment: "Searched places")
        case "navigate_to":
            return NSLocalizedString("chat.tool.navigate", comment: "Opened directions")
        default:
            return NSLocalizedString("chat.tool.generic", comment: "Ran an action")
        }
    }

    private var toolIconName: String {
        switch toolName ?? "" {
        case "explore_nearby", "search_places":
            return "magnifyingglass"
        case "filter_by_category":
            return "line.3.horizontal.decrease.circle"
        case "show_details":
            return "mappin.and.ellipse"
        case "save_to_favorites":
            return "heart"
        case "dismiss_recommendation":
            return "xmark"
        case "navigate_to":
            return "arrow.triangle.turn.up.right.circle"
        default:
            return "gearshape"
        }
    }

    // MARK: - Beta-P0-E: citation rendering
    //
    // The assistant's system prompt now requires that any place mentioned by
    // name be tagged with [exp:<id>] (or the sentence prefixed with "Guess —"
    // when the model is hunching). We translate those tags into a small
    // markdown link so the user can visually distinguish a Solo-grounded
    // recommendation from a free-form guess. The link target is a custom
    // scheme `solocompass://experience/<id>` — ChatSheet's openURL handler
    // (or the system-wide handler) can route this to the detail screen.
    // Streaming tokens that contain an incomplete `[exp:` are left alone so
    // a partial fragment doesn't render as a broken link mid-stream.
    nonisolated static func renderCitations(_ text: String) -> String {
        guard text.contains("[exp:") else { return text }
        let pattern = #"\[exp:([A-Za-z0-9._\-]+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        let mutable = NSMutableString(string: text)
        let range = NSRange(location: 0, length: mutable.length)
        regex.replaceMatches(
            in: mutable,
            options: [],
            range: range,
            withTemplate: " [↗](solocompass://experience/$1)"
        )
        return mutable as String
    }
}

/// Shared compass-mark avatar for the assistant. Used by both `MessageBubble`
/// and `TypingIndicatorBubble` so the two stay visually in sync and we don't
/// duplicate the styling.
@MainActor
struct AssistantAvatar: View {
    var body: some View {
        Circle()
            .fill(CT.sunGoldSoft)
            .frame(width: 32, height: 32)
            .overlay {
                Image(systemName: "location.north.line.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(CT.sunGoldDeep)
            }
            .overlay(Circle().strokeBorder(CT.accentBorder, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
            .accessibilityHidden(true)
    }
}

/// Animated three-dot 'typing' bubble shown while the agent is thinking or
/// executing a tool and no streamed text has arrived yet.
@MainActor
public struct TypingIndicatorBubble: View {
    /// Optional localized step label (e.g. "🔍 Searching nearby…").
    public let label: String?

    @Environment(\.colorScheme) private var colorScheme

    public init(label: String? = nil) {
        self.label = label
    }

    public var body: some View {
        // Avatar-free to match `MessageBubble.assistantBubble` — the typing
        // bubble sits left-aligned in the same warm parchment fill.
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        BouncingDot(delay: Double(index) * 0.18)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background {
                    typingBubbleShape
                        .fill(MessageBubble.assistantFill(colorScheme))
                }
                .overlay(
                    typingBubbleShape
                        .strokeBorder(CT.borderSubtle, lineWidth: 0.5)
                )

                if let label, !label.isEmpty {
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(stepPillFill, in: Capsule())
                        .overlay(Capsule().strokeBorder(CT.borderSubtle, lineWidth: 0.5))
                        .transition(.opacity)
                }
            }
            Spacer(minLength: 48)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(NSLocalizedString(
            "chat.typing.a11y",
            comment: "VoiceOver label for the typing indicator — Solo Compass is thinking…"
        )))
    }

    private var stepPillFill: Color {
        colorScheme == .dark ? Color(.secondarySystemBackground) : CT.surfaceSunken
    }

    /// Match `MessageBubble.assistantBubbleShape` — left-tucked tail so the
    /// thinking bubble reads as Solo's, same as the replies that follow it.
    private var typingBubbleShape: some InsettableShape {
        UnevenRoundedRectangle(
            topLeadingRadius: 18,
            bottomLeadingRadius: 5,
            bottomTrailingRadius: 18,
            topTrailingRadius: 18,
            style: .continuous
        )
    }
}

/// Single dot in the typing indicator, bouncing with a staggered delay.
private struct BouncingDot: View {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bouncing = false

    var body: some View {
        Circle()
            .fill(CT.fgSubtle)
            .frame(width: 7, height: 7)
            .offset(y: bouncing ? -4 : 0)
            .opacity(bouncing ? 1.0 : 0.5)
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: 0.5)
                        .repeatForever(autoreverses: true)
                        .delay(delay),
                value: bouncing
            )
            .onAppear { if !reduceMotion { bouncing = true } }
            .accessibilityHidden(true)
    }
}

#Preview("Typing Indicator") {
    VStack(alignment: .leading, spacing: 12) {
        TypingIndicatorBubble()
        TypingIndicatorBubble(label: "🔍 Searching nearby…")
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(CT.bgWarm)
}

#Preview("Conversation") {
    VStack(alignment: .leading, spacing: 12) {
        MessageBubble(role: .user, text: "What's good around me?", voiceDuration: "0:03")
        MessageBubble(
            role: .tool,
            text: "{}",
            toolName: "explore_nearby"
        )
        MessageBubble(
            role: .assistant,
            text: "I found 5 quiet cafés within walking distance. Café Zenith looks like your best bet — it's calm, has good wifi, and a 9.4/10 solo score."
        )
        MessageBubble(role: .user, text: "Take me to Café Zenith.")
        MessageBubble(
            role: .assistant,
            text: "Opening directions now…",
            isStreaming: true
        )
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(CT.bgWarm)
}
