import SwiftUI

/// Lightweight, tap-only place card rendered inside the chat stream. Unlike the
/// heavyweight `ExperienceCardView` (drag gestures, live distance/bearing, map
/// environment deps), this is a flat, self-contained card: it needs no
/// `LocationService` / `BestNowClock` and never moves the map on its own. The
/// single `onTap` is the user's explicit "show me this on the map" action — the
/// agent never jumps there for them.
@MainActor
struct ChatExperienceCard: View {
    let experience: Experience
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A quiet two-step reveal: the result reads as a tight search row first
    /// (disc · name · meta · arrow), and the arrow expands a single line of
    /// context + Solo score in place. Only the *whole row* then jumps to the
    /// map — so a curious glance never costs you your scroll position.
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            if expanded {
                expandedDetail
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(CT.borderSubtle, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(experience.title). \(experience.oneLiner)"))
        .accessibilityHint(Text(NSLocalizedString("chat.card.viewOnMap.a11y", comment: "Double tap to reveal this place on the map")))
    }

    /// The always-visible compact row.
    private var row: some View {
        HStack(spacing: 11) {
            Button(action: onTap) {
                HStack(spacing: 11) {
                    disc
                    VStack(alignment: .leading, spacing: 2) {
                        Text(experience.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(metaLine)
                            .font(.system(size: 10.5, design: .monospaced))
                            .tracking(0.2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle(pressedScale: 0.98))
            .accessibilityLabel(Text(String(
                format: NSLocalizedString("chat.card.open.a11y", comment: "Open %@ on the map"),
                experience.title
            )))

            expandToggle
        }
    }

    private var disc: some View {
        Image(systemName: experience.category.symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(experience.category.color)
            )
    }

    /// Right-edge arrow pill. Tapping it flips `expanded` rather than navigating
    /// — the two affordances (peek vs. go) stay distinct.
    private var expandToggle: some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82)) {
                expanded.toggle()
            }
            Haptics.impact(.light)
        } label: {
            Image(systemName: expanded ? "chevron.up" : "arrow.up.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CT.fgMuted)
                .frame(width: 28, height: 28)
                .background(Circle().fill(CT.surfaceSunken))
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.9))
        .accessibilityLabel(Text(NSLocalizedString("chat.card.expand.a11y", comment: "Show more about this place")))
    }

    /// One line of prose + a Solo-score chip, revealed under the row.
    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(experience.oneLiner)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text(scoreLabel)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(CT.verifiedGreen)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(CT.successSoft))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 47) // align under the title (disc 36 + spacing 11)
    }

    /// Mono meta line: "<category> · Solo 7.5" — grounded only in data this card
    /// already holds (it deliberately has no LocationService dep for distance).
    private var metaLine: String {
        let category = experience.category.localizedTitle
        return "\(category) · \(scoreLabel)"
    }

    private var scoreLabel: String {
        String(
            format: NSLocalizedString("chat.card.solo", comment: "Solo %@"),
            String(format: "%.1f", experience.soloScore.overall)
        )
    }

    private var cardFill: Color {
        colorScheme == .dark ? Color(.secondarySystemBackground) : CT.surfaceWhite
    }
}

/// In-chat card for a route the agent proposed but has NOT saved. Lists the
/// stops in walk order with an optional per-stop reason, and offers an explicit
/// "采用这条路线" action — only then is the route persisted and opened. The
/// user, not the agent, commits the route.
@MainActor
struct ChatRouteProposalCard: View {
    let proposal: RouteProposal
    /// User tapped "Open" — persist + open the route detail.
    let onAdopt: () -> Void
    /// User tapped a single stop bead — reveal that place on the map.
    let onTapStop: (Experience) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var saved = false

    private var route: Route { proposal.route }

    /// A route the agent just drafted (unsaved) vs. one already walked & proven.
    /// The handoff splits the tag into DRAFT vs. VERIFIED on exactly this signal.
    private var isVerified: Bool {
        route.verification.status == .verified && route.verification.walkedByCount > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            tagRow
            Text(route.title)
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if !route.reasonNow.isNilOrEmpty {
                reasonNowBanner
            }
            beadStrip
            actions
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(CT.accentBorder, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
        .accessibilityElement(children: .contain)
    }

    /// "⚑ DRAFT ROUTE" / "⚑ VERIFIED ROUTE … ✓ N walked" — display-face caps with
    /// wide tracking, the typographic signature of the handoff route card.
    private var tagRow: some View {
        HStack(spacing: 5) {
            Image(systemName: "flag.fill")
                .font(.system(size: 9, weight: .bold))
            Text(NSLocalizedString(
                isVerified ? "chat.route.tag.verified" : "chat.route.tag.draft",
                comment: "Route card tag"
            ))
            .font(.system(size: 9.5, weight: .bold, design: .rounded))
            .tracking(1.3)
            Spacer(minLength: 0)
            if isVerified {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text(String(
                        format: NSLocalizedString("chat.route.walked", comment: "%d walked"),
                        route.verification.walkedByCount
                    ))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(CT.verifiedGreen)
            }
        }
        .foregroundStyle(CT.accent)
    }

    private var reasonNowBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
            Text(route.reasonNow ?? "")
                .font(.caption2.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(CT.sunGoldDeep)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(CT.sunGoldSoft))
    }

    /// Color-bead strip: each stop is a small category disc, joined by hairline
    /// connectors, with a mono "N stops · duration" tail. Tapping a bead reveals
    /// that stop on the map (the stops stay reachable without a long list).
    private var beadStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(proposal.stops.enumerated()), id: \.element.id) { index, stop in
                if index > 0 {
                    Rectangle()
                        .fill(CT.borderDefault)
                        .frame(width: 12, height: 1.5)
                }
                Button { onTapStop(stop) } label: {
                    Image(systemName: stop.category.symbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(stop.category.color))
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                }
                .buttonStyle(PressableButtonStyle(pressedScale: 0.9))
                .accessibilityLabel(Text("\(index + 1). \(stop.title)"))
            }
            Text(stopsMeta)
                .font(.system(size: 10.5, design: .monospaced))
                .tracking(0.2)
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: onAdopt) {
                HStack(spacing: 5) {
                    Text(NSLocalizedString("chat.route.open", comment: "Open route"))
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Capsule().fill(CT.accent))
            }
            .buttonStyle(PressableButtonStyle(pressedScale: 0.97))
            .accessibilityHint(Text(NSLocalizedString("chat.route.adopt.a11y", comment: "Double tap to save this route and open it")))

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { saved = true }
                Haptics.notify(.success)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: saved ? "checkmark" : "heart")
                        .font(.system(size: 12, weight: .semibold))
                    Text(NSLocalizedString(
                        saved ? "chat.route.saved" : "chat.route.save",
                        comment: "Save route"
                    ))
                    .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(saved ? CT.verifiedGreen : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(saved ? CT.successSoft : CT.surfaceSunken))
            }
            .buttonStyle(PressableButtonStyle(pressedScale: 0.97))
            .disabled(saved)
        }
    }

    // MARK: - Helpers

    private var stopsMeta: String {
        String(
            format: NSLocalizedString("chat.route.stops", comment: "%1$d stops · %2$@"),
            proposal.stops.count,
            durationLabel
        )
    }

    private var durationLabel: String {
        route.estimatedDuration >= 60
            ? String(format: "%dh%02dm", route.estimatedDuration / 60, route.estimatedDuration % 60)
            : "\(route.estimatedDuration)min"
    }

    private var cardFill: Color {
        colorScheme == .dark ? Color(.secondarySystemBackground) : CT.surfaceWhite
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        switch self {
        case .none: return true
        case let .some(value): return value.isEmpty
        }
    }
}
