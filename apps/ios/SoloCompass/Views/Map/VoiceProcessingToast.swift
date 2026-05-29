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
            ProgressView()
                .scaleEffect(0.8)
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

#Preview {
    VoiceProcessingToast(text: "Thinking about “coffee near me”…")
        .padding()
}
