import SwiftUI

// MARK: - RouteCard

/// Single row in the 路线 section of BottomInfoSheet.
///
/// Layout: 44×44 gradient cover (left) | title + mono baseline (right) |
/// small verified corner pill when route.verification.status == .verified.
/// P0: no companion info shown.
public struct RouteCard: View {
    let route: Route
    /// Whether the companion layer is active. When off (or the route has no
    /// companion slot), the card surfaces a social-proof walked-by row instead
    /// of the recruit-mini strip.
    var companionOn: Bool = false

    public init(route: Route, companionOn: Bool = false) {
        self.route = route
        self.companionOn = companionOn
    }

    private var monoBaseline: String {
        let dur = route.estimatedDuration >= 60
            ? String(format: "%dh%02dm", route.estimatedDuration / 60, route.estimatedDuration % 60)
            : "\(route.estimatedDuration)min"
        let dist = route.distanceMeters >= 1000
            ? String(format: "%.1fkm", Double(route.distanceMeters) / 1000)
            : "\(route.distanceMeters)m"
        return "\(dur) · \(dist) · \(route.pace.localizedLabel)"
    }

    private var isVerified: Bool {
        route.verification.status == .verified
    }

    public var body: some View {
        HStack(spacing: 10) {
            coverSquare

            VStack(alignment: .leading, spacing: 3) {
                Text(route.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(monoBaseline)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !stopColors.isEmpty {
                    stopStrip
                }

                if showWalkedBy {
                    walkedByRow
                } else if let mini = recruitMini {
                    recruitMiniStrip(mini)
                }
            }

            Spacer(minLength: 4)

            if isVerified {
                verifiedPill
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(route.title + ", " + monoBaseline))
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

    /// Horizontal breadcrumb: colored discs joined by 1px `CT.fgSubtle` connectors.
    private var stopStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(stopColors.enumerated()), id: \.offset) { offset, color in
                if offset > 0 {
                    Rectangle()
                        .fill(CT.fgSubtle)
                        .frame(width: 8, height: 1)
                }
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.top, 2)
        .accessibilityHidden(true)
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

    /// Inline strip below the title: host color dot + status-toned line, so the
    /// recruiting state reads at a glance in the route list.
    private func recruitMiniStrip(_ mini: RecruitMini) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(mini.tone)
                .frame(width: 6, height: 6)
            Text(mini.text)
                .font(CT.body(11, .medium))
                .foregroundStyle(mini.tone)
                .lineLimit(1)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(mini.text))
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

    /// Avatar stack (max 4, CT.fgSubtle ring) + count + chevron, reading the
    /// social proof for the route at a glance.
    private var walkedByRow: some View {
        HStack(spacing: 6) {
            AvatarStack(ids: walkedByIds, maxVisible: 4, size: 18, ring: CT.fgSubtle)
            Text(walkedByLabel)
                .font(CT.body(11, .medium))
                .foregroundStyle(CT.fgMuted)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(CT.fgSubtle)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(walkedByLabel))
    }

    // MARK: - Cover square

    private var coverSquare: some View {
        ZStack {
            CategoryVisual.gradient(for: primaryCategory)
            Text(CategoryVisual.emoji(for: primaryCategory))
                .font(.system(size: 20))
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Verified corner pill

    private var verifiedPill: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10, weight: .semibold))
            Text(NSLocalizedString("route.card.verified", comment: "Verified pill"))
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(CT.accent))
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
        .background(Color(.systemBackground))
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
    return VStack(spacing: 0) {
        RouteCard(route: route(.open, members: ["maya"]))
        RouteCard(route: route(.forming, members: ["maya", "leon"]))
        RouteCard(route: route(.closed, members: ["maya", "leon", "rina"]))
        RouteCard(route: route(.completed, members: ["maya", "leon", "rina", "tom"]))
    }
    .padding()
    .background(Color(.systemBackground))
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
    return VStack(spacing: 0) {
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
        .background(Color(.systemBackground))
}
