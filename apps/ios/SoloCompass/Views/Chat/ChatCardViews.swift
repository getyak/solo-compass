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

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: experience.category.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(experience.category.color))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(experience.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CT.fgPrimary)
                            .lineLimit(1)
                        Text(scoreLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(CT.verifiedGreen)
                    }
                    Spacer(minLength: 0)
                }
                Text(experience.oneLiner)
                    .font(.caption)
                    .foregroundStyle(CT.fgMuted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    Image(systemName: "map")
                        .font(.system(size: 10, weight: .semibold))
                    Text(NSLocalizedString("chat.card.viewOnMap", comment: "Tap a chat place card to reveal it on the map"))
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(CT.accent)
            }
            .padding(12)
            .frame(width: 220, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(CT.borderSubtle, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.97))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(experience.title). \(experience.oneLiner)"))
        .accessibilityHint(Text(NSLocalizedString("chat.card.viewOnMap.a11y", comment: "Double tap to reveal this place on the map")))
    }

    private var scoreLabel: String {
        String(format: NSLocalizedString("nearby.chip.solo", comment: "Solo score"), experience.soloScore.overall)
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
    /// User tapped "采用这条路线" — persist + open the route detail.
    let onAdopt: () -> Void
    /// User tapped a single stop — reveal that place on the map.
    let onTapStop: (Experience) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var route: Route { proposal.route }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !route.reasonNow.isNilOrEmpty {
                reasonNowBanner
            }
            stopsList
            adoptButton
        }
        .padding(14)
        .frame(maxWidth: 280, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(CT.accentBorder, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.07), radius: 5, y: 2)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CT.accent)
                Text(route.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CT.fgPrimary)
                    .lineLimit(2)
            }
            if !route.summary.isEmpty {
                Text(route.summary)
                    .font(.caption)
                    .foregroundStyle(CT.fgMuted)
                    .lineLimit(3)
            }
            metaRow
        }
    }

    private var metaRow: some View {
        HStack(spacing: 10) {
            Label(durationLabel, systemImage: "clock")
            Label(distanceLabel, systemImage: "figure.walk")
            Label("\(proposal.stops.count)", systemImage: "mappin.and.ellipse")
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(CT.fgSubtle)
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

    private var stopsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(proposal.stops.enumerated()), id: \.element.id) { index, stop in
                Button { onTapStop(stop) } label: {
                    stopRow(index: index, stop: stop)
                }
                .buttonStyle(PressableButtonStyle(pressedScale: 0.98))
            }
        }
    }

    private func stopRow(index: Int, stop: Experience) -> some View {
        HStack(alignment: .top, spacing: 9) {
            ZStack {
                Circle().fill(stop.category.color).frame(width: 22, height: 22)
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(stop.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CT.fgPrimary)
                    .lineLimit(1)
                if let reason = reason(at: index), !reason.isEmpty {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(CT.fgMuted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(index + 1). \(stop.title)"))
    }

    private var adoptButton: some View {
        Button(action: onAdopt) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text(NSLocalizedString("chat.route.adopt", comment: "Adopt this route button"))
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CT.accent))
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.98))
        .accessibilityHint(Text(NSLocalizedString("chat.route.adopt.a11y", comment: "Double tap to save this route and open it")))
    }

    // MARK: - Helpers

    private func reason(at index: Int) -> String? {
        guard index < proposal.stopReasons.count else { return nil }
        return proposal.stopReasons[index]
    }

    private var durationLabel: String {
        route.estimatedDuration >= 60
            ? String(format: "%dh%02dm", route.estimatedDuration / 60, route.estimatedDuration % 60)
            : "\(route.estimatedDuration)min"
    }

    private var distanceLabel: String {
        route.distanceMeters >= 1000
            ? String(format: "%.1fkm", Double(route.distanceMeters) / 1000)
            : "\(route.distanceMeters)m"
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
