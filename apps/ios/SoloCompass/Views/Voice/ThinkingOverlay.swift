import SwiftUI

/// Inline overlay that appears on the map while the voice agent is
/// thinking or executing tools. Shows the current step label and
/// streams the growing assistant text word-by-word.
///
/// Designed to be placed in a ZStack above the map. Auto-hides when
/// both `stepLabel` and `streamingText` are empty.
public struct ThinkingOverlay: View {
    /// e.g. "🔍 Searching nearby…", "Thinking…", ""
    public let stepLabel: String
    /// Partial assistant text being streamed in.
    public let streamingText: String
    /// Whether a tool is currently executing (drives spinner visibility).
    public let isExecutingTool: Bool
    /// When non-nil, shown as an error banner above the thinking content.
    public let errorMessage: String?

    public init(
        stepLabel: String,
        streamingText: String,
        isExecutingTool: Bool,
        errorMessage: String? = nil
    ) {
        self.stepLabel = stepLabel
        self.streamingText = streamingText
        self.isExecutingTool = isExecutingTool
        self.errorMessage = errorMessage
    }

    private var isVisible: Bool {
        !stepLabel.isEmpty || !streamingText.isEmpty || errorMessage != nil
    }

    public var body: some View {
        if isVisible {
            VStack(alignment: .leading, spacing: 6) {
                if let error = errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.exclamationmark")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    .transition(.opacity)
                }

                if !stepLabel.isEmpty {
                    HStack(spacing: 8) {
                        if isExecutingTool || streamingText.isEmpty {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(stepLabel)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                }

                if !streamingText.isEmpty {
                    Text(streamingText)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            .padding(.horizontal, 16)
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text([errorMessage, stepLabel, streamingText].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ". ")))
        }
    }
}

#Preview("thinking") {
    ZStack {
        Color.gray.opacity(0.2).ignoresSafeArea()
        VStack {
            ThinkingOverlay(
                stepLabel: "🔍 Searching nearby…",
                streamingText: "",
                isExecutingTool: true
            )
            Spacer()
        }
        .padding(.top, 120)
    }
}

#Preview("streaming response") {
    ZStack {
        Color.gray.opacity(0.2).ignoresSafeArea()
        VStack {
            ThinkingOverlay(
                stepLabel: "",
                streamingText: "There's a great ramen spot about 200m away — Ichiran has private solo booths and opens at 11am.",
                isExecutingTool: false
            )
            Spacer()
        }
        .padding(.top, 120)
    }
}
