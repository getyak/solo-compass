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

    @Environment(\.colorScheme) private var colorScheme

    public init(
        role: VoiceAgentSession.Role,
        text: String,
        toolName: String? = nil,
        isStreaming: Bool = false
    ) {
        self.role = role
        self.text = text
        self.toolName = toolName
        self.isStreaming = isStreaming
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
            Spacer(minLength: 48)
            Text(text)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(CT.accent, in: bubbleShape)
                .overlay(bubbleShape.strokeBorder(CT.accentBorder, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
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
        }
    }

    private var assistantBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            AssistantAvatar()
            VStack(alignment: .leading, spacing: 0) {
                // Assistant replies render Markdown (code/lists/links/quotes).
                // Streaming throttle (batched ~50–80 chars / ~80ms) lives in the
                // orchestrator (Phase D) so this view re-renders smoothly.
                MarkdownMessageText(text: text.isEmpty ? " " : text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    // background{shape.fill.shadow} lets the soft shadow escape
                    // the rounded clip instead of being chopped by it.
                    .background {
                        bubbleShape
                            .fill(MessageBubble.assistantFill(colorScheme))
                            .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
                    }
                    .overlay(bubbleShape.strokeBorder(CT.borderSubtle, lineWidth: 0.5))
                    .overlay(alignment: .trailing) {
                        if isStreaming {
                            StreamingCursor()
                                .padding(.trailing, 10)
                        }
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
            }
            Spacer(minLength: 48)
        }
        .accessibilityLabel(Text(String(
            format: NSLocalizedString("chat.bubble.assistant.a11y", comment: "Solo said: %@"),
            text
        )))
        .accessibilityAction(named: Text(NSLocalizedString("chat.bubble.copy", comment: "Copy bubble text"))) {
            copyText()
        }
    }

    /// AI bubble fill: warm white in light mode, the dark token in dark mode so
    /// the parchment surface doesn't glare on a near-black background.
    static func assistantFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? CT.chatAIBubbleBgDark : CT.surfaceWhite
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

    private var bubbleShape: some InsettableShape {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
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
        HStack(alignment: .top, spacing: 8) {
            AssistantAvatar()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        BouncingDot(delay: Double(index) * 0.18)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(MessageBubble.assistantFill(colorScheme))
                        .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
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

/// Blinking caret rendered on the trailing edge of a streaming bubble, echoing
/// a text-cursor so the live response reads as "still typing". Pure visual —
/// no semantic meaning for VoiceOver.
private struct StreamingCursor: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(CT.accent)
            .frame(width: 2, height: 14)
            .opacity(visible ? 1.0 : 0.15)
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: 0.55).repeatForever(autoreverses: true),
                value: visible
            )
            .onAppear { if !reduceMotion { visible = false } }
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
        MessageBubble(role: .user, text: "What's good around me?")
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
