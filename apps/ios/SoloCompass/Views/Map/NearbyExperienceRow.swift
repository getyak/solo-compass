import SwiftUI
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - NearbyExperienceRow

/// Single card in the '附近' section of the BottomInfoSheet.
///
/// Card layout (mirrors the route-card chrome so the list reads as a stack of
/// discrete cards rather than ruled rows): a left category color-bar, a filled
/// category disc, the title + romanized·local subtitle, a chip row
/// (walk-time · Solo score · 此刻最佳), and a trailing distance + compass arrow.
struct NearbyExperienceRow: View {
    let experience: Experience
    let isSmartPick: Bool
    /// Distance in meters from the user's current location (or map center).
    let distanceMeters: Double?
    /// True when the experience's bestTimes include the current clock hour (Now sort mode only).
    let isOpenNow: Bool
    /// Live "best now / closing soon" chip state, resolved by the parent section
    /// from the shared `BestNowClock` so the countdown stays current. Only read
    /// when `isOpenNow` is true; nil leaves the chip in its plain form.
    var bestNowChipState: BestNowChipState? = nil
    /// Tapping the card jumps straight to the detail sheet.
    let onTap: () -> Void
    /// Long-pressing the card floats the quick preview card instead. Optional so
    /// existing callers that only want a tap action keep compiling.
    var onLongPress: (() -> Void)? = nil
    /// "问 Solo" context-menu action — opens a chat scoped to this experience.
    /// Optional so callers that don't wire chat keep compiling.
    var onAskSolo: (() -> Void)? = nil

    @State private var pressed = false
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(LocationService.self) private var locationService
    @Environment(UserPreferences.self) private var preferences

    private var isNearby: Bool {
        guard let m = distanceMeters else { return false }
        return m < 150
    }

    private static let distanceFormatter: MeasurementFormatter = {
        let f = MeasurementFormatter()
        f.unitOptions = .naturalScale
        f.unitStyle = .short
        f.numberFormatter.maximumFractionDigits = 1
        return f
    }()

    // MARK: Proximity helpers (mirrors FavoritesListView.Proximity)

    private enum Proximity {
        case near, mid, far

        static func from(meters: Double) -> Proximity {
            if meters <= 1000 { return .near }
            if meters <= 5000 { return .mid }
            return .far
        }

        var dotColor: Color {
            switch self {
            case .near: return CT.verifiedGreenDot
            case .mid: return CT.toneForming
            case .far: return CT.fgSubtle
            }
        }

        /// Localized density word shown next to the chip row (稀疏 / 中等 / 较远),
        /// mirroring the screenshot's proximity caption.
        var labelKey: String {
            switch self {
            case .near: return "nearby.proximity.sparse"
            case .mid:  return "nearby.proximity.moderate"
            case .far:  return "nearby.proximity.far"
            }
        }
    }

    private var proximity: Proximity? {
        guard let m = distanceMeters else { return nil }
        return Proximity.from(meters: m)
    }

    // MARK: Bearing helpers

    private var relativeBearing: Double? {
        guard let coord = experience.coordinate else { return nil }
        return locationService.relativeBearing(to: coord)
    }

    /// 8-point compass label derived from an absolute bearing (0 = N, clockwise).
    private func compassPoint(for absoluteBearing: Double) -> String {
        let points = [
            NSLocalizedString("compass.N",  comment: "Compass point: North"),
            NSLocalizedString("compass.NE", comment: "Compass point: North-East"),
            NSLocalizedString("compass.E",  comment: "Compass point: East"),
            NSLocalizedString("compass.SE", comment: "Compass point: South-East"),
            NSLocalizedString("compass.S",  comment: "Compass point: South"),
            NSLocalizedString("compass.SW", comment: "Compass point: South-West"),
            NSLocalizedString("compass.W",  comment: "Compass point: West"),
            NSLocalizedString("compass.NW", comment: "Compass point: North-West"),
        ]
        let index = Int((absoluteBearing + 22.5) / 45) % 8
        return points[index]
    }

    private var compassDirectionSuffix: String? {
        guard let coord = experience.coordinate,
              let absolute = locationService.bearing(to: coord) else { return nil }
        let point = compassPoint(for: absolute)
        let fmt = NSLocalizedString("nearby.direction.suffix",
                                    comment: "Compass direction suffix, e.g. 'to the North'")
        return String(format: fmt, point)
    }

    var body: some View {
        Button {
            #if canImport(UIKit)
            Haptics.selection()
            if !reduceMotion {
                withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { pressed = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { pressed = false }
                }
            }
            #endif
            onTap()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                categoryDisc
                VStack(alignment: .leading, spacing: 7) {
                    titleStack
                    chipRow
                }
                Spacer(minLength: 4)
                distanceColumn
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12 * BottomSheetDetentScale.factor())
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSmartPick ? CT.accentBorder : CT.borderSubtle, lineWidth: 0.5)
            )
            .overlay(alignment: .leading) {
                // Left color-bar: golden for smart picks, else the category tint.
                UnevenRoundedRectangle(
                    topLeadingRadius: 14, bottomLeadingRadius: 14,
                    bottomTrailingRadius: 0, topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(isSmartPick ? CT.sunGold : experience.category.color)
                .frame(width: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .scaleEffect(pressed ? 0.97 : 1.0)
        // Long-press now raises the native context menu: a warm-amber preview
        // card (key info + hero image) floating over a blurred backdrop, plus a
        // quick-action menu (details · show on map · favorite · navigate · 问
        // Solo). This replaces the former custom floating-card long-press —
        // `onLongPress` is still wired as the "show on map" action so that
        // behavior is preserved, just relocated into the menu.
        .contextMenu {
            cardContextMenu
        } preview: {
            ExperiencePreviewCard(
                experience: experience,
                distanceMeters: distanceMeters,
                bestNowChipState: bestNowChipState
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(Text(NSLocalizedString("experience.card.hint", comment: "Double tap to view details")))
        .accessibilityAction(named: Text(NSLocalizedString("experience.card.preview.a11y", comment: "Preview action: float the quick preview card"))) {
            onLongPress?()
        }
    }

    /// Quick actions for the long-press context menu. Favorite + navigate act
    /// inline (preferences / NavigationLauncher); details, show-on-map, and 问
    /// Solo route through the caller's handlers.
    @ViewBuilder
    private var cardContextMenu: some View {
        Button {
            onTap()
        } label: {
            Label(NSLocalizedString("menu.viewDetails", comment: "View details"), systemImage: "doc.text.magnifyingglass")
        }

        if let onLongPress {
            Button {
                onLongPress()
            } label: {
                Label(NSLocalizedString("menu.showOnMap", comment: "Show on map"), systemImage: "mappin.and.ellipse")
            }
        }

        if let onAskSolo {
            Button {
                onAskSolo()
            } label: {
                Label(NSLocalizedString("menu.askSolo", comment: "Ask Solo about this place"), systemImage: "sparkles")
            }
        }

        Divider()

        let favorited = preferences.isFavorited(experience.id)
        Button {
            Haptics.impact(.light)
            preferences.toggleFavorite(experience.id)
        } label: {
            Label(
                favorited
                    ? NSLocalizedString("menu.unfavorite", comment: "Remove from saved")
                    : NSLocalizedString("menu.favorite", comment: "Save place"),
                systemImage: favorited ? "heart.slash" : "heart"
            )
        }

        if let coord = experience.coordinate {
            Button {
                NavigationLauncher.open(app: .appleMaps, coordinate: coord, name: experience.title)
            } label: {
                Label(NSLocalizedString("menu.navigate", comment: "Navigate there"), systemImage: "arrow.triangle.turn.up.right.diamond")
            }
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var categoryDisc: some View {
        if let firstURL = experience.location.photoUrls?.first,
           let url = URL(string: firstURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                default:
                    categoryIcon
                }
            }
        } else {
            categoryIcon
        }
    }

    private var categoryIcon: some View {
        ZStack {
            Circle()
                .fill(experience.category.color)
                .frame(width: 40, height: 40)
            Image(systemName: experience.category.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var titleStack: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(experience.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(textPrimary)
                // Long names like "Savor Japanese small plates al…" were cut to
                // one line; allow two and shrink slightly before truncating.
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            let sub = subtitleText
            if !sub.isEmpty {
                Text(sub)
                    .font(.caption)
                    .foregroundStyle(colorScheme == .dark ? CT.fgMutedDark : CT.fgMuted)
                    .lineLimit(1)
            }
        }
    }

    /// Horizontal chip row: walk-time · Solo score · (此刻最佳) · proximity word.
    private var chipRow: some View {
        HStack(spacing: 6) {
            if let meters = distanceMeters, meters < 1500 {
                walkTimeChip(meters: meters)
            }
            soloScoreChip
            if isOpenNow {
                bestNowChip
                    .transition(
                        reduceMotion ? .identity :
                            .scale(scale: 0.8).combined(with: .opacity)
                    )
            }
            // The proximity word ("Far"/"Quiet") duplicated the precise distance
            // already shown in `distanceColumn` and read as a negative signal for
            // a solo traveler. The km figure on the right is clearer; drop the word.
        }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: isOpenNow)
    }

    /// Neutral chip: estimated walk minutes (≈ 80 m/min) for nearby experiences.
    private func walkTimeChip(meters: Double) -> some View {
        let minutes = max(1, Int((meters / 80).rounded()))
        let label = String(
            format: NSLocalizedString("nearby.chip.walkMin", comment: "Walk minutes chip, e.g. '4 分钟'"),
            minutes
        )
        return HStack(spacing: 3) {
            Image(systemName: "figure.walk")
                .font(.system(size: 9.5, weight: .semibold))
            Text(label)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(CT.fgMuted)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(CT.surfaceSunken))
    }

    /// Green chip: Solo score (e.g. "Solo 7.5").
    private var soloScoreChip: some View {
        Text(
            String(
                format: NSLocalizedString("nearby.chip.solo", comment: "Solo score chip, e.g. 'Solo 7.5'"),
                experience.soloScore.overall
            )
        )
        .font(.caption2.weight(.bold))
        .foregroundStyle(CT.verifiedGreen)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(CT.verifiedGreen.opacity(0.12)))
    }

    /// Golden chip: 此刻最佳 — shown when the experience is open in the current
    /// hour. Flips to an amber "Closing · Nm" countdown when the active window
    /// has ≤ 45 minutes left, matching the detail card and Saved list.
    private var bestNowChip: some View {
        let state = bestNowChipState ?? BestNowChipState(isClosingSoon: false, minutesLeft: nil)
        return HStack(spacing: 3) {
            Image(systemName: state.symbol)
                .font(.system(size: 9, weight: .semibold))
            Text(state.label)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
        }
        .foregroundStyle(state.foreground)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(state.background))
    }

    private var subtitleText: String {
        let parts = [
            experience.location.placeNameRomanized,
            experience.location.placeNameLocal
        ].compactMap { $0?.isEmpty == false ? $0 : nil }
        if parts.isEmpty {
            return experience.location.addressHint ?? ""
        }
        return parts.joined(separator: " · ")
    }

    /// Trailing column: compass arrow over the formatted distance, right-aligned.
    private var distanceColumn: some View {
        let bearing = relativeBearing
        let hasLiveBearing = bearing != nil
        let arrowColor: AnyShapeStyle = isNearby
            ? AnyShapeStyle(CT.sunGoldDeep)
            : (hasLiveBearing ? AnyShapeStyle(CT.fgMuted) : AnyShapeStyle(CT.fgSubtle))
        return VStack(alignment: .trailing, spacing: 4) {
            if !isFarAway {
                Image(systemName: "location.north.line.fill")
                    .font(.caption2)
                    .foregroundStyle(arrowColor)
                    .rotationEffect(.degrees(bearing ?? 0))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: bearing)
                    .scaleEffect(pulsing ? 1.18 : 1.0)
            }
            if let meters = distanceMeters {
                Text(formattedDistance(meters))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(isFarAway ? AnyShapeStyle(CT.fgMuted) : (isNearby ? AnyShapeStyle(CT.sunGoldDeep) : AnyShapeStyle(CT.fgSubtle)))
                    .lineLimit(1)
                if isNearby {
                    Text(NSLocalizedString("peek.card.almostThere", comment: "Almost there micro-label shown when < 150m"))
                        .font(.caption2)
                        .foregroundStyle(CT.sunGoldDeep)
                }
            }
        }
        .accessibilityHidden(true)
        .onAppear { startNearbyPulseIfNeeded() }
        .onChange(of: isNearby) { _, nearby in
            if nearby {
                startNearbyPulseIfNeeded()
            } else {
                withAnimation(.default) { pulsing = false }
            }
        }
    }

    private func startNearbyPulseIfNeeded() {
        guard isNearby, !reduceMotion else {
            pulsing = false
            return
        }
        withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
            pulsing = true
        }
    }

    private var cardFill: Color {
        colorScheme == .dark ? CT.warmCardDark : CT.surfaceWhite
    }

    private var textPrimary: Color {
        colorScheme == .dark ? CT.fgPrimaryDark : CT.fgPrimary
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(isSmartPick ? AnyShapeStyle(smartPickGradient) : AnyShapeStyle(cardFill))
    }

    private var smartPickGradient: LinearGradient {
        let colors: [Color] = colorScheme == .dark
            ? [CT.sunGoldDeep.opacity(0.25), CT.warmCardDark]
            : [CT.sunGoldSoft.opacity(0.55), CT.surfaceWhite]
        return LinearGradient(
            colors: colors,
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var accessibilityLabel: Text {
        var label = experience.title
        label += ", Solo \(String(format: "%.1f", experience.soloScore.overall))"
        if let meters = distanceMeters {
            if isFarAway {
                label += ", " + String(
                    format: NSLocalizedString("nearby.distance.inCity.a11y", comment: "VoiceOver: located in city"),
                    cityDisplayName
                )
            } else {
                label += ", \(formattedDistance(meters))"
            }
        }
        if !isFarAway, let dirSuffix = compassDirectionSuffix {
            label += ", \(dirSuffix)"
        }
        if isSmartPick {
            label += ", " + NSLocalizedString("sheet.nearby.smartPick.a11y", comment: "AI pick")
        }
        if isOpenNow {
            // Prefer the live closing-soon phrasing when the window is winding
            // down; otherwise the plain open-now cue.
            if let state = bestNowChipState, state.isClosingSoon {
                label += ", " + state.accessibilityLabel
            } else {
                label += ", " + NSLocalizedString("sheet.nearby.openNow.a11y", comment: "Open now accessibility")
            }
        }
        if isNearby {
            label += ", " + NSLocalizedString("peek.card.almostThere.a11y", comment: "VoiceOver: almost there proximity cue")
        }
        return Text(label)
    }

    /// Beyond this threshold, raw distance is meaningless (cross-continent);
    /// we show the city name instead.
    private static let farAwayThreshold: Double = 500_000

    private var isFarAway: Bool {
        guard let m = distanceMeters else { return false }
        return m >= Self.farAwayThreshold
    }

    private var cityDisplayName: String {
        Self.cityNames[experience.location.cityCode] ?? experience.location.cityCode
    }

    private static let cityNames: [String: String] = [
        "cmi": "Chiang Mai",
        "VTE": "Vientiane",
        "cn-深圳市": "Shenzhen",
    ]

    private func formattedDistance(_ meters: Double) -> String {
        if meters >= Self.farAwayThreshold {
            return String(
                format: NSLocalizedString("nearby.distance.inCity", comment: "Distance replaced by city name when > 500km"),
                cityDisplayName
            )
        }
        return Self.distanceFormatter.string(from: Measurement(value: meters, unit: UnitLength.meters))
    }
}
