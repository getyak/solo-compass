import SwiftUI

/// 游民基地卡 — the persistent Base entry in the dock slot above the peek
/// sheet. Replaces the v3 Plan/Recall placeholder cards with one face-driven
/// card: the object never changes, only its content morphs with the lifecycle
/// (see `BaseFace`). Everything shown here is synchronously available at
/// render time — async signals (weather) live in the panel, so the dock stays
/// cheap and never pops in late.
struct BaseCard: View {
    let face: BaseFace
    let cityName: String

    /// Compliance countdown — nil until the traveler confirms an entry date.
    let daysStayed: Int?
    let visaDaysRemaining: Int?

    /// Plan-face policy signal: the city's visa allowance from the kit
    /// (`CityKitAction.visaDays`), not a personal countdown.
    let visaPolicyDays: Int?

    /// Sync counts for the face's signal line.
    let workReadyCount: Int
    let eventCount: Int
    let kitDone: Int
    let kitTotal: Int
    let recallVisited: Int
    let recallPending: Int

    let onOpen: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            Haptics.impact(.light)
            onOpen()
        } label: {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    tag
                    Text(String(
                        format: NSLocalizedString("cityos.base.title", comment: "%@ · 基地"),
                        cityName
                    ))
                    .font(CT.displayRounded(17, .semibold))
                    .foregroundStyle(primaryText)
                    .lineLimit(1)
                    signalLine
                }
                Spacer(minLength: 0)
                trailing
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
            .shadow(color: CT.scrimShadow, radius: 10, y: 3)
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.97))
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(NSLocalizedString("cityos.base.cta", comment: "进入基地")))
    }

    // MARK: - Pieces

    private var tag: some View {
        Text(face.tagText)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.0)
            .textCase(.uppercase)
            .foregroundStyle(face.tagColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(face.tagColor.opacity(0.12)))
    }

    /// One compact, face-specific stat line. Stats that have no data simply
    /// drop out — the card never shows an empty stub. Capped at two: a third
    /// stat truncates at this width (verified by render), and a truncated
    /// number is worse than a missing one — the panel carries the rest.
    private var signalLine: some View {
        HStack(spacing: 6) {
            ForEach(Array(stats.prefix(2).enumerated()), id: \.offset) { index, stat in
                if index > 0 {
                    Text("·")
                        .font(CT.body(12))
                        .foregroundStyle(CT.fgSubtle)
                }
                HStack(spacing: 3.5) {
                    Image(systemName: stat.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(face.tagColor)
                    Text(stat.text)
                        .font(CT.body(12, .medium))
                        .foregroundStyle(CT.fgMuted)
                        .lineLimit(1)
                }
            }
        }
    }

    private struct Stat {
        let symbol: String
        let text: String
    }

    private var stats: [Stat] {
        var result: [Stat] = []
        switch face {
        case .plan:
            if let visaPolicyDays {
                result.append(Stat(symbol: "doc.text", text: String(
                    format: NSLocalizedString("cityos.base.visa.policy", comment: "签证 %d 天"),
                    visaPolicyDays
                )))
            }
            if workReadyCount > 0 {
                result.append(Stat(symbol: "laptopcomputer", text: String(
                    format: NSLocalizedString("cityos.base.work.count", comment: "可办公 %d 处"),
                    workReadyCount
                )))
            }
            if kitTotal > 0 {
                result.append(Stat(symbol: "checklist", text: String(
                    format: NSLocalizedString("cityos.base.kit.progress", comment: "行前 %1$d/%2$d"),
                    kitDone, kitTotal
                )))
            }
        case .arrive:
            if let daysStayed {
                result.append(Stat(symbol: "sun.horizon", text: String(
                    format: NSLocalizedString("cityos.base.day", comment: "第 %d 天"),
                    daysStayed
                )))
            } else {
                result.append(Stat(symbol: "calendar.badge.plus", text:
                    NSLocalizedString("cityos.base.visa.setEntry", comment: "设置入境日期")
                ))
            }
            if kitTotal > 0 {
                result.append(Stat(symbol: "shippingbox", text: String(
                    format: NSLocalizedString("cityos.base.kit.count", comment: "落地包 %d 项"),
                    kitTotal
                )))
            }
        case .live:
            if let daysStayed {
                result.append(Stat(symbol: "sun.horizon", text: String(
                    format: NSLocalizedString("cityos.base.day", comment: "第 %d 天"),
                    daysStayed
                )))
            }
            if workReadyCount > 0 {
                result.append(Stat(symbol: "laptopcomputer", text: String(
                    format: NSLocalizedString("cityos.base.work.count", comment: "可办公 %d 处"),
                    workReadyCount
                )))
            }
            if eventCount > 0 {
                result.append(Stat(symbol: "calendar", text: String(
                    format: NSLocalizedString("cityos.base.events.count", comment: "活动 %d 场"),
                    eventCount
                )))
            }
        case .recall:
            if recallVisited > 0 || recallPending > 0 {
                result.append(Stat(symbol: "eye", text: String(
                    format: NSLocalizedString("cityos.base.recall.stats", comment: "去过 %1$d · 待印证 %2$d"),
                    recallVisited, recallPending
                )))
            } else {
                // Nothing checked in yet — an all-zero stat line reads as a
                // bug, not an invitation. Say what the face is for instead.
                result.append(Stat(symbol: "eye", text:
                    NSLocalizedString("cityos.base.recall.empty", comment: "回顾这段旅程")
                ))
            }
        }
        return result
    }

    /// Trailing affordance: the visa countdown ring once the traveler has a
    /// confirmed entry date (the honesty gate — never a guessed number),
    /// otherwise the face's symbol in a soft tile.
    @ViewBuilder
    private var trailing: some View {
        if face.showsCountdown, let visaDaysRemaining, let daysStayed {
            BaseCountdownRing(
                remaining: visaDaysRemaining,
                total: max(visaDaysRemaining + daysStayed, 1),
                size: 46
            )
        } else {
            Image(systemName: face.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(face.tagColor)
                .frame(width: 46, height: 46)
                .background(Circle().fill(face.tagColor.opacity(0.10)))
        }
    }

    /// Visa inside a week pushes the whole card into a visible warning state —
    /// the ring alone is easy to scan past, and the top banner is dismissable.
    private var urgencyTone: Color? {
        guard face.showsCountdown, let visaDaysRemaining, daysStayed != nil else { return nil }
        if visaDaysRemaining <= 3 { return CT.bannerError }
        if visaDaysRemaining <= 7 { return CT.warningText }
        return nil
    }

    private var cardFill: Color { colorScheme == .dark ? CT.warmCardDark : CT.surfaceWhite }
    private var borderColor: Color {
        if let urgencyTone { return urgencyTone.opacity(0.55) }
        return colorScheme == .dark ? CT.warmBorderDark : CT.borderSubtle
    }
    private var borderWidth: CGFloat { urgencyTone == nil ? 0.5 : 1.5 }
    private var primaryText: Color { colorScheme == .dark ? CT.fgPrimaryDark : CT.fgPrimary }
}

// MARK: - BaseCountdownRing

/// The visa countdown ring — mono digits inside a trimmed circle. Mono because
/// the number is self-computed and checkable (公理二); the stroke shifts to the
/// warning amber inside a week and the error red inside 3 days.
struct BaseCountdownRing: View {
    let remaining: Int
    let total: Int
    var size: CGFloat = 46

    @Environment(\.colorScheme) private var colorScheme

    private var fraction: CGFloat {
        guard total > 0 else { return 0 }
        return min(max(CGFloat(remaining) / CGFloat(total), 0), 1)
    }

    private var tone: Color {
        if remaining <= 3 { return CT.bannerError }
        if remaining <= 7 { return CT.warningText }
        return CT.accent
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(track, lineWidth: 4)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tone, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: fraction)
            VStack(spacing: -1) {
                Text("\(max(remaining, 0))")
                    .font(CT.mono(size * 0.30, .semibold))
                    .foregroundStyle(tone)
                    .contentTransition(.numericText())
                Text(NSLocalizedString("cityos.base.ring.unit", comment: "天"))
                    .font(CT.mono(size * 0.16, .medium))
                    .foregroundStyle(CT.fgSubtle)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(
            format: NSLocalizedString("cityos.base.visa.remaining", comment: "签证剩 %d 天"),
            max(remaining, 0)
        )))
    }

    private var track: Color {
        colorScheme == .dark ? CT.warmSunkenDark : CT.surfaceSunken
    }
}
