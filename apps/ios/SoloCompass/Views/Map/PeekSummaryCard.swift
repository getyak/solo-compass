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
    /// Fired when the card is tapped — the caller expands the sheet to `.mid`.
    let onTap: () -> Void

    @State private var pressed = false
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(LocationService.self) private var locationService
    @Environment(BestNowClock.self) private var clock

    private var isNearby: Bool {
        guard let meters = distanceMeters else { return false }
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
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    categoryDisc
                    VStack(alignment: .leading, spacing: 7) {
                        titleStack
                        chipRow
                    }
                    Spacer(minLength: 4)
                    distanceColumn
                }
                // Warm-start reason: one line of friend-voice copy under the
                // card. The map opens and Solo already has a *reason* to
                // suggest this spot — not just a name.
                warmReasonLine
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
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
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .scaleEffect(pressed ? 0.97 : 1.0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(Text(NSLocalizedString("peek.card.hint", comment: "Double tap to expand the nearby list")))
    }

    // MARK: - Sub-views

    /// One-line warm-amber rationale shown under the chip row. Friend voice —
    /// "I'd take you here right now because…". Empty when there's nothing
    /// honest to say so the card stays clean.
    @ViewBuilder
    private var warmReasonLine: some View {
        let copy = reasonCopy
        if !copy.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: isSmartPick ? "sparkles" : "heart.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CT.sunGoldDeep)
                    .padding(.top, 2)
                Text(copy)
                    .font(.footnote)
                    .foregroundStyle(CT.sunGoldDeep)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(copy))
        }
    }

    /// The reason copy to show. Friend voice in both languages — never bare facts.
    /// Order: AI oneLiner (when non-empty and adds signal beyond the title) →
    ///        AI whyItMatters (smart-pick framing) →
    ///        warmStart template fallback → empty.
    ///
    /// Rubric fix: baseline only reached the AI signal when isSmartPick was
    /// set, so every non-smart-pick peek card showed the hardcoded
    /// "Strongest <category> pick · Solo N.N" copy. AI-enriched Amap POIs
    /// had a real oneLiner (e.g. "深夜串烧配清酒") that never surfaced
    /// until the user tapped through to the detail. Surface it here.
    private var reasonCopy: String {
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

    /// Chip row: travel-time + Solo-Score badge + (optional) 此刻最佳 chip.
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
            if isOpenNow {
                bestNowChip
            }
        }
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
                .lineLimit(1)
        }
        .foregroundStyle(CT.fgMuted)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(CT.surfaceSunken))
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

    /// Golden chip: 此刻最佳 — shown when the experience is at its best right now.
    /// Flips to an amber "Closing · Nm" countdown when the active window has
    /// ≤ 45 minutes left, matching the detail card and Saved list so the peek
    /// pick carries the same urgency cue the rest of the app already shows.
    private var bestNowChip: some View {
        let state = bestNowChipState
        return HStack(spacing: 3) {
            Image(systemName: state.symbol)
                .font(.system(size: 9, weight: .semibold))
            Text(state.label)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(reduceMotion ? .identity : .numericText())
        }
        .foregroundStyle(state.foreground)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(state.background))
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityHidden(true)
    }

    /// Trailing column: compass arrow over the formatted distance, right-aligned.
    private var distanceColumn: some View {
        let bearing = relativeBearing
        let hasLiveBearing = bearing != nil
        let arrowColor: AnyShapeStyle = isNearby
            ? AnyShapeStyle(CT.sunGoldDeep)
            : (hasLiveBearing ? AnyShapeStyle(CT.fgMuted) : AnyShapeStyle(CT.fgSubtle))
        return VStack(alignment: .trailing, spacing: 4) {
            Image(systemName: "location.north.line.fill")
                .font(.caption2)
                .foregroundStyle(arrowColor)
                .rotationEffect(.degrees(bearing ?? 0))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: bearing)
                .scaleEffect(pulsing ? 1.18 : 1.0)
            if let meters = distanceMeters {
                Text(formattedDistance(meters))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(isNearby ? AnyShapeStyle(CT.sunGoldDeep) : AnyShapeStyle(CT.fgSubtle))
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

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
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

    private var relativeBearing: Double? {
        guard let coord = experience.coordinate else { return nil }
        return locationService.relativeBearing(to: coord)
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CT.surfaceWhite)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
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
