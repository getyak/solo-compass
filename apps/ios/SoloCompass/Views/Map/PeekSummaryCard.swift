import SwiftUI
import CoreLocation

// MARK: - PeekSummaryCard

/// "此刻最值得去" summary card shown in the BottomInfoSheet's peek state.
///
/// Replaces the empty single-line hint with one concrete, tappable suggestion so
/// the resting sheet earns its 240pt height. Tapping the card expands the sheet
/// to `.mid` (the full nearby list) rather than opening the detail sheet — the
/// expand semantics are owned by the caller via `onTap`.
///
/// The card's chrome is a *visual* port of `NearbyExperienceRow` (the disc,
/// title stack, chip row, distance column are all private to that view in a
/// different parent context, so they are reproduced here rather than extracted):
/// a 3pt left color bar (sun-gold for the AI smart pick, else the category tint),
/// a 40×40 category disc, the title + romanized·local subtitle, a chip row
/// (`SoloScoreBadge(.compact)` + an optional 此刻最佳 chip) and a trailing
/// compass-arrow + distance column.
struct PeekSummaryCard: View {
    let experience: Experience
    /// True when this card is the AI smart pick — drives the warm gold gradient
    /// background and the "AI Pick" marker.
    let isSmartPick: Bool
    /// Reference coordinate (user location or map center) for distance + bearing.
    let referenceCoordinate: CLLocationCoordinate2D?
    /// True when `referenceCoordinate` is a real GPS fix. The "就快到了"
    /// proximity cue claims *presence* — without a fix the reference is just
    /// the city's default center, and announcing "almost there" would be a
    /// lie. Walk/drive estimates still show (they read as "from where you're
    /// looking"), only the presence claim is gated.
    var referenceIsUserLocation: Bool = false
    /// Fired when the card is tapped — the caller expands the sheet to `.mid`.
    let onTap: () -> Void
    /// Fired by the "换一个" pill — the caller rotates to the next pick. The
    /// pill is hidden when nil (previews / contexts without a rotation source).
    var onShuffle: (() -> Void)? = nil

    @State private var pressed = false
    @State private var isShowingNavPicker = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(BestNowClock.self) private var clock

    private var isNearby: Bool {
        guard referenceIsUserLocation, let meters = distanceMeters else { return false }
        return meters < ProximityConfig.nearbyThreshold(for: experience.location.cityCode)
    }

    /// Single shared formatter — re-allocating a `MeasurementFormatter` per body
    /// evaluation is wasteful (it parses locale data each time).
    private static let distanceFormatter: MeasurementFormatter = {
        let f = MeasurementFormatter()
        f.unitOptions = .naturalScale
        f.unitStyle = .short
        f.numberFormatter.maximumFractionDigits = 1
        return f
    }()

    var body: some View {
        // North-star card ("此刻卡片", PRD solo-city-os-v2 §5.1): three answer
        // rows — Now (gold) / Solo (amber) / Confidence (mono) — plus the two
        // actions the decision deserves, CityMapper-style: decide on the card,
        // act on the card. The container is a tap-gesture view rather than a
        // Button so the inner 带我去 / 换一个 pills get clean hit-testing.
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 12) {
                categoryDisc
                VStack(alignment: .leading, spacing: 7) {
                    titleStack
                    chipRow
                }
                Spacer(minLength: 0)
            }
            // Row 1 — is right now a good moment? (NowScore percent + reason)
            nowScoreLine
            // Row 2 — solo insight: one line of friend-voice copy. The map
            // opens and Solo already has a *reason* to suggest this spot —
            // not just a name.
            warmReasonLine
            // Row 3 — falsifiable facts (mono) + the two actions.
            confidenceActionFooter
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(isSmartPick ? CT.accentBorder : CT.borderSubtle, lineWidth: 0.5)
        )
        .overlay(alignment: .leading) {
            // 3pt left color bar: gold for the smart pick, else the category tint.
            UnevenRoundedRectangle(
                topLeadingRadius: 14, bottomLeadingRadius: 14,
                bottomTrailingRadius: 0, topTrailingRadius: 0,
                style: .continuous
            )
            .fill(isSmartPick ? CT.sunGold : experience.category.color)
            .frame(width: 3)
        }
        .clipShape(Radius.shape(Radius.md))
        .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
        .contentShape(Rectangle())
        .onTapGesture {
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
        }
        .scaleEffect(pressed ? 0.97 : 1.0)
        .confirmationDialog(
            NSLocalizedString("location.navigate", comment: "Navigate"),
            isPresented: $isShowingNavPicker,
            titleVisibility: .hidden
        ) {
            ForEach(NavigationLauncher.availableApps()) { app in
                Button(app.displayName) {
                    if let coord = experience.coordinate {
                        NavigationLauncher.open(app: app, coordinate: coord, name: experience.shortName)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(Text(NSLocalizedString("peek.card.hint", comment: "Double tap to expand the nearby list")))
        .accessibilityAction(named: Text(NSLocalizedString("peek.action.go", comment: "Take me there"))) {
            launchNavigation()
        }
        .accessibilityAction(named: Text(NSLocalizedString("peek.action.shuffle", comment: "Show another pick"))) {
            onShuffle?()
        }
    }

    // MARK: - Sub-views

    /// North-star row 1 — "is right now a good moment?". Gold percent (the
    /// hero number, Apple-Weather style); when the active window is winding
    /// down, the live closing countdown follows in amber (the chip's own
    /// localized copy, so the urgency voice matches the rest of the app).
    /// Hidden below 0.55 so the card never celebrates a mediocre moment —
    /// honesty first. `NowScore.reason` is deliberately NOT shown: today's
    /// signal reasons are developer strings ("in bestTimes window"), not
    /// traveler copy.
    @ViewBuilder
    private var nowScoreLine: some View {
        if let percent = nowPercent {
            let state = bestNowChipState
            HStack(spacing: 6) {
                Circle()
                    .fill(CT.sunGold)
                    .frame(width: 6, height: 6)
                Text(String(
                    format: NSLocalizedString("peek.now.goodTime", comment: "Now-score line, e.g. '现在 87% 好时机'"),
                    percent
                ))
                .ctDisplay(12, .bold)
                .monospacedDigit()
                .foregroundStyle(CT.sunGoldDeep)
                if state.isClosingSoon {
                    Text(state.label)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(state.foreground)
                        .lineLimit(1)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// The current NowScore as a display percent, or nil when it isn't worth
    /// announcing. Recomputed on each `BestNowClock` tick so it tracks real time.
    private var nowPercent: Int? {
        let score = experience.nowScore(at: clock.tick)
        guard score.value >= 0.55 else { return nil }
        return Int((score.value * 100).rounded())
    }

    /// North-star row 3 + CTA: the falsifiable-facts line (health dot + trust
    /// state + signal count + based-on, all mono — Flighty-style honest data)
    /// with the two actions the decision deserves: 换一个 rotates the pick,
    /// 带我去 launches walking directions.
    private var confidenceActionFooter: some View {
        HStack(spacing: 8) {
            confidenceLine
            Spacer(minLength: 6)
            if onShuffle != nil {
                shufflePill
            }
            goPill
        }
    }

    private var confidenceLine: some View {
        let facts = confidenceFacts
        return HStack(spacing: 5) {
            Circle()
                .fill(facts.dotColor)
                .frame(width: 6, height: 6)
            Text(facts.text)
                .ctMono(10)
                .foregroundStyle(CT.fgMuted)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(facts.a11y))
    }

    /// Health-dot color + mono facts. The visible line keeps only the fact a
    /// solo traveler weighs most — how many solos this is based on (or that
    /// it's an unverified AI estimate); the colored dot carries the trust
    /// state, so the line survives next to the two action pills without
    /// truncating. VoiceOver gets the full story: trust state (the detail
    /// hero's vocabulary) + signal count + based-on.
    private var confidenceFacts: (dotColor: Color, text: String, a11y: String) {
        let confidence = experience.confidence
        let state: (key: String, dot: Color) = {
            switch confidence.health {
            case .healthy:
                return ("trust.verified", CT.verifiedGreenDot)
            case .fading:
                return ("trust.observing", CT.sunGoldDeep)
            case .questioned, .mayBeGone:
                return ("trust.questioned", CT.warningText)
            }
        }()
        let basedOn = experience.soloScore.basedOnCount
        let text: String = switch basedOn {
        case 0:
            NSLocalizedString("peek.confidence.aiEstimate", comment: "AI estimate · unverified")
        case 1:
            NSLocalizedString("peek.confidence.basedOn.one", comment: "e.g. '基于 1 位独行者'")
        default:
            String(
                format: NSLocalizedString("peek.confidence.basedOn", comment: "e.g. '基于 3 位独行者'"),
                basedOn
            )
        }
        let a11y = [
            NSLocalizedString(state.key, comment: "Trust state label"),
            "\(confidence.signals.totalCount) " + NSLocalizedString("notes.signals", comment: "signals unit"),
            text
        ].joined(separator: " · ")
        return (state.dot, text, a11y)
    }

    /// Primary amber pill — walking directions in one tap, matching the detail
    /// dock's navigate treatment so the CTA reads identically across surfaces.
    private var goPill: some View {
        Button {
            launchNavigation()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(NSLocalizedString("peek.action.go", comment: "Take me there"))
                    .ctBody(12, .semibold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(CT.accent))
        }
        .buttonStyle(.plain)
        .disabled(experience.coordinate == nil)
        .accessibilityLabel(Text(NSLocalizedString("peek.action.go", comment: "Take me there")))
    }

    /// Ghost pill — rotate to the next pick. Never empty-handed: the resolver
    /// wraps around when every visible experience has been shuffled away.
    private var shufflePill: some View {
        Button {
            #if canImport(UIKit)
            Haptics.selection()
            #endif
            onShuffle?()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.2.circlepath")
                    .font(.system(size: 10, weight: .semibold))
                Text(NSLocalizedString("peek.action.shuffle", comment: "Show another pick"))
                    .ctBody(12, .medium)
            }
            .foregroundStyle(CT.fgMuted)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Capsule().fill(CT.surfaceSunken))
            .overlay(Capsule().strokeBorder(CT.borderSubtle, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(NSLocalizedString("peek.action.shuffle", comment: "Show another pick")))
    }

    /// Detail-dock parity: a sole installed maps app launches directly; more
    /// than one presents the picker dialog.
    private func launchNavigation() {
        guard let coord = experience.coordinate else { return }
        #if canImport(UIKit)
        Haptics.impact(.light)
        #endif
        if let only = NavigationLauncher.soleApp() {
            NavigationLauncher.open(app: only, coordinate: coord, name: experience.shortName)
        } else {
            isShowingNavPicker = true
        }
    }

    /// One-line warm rationale shown under the chip row. Friend voice —
    /// "I'd take you here right now because…". Empty when there's nothing
    /// honest to say so the card stays clean. When the copy is the Solo hint
    /// it wears the amber solo-lens treatment (figure + accent).
    @ViewBuilder
    private var warmReasonLine: some View {
        let copy = reasonCopy
        if !copy.isEmpty {
            let isSoloHint = hasSoloHint
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: isSoloHint ? "figure.stand" : (isSmartPick ? "sparkles" : "heart.fill"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSoloHint ? CT.accent : CT.sunGoldDeep)
                    .padding(.top, 2)
                Text(copy)
                    .font(.footnote)
                    .foregroundStyle(isSoloHint ? CT.accent : CT.sunGoldDeep)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(copy))
        }
    }

    /// Whether the Solo-Score hint is present — it owns row 2 when it exists.
    private var hasSoloHint: Bool {
        !(experience.soloScore.hint ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    /// The reason copy to show. Friend voice in both languages — never bare facts.
    /// Order: Solo hint (the one line a solo traveler most wants, PRD v2 §5.1) →
    ///        AI oneLiner (when non-empty and adds signal beyond the title) →
    ///        AI whyItMatters (smart-pick framing) →
    ///        warmStart template fallback → empty.
    ///
    /// Rubric fix: baseline only reached the AI signal when isSmartPick was
    /// set, so every non-smart-pick peek card showed the hardcoded
    /// "Strongest <category> pick · Solo N.N" copy. AI-enriched Amap POIs
    /// had a real oneLiner (e.g. "深夜串烧配清酒") that never surfaced
    /// until the user tapped through to the detail. Surface it here.
    private var reasonCopy: String {
        // 0. The Solo hint owns this row when it exists — it is the solo-lens
        //    voice ("Order at the bar, sit upstairs") the north-star card
        //    promises. Amap POIs rarely carry one, so the oneLiner rung below
        //    still surfaces their enrichment unchanged.
        if hasSoloHint, let hint = experience.soloScore.hint {
            return hint.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // 1. AI oneLiner wins when it exists and adds signal beyond the title.
        let oneLiner = experience.oneLiner.trimmingCharacters(in: .whitespacesAndNewlines)
        if !oneLiner.isEmpty
            && oneLiner.lowercased() != experience.title.lowercased() {
            return oneLiner
        }
        // 2. Smart-pick framing around whyItMatters — kept as an intermediate
        //    rung so a smart-pick with an empty oneLiner still gets warm copy.
        if isSmartPick {
            let why = experience.whyItMatters.trimmingCharacters(in: .whitespacesAndNewlines)
            if !why.isEmpty {
                let firstSentence = why
                    .split(whereSeparator: { ".。！？!?".contains($0) })
                    .first
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? why
                let format = NSLocalizedString(
                    "peek.reason.aiPick",
                    comment: "AI smart pick rationale, friend voice. %@ = why-it-matters first sentence."
                )
                return String(format: format, firstSentence)
            }
        }
        // 3. Warm-start fallback — for entries with no AI enrichment yet.
        let format = NSLocalizedString(
            "peek.reason.warmStart",
            comment: "Warm-start fallback reason, friend voice. %.1f = Solo score, %@ = category name."
        )
        return String(format: format, experience.category.localizedTitle, experience.soloScore.overall)
    }

    private var categoryDisc: some View {
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
            HStack(spacing: 6) {
                Text(experience.shortName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CT.fgPrimary)
                    .lineLimit(2)
                if isSmartPick {
                    aiPickTag
                }
            }
            let sub = subtitleText
            if !sub.isEmpty {
                Text(sub)
                    .font(.caption)
                    .foregroundStyle(CT.fgMuted)
                    .lineLimit(1)
            }
        }
    }

    /// Small "AI Pick" marker shown beside the title on the smart pick.
    private var aiPickTag: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
                .font(.system(size: 8, weight: .semibold))
            Text(NSLocalizedString("peek.card.aiPick", comment: "AI Pick tag"))
                .font(.system(size: 9, weight: .bold))
                .tracking(0.3)
        }
        .foregroundStyle(CT.sunGoldDeep)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(CT.sunGoldSoft))
        .accessibilityHidden(true)
    }

    /// Chip row: travel-time + Solo-Score badge. The old 此刻最佳 chip folded
    /// into the now-score line (row 1) and the old trailing distance column
    /// folded into the walk chip — three fixed-size chips plus a distance
    /// column starved each other of width; two chips always fit.
    ///
    /// Within walking range (< 1.5 km) we show estimated walk minutes; for
    /// mid-range picks (1.5–15 km) — too far to walk but still in-city — we
    /// show an estimated drive time so a far smart pick reads as a concrete
    /// effort ("~12 min drive") rather than a bare distance.
    private var chipRow: some View {
        HStack(spacing: 6) {
            if let meters = distanceMeters {
                if meters < 1500 {
                    walkTimeChip(meters: meters)
                } else if meters < 15_000 {
                    rideTimeChip(meters: meters)
                }
            }
            SoloScoreBadge(score: experience.soloScore, style: .compact)
        }
    }

    /// Walk chip: estimated walk minutes (≈ 80 m/min). Within ~150m it turns
    /// gold and reads "就快到了" — the proximity cue the removed distance
    /// column used to carry.
    private func walkTimeChip(meters: Double) -> some View {
        let minutes = max(1, Int((meters / 80).rounded()))
        let label = isNearby
            ? NSLocalizedString("peek.card.almostThere", comment: "Almost there micro-label shown when < 150m")
            : String(
                format: NSLocalizedString("nearby.chip.walkMin", comment: "Walk minutes chip, e.g. '4 分钟'"),
                minutes
            )
        return HStack(spacing: 3) {
            Image(systemName: "figure.walk")
                .font(.system(size: 9.5, weight: .semibold))
            Text(label)
                .font(.caption2.weight(isNearby ? .semibold : .medium))
                .lineLimit(1)
        }
        .foregroundStyle(isNearby ? AnyShapeStyle(CT.sunGoldDeep) : AnyShapeStyle(CT.fgMuted))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(isNearby ? AnyShapeStyle(CT.sunGoldSoft) : AnyShapeStyle(CT.surfaceSunken)))
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityHidden(true)
    }

    /// Neutral chip: estimated drive minutes (≈ 6 min/km in-city) for mid-range
    /// picks that are past comfortable walking distance.
    private func rideTimeChip(meters: Double) -> some View {
        let minutes = max(1, Int((meters / 1000 * 6).rounded()))
        let label = String(
            format: NSLocalizedString("nearby.chip.driveMin", comment: "Drive minutes chip, e.g. '12 min drive'"),
            minutes
        )
        return HStack(spacing: 3) {
            Image(systemName: "car.fill")
                .font(.system(size: 9.5, weight: .semibold))
            Text(label)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(CT.fgMuted)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(CT.surfaceSunken))
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityHidden(true)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(isSmartPick ? AnyShapeStyle(smartPickGradient) : AnyShapeStyle(CT.surfaceWhite))
    }

    private var smartPickGradient: LinearGradient {
        LinearGradient(
            colors: [CT.sunGoldSoft.opacity(0.55), CT.surfaceWhite],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Derived values

    private var subtitleText: String {
        let parts = [
            experience.location.placeNameRomanized,
            experience.location.placeNameLocal
        ].compactMap { $0?.isEmpty == false ? $0 : nil }
        // Drop place-name parts that just duplicate the card's shortName — a
        // peek card titled "Nimman Roasters" subtitled "Nimman Roasters" reads
        // as a render bug. Keep neighborhood-ish parts, swap pure duplicates
        // for a soft category hint.
        let shortName = experience.shortName
        let deduped = parts.filter { $0.caseInsensitiveCompare(shortName) != .orderedSame }
        if deduped.isEmpty {
            return experience.category.localizedTitle
        }
        return deduped.joined(separator: " · ")
    }

    /// Live "best now / closing soon" chip state, recomputed each time the shared
    /// `BestNowClock` advances (the `clock.tick` read makes this card an observer).
    private var bestNowChipState: BestNowChipState {
        BestNowChipState.resolve(for: experience, at: clock.tick)
    }

    /// True when the experience is genuinely at its best right now. Uses
    /// `minutesLeftInBestWindow` (via the chip state) as the single source of
    /// truth — it honours weekday / season filters and midnight-wrapping
    /// windows, unlike the old bare "current hour ∈ bestTimes" check which would
    /// falsely flag a weekend-only or summer-only window on the wrong day.
    private var isOpenNow: Bool {
        bestNowChipState.minutesLeft != nil
    }

    /// Distance (m) from the reference coordinate to the experience.
    private var distanceMeters: Double? {
        guard let ref = referenceCoordinate,
              let coord = experience.coordinate else { return nil }
        let from = CLLocation(latitude: ref.latitude, longitude: ref.longitude)
        let to = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        return from.distance(from: to)
    }

    private func formattedDistance(_ meters: Double) -> String {
        Self.distanceFormatter.string(from: Measurement(value: meters, unit: UnitLength.meters))
    }

    private var accessibilityLabel: Text {
        var label = experience.title
        if isSmartPick {
            label += ", " + NSLocalizedString("peek.card.aiPick.a11y", comment: "AI pick for right now")
        }
        label += ", Solo \(String(format: "%.1f", experience.soloScore.overall))"
        if let meters = distanceMeters {
            label += ", \(formattedDistance(meters))"
            if meters < 1500 {
                let minutes = max(1, Int((meters / 80).rounded()))
                label += ", \(String(format: NSLocalizedString("card.distance.walk", comment: "Walk minutes, e.g. '4 min walk'"), minutes))"
            } else if meters < 15_000 {
                let minutes = max(1, Int((meters / 1000 * 6).rounded()))
                label += ", \(String(format: NSLocalizedString("nearby.chip.driveMin", comment: "Drive minutes chip, e.g. '12 min drive'"), minutes))"
            }
        }
        if isOpenNow {
            // Surface the live timing the same way the visible chip does: the
            // closing-soon countdown when winding down, else a plain best-now cue.
            let state = bestNowChipState
            label += ", " + (state.isClosingSoon
                ? state.accessibilityLabel
                : NSLocalizedString("sheet.nearby.openNow.a11y", comment: "Open now accessibility"))
        }
        if isNearby {
            label += ", " + NSLocalizedString("peek.card.almostThere.a11y", comment: "VoiceOver: almost there proximity cue")
        }
        // North-star rows: the now-percent and the full confidence facts (the
        // visible line abbreviates; VoiceOver gets the complete story).
        if let percent = nowPercent {
            label += ", " + String(
                format: NSLocalizedString("peek.now.goodTime", comment: "Now-score line, e.g. '现在 87% 好时机'"),
                percent
            )
        }
        label += ", " + confidenceFacts.a11y
        return Text(label)
    }
}

// MARK: - PeekEmptyCard

/// Peek-state placeholder shown when no experiences are visible. The mappin.slash
/// icon pulses gently (scale + opacity) to invite the traveler to pan the map.
/// Pulse is suppressed when Reduce Motion is on.
struct PeekEmptyCard: View {
    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(CT.fgSubtle)
                .scaleEffect(isPulsing ? 1.08 : 0.94)
                .opacity(isPulsing ? 1.0 : 0.6)
            Text(NSLocalizedString("peek.empty.hint", comment: "Move the map to discover nearby spots"))
                .font(.subheadline)
                .foregroundStyle(CT.fgMuted)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(CT.surfaceWhite)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(CT.borderSubtle, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(NSLocalizedString("peek.empty.hint", comment: "Move the map to discover nearby spots")))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced {
                withAnimation(.default) { isPulsing = false }
            } else {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("PeekSummaryCard") {
    let seed = ExperienceService.hardcodedSeed
    return ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()
        VStack(spacing: 16) {
            if let pick = seed.first {
                PeekSummaryCard(
                    experience: pick,
                    isSmartPick: true,
                    referenceCoordinate: pick.coordinate,
                    onTap: {}
                )
            }
            if seed.count > 1 {
                PeekSummaryCard(
                    experience: seed[1],
                    isSmartPick: false,
                    referenceCoordinate: seed.first?.coordinate,
                    onTap: {}
                )
            }
            PeekEmptyCard()
        }
        .padding(16)
    }
    .environment(LocationService.shared)
    .environment(BestNowClock.shared)
}

#Preview("Best now vs. Closing soon") {
    // Two synthetic picks at the same spot: one whose best window has hours left
    // (plain gold "Best now" chip) and one whose window ends at the top of the
    // next hour, so within ~45 min of most open times it renders the amber
    // "Closing · Nm" chip. Demonstrates the live urgency treatment.
    let cal = Calendar.current
    let hour = cal.component(.hour, from: Date())
    func pick(from base: Experience, id: String, endsInHours: Int) -> Experience {
        Experience(
            id: id, title: base.title, oneLiner: base.oneLiner, whyItMatters: base.whyItMatters,
            category: base.category, location: base.location,
            bestTimes: [TimeWindow(startHour: (hour + 23) % 24, endHour: (hour + endsInHours) % 24)],
            durationMinutes: base.durationMinutes, howTo: base.howTo,
            realInconveniences: base.realInconveniences, soloScore: base.soloScore,
            sources: base.sources, confidence: base.confidence,
            nearbyExperienceIds: base.nearbyExperienceIds, stats: base.stats, status: base.status,
            createdAt: base.createdAt, updatedAt: base.updatedAt, userTags: base.userTags
        )
    }
    return ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()
        VStack(spacing: 16) {
            if let base = ExperienceService.hardcodedSeed.first {
                PeekSummaryCard(
                    experience: pick(from: base, id: "preview_open_all_evening", endsInHours: 4),
                    isSmartPick: true,
                    referenceCoordinate: base.coordinate,
                    onTap: {}
                )
                PeekSummaryCard(
                    experience: pick(from: base, id: "preview_closing_soon", endsInHours: 1),
                    isSmartPick: false,
                    referenceCoordinate: base.coordinate,
                    onTap: {}
                )
            }
        }
        .padding(16)
    }
    .environment(LocationService.shared)
    .environment(BestNowClock.shared)
}

#Preview("Proximity Pulse — nearby (<150m)") {
    let seed = ExperienceService.hardcodedSeed
    return ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()
        VStack(spacing: 16) {
            if let pick = seed.first, let coord = pick.coordinate {
                // Reference coordinate 80m north of the experience — forces isNearby = true
                let nearbyRef = CLLocationCoordinate2D(
                    latitude: coord.latitude + 0.00072,
                    longitude: coord.longitude
                )
                PeekSummaryCard(
                    experience: pick,
                    isSmartPick: true,
                    referenceCoordinate: nearbyRef,
                    onTap: {}
                )
                // Far pick for contrast — same experience, reference 5 km away
                let farRef = CLLocationCoordinate2D(
                    latitude: coord.latitude + 0.045,
                    longitude: coord.longitude
                )
                PeekSummaryCard(
                    experience: pick,
                    isSmartPick: false,
                    referenceCoordinate: farRef,
                    onTap: {}
                )
            }
        }
        .padding(16)
    }
    .environment(LocationService.shared)
    .environment(BestNowClock.shared)
}

#Preview("Empty Pulse") {
    ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()
        VStack(spacing: 16) {
            PeekEmptyCard()
        }
        .padding(16)
    }
}
