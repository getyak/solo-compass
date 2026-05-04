import SwiftUI

/// "Solo 8.5" pill. Compact form for cards, expanded form for the detail sheet.
public struct SoloScoreBadge: View {
    let score: SoloScore
    var style: Style = .compact

    public enum Style { case compact, full }

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
        .accessibilityLabel(Text("Solo Score \(formatted(score.overall)) of 10"))
    }

    private var fullView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(NSLocalizedString("solo.scoreTitle", comment: "Solo Score"))
                    .font(.headline)
                Spacer()
                Text(formatted(score.overall))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(score.scoreColor)
            }
            if let hint = score.hint {
                Text(hint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 6) {
                breakdownBar(label: NSLocalizedString("solo.seating", comment: ""), value: score.breakdown.seatingFriendly)
                breakdownBar(label: NSLocalizedString("solo.patrons", comment: ""), value: score.breakdown.soloPatronRatio)
                breakdownBar(label: NSLocalizedString("solo.staff", comment: ""), value: score.breakdown.staffPressure)
                breakdownBar(label: NSLocalizedString("solo.portioning", comment: ""), value: score.breakdown.soloPortioning)
                breakdownBar(label: NSLocalizedString("solo.ambiance", comment: ""), value: score.breakdown.ambianceFit)
                breakdownBar(label: NSLocalizedString("solo.safety", comment: ""), value: score.breakdown.safety)
            }
            Text(String(format: NSLocalizedString("solo.basedOn", comment: ""), score.basedOnCount))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func breakdownBar(label: String, value: Double) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.2))
                    Capsule()
                        .fill(score.scoreColor)
                        .frame(width: geo.size.width * (value / 10.0))
                }
            }
            .frame(height: 6)
            Text(formatted(value))
                .font(.caption.monospacedDigit())
                .frame(width: 32, alignment: .trailing)
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
