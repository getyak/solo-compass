import SwiftUI

/// "Solo 8.5" pill. Compact form for cards, expanded form for the detail sheet.
public struct SoloScoreBadge: View {
    let score: SoloScore
    var style: Style = .compact

    public enum Style { case compact, full }

    @State private var animatedScore: Double = 0
    @State private var appeared = false
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

    private var isExcellent: Bool { score.overall >= 8.5 }

    private var compactView: some View {
        HStack(spacing: 4) {
            if isExcellent {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.95))
            }
            Text(NSLocalizedString("solo.label", comment: "Solo"))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.9))
            Text(formatted(animatedScore))
                .font(.caption.bold())
                .foregroundStyle(.white)
                .monospacedDigit()
                .contentTransition(.numericText(value: animatedScore))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(score.scoreColor.opacity(0.95))
        )
        .scaleEffect(appeared ? 1 : 0.7)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                    appeared = true
                }
            }
        }
        .accessibilityLabel(Text(
            isExcellent
                ? String(format: NSLocalizedString("solo.a11y", comment: "Solo Score %@ of 10"), formatted(score.overall))
                    + ", " + NSLocalizedString("solo.excellent.a11y", comment: "Excellent for solo travelers")
                : String(format: NSLocalizedString("solo.a11y", comment: "Solo Score %@ of 10"), formatted(score.overall))
        ))
        .onChange(of: score.overall) { _, _ in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                appeared = true
            }
        }
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
        .onChange(of: score.overall) { triggerAnimation() }
    }

    private func triggerAnimation() {
        if reduceMotion {
            animatedScore = score.overall
        } else {
            withAnimation(.easeOut(duration: 0.5)) {
                animatedScore = score.overall
            }
        }
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

#Preview {
    let excellentScore = SoloScore(
        overall: 8.7,
        breakdown: .init(seatingFriendly: 9, soloPatronRatio: 8, staffPressure: 9, soloPortioning: 10, ambianceFit: 8, safety: 9),
        hint: "Order at the bar, sit upstairs.",
        basedOnCount: 14
    )
    let midScore = SoloScore(
        overall: 5.2,
        breakdown: .init(seatingFriendly: 5, soloPatronRatio: 5, staffPressure: 6, soloPortioning: 5, ambianceFit: 5, safety: 5),
        hint: nil,
        basedOnCount: 3
    )
    VStack(spacing: 24) {
        SoloScoreBadge(score: excellentScore, style: .compact)
        SoloScoreBadge(score: midScore, style: .compact)
        SoloScoreBadge(score: excellentScore, style: .full)
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    .padding()
}

#Preview("Compact count-up") {
    struct CompactCountUpPreview: View {
        @State private var score = SoloScore(
            overall: 5.0,
            breakdown: .init(seatingFriendly: 5, soloPatronRatio: 5, staffPressure: 5, soloPortioning: 5, ambianceFit: 5, safety: 5),
            basedOnCount: 4
        )

        var body: some View {
            VStack(spacing: 20) {
                SoloScoreBadge(score: score, style: .compact)
                Button(NSLocalizedString("preview.raiseScore", comment: "Raise Score")) {
                    score = SoloScore(
                        overall: 9.2,
                        breakdown: .init(seatingFriendly: 9, soloPatronRatio: 9, staffPressure: 9, soloPortioning: 9, ambianceFit: 10, safety: 9),
                        basedOnCount: 20
                    )
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
    return CompactCountUpPreview()
}
