import SwiftUI
import SwiftData

/// Nomad OS B1-b status header: the sticky top of the Today home —
/// **city · day-in-city · lifecycle face · visa ring** (design
/// nomad-os-b1-today-home-20260719 §2 ①).
///
/// It reuses the map's visual language — `BaseFace` for the lifecycle chip and
/// `BaseCountdownRing` for the visa ring — but derives its data from
/// independently-obtainable sources rather than the map's `MapViewModel`
/// `@State` (which Today can't reach), so it never forces the map's internal
/// state to be hoisted:
///
///   - city       ← `preferences.lastSelectedCity` + the now-`static`
///                  `MapViewModel.cityNameMap` (one source of truth for names)
///   - day-in-city← `ArchiveViewModel.currentTrip?.dayCount` (the ledger's
///                  in-city day span, NOT the visa stay day the map's BaseCard
///                  fills — design §2 ① calls out the two口径 must not be mixed)
///   - face       ← `CityOSStore.mode/stage` → `BaseFace.derive`
///   - visa ring  ← `ComplianceService.state()`, three-state per decision C:
///                  unset (entry-date CTA) / confirmed (ring) / critical (tint)
struct TodayStatusHeader: View {
    @Environment(UserPreferences.self) private var preferences

    /// Independently-built ledger + compliance sources. Kept as `@State` so
    /// they survive re-renders; refreshed in `.task` and when the city changes.
    @State private var archive: ArchiveViewModel?
    @State private var compliance: ComplianceService?
    @State private var cityStore: CityOSStore?

    /// Called when the traveler taps the unset visa ring — the entry-date
    /// confirm hook (design decision C: empty state is the ledger's first
    /// onboarding hook, not a hidden block). Wired in a later slice.
    var onConfirmEntryDate: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.sm) {
                faceChip
                Text(cityName)
                    .ctDisplay(20, .bold, relativeTo: .title2)
                    .foregroundStyle(CT.textPrimaryAdaptive)
                    .lineLimit(1)
                dayLine
            }
            Spacer(minLength: 0)
            visaRing
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.lg)
        .background(CT.pageAdaptive)
        .task { rebuildSources() }
        .onChange(of: preferences.lastSelectedCity) { _, _ in rebuildSources() }
    }

    // MARK: Derived values

    private var cityCode: String? {
        preferences.lastSelectedCity
    }

    private var cityName: String {
        guard let code = cityCode, !code.isEmpty else {
            return NSLocalizedString("today.header.noCity", comment: "No city selected yet")
        }
        return MapViewModel.cityNameMap[code] ?? code
    }

    /// In-city day span from the ledger (nil when no visits recorded yet).
    private var dayInCity: Int? {
        archive?.currentTrip?.dayCount
    }

    private var face: BaseFace {
        let mode = cityStore?.mode(for: cityCode) ?? .live
        let stage = cityStore?.stage(for: cityCode, daysStayed: dayInCity)
        return BaseFace.derive(mode: mode, stage: stage)
    }

    // MARK: Pieces

    private var faceChip: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: face.symbol)
                .font(.system(size: 10, weight: .bold))
            Text(face.tagText)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.0)
                .textCase(.uppercase)
        }
        .foregroundStyle(face.tagColor)
        .padding(.horizontal, Space.sm)
        .padding(.vertical, 3)
        .background(Capsule().fill(face.tagColor.opacity(0.12)))
    }

    @ViewBuilder
    private var dayLine: some View {
        if let day = dayInCity {
            Text(String(
                format: NSLocalizedString("today.header.dayInCity", comment: "Day %d in this city"),
                day
            ))
            .ctBody(13, .medium)
            .foregroundStyle(CT.textMutedAdaptive)
        } else {
            Text(NSLocalizedString("today.header.firstDay", comment: "Just arrived / no visits yet"))
                .ctBody(13, .medium)
                .foregroundStyle(CT.textMutedAdaptive)
        }
    }

    /// Three-state visa ring (decision C). `state()` is nil until the traveler
    /// confirms an entry date → show a tap-to-confirm affordance instead of an
    /// empty ring, turning the void into the ledger's first onboarding hook.
    @ViewBuilder
    private var visaRing: some View {
        if let state = compliance?.state(),
           let policyDays = visaPolicyDays {
            BaseCountdownRing(
                remaining: state.visaDaysRemaining,
                total: policyDays
            )
            .accessibilityLabel(Text(String(
                format: NSLocalizedString("today.header.visaRemaining", comment: "%d visa days left"),
                state.visaDaysRemaining
            )))
        } else {
            Button(action: onConfirmEntryDate) {
                VStack(spacing: 2) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 18, weight: .semibold))
                    Text(NSLocalizedString("today.header.setEntryDate", comment: "Set entry date CTA"))
                        .ctBody(10, .semibold)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(CT.accent)
                .frame(width: 56)
            }
            .buttonStyle(.plain)
        }
    }

    /// The city's visa allowance (denominator for the ring). Read from the
    /// persisted stay length the traveler set; nil hides the ring in favour of
    /// the confirm CTA. `ComplianceService.state()` supplies remaining; total
    /// comes from `preferences.visaLengthDays`.
    private var visaPolicyDays: Int? {
        guard let days = preferences.visaLengthDays, days > 0 else { return nil }
        return days
    }

    // MARK: Source lifecycle

    private func rebuildSources() {
        let container = SoloCompassModelContainer.shared
        let vm = archive ?? ArchiveViewModel(modelContainer: container, activeCityCode: cityCode)
        vm.activeCityCode = cityCode
        vm.refresh()
        archive = vm

        if compliance == nil { compliance = ComplianceService(preferences: preferences) }
        if cityStore == nil { cityStore = CityOSStore(preferences: preferences) }
    }
}
