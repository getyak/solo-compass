import SwiftUI
import MarkdownUI

// The app defines its own `Theme` protocol (Services/Themes/Theme.swift), which
// shadows `MarkdownUI.Theme` when referenced unqualified. Alias the library type
// so this file's chat theme builds against the correct concrete struct.
private typealias MarkdownTheme = MarkdownUI.Theme

/// Renders an LLM chat reply as Markdown inside a chat bubble.
///
/// Wraps `MarkdownUI`'s `Markdown(_:)` with a compact, chat-tuned theme that
/// reuses the `CT` design tokens (no hardcoded colors) and adapts to light/dark
/// via `@Environment(\.colorScheme)`. Headings/lists/quotes use modest margins
/// because this lives inside a bubble — full document spacing would look loud.
///
/// Only the assistant bubble uses this; user bubbles stay plain `Text`.
@MainActor
struct MarkdownMessageText: View {
    let text: String

    @Environment(\.colorScheme) private var colorScheme

    init(text: String) {
        self.text = text
    }

    var body: some View {
        Markdown(text)
            .markdownTheme(chatTheme)
            // Body text matches the surrounding bubble: system body, primary fg.
            .font(.body)
            .foregroundStyle(.primary)
    }

    // MARK: - Theme

    /// Subtle, dark-aware fill for inline code & code blocks. Sunken parchment
    /// in light mode; a touch lighter than the dark bubble fill in dark mode so
    /// the code chip reads as inset without glaring.
    private var codeBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.14)   // readable inset on the #28241E bubble
            : CT.surfaceSunken
    }

    private var chatTheme: MarkdownTheme {
        MarkdownTheme()
            // Base text inherits the bubble's font/foreground.
            .text {
                FontSize(UIFont.preferredFont(forTextStyle: .body).pointSize)
            }
            // Inline `code`: monospaced, subtle inset background, readable fg.
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.94))
                ForegroundColor(.primary)
                BackgroundColor(codeBackground)
            }
            // Links: accent-colored + underlined.
            .link {
                ForegroundColor(CT.accent)
                UnderlineStyle(.single)
            }
            // Headings — modest margins so they don't dominate the bubble.
            .heading1 { configuration in
                configuration.label
                    .markdownMargin(top: .em(0.5), bottom: .em(0.3))
                    .markdownTextStyle {
                        FontWeight(.bold)
                        FontSize(.em(1.3))
                    }
            }
            .heading2 { configuration in
                configuration.label
                    .markdownMargin(top: .em(0.45), bottom: .em(0.28))
                    .markdownTextStyle {
                        FontWeight(.bold)
                        FontSize(.em(1.18))
                    }
            }
            .heading3 { configuration in
                configuration.label
                    .markdownMargin(top: .em(0.4), bottom: .em(0.25))
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.08))
                    }
            }
            // Paragraphs: tight vertical rhythm for chat density.
            .paragraph { configuration in
                configuration.label
                    .markdownMargin(top: .em(0.2), bottom: .em(0.2))
            }
            // Ordered / unordered / task lists: modest indent + spacing.
            .list { configuration in
                configuration.label
                    .markdownMargin(top: .em(0.2), bottom: .em(0.2))
            }
            .listItem { configuration in
                configuration.label
                    .markdownMargin(top: .em(0.08))
            }
            // Blockquote: accent left rule, muted fg, light inset.
            .blockquote { configuration in
                configuration.label
                    .padding(.leading, 12)
                    .padding(.vertical, 2)
                    .foregroundStyle(.secondary)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(CT.accentBorder)
                            .frame(width: 3)
                    }
                    .markdownMargin(top: .em(0.25), bottom: .em(0.25))
            }
            // Fenced code blocks: render the raw `configuration.content` with our
            // own monospaced `Text` rather than `configuration.label`. MarkdownUI's
            // default code-block label wraps the lines in a container that renders
            // blank under `ImageRenderer` (share cards / snapshots) — using the
            // plain string guarantees the code is always visible and wraps inside
            // the bubble instead of overflowing.
            .codeBlock { configuration in
                Text(configuration.content)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(codeBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .markdownMargin(top: .em(0.3), bottom: .em(0.3))
            }
    }
}

#Preview("Markdown Message") {
    let sample = """
    # Trip ideas
    Here's a **bold** plan with some *italic* nuance and an inline `solo_score` tag.

    ```swift
    func recommend(_ city: String) -> [Experience] {
        experiences.filter { $0.soloScore > 8.5 }
    }
    ```

    Unordered:
    - Quiet café with wifi
    - Sunrise viewpoint
    - Riverside walk

    Ordered:
    1. Coffee at Café Zenith
    2. Walk to the old town
    3. Sunset at the pier

    > Travel light — the map is the home screen.

    More at [Solo Compass](https://example.com).
    """

    ScrollView {
        MarkdownMessageText(text: sample)
            .padding(14)
            .frame(maxWidth: 320, alignment: .leading)
            .background(CT.surfaceWhite, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding()
    }
    .background(CT.bgWarm)
}

#Preview("Markdown Message — Dark") {
    let sample = """
    Here's a **bold** plan with *italic* nuance and inline `solo_score`.

    ```swift
    func recommend(_ city: String) -> [Experience] {
        experiences.filter { $0.soloScore > 8.5 }
    }
    ```

    > Travel light — the map is the home screen.

    More at [Solo Compass](https://example.com).
    """

    ScrollView {
        MarkdownMessageText(text: sample)
            .padding(14)
            .frame(maxWidth: 320, alignment: .leading)
            .background(CT.chatAIBubbleBgDark, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding()
    }
    .background(Color.black)
    .preferredColorScheme(.dark)
}
