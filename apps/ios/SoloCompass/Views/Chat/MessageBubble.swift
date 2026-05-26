import SwiftUI

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
    /// When true, renders a soft pulse on the trailing edge to signal that
    /// content is still arriving from the model.
    public let isStreaming: Bool

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
                .background(Color.accentColor, in: bubbleShape)
                .accessibilityLabel(Text(String(
                    format: NSLocalizedString("chat.bubble.user.a11y", comment: "You said: %@"),
                    text
                )))
        }
    }

    private var assistantBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            assistantAvatar
            VStack(alignment: .leading, spacing: 0) {
                Text(text.isEmpty ? " " : text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.thinMaterial, in: bubbleShape)
                    .overlay(alignment: .trailing) {
                        if isStreaming {
                            StreamingCursor()
                                .padding(.trailing, 10)
                        }
                    }
            }
            Spacer(minLength: 48)
        }
        .accessibilityLabel(Text(String(
            format: NSLocalizedString("chat.bubble.assistant.a11y", comment: "Solo said: %@"),
            text
        )))
    }

    private var assistantAvatar: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.15))
            .frame(width: 28, height: 28)
            .overlay {
                Image(systemName: "location.north.line.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityHidden(true)
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
        .padding(.leading, 36) // align under assistant avatar
        .padding(.trailing, 16)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var bubbleShape: some Shape {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
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

/// Animated three-dot 'typing' bubble shown while the agent is thinking or
/// executing a tool and no streamed text has arrived yet.
public struct TypingIndicatorBubble: View {
    /// Optional localized step label (e.g. "🔍 Searching nearby…").
    public let label: String?

    public init(label: String? = nil) {
        self.label = label
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            assistantAvatar
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        BouncingDot(delay: Double(index) * 0.18)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                if let label, !label.isEmpty {
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
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

    private var assistantAvatar: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.15))
            .frame(width: 28, height: 28)
            .overlay {
                Image(systemName: "location.north.line.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityHidden(true)
    }
}

/// Single dot in the typing indicator, bouncing with a staggered delay.
private struct BouncingDot: View {
    let delay: Double
    @State private var bouncing = false

    var body: some View {
        Circle()
            .fill(Color.secondary.opacity(0.6))
            .frame(width: 7, height: 7)
            .offset(y: bouncing ? -4 : 0)
            .opacity(bouncing ? 1.0 : 0.5)
            .animation(
                .easeInOut(duration: 0.5)
                    .repeatForever(autoreverses: true)
                    .delay(delay),
                value: bouncing
            )
            .onAppear { bouncing = true }
            .accessibilityHidden(true)
    }
}

/// Soft pulsing dot rendered on the trailing edge of a streaming bubble.
/// Pure visual — has no semantic meaning for VoiceOver.
private struct StreamingCursor: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 6, height: 6)
            .opacity(pulse ? 0.3 : 1.0)
            .animation(
                .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                value: pulse
            )
            .onAppear { pulse = true }
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
}
