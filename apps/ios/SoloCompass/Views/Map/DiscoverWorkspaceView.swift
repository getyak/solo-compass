import CoreLocation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The 发现 surface: a working, curated discovery view built on the same real
/// data and actions the map already had — `RoutesSection`, `CreateRouteEntryCard`
/// and `NearbySection` — rather than a parallel mock catalogue.
///
/// It is deliberately data-in / closures-out so it can be previewed and hosted
/// in tests without a live `MapViewModel`. Nothing here invents places, times,
/// sources or photos; every row is an existing `Experience` or `Route` and the
/// Ask Solo / open / adopt actions route back through the map's real flows.
@MainActor
struct DiscoverWorkspaceView: View {
    let cityDisplayName: String
    let routes: [Route]
    let experiences: [Experience]
    let smartPickIds: [String]
    let referenceCoordinate: CLLocationCoordinate2D?
    let isLoading: Bool
    let isSearchingWeb: Bool
    let isNowFilter: Bool
    let isOffline: Bool
    let suggestedCityName: String?

    let onSelectExperience: (Experience) -> Void
    let onLongPressExperience: (Experience) -> Void
    let onAskSoloExperience: (Experience) -> Void
    let onSelectRoute: (Route) -> Void
    let onProposeRoute: () -> Void
    let onCreateRoute: () -> Void
    let onExploreElsewhere: () -> Void
    let onSwitchToSuggestedCity: (() -> Void)?
    let onWebSearch: (String) -> Void
    let onRefresh: () -> Void

    /// Optional City-OS 游民基地 card, built by the host (it needs the city-mode
    /// store, visa math and work-ready counts). Keeping it here preserves the
    /// feature the legacy bottom sheet's peek header used to expose.
    var baseCard: AnyView? = nil

    @State private var sortMode: SortMode = .smart
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                if isOffline {
                    InlineBanner(
                        tone: .warning,
                        title: NSLocalizedString(
                            "discover.offline.title",
                            comment: "Discovery offline banner title"
                        ),
                        subtitle: NSLocalizedString(
                            "discover.offline.subtitle",
                            comment: "Discovery offline banner subtitle"
                        ),
                        icon: "wifi.slash",
                        ctaLabel: NSLocalizedString("discover.retry", comment: "Retry"),
                        onCTA: onRefresh
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                if let baseCard {
                    baseCard
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                }

                if isLoading && experiences.isEmpty {
                    NearbyRowSkeletonList()
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .accessibilityIdentifier("discover.loading")
                }
                // When the list is empty, `NearbySection` renders the canonical
                // empty state (explore-elsewhere / switch-city CTAs) itself — a
                // second empty block here would compete with it.

                if Self.showsRoutes(isNowFilter: isNowFilter) {
                    RoutesSection(
                        routes: routes,
                        isNowFilter: isNowFilter,
                        onSelectRoute: onSelectRoute,
                        onProposeRoute: onProposeRoute
                    )
                    CreateRouteEntryCard(onTap: onCreateRoute)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                NearbySection(
                    experiences: experiences,
                    smartPickIds: smartPickIds,
                    referenceCoordinate: referenceCoordinate,
                    sortMode: sortMode,
                    showsSectionDivider: Self.showsRoutes(isNowFilter: isNowFilter),
                    isLoading: isLoading,
                    isNowFilter: isNowFilter,
                    isSearchingWeb: isSearchingWeb,
                    onExploreElsewhere: onExploreElsewhere,
                    suggestedCityName: suggestedCityName,
                    onSwitchToSuggestedCity: onSwitchToSuggestedCity,
                    onWebSearch: onWebSearch,
                    onSelectExperience: onSelectExperience,
                    onLongPressExperience: onLongPressExperience,
                    onAskSoloExperience: onAskSoloExperience
                )

                Color.clear.frame(height: 12)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier(WorkspaceAccessibility.discover)
        .refreshable { await MainActor.run { onRefresh() } }
    }

    /// Routes are a Now-context artifact (the same rule the map sheet used), so
    /// discovery only surfaces them when the Now filter is active.
    static func showsRoutes(isNowFilter: Bool) -> Bool {
        isNowFilter
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("discover.title", comment: "Discovery surface title"))
                        .ctDisplay(20, .bold)
                        .foregroundStyle(colorScheme == .dark ? CT.fgPrimaryDark : CT.fgPrimary)
                    Text(String(
                        format: NSLocalizedString("discover.subtitle", comment: "Discovery subtitle — %@ city"),
                        cityDisplayName
                    ))
                        .font(.footnote)
                        .foregroundStyle(colorScheme == .dark ? CT.fgMutedDark : CT.fgMuted)
                }
                Spacer(minLength: 8)
                sortMenu
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    /// Sort control mirrors the sheet's sort menu, but only for the Nearby
    /// section — routes keep their own Now/verified ordering.
    private var sortMenu: some View {
        Menu {
            ForEach(SortMode.allCases) { mode in
                Button {
                    #if canImport(UIKit)
                    Haptics.selection()
                    #endif
                    sortMode = mode
                } label: {
                    Label(mode.localizedTitle, systemImage: mode.symbol)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: sortMode.symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(sortMode.localizedTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(colorScheme == .dark ? CT.sunGold : CT.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassSurface(.control, in: Capsule(), opaqueFallback: CT.cardAdaptive)
        }
        .accessibilityIdentifier("discover.sort")
        .accessibilityLabel(Text(NSLocalizedString("sort.a11y", comment: "Sort experiences")))
        .accessibilityValue(Text(sortMode.accessibilityValue))
    }
}

#Preview("Discover") {
    DiscoverWorkspaceView(
        cityDisplayName: "Chiang Mai",
        routes: [],
        experiences: [],
        smartPickIds: [],
        referenceCoordinate: nil,
        isLoading: false,
        isSearchingWeb: false,
        isNowFilter: false,
        isOffline: false,
        suggestedCityName: nil,
        onSelectExperience: { _ in },
        onLongPressExperience: { _ in },
        onAskSoloExperience: { _ in },
        onSelectRoute: { _ in },
        onProposeRoute: {},
        onCreateRoute: {},
        onExploreElsewhere: {},
        onSwitchToSuggestedCity: nil,
        onWebSearch: { _ in },
        onRefresh: {}
    )
    .environment(BestNowClock.shared)
    .background(CT.bgWarm)
}
