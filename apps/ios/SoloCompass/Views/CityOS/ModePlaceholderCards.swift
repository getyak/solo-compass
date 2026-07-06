import SwiftUI

/// City OS v2 · Plan / Recall mode placeholder cards (PRD §4.1). The product
/// decision for v2 is: Live mode is fully built; Plan and Recall get honest
/// placeholder cards so the mode switch is real and legible, but they don't
/// pretend to have features that aren't there yet. Each teases what the mode
/// will hold and offers the one thing that IS live — the landing kit.
struct PlanCard: View {
    let cityName: String
    let onOpenKit: () -> Void

    var body: some View {
        ModeCard(
            tagText: NSLocalizedString("cityos.mode.plan.tag", comment: "计划"),
            tagColor: CT.modePlanBlue,
            title: String(
                format: NSLocalizedString("cityos.mode.plan.title", comment: "%@ · 计划中"),
                cityName
            ),
            bodyText: NSLocalizedString("cityos.mode.plan.body", comment: "Pre-trip checklist teaser"),
            ctaText: NSLocalizedString("cityos.mode.plan.cta", comment: "先看落地包"),
            onCTA: onOpenKit
        )
    }
}

/// The Recall-mode placeholder — muted, retrospective register.
struct RecallCard: View {
    let cityName: String
    let onOpenKit: () -> Void

    var body: some View {
        ModeCard(
            tagText: NSLocalizedString("cityos.mode.recall.tag", comment: "回顾"),
            tagColor: CT.fgMuted,
            title: String(
                format: NSLocalizedString("cityos.mode.recall.title", comment: "%@ · 回顾"),
                cityName
            ),
            bodyText: NSLocalizedString("cityos.mode.recall.body", comment: "Looking-back teaser"),
            ctaText: nil,
            onCTA: onOpenKit
        )
    }
}

// MARK: - ModeCard

/// Shared chrome for the mode placeholder cards.
private struct ModeCard: View {
    let tagText: String
    let tagColor: Color
    let title: String
    let bodyText: String
    let ctaText: String?
    let onCTA: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            tag
            Text(title)
                .font(CT.displayRounded(16, .semibold))
                .foregroundStyle(primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(bodyText)
                .font(CT.body(13))
                .foregroundStyle(CT.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
            if let ctaText {
                Button {
                    Haptics.impact(.light)
                    onCTA()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "backpack")
                            .font(.system(size: 12, weight: .semibold))
                        Text(ctaText)
                            .font(CT.body(13, .semibold))
                    }
                    .foregroundStyle(CT.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(CT.accentSoft))
                }
                .buttonStyle(PressableButtonStyle(pressedScale: 0.96))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 0.5)
        )
        .shadow(color: CT.scrimShadow, radius: 10, y: 3)
        .accessibilityElement(children: .contain)
    }

    private var tag: some View {
        Text(tagText)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.0)
            .textCase(.uppercase)
            .foregroundStyle(tagColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tagColor.opacity(0.12)))
    }

    private var cardFill: Color { colorScheme == .dark ? CT.warmCardDark : CT.surfaceWhite }
    private var borderColor: Color { colorScheme == .dark ? CT.warmBorderDark : CT.borderSubtle }
    private var primaryText: Color { colorScheme == .dark ? CT.fgPrimaryDark : CT.fgPrimary }
}
