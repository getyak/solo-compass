import SwiftUI

// MARK: - RouteCard

/// Single card in the 路线 section of BottomInfoSheet.
///
/// Vertical layout (mirrors styles.css `.sc-route-card` / route.jsx `RouteCard`):
/// head row (category dot + uppercase tag + verified-mini chip / now-pill) →
/// title → stop-strip breadcrumb → foot (walked-by row or recruit-mini strip).
public struct RouteCard: View {
    let route: Route
    /// Whether the companion layer is active. When off (or the route has no
    /// companion slot), the card surfaces a social-proof walked-by row instead
    /// of the recruit-mini strip.
    var companionOn: Bool = false
    /// Whether the card is rendered in the 此刻適合 (now) context. When true and
    /// the route carries a `reasonNow`, a golden "此刻理由" banner is shown on top
    /// and the card border shifts to the warm accent tone (`.sc-route-card.is-now`).
    var nowContext: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    public init(route: Route, companionOn: Bool = false, nowContext: Bool = false) {
        self.route = route
        self.companionOn = companionOn
        self.nowContext = nowContext
    }

    private var monoBaseline: String {
        let dist = route.distanceMeters >= 1000
            ? String(format: "%.1fkm", Double(route.distanceMeters) / 1000)
            : "\(route.distanceMeters)m"
        return "\(durationLabel) · \(dist) · \(route.pace.localizedLabel)"
    }

    /// Compact duration label (e.g. `1h30m` / `90min` / `3 小时` / `90 分钟`).
    /// Localized — zh-Hans gets "3 小时 / 30 分钟" instead of the H/M form so the
    /// uppercased head tag doesn't render an alien "3H00M" inside a Chinese card.
    private var durationLabel: String {
        let mins = route.estimatedDuration
        if mins >= 60 {
            let h = mins / 60
            let m = mins % 60
            if m == 0 {
                return String(
                    format: NSLocalizedString("route.duration.hours", comment: "%d hours"),
                    h
                )
            }
            return String(
                format: NSLocalizedString("route.duration.hoursMinutes", comment: "%d h %d min"),
                h, m
            )
        }
        return String(
            format: NSLocalizedString("route.duration.minutes", comment: "%d minutes"),
            mins
        )
    }

    /// Uppercase head tag: "路线 · N 站 · DURATION".
    private var tagLabel: String {
        String(
            format: NSLocalizedString("route.card.tag", comment: "路线 · N 站 · DURATION"),
            route.experienceIds.count,
            durationLabel
        )
    }

    var isVerified: Bool {
        route.verification.status == .verified
    }

    /// Whether the golden "此刻理由" banner should surface: only in now-context
    /// and when the route carries a non-empty `reasonNow`.
    var showsNowReason: Bool {
        nowContext && !(route.reasonNow ?? "").isEmpty
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsNowReason, let reason = route.reasonNow {
                nowReasonBanner(reason)
            }

            headRow

            Text(route.title)
                .ctBody(16, .semibold)
                .foregroundStyle(CT.fgPrimary)
                .lineLimit(2)
                .padding(.bottom, 10)

            if !stopColors.isEmpty {
                stopStrip
                    .padding(.bottom, 11)
            }

            if showWalkedBy {
                walkedByRow
            } else if let mini = recruitMini {
                recruitMiniStrip(mini)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 11)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(CT.surfaceWhite)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                // `.sc-route-card.is-now` warms the border to the accent tone.
                .strokeBorder(nowContext ? CT.accentBorder : CT.borderSubtle, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
        // Press feedback is owned by the hosting Button's ButtonStyle
        // (PressableButtonStyle in RoutesSection), NOT a local gesture. The card
        // previously drove its own press-scale via
        // `.simultaneousGesture(DragGesture(minimumDistance: 0))`. Inside the
        // BottomInfoSheet's ScrollView that zero-distance drag claimed the touch
        // the instant a finger landed — it played the press animation (so the card
        // *looked* tappable, "有按下效果") but on release the host scroll view
        // classified the interaction as a drag, so the wrapping Button's tap never
        // fired and the route detail never opened ("不跳转"). Removing the gesture
        // lets the tap reach the Button. Kin to [[project_dead_fab_sheet_wiring]].
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(route.title + ", " + monoBaseline))
        .onAppear {
            guard !reduceMotion else { return }
            pulse = true
        }
    }

    // MARK: - Now-reason banner (此刻理由)

    /// Golden banner explaining *why* the route is surfaced right now, e.g.
    /// "日落將至 · 30 分鐘後是最佳光線". Mirrors styles.css `.sc-route-card .now-reason`:
    /// sun-gold-soft fill, sun-gold-deep text, 9pt radius, 11pt bottom gap.
    private func nowReasonBanner(_ reason: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
            Text(reason)
                .ctBody(11.5, .semibold)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(CT.sunGoldDeep)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(CT.sunGoldSoft)
        )
        .padding(.bottom, 11)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(reason))
    }

    // MARK: - Head row (category dot + tag + verified-mini / now-pill)

    private var headRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(primaryCategory.color)
                    .frame(width: 6, height: 6)

                Text(tagLabel)
                    .ctDisplay(10, .bold)
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(CT.fgMuted)
                    .lineLimit(1)

                if isVerified {
                    verifiedMini
                }
            }

            Spacer(minLength: 4)

            if route.bestNow {
                nowPill
            }
        }
        .padding(.bottom, 7)
    }

    /// Verified-mini green chip next to the tag.
    private var verifiedMini: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 9.5, weight: .semibold))
            Text(NSLocalizedString("route.card.verified", comment: "Verified pill"))
                .ctMono(9.5, .semibold)
        }
        .foregroundStyle(CT.verifiedGreen)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(CT.verifiedGreen.opacity(0.12)))
    }

    /// "此刻" now-pill shown when the route is best right now.
    private var nowPill: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .bold))
            Text(NSLocalizedString("route.card.now", comment: "此刻 now pill"))
                .ctDisplay(10, .bold)
                .tracking(0.6)
        }
        .foregroundStyle(CT.sunGoldDeep)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Capsule().fill(CT.sunGoldSoft))
    }

    // MARK: - Stop-strip breadcrumb (CompareCanvas A-001)

    /// One disc per stop (one per `experienceIds` entry). The first stop takes the
    /// route's primary-category color; later stops cycle the `CategoryVisual` palette
    /// so the journey reads as a sequence at a glance. Exposed for tests.
    var stopColors: [Color] {
        guard !route.experienceIds.isEmpty else { return [] }
        let palette = ExperienceCategory.allCases
        let startIndex = palette.firstIndex(of: primaryCategory) ?? 0
        return route.experienceIds.indices.map { offset in
            let category = palette[(startIndex + offset) % palette.count]
            return CategoryVisual.colorPair(for: category).0
        }
    }

    /// Horizontal breadcrumb: 22×22 colored discs (white ring) joined by 16pt
    /// connectors with a small arrowhead.
    private var stopStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(stopColors.enumerated()), id: \.offset) { offset, color in
                if offset > 0 {
                    connector
                }
                Circle()
                    .fill(color)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Circle().strokeBorder(.white, lineWidth: 1.5)
                    )
            }
        }
        .accessibilityHidden(true)
    }

    /// 16pt connector line + small arrowhead, in `CT.borderDefault`.
    private var connector: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(CT.borderDefault)
                .frame(width: 16, height: 1.5)
            Image(systemName: "arrowtriangle.right.fill")
                .font(.system(size: 5))
                .foregroundStyle(CT.borderDefault)
                .offset(x: -2)
        }
    }

    // MARK: - Recruit-mini inline state (CompareCanvas A-002)

    /// Resolved inline-recruiting model: the localized text and tone color for the
    /// route's companion slot, or `nil` when the route has no companion. Surfaces
    /// the recruiting state — host, N/M filled, departure — without opening detail.
    /// Exposed for tests.
    struct RecruitMini: Equatable {
        let text: String
        let tone: Color
    }

    /// `nil` unless `route.companion != nil`. Text per status:
    /// - open/forming: `<handle> 招募 · N/M · <departure>`
    /// - closed:       `已成团 · N 人 · 出发中`
    /// - completed:    `已完成 · 路线升级`
    /// Tone: accent for open, amber for forming, green for completed, subtle for closed.
    var recruitMini: RecruitMini? {
        guard let companion = route.companion else { return nil }
        let filled = companion.confirmedMembers.count
        switch companion.status {
        case .open, .forming:
            let text = String(
                format: NSLocalizedString("route.card.recruit.recruiting", comment: "<handle> 招募 · N/M · <departure>"),
                companion.hostId,
                filled,
                companion.maxMembers,
                companion.departureLabel
            )
            return RecruitMini(text: text, tone: companion.status == .open ? CT.accent : CT.toneForming)
        case .closed:
            let text = String(
                format: NSLocalizedString("route.card.recruit.closed", comment: "已成团 · N 人 · 出发中"),
                filled
            )
            return RecruitMini(text: text, tone: CT.toneClosed)
        case .completed:
            let text = NSLocalizedString("route.card.recruit.completed", comment: "已完成 · 路线升级")
            return RecruitMini(text: text, tone: CT.toneCompleted)
        }
    }

    /// Inline strip in the foot: accent-soft card with a (pulsing) status dot +
    /// status-toned line. Formed → verified-green wash, completed → sunken surface.
    private func recruitMiniStrip(_ mini: RecruitMini) -> some View {
        let isFormed = mini.tone == CT.toneClosed
        let isCompleted = mini.tone == CT.toneCompleted
        let bg: Color = isFormed
            ? CT.verifiedGreenDot.opacity(0.06)
            : (isCompleted ? CT.surfaceSunken : CT.accentSoft)
        let border: Color = isFormed
            ? CT.verifiedGreenDot.opacity(0.3)
            : (isCompleted ? CT.borderSubtle : CT.accentBorder)
        let dotColor: Color = isFormed
            ? CT.verifiedGreenDot
            : (isCompleted ? CT.fgSubtle : CT.accent)

        // Open / forming slots are joinable, so the strip carries a trailing
        // "查看 >" affordance hinting the card opens the recruit detail. Closed /
        // completed states are terminal, so they omit the chevron.
        let showsChevron = !isFormed && !isCompleted

        return HStack(spacing: 8) {
            statusDot(dotColor, pulsing: !isCompleted)
            Text(mini.text)
                .ctBody(11.5, .regular)
                .foregroundStyle(mini.tone)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                HStack(spacing: 2) {
                    Text(NSLocalizedString("route.card.recruit.view", comment: "查看 — open recruit detail"))
                        .ctMono(10.5, .semibold)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(mini.tone)
                .layoutPriority(1)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        // Inner tile nested in the md (12pt) route card → sm (8pt) keeps concentric
        // corners (inner < outer); md here equalled the parent radius (HIG smell).
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(bg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(border, lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(mini.text))
    }

    /// Status dot with an optional pulsing ring (gated on reduce-motion).
    private func statusDot(_ color: Color, pulsing: Bool) -> some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .overlay {
                if pulsing {
                    Circle()
                        .strokeBorder(color.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 13, height: 13)
                        .scaleEffect(reduceMotion ? 1 : (pulse ? 1.15 : 0.85))
                        .animation(
                            reduceMotion
                                ? nil
                                : .easeInOut(duration: 1.3).repeatForever(autoreverses: true),
                            value: pulse
                        )
                }
            }
    }

    // MARK: - Walked-by social-proof row (CompareCanvas A-003)

    /// Show the walked-by row when the companion layer is off, or the route has
    /// no companion slot — so the card always carries social proof when it is
    /// not actively recruiting.
    var showWalkedBy: Bool {
        !companionOn || route.companion == nil
    }

    /// The walker ids backing the avatar stack. Falls back to synthesized
    /// placeholder ids (so the stack still reads) when `walkedBy` is empty but
    /// `walkedByCount` is positive.
    var walkedByIds: [String] {
        let ids = route.verification.walkedBy
        guard ids.isEmpty else { return ids }
        let count = max(0, route.verification.walkedByCount)
        return (0..<count).map { "walker-\($0)" }
    }

    /// Localized "<count> 位旅人走过" label driven by `walkedByCount`.
    var walkedByLabel: String {
        String(
            format: NSLocalizedString("route.card.walkedBy", comment: "<count> 位旅人走过"),
            route.verification.walkedByCount
        )
    }

    /// Foot row with a top border: avatar stack + count + chevron, reading the
    /// social proof for the route at a glance.
    private var walkedByRow: some View {
        HStack(spacing: 8) {
            AvatarStack(ids: walkedByIds, maxVisible: 4, size: 18, ring: CT.surfaceWhite)
            Text(walkedByLabel)
                .ctMono(11, .regular)
                .foregroundStyle(CT.fgMuted)
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CT.fgMuted)
        }
        .padding(.top, 9)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(CT.borderSubtle)
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(walkedByLabel))
    }

    // MARK: - Derive primary category from route tags or fallback

    private var primaryCategory: ExperienceCategory {
        // Use first matching tag; fallback to .hidden so the gradient is always valid.
        let tagMap: [String: ExperienceCategory] = [
            "culture": .culture, "food": .food, "coffee": .coffee,
            "nature": .nature, "work": .work, "wellness": .wellness, "nightlife": .nightlife
        ]
        for tag in route.tags {
            if let cat = tagMap[tag.lowercased()] { return cat }
        }
        return .hidden
    }
}

// MARK: - Preview

#Preview("RouteCard — verified") {
    let route = Route(
        id: RouteId(rawValue: "r1"),
        title: "Mekong Sunset Walk",
        summary: "Promenade along the river.",
        experienceIds: ["e1", "e2"],
        cityCode: "VTE",
        region: "Riverfront",
        estimatedDuration: 90,
        distanceMeters: 1200,
        pace: .relaxed,
        tags: ["nature"],
        source: .editorial,
        bestNow: true,
        verification: RouteVerification(status: .verified, walkedByCount: 12, walkedBy: [])
    )
    RouteCard(route: route)
        .padding()
        .background(CT.bgWarm)
}

#Preview("RouteCard — now-context (此刻理由)") {
    let route = Route(
        id: RouteId(rawValue: "r-now"),
        title: "Mekong Sunset Walk",
        summary: "Promenade along the river.",
        experienceIds: ["e1", "e2", "e3"],
        cityCode: "VTE",
        region: "Riverfront",
        estimatedDuration: 90,
        distanceMeters: 1200,
        pace: .relaxed,
        tags: ["nature"],
        source: .editorial,
        bestStartHour: 17.0,
        bestNow: true,
        reasonNow: "日落將至 · 30 分鐘後是最佳光線",
        verification: RouteVerification(status: .verified, walkedByCount: 12, walkedBy: [])
    )
    return RouteCard(route: route, nowContext: true)
        .padding()
        .background(CT.bgWarm)
}

#Preview("RouteCard — recruit-mini all states") {
    func route(_ status: CompanionStatus, members: [String]) -> Route {
        Route(
            id: RouteId(rawValue: "r-\(status.rawValue)"),
            title: "Mekong Sunset Walk",
            summary: "Promenade along the river.",
            experienceIds: ["e1", "e2"],
            cityCode: "VTE",
            region: "Riverfront",
            estimatedDuration: 90,
            distanceMeters: 1200,
            pace: .relaxed,
            tags: ["nature"],
            source: .editorial,
            companion: RouteCompanion(
                status: status,
                hostId: "maya",
                departureWindow: DepartureWindow(startDate: "2026-06-10", to: "2026-06-12", time: "morning"),
                departureLabel: "Jun 10–12 · morning",
                maxMembers: 4,
                confirmedMembers: members
            )
        )
    }
    return VStack(spacing: 10) {
        RouteCard(route: route(.open, members: ["maya"]), companionOn: true)
        RouteCard(route: route(.forming, members: ["maya", "leon"]), companionOn: true)
        RouteCard(route: route(.closed, members: ["maya", "leon", "rina"]), companionOn: true)
        RouteCard(route: route(.completed, members: ["maya", "leon", "rina", "tom"]), companionOn: true)
    }
    .padding()
    .background(CT.bgWarm)
}

#Preview("RouteCard — walked-by row") {
    func route(_ id: String, walkers: Int, ids: [String]) -> Route {
        Route(
            id: RouteId(rawValue: id),
            title: "Mekong Sunset Walk",
            summary: "Promenade along the river.",
            experienceIds: ["e1", "e2"],
            cityCode: "VTE",
            region: "Riverfront",
            estimatedDuration: 90,
            distanceMeters: 1200,
            pace: .relaxed,
            tags: ["nature"],
            source: .editorial,
            verification: RouteVerification(status: .walkedBy, walkedByCount: walkers, walkedBy: ids)
        )
    }
    return VStack(spacing: 10) {
        RouteCard(route: route("w0", walkers: 0, ids: []))
        RouteCard(route: route("w3", walkers: 3, ids: ["maya", "leon", "rina"]))
        RouteCard(route: route("w12", walkers: 12, ids: ["a", "b", "c", "d", "e", "f"]))
    }
    .padding()
    .background(CT.bgWarm)
}

#Preview("RouteCard — not verified") {
    let route = Route(
        id: RouteId(rawValue: "r2"),
        title: "Old Quarter Night Circuit",
        summary: "Street food, temples, and neon.",
        experienceIds: ["e3", "e4", "e5"],
        cityCode: "HAN",
        region: "Old Quarter",
        estimatedDuration: 45,
        distanceMeters: 800,
        pace: .packed,
        tags: ["food"],
        source: .aiGenerated,
        verification: RouteVerification(status: .walkedBy, walkedByCount: 3, walkedBy: [])
    )
    RouteCard(route: route)
        .padding()
        .background(CT.bgWarm)
}
