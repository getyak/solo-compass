import SwiftUI

/// City OS v3 · Plan / Recall mode dock cards. v2 shipped these as honest
/// placeholders; v3 makes them real: Plan carries the pre-trip checklist
/// progress, Recall carries the visited/verified contribution loop —
/// "从消费者变成贡献者" (design handoff v3/modules.jsx).
struct PlanCard: View {
    let cityName: String
    /// Pre-trip checklist progress (ticked / total kit items). Zero total
    /// means the city has no kit yet — the progress row hides.
    let doneCount: Int
    let totalCount: Int
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
            ctaText: NSLocalizedString("cityos.mode.plan.cta.checklist", comment: "查看行前清单"),
            ctaSymbol: "checklist",
            onCTA: onOpenKit
        ) {
            if totalCount > 0 {
                PlanProgressRow(done: doneCount, total: totalCount)
            }
        }
    }
}

/// The Recall-mode card: visited / pending-verify stats plus the 印证 CTA.
struct RecallCard: View {
    let cityName: String
    /// Experiences in this city the traveler completed (去过).
    let visitedCount: Int
    /// Visited experiences not yet personally verified.
    let pendingCount: Int
    /// Display name of the next pending experience, for the CTA label.
    let nextPendingName: String?
    let onVerifyNext: () -> Void
    let onOpenKit: () -> Void

    var body: some View {
        ModeCard(
            tagText: NSLocalizedString("cityos.mode.recall.tag", comment: "回顾"),
            tagColor: CT.fgMuted,
            title: String(
                format: NSLocalizedString("cityos.mode.recall.title", comment: "%@ · 回顾"),
                cityName
            ),
            bodyText: bodyText,
            ctaText: ctaText,
            ctaSymbol: "eye",
            onCTA: pendingCount > 0 ? onVerifyNext : onOpenKit
        ) {
            EmptyView()
        }
    }

    private var bodyText: String {
        if visitedCount == 0 {
            return NSLocalizedString("cityos.mode.recall.body", comment: "Looking-back teaser")
        }
        if pendingCount > 0 {
            return String(
                format: NSLocalizedString(
                    "cityos.mode.recall.pending.body",
                    comment: "你去过 N 个点，还有 M 个没印证"
                ),
                visitedCount, pendingCount
            )
        }
        return String(
            format: NSLocalizedString(
                "cityos.mode.recall.alldone.body",
                comment: "你去过 N 个点，全部已印证"
            ),
            visitedCount
        )
    }

    private var ctaText: String? {
        guard pendingCount > 0 else { return nil }
        guard let nextPendingName else {
            return NSLocalizedString("cityos.mode.recall.verify.cta.generic", comment: "印证一个去过的点")
        }
        return String(
            format: NSLocalizedString("cityos.mode.recall.verify.cta", comment: "印证「%@」"),
            nextPendingName
        )
    }
}

// MARK: - PlanProgressRow

/// The pre-trip progress bar: modePlanBlue fill + mono "行前 N/M 已备" count —
/// mono because the count is a self-computed, checkable number (PRD §2 公理二).
private struct PlanProgressRow: View {
    let done: Int
    let total: Int

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(trackFill)
                    Capsule()
                        .fill(CT.modePlanBlue)
                        .frame(width: geo.size.width * CGFloat(done) / CGFloat(max(total, 1)))
                        .animation(.easeInOut(duration: 0.3), value: done)
                }
            }
            .frame(height: 5)
            Text(String(
                format: NSLocalizedString("cityos.mode.plan.progress", comment: "行前 %1$d/%2$d 已备"),
                done, total
            ))
            .font(CT.mono(10.5, .medium))
            .foregroundStyle(CT.fgMuted)
            .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }

    private var trackFill: Color {
        colorScheme == .dark ? CT.warmSunkenDark : CT.surfaceSunken
    }
}

// MARK: - ModeCard

/// Shared chrome for the mode dock cards. `extra` slots between the body copy
/// and the CTA (the Plan progress row lives there).
private struct ModeCard<Extra: View>: View {
    let tagText: String
    let tagColor: Color
    let title: String
    let bodyText: String
    let ctaText: String?
    var ctaSymbol: String = "backpack"
    let onCTA: () -> Void
    @ViewBuilder let extra: () -> Extra

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
            extra()
            if let ctaText {
                Button {
                    Haptics.impact(.light)
                    onCTA()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: ctaSymbol)
                            .font(.system(size: 12, weight: .semibold))
                        Text(ctaText)
                            .font(CT.body(13.5, .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(CT.accent))
                }
                .buttonStyle(PressableButtonStyle(pressedScale: 0.97))
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
