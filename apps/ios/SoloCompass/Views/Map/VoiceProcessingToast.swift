import SwiftUI

/// US-008: The "AI is thinking about your request…" toast shown while a voice
/// intent is being processed.
///
/// VoiceOver users do not automatically move focus to a transient toast, so
/// the toast posts a `UIAccessibility` announcement on appear and whenever its
/// text changes, and carries the `.updatesFrequently` trait so assistive
/// technologies treat it as live, frequently-changing content.
struct VoiceProcessingToast: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Builds the localized toast string for a given (possibly long) voice
    /// transcript, truncating it to keep the capsule to a single line.
    static func localizedText(for transcript: String) -> String {
        String(
            format: NSLocalizedString("voice.processing", comment: "AI is thinking about your request"),
            transcript.truncated(limit: 30)
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            if reduceMotion {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                ThinkingDots()
            }
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .accessibilityIdentifier("voiceProcessingToast")
        .accessibilityElement()
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityLabel(Text(text))
        .onAppear {
            UIAccessibility.post(.announcement, argument: text)
        }
        .onChange(of: text) { _, newValue in
            UIAccessibility.post(.announcement, argument: newValue)
        }
    }
}

/// Three sequential dots that animate one at a time to suggest AI deliberation.
private struct ThinkingDots: View {
    @State private var phase: Int = 0
    @State private var advanceTask: Task<Void, Never>?

    private let dotSize: CGFloat = 4
    private let dotCount = 3

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .fill(.secondary)
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(phase == index ? 1.4 : 1.0)
                    .opacity(phase == index ? 1.0 : 0.4)
                    .animation(.easeInOut(duration: 0.4), value: phase)
            }
        }
        .accessibilityHidden(true)
        .onAppear {
            advanceTask = Task { @MainActor in
                await advancePhase()
            }
        }
        .onDisappear {
            advanceTask?.cancel()
            advanceTask = nil
        }
    }

    @MainActor
    private func advancePhase() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            phase = (phase + 1) % dotCount
        }
    }
}

#Preview("Animated") {
    VoiceProcessingToast(text: "Thinking about \"coffee near me\"…")
        .padding()
}

#Preview("Reduce Motion") {
    VoiceProcessingToast(text: "Thinking about \"coffee near me\"…")
        .environment(\.accessibilityReduceMotion, true)
        .padding()
}
