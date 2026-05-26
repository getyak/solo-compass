import SwiftUI

/// "Solo 8.5" pill. Compact form for cards, expanded form for the detail sheet.
public struct SoloScoreBadge: View {
    let score: SoloScore
    var style: Style = .compact

    public enum Style { case compact, full }

    @State private var animatedScore: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(score: SoloScore, style: Style = .compact) {
        self.score = score
        self.style = style
    }

    public var body: some View {
        switch style {
        case .compact: compactView
        case .full: fullView
        }
    }

    private var compactView: some View {
        HStack(spacing: 4) {
            Text(NSLocalizedString("solo.label", comment: "Solo"))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.9))
            Text(formatted(score.overall))
                .font(.caption.bold())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(score.scoreColor.opacity(0.95))
        )
        .accessibilityLabel(Text(String(
            format: NSLocalizedString("solo.a11y", comment: "Solo Score %@ of 10"),
            formatted(score.overall)
        )))
    }

    private var fullView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(NSLocalizedString("solo.scoreTitle", comment: "Solo Score"))
                    .font(.headline)
                Spacer()
                Text(formatted(animatedScore))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(score.scoreColor)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: animatedScore))
                    .accessibilityLabel(Text(String(
                        format: NSLocalizedString("solo.a11y", comment: "Solo Score %@ of 10"),
                        formatted(score.overall)
                    )))
            }
            if let hint = score.hint {
                Text(hint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            // Per-dimension breakdown intentionally omitted: the detail view
            // renders SoloScoreRadarChart directly below this badge, so a
            // second bar list would duplicate it. This badge is the score
            // header only (overall + hint).
        }
        .onAppear {
            if reduceMotion {
                animatedScore = score.overall
            } else {
                withAnimation(.easeOut(duration: 0.7)) {
                    animatedScore = score.overall
                }
            }
        }
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

#Preview {
    let score = SoloScore(
        overall: 8.7,
        breakdown: .init(seatingFriendly: 9, soloPatronRatio: 8, staffPressure: 9, soloPortioning: 10, ambianceFit: 8, safety: 9),
        hint: "Order at the bar, sit upstairs.",
        basedOnCount: 14
    )
    return VStack(spacing: 24) {
        SoloScoreBadge(score: score, style: .compact)
        SoloScoreBadge(score: score, style: .full)
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    .padding()
}
