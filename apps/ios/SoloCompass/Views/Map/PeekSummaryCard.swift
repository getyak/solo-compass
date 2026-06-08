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
        return meters < 150
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
                Text(experience.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CT.fgPrimary)
                    .lineLimit(1)
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

    /// Chip row: walk-time (if nearby) + Solo-Score badge + (optional) 此刻最佳 chip.
    private var chipRow: some View {
        HStack(spacing: 6) {
            if let meters = distanceMeters, meters < 1500 {
                walkTimeChip(meters: meters)
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
        }
        .foregroundStyle(CT.fgMuted)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(CT.surfaceSunken))
        .accessibilityHidden(true)
    }

    /// Golden chip: 此刻最佳 — shown when the experience is open in the current hour.
    private var bestNowChip: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .semibold))
            Text(NSLocalizedString("nearby.chip.bestNow", comment: "此刻最佳 chip"))
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(CT.sunGoldDeep)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(CT.sunGoldSoft))
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
        if parts.isEmpty {
            return experience.location.addressHint ?? ""
        }
        return parts.joined(separator: " · ")
    }

    private var isOpenNow: Bool {
        let hour = Calendar.current.component(.hour, from: clock.tick)
        return experience.bestTimes.contains { $0.contains(hour: hour) }
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
                label += ", \(String(format: NSLocalizedString("nearby.chip.walkMin", comment: "Walk minutes chip, e.g. '4 分钟'"), minutes)) walk"
            }
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
