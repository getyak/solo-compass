import SwiftUI

/// The "living" entry orb used at the top of the chat sheet's half-expanded
/// empty state. Replaces the static sparkles disc with a soft, slowly-breathing
/// circle so the sheet reads as a doorway to a present, attentive companion —
/// not a feature panel. Two halos + a gradient core scale-pulse on a 3.2s
/// cycle; reduceMotion lands it static.
///
/// Purely decorative — hidden from VoiceOver.
@MainActor
struct SoloOrb: View {
    /// Diameter of the inner gradient core. Halos scale relative to this.
    var size: CGFloat = 64

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        ZStack {
            // Outer ambient bloom — barely-there warmth that softens the edge.
            Circle()
                .fill(CT.accent.opacity(colorScheme == .dark ? 0.18 : 0.10))
                .frame(width: size * 1.75, height: size * 1.75)
                .blur(radius: size * 0.22)
                .scaleEffect(breathing ? 1.06 : 0.94)
                .opacity(breathing ? 1.0 : 0.78)

            // Mid ring — a thin warm border floating just outside the core.
            Circle()
                .strokeBorder(
                    CT.sunGold.opacity(colorScheme == .dark ? 0.34 : 0.42),
                    lineWidth: 1
                )
                .frame(width: size * 1.26, height: size * 1.26)
                .scaleEffect(breathing ? 1.03 : 0.98)

            // Core — gradient amber fill with a hairline highlight + sparkles.
            Circle()
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [CT.accent, CT.accentHover]
                            : [CT.sunGoldSoft, CT.accentSoft],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Circle().strokeBorder(
                        Color.white.opacity(colorScheme == .dark ? 0.10 : 0.55),
                        lineWidth: 0.75
                    )
                )
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? Color.white : CT.accent)
                )
                .shadow(color: CT.accent.opacity(colorScheme == .dark ? 0.45 : 0.18), radius: size * 0.18, y: 4)
                .scaleEffect(breathing ? 1.02 : 0.98)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Solo Orb — light") {
    VStack(spacing: 40) {
        SoloOrb(size: 48)
        SoloOrb(size: 64)
        SoloOrb(size: 80)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(CT.bgWarm)
}

#Preview("Solo Orb — dark") {
    VStack(spacing: 40) {
        SoloOrb(size: 64)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
    .preferredColorScheme(.dark)
}
