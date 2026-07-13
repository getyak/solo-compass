import SwiftUI

/// City OS v2 · 在地 · 本周 local-events sheet (PRD §5.3). Lists this week's
/// solo-scored happenings and travel notices for the city, each an honest card:
/// name, limited-time chip, a Solo chip + one-line "一个人去合不合适" note, a
/// freshness footer, and a "在地图上看" jump. Notices render in the warning
/// treatment — no Solo score, just the heads-up.
struct LiveSheet: View {
    let events: [CityEvent]
    /// Dismiss the sheet, recenter the map on the event, and highlight its marker.
    let onShowOnMap: (CityEvent) -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// Notices first (they affect movement today), then events by start time.
    private var ordered: [CityEvent] {
        events.sorted { lhs, rhs in
            if lhs.isNotice != rhs.isNotice { return lhs.isNotice }
            return (lhs.startsAt ?? .distantFuture) < (rhs.startsAt ?? .distantFuture)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if ordered.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(ordered) { event in
                                LiveEventCard(
                                    event: event,
                                    onShowOnMap: event.lat != nil && event.lng != nil
                                        ? { onShowOnMap(event) }
                                        : nil
                                )
                            }
                        }
                        .padding(16)
                    }
                    .background(background.ignoresSafeArea())
                }
            }
            .navigationTitle(NSLocalizedString("cityos.live.title", comment: "在地 · 本周 sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "Done")) { onDismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var background: Color {
        colorScheme == .dark ? CT.warmSheetDark : CT.surfaceSunken
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 40))
                .foregroundStyle(CT.fgSubtle)
            Text(NSLocalizedString("cityos.live.empty.title", comment: "No local events this week"))
                .ctDisplay(16, .semibold)
                .foregroundStyle(colorScheme == .dark ? CT.fgPrimaryDark : CT.fgPrimary)
            Text(NSLocalizedString("cityos.live.empty.hint", comment: "Check back — the city brief refreshes twice a week."))
                .ctBody(13)
                .foregroundStyle(CT.fgMuted)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background.ignoresSafeArea())
    }
}

// MARK: - LiveEventCard

/// One 在地 event card. Shared between `LiveSheet` and the chat `ChatEventCard`
/// (B4) so the two surfaces stay visually identical. When `onShowOnMap` is nil
/// (no coordinate), the map button is omitted.
struct LiveEventCard: View {
    let event: CityEvent
    var onShowOnMap: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    /// Events carry no `lastVerifiedAt` (the schema tracks freshness via
    /// `seenLabel` + `endsAt`), so the dot maps the server health directly
    /// rather than through the age-decay path, which would flag every event
    /// `.questioned` for a missing timestamp.
    private var health: HealthStatus {
        switch event.serverHealth {
        case "green":  return .healthy
        case "yellow": return .fading
        case "red":    return .questioned
        default:       return .fading
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            titleRow
            metaRow
            if let note = event.soloNote, !note.isEmpty {
                Text(note)
                    .ctBody(13)
                    .foregroundStyle(event.isNotice ? CT.warningText : primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            footer
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
    }

    private var titleRow: some View {
        HStack(alignment: .top, spacing: 8) {
            if event.isNotice {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CT.warningText)
            }
            Text(event.name)
                .ctDisplay(15, .semibold)
                .foregroundStyle(event.isNotice ? CT.warningText : primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let limited = event.limitedLabel, !limited.isEmpty {
                limitedChip(limited)
            }
        }
    }

    private func limitedChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(CT.eventLimited)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(CT.eventLimitedSoft))
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            Text(event.whenLabel)
                .ctMono(11)
                .foregroundStyle(CT.fgMuted)
            if !event.isNotice, let score = event.soloScore {
                soloChip(score)
            }
            Spacer(minLength: 0)
        }
    }

    private func soloChip(_ score: Double) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "person.fill")
                .font(.system(size: 9, weight: .semibold))
            Text(String(
                format: NSLocalizedString("cityos.live.solo", comment: "Solo %@"),
                String(format: "%.1f", score)
            ))
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(CT.verifiedGreen)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(CT.successSoft))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            HealthDot(status: health)
            if let seen = event.seenLabel, !seen.isEmpty {
                Text(seen)
                    .ctMono(10)
                    .foregroundStyle(CT.fgMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let onShowOnMap {
                Button {
                    Haptics.impact(.light)
                    onShowOnMap()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 10, weight: .semibold))
                        Text(NSLocalizedString("cityos.live.showOnMap", comment: "在地图上看"))
                            .ctBody(12, .semibold)
                    }
                    .foregroundStyle(CT.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(mapButtonFill))
                }
                .buttonStyle(PressableButtonStyle(pressedScale: 0.96))
                .accessibilityLabel(Text(String(
                    format: NSLocalizedString("cityos.live.showOnMap.a11y", comment: "Show %@ on the map"),
                    event.name
                )))
            }
        }
    }

    // MARK: - Colors

    private var cardFill: Color {
        if event.isNotice { return colorScheme == .dark ? CT.warmSunkenDark : CT.warningSoft }
        return colorScheme == .dark ? CT.warmCardDark : CT.surfaceWhite
    }
    private var borderColor: Color { colorScheme == .dark ? CT.warmBorderDark : CT.borderSubtle }
    private var mapButtonFill: Color { colorScheme == .dark ? CT.warmSunkenDark : CT.accentSoft }
    private var primaryText: Color { colorScheme == .dark ? CT.fgPrimaryDark : CT.fgPrimary }
}
