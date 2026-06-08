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

    /// Preview-only override that forces the static-spinner branch. `nil` in
    /// production so the live `@Environment` value drives the choice; previews
    /// can't override the read-only `accessibilityReduceMotion` env key.
    var forceReduceMotion: Bool? = nil

    @Environment(\.accessibilityReduceMotion) private var environmentReduceMotion

    private var reduceMotion: Bool { forceReduceMotion ?? environmentReduceMotion }

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
            UIAccessibility.post(notification: .announcement, argument: text)
        }
        .onChange(of: text) { _, newValue in
            UIAccessibility.post(notification: .announcement, argument: newValue)
        }
    }
}

/// Three dots that animate as a continuous left-to-right traveling wave,
/// each dot peaking in scale and opacity in sequence with overlapping easing.
private struct ThinkingDots: View {
    @State private var animate = false

    private let dotSize: CGFloat = 4
    private let dotCount = 3
    private let waveDuration = 0.6
    private let dotDelay = 0.15

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .fill(.secondary)
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(animate ? 1.4 : 1.0)
                    .opacity(animate ? 1.0 : 0.4)
                    .animation(
                        .easeInOut(duration: waveDuration)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * dotDelay),
                        value: animate
                    )
            }
        }
        .accessibilityHidden(true)
        .onAppear { animate = true }
    }
}

#Preview("Animated — traveling wave") {
    VoiceProcessingToast(text: "Thinking about \"coffee near me\"…")
        .padding()
}

#Preview("Wave dots only") {
    ThinkingDots()
        .padding()
        .background(.thinMaterial, in: Capsule())
        .padding()
}

#Preview("Reduce Motion") {
    // `accessibilityReduceMotion` is a read-only EnvironmentValues key (it
    // reflects the system setting), so it can't be overridden via
    // `.environment(_:_:)`, which needs a WritableKeyPath. Drive the static
    // spinner branch directly via the `forceReduceMotion` preview hook instead.
    VoiceProcessingToast(
        text: "Thinking about \"coffee near me\"…",
        forceReduceMotion: true
    )
    .padding()
}
