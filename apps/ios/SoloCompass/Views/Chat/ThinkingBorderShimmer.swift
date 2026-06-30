import SwiftUI

/// A calm, accent-tinted highlight that sweeps around the input field's border
/// while Solo is thinking — the GPT-5 "composer is busy" cue. Adds visual
/// presence without a second text label, keeping the AgentStatusLine as the
/// single source of thinking-state truth in the message list.
///
/// Implementation: an `AngularGradient` rotates inside an 18pt rounded-rect
/// stroke. Strictly decorative — hidden from VoiceOver. Respects
/// `accessibilityReduceMotion` (renders static).
@MainActor
struct ThinkingBorderShimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Double = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(gradient, lineWidth: 1.1)
            .opacity(0.85)
            .rotationEffect(.degrees(reduceMotion ? 0 : phase))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 360
                }
            }
            .accessibilityHidden(true)
    }

    private var gradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(stops: [
                .init(color: CT.accent.opacity(0.0), location: 0.0),
                .init(color: CT.accent.opacity(0.0), location: 0.55),
                .init(color: CT.accent.opacity(0.55), location: 0.75),
                .init(color: CT.sunGold.opacity(0.7), location: 0.85),
                .init(color: CT.accent.opacity(0.0), location: 1.0),
            ]),
            center: .center
        )
    }
}

#Preview("Thinking Shimmer") {
    VStack(spacing: 24) {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(CT.surfaceWhite)
            .frame(height: 46)
            .overlay {
                ThinkingBorderShimmer()
            }
            .padding(.horizontal)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(CT.bgWarm)
}
