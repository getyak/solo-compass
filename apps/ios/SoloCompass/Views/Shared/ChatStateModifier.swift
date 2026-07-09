import SwiftUI

// MARK: - ChatStateModifier

/// One ViewModifier per ChatUIState. Applied to the chat container to
/// communicate state through border, tint, and animation.
struct ChatStateModifier: ViewModifier {
    let state: ChatUIState
    @State private var pulseScale: CGFloat = 1.0
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        switch state {
        case .idle:
            content.modifier(IdleModifier())
        case .listening:
            content.modifier(ListeningModifier(reduceMotion: reduceMotion))
        case .processing:
            content.modifier(ProcessingModifier())
        case .responding(let text):
            content.modifier(RespondingModifier(text: text))
        case .error(let err):
            content.modifier(ErrorModifier(error: err))
        case .unconfigured:
            content.modifier(UnconfiguredModifier())
        }
    }
}

// MARK: - State-specific modifiers

private struct IdleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
    }
}

private struct ListeningModifier: ViewModifier {
    let reduceMotion: Bool
    @State private var pulse: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(CT.accent, lineWidth: 2)
                    .scaleEffect(pulse)
                    .opacity(reduceMotion ? 1 : 2 - pulse)
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulse = 1.06
                }
            }
    }
}

private struct ProcessingModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(CT.accent.opacity(0.5), lineWidth: 1.5)
            )
            .overlay(alignment: .topTrailing) {
                ProgressView()
                    .scaleEffect(0.7)
                    .padding(8)
            }
    }
}

private struct RespondingModifier: ViewModifier {
    let text: String

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(CT.verifiedGreen.opacity(0.5), lineWidth: 1.5)
            )
    }
}

private struct ErrorModifier: ViewModifier {
    let error: ChatError

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(CT.savedRed, lineWidth: 2)
            )
    }
}

private struct UnconfiguredModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(CT.warningText.opacity(0.6), lineWidth: 1.5)
            )
            .tint(CT.warningText)
    }
}

// MARK: - View extension

extension View {
    func chatState(_ state: ChatUIState) -> some View {
        modifier(ChatStateModifier(state: state))
    }
}

// MARK: - Preview

#Preview("All Chat States") {
    ScrollView {
        VStack(spacing: 20) {
            ForEach([
                ("Idle", ChatUIState.idle),
                ("Listening", .listening),
                ("Processing", .processing),
                ("Responding", .responding("Great spot for solo travel!")),
                ("Error Network", .error(.network)),
                ("Error API Key", .error(.apiKey)),
                ("Unconfigured", .unconfigured),
            ], id: \.0) { label, state in
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                        .frame(height: 80)
                        .chatState(state)
                }
            }
        }
        .padding()
    }
}
