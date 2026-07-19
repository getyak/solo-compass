import SwiftUI

/// Nomad OS B1-c: the "today's three things" block on the Today home — the
/// north-star content (design nomad-os-b1-today-home-20260719 §2 ②).
///
/// Three cards in a fixed order — **work → now → tonight** — each picked from
/// the current city's experiences by a distinct lens:
///
///   - ☕ work    : the best work-ready spot (`isWorkReady`, solo-score ranked)
///   - ✨ now     : what's most worth it *right now* (`nowScore` ranked)
///   - 🌙 tonight : something whose best window opens this evening (≥18:00)
///
/// The selection is a pure function (`pick`) so it's unit-testable without a
/// view. Data comes from the same independent sources the other Today
/// components use — `ExperienceService.allExperiences` filtered to
/// `preferences.lastSelectedCity` — never the map's `MapViewModel` @State
/// (which Today can't reach). A city with nothing to show renders an honest
/// empty line rather than three blank cards; non-seed cities are filled by the
/// A2 backend hydrate, and a truly empty city says so plainly.
struct TodayThreeThings: View {
    @Environment(ExperienceService.self) private var experienceService
    @Environment(UserPreferences.self) private var preferences

    /// Recomputed on appear and when the city changes. `nowScore` depends on the
    /// wall clock, but a per-render re-pick would thrash; a snapshot on appear is
    /// the right granularity for a home screen (the map is where live "now"
    /// browsing happens).
    @State private var picks: Picks = .empty

    var body: some View {
        VStack(spacing: Space.md) {
            if picks.isEmpty {
                emptyState
            } else {
                if let work = picks.work {
                    TodayCard(kind: .work, experience: work)
                }
                if let now = picks.now {
                    TodayCard(kind: .now, experience: now)
                }
                if let tonight = picks.tonight {
                    TodayCard(kind: .tonight, experience: tonight)
                }
            }
        }
        .task(id: preferences.lastSelectedCity) { refresh() }
    }

    private var emptyState: some View {
        Text(NSLocalizedString(
            "today.threeThings.empty",
            comment: "No experiences to build today's three things from yet"
        ))
        .ctBody(15)
        .foregroundStyle(CT.textMutedAdaptive)
        .multilineTextAlignment(.center)
        .padding(.horizontal, Space.xxl)
        .padding(.top, Space.xxl)
    }

    private func refresh() {
        picks = Self.pick(
            from: experienceService.allExperiences,
            cityCode: preferences.lastSelectedCity,
            now: Date()
        )
    }

    // MARK: - Selection (pure, testable)

    /// The three chosen experiences, any of which may be nil when the city has
    /// nothing that fits that lens.
    struct Picks: Equatable {
        var work: Experience?
        var now: Experience?
        var tonight: Experience?

        static let empty = Picks(work: nil, now: nil, tonight: nil)
        var isEmpty: Bool { work == nil && now == nil && tonight == nil }
    }

    /// Pick the three cards from a full experience list. Pure so
    /// `TodayThreeThingsTests` can pin the lenses without a view or a store.
    /// `@MainActor` because it calls `MapViewModel`'s main-actor-isolated
    /// `cityCodeMatches` / `isWorkReady` statics — and `pick` only ever runs on
    /// the main thread (the view's `refresh`) anyway.
    ///
    /// De-dupes across cards: if the same experience wins two lenses (a great
    /// evening work café that's also best-now), the earlier lens in
    /// work→now→tonight order keeps it and the later lens takes its runner-up,
    /// so the block never shows the same place twice.
    @MainActor
    static func pick(
        from all: [Experience],
        cityCode: String?,
        now: Date
    ) -> Picks {
        guard let cityCode, !cityCode.isEmpty else { return .empty }
        let inCity = all.filter {
            MapViewModel.cityCodeMatches($0.location.cityCode, selected: cityCode)
        }
        guard !inCity.isEmpty else { return .empty }

        var used = Set<String>()

        // ☕ Work: work-ready, solo-score ranked (mirrors workReadySpots).
        let workReady = inCity
            .filter { MapViewModel.isWorkReady($0) }
            .sorted(by: soloDescendingTitleAscending)
        let work = workReady.first { used.insert($0.id).inserted }

        // ✨ Now: highest nowScore, only if it's genuinely a good time (≥0.5 —
        // below that we'd be celebrating a mediocre moment; the map is where
        // marginal now-browsing belongs). Scored first, then sorted, in
        // separate steps so the type-checker doesn't choke on one long chain.
        let scored: [(exp: Experience, score: Double)] = inCity
            .map { (exp: $0, score: $0.nowScore(at: now).value) }
            .filter { $0.score >= 0.5 }
        let nowRanked = scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.exp.title < $1.exp.title }
            .map(\.exp)
        let nowPick = nowRanked.first { used.insert($0.id).inserted }

        // 🌙 Tonight: has an evening window (opens ≥18:00), solo-score ranked.
        let evening = inCity
            .filter { exp in exp.bestTimes.contains { $0.startHour >= 18 } }
            .sorted(by: soloDescendingTitleAscending)
        let tonight = evening.first { used.insert($0.id).inserted }

        return Picks(work: work, now: nowPick, tonight: tonight)
    }

    private static func soloDescendingTitleAscending(_ a: Experience, _ b: Experience) -> Bool {
        if a.soloScore.overall != b.soloScore.overall {
            return a.soloScore.overall > b.soloScore.overall
        }
        return a.title < b.title
    }
}

/// One of the three Today cards. A single container that differs by `kind` — the
/// icon, accent, and eyebrow label change; the body (place name + a warm,
/// self-written subtitle + solo score) is shared. Visual token set matches the
/// other Today rows (`Radius.lg` / `CT.cardAdaptive` / `Space.lg`).
struct TodayCard: View {
    enum Kind {
        case work, now, tonight

        var symbol: String {
            switch self {
            case .work:    return "cup.and.saucer.fill"
            case .now:     return "sparkles"
            case .tonight: return "moon.stars.fill"
            }
        }

        var eyebrowKey: String {
            switch self {
            case .work:    return "today.card.work.eyebrow"
            case .now:     return "today.card.now.eyebrow"
            case .tonight: return "today.card.tonight.eyebrow"
            }
        }
    }

    let kind: Kind
    let experience: Experience

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: kind.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(CT.accent)
                .frame(width: 34, height: 34)
                .background(Circle().fill(CT.accent.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString(kind.eyebrowKey, comment: "Today card eyebrow label"))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(CT.accent)
                Text(experience.shortName)
                    .ctBody(15, .semibold)
                    .foregroundStyle(CT.textPrimaryAdaptive)
                    .lineLimit(1)
                if let subtitle = warmSubtitle {
                    Text(subtitle)
                        .ctBody(12)
                        .foregroundStyle(CT.textMutedAdaptive)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CT.fgSubtle)
        }
        .padding(Space.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(CT.cardAdaptive)
        )
        .padding(.horizontal, Space.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    /// A warm, user-facing subtitle written here — never `NowScore.reason`,
    /// which is a developer string. Prefers the solo-lens hint, then the AI
    /// one-liner (if it isn't just the title again), then the first sentence of
    /// why-it-matters. Nil when none is usable (the card still reads fine on
    /// name + eyebrow alone).
    private var warmSubtitle: String? {
        if let hint = experience.soloScore.hint, !hint.isEmpty {
            return hint
        }
        let oneLiner = experience.oneLiner
        if !oneLiner.isEmpty, oneLiner != experience.title {
            return oneLiner
        }
        let why = experience.whyItMatters
        if !why.isEmpty {
            return why.split(whereSeparator: { $0 == "." || $0 == "。" }).first.map(String.init)
        }
        return nil
    }

    private var accessibilityLabel: String {
        let eyebrow = NSLocalizedString(kind.eyebrowKey, comment: "")
        if let subtitle = warmSubtitle {
            return "\(eyebrow): \(experience.shortName). \(subtitle)"
        }
        return "\(eyebrow): \(experience.shortName)"
    }
}
