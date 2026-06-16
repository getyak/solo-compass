import SwiftUI
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - NearbySection

/// '附近' section rendered inside BottomInfoSheet when detent > .peek.
struct NearbySection: View {
    let experiences: [Experience]
    /// IDs of AI-ranked top picks (up to 3 pinned at top).
    let smartPickIds: [String]
    /// Reference coordinate for distance calculation (user location or map center).
    let referenceCoordinate: CLLocationCoordinate2D?
    let sortMode: SortMode
    /// Tapping a row jumps straight to the detail sheet.
    let onSelectExperience: (Experience) -> Void
    /// Long-pressing a row floats the quick preview card instead. Optional so
    /// callers that only wire a tap keep compiling.
    let onLongPressExperience: ((Experience) -> Void)?
    /// "问 Solo" context-menu action — opens a chat scoped to the experience.
    let onAskSoloExperience: ((Experience) -> Void)?
    /// When non-nil, passed through to EmptySheetListView to render the
    /// 'Explore another area' CTA that zooms the map out.
    let onExploreElsewhere: (() -> Void)?
    /// Suggested city name shown in the empty state when the current area has
    /// no experiences. Passed through to EmptySheetListView.
    let suggestedCityName: String?
    let onSwitchToSuggestedCity: (() -> Void)?
    let isNowFilter: Bool

    @Environment(BestNowClock.self) private var clock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchText: String = ""

    let isLoading: Bool

    init(
        experiences: [Experience],
        smartPickIds: [String],
        referenceCoordinate: CLLocationCoordinate2D?,
        sortMode: SortMode = .smart,
        showsSectionDivider: Bool = false,
        isLoading: Bool = false,
        isNowFilter: Bool = false,
        onExploreElsewhere: (() -> Void)? = nil,
        suggestedCityName: String? = nil,
        onSwitchToSuggestedCity: (() -> Void)? = nil,
        onSelectExperience: @escaping (Experience) -> Void,
        onLongPressExperience: ((Experience) -> Void)? = nil,
        onAskSoloExperience: ((Experience) -> Void)? = nil
    ) {
        self.experiences = experiences
        self.smartPickIds = smartPickIds
        self.referenceCoordinate = referenceCoordinate
        self.sortMode = sortMode
        self.showsSectionDivider = showsSectionDivider
        self.isLoading = isLoading
        self.isNowFilter = isNowFilter
        self.onExploreElsewhere = onExploreElsewhere
        self.suggestedCityName = suggestedCityName
        self.onSwitchToSuggestedCity = onSwitchToSuggestedCity
        self.onSelectExperience = onSelectExperience
        self.onLongPressExperience = onLongPressExperience
        self.onAskSoloExperience = onAskSoloExperience
    }

    /// US-036: When true, the Nearby header is preceded by an inset divider so a
    /// clear visual break separates it from the Routes section above. Set false
    /// when Nearby is rendered standalone (no Routes section present).
    let showsSectionDivider: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // US-036: inset divider + localized "Nearby" header separates this
            // section from Routes above (showsDivider gated by composition).
            SheetSectionSeparator(titleKey: "sheet.section.nearby", showsDivider: showsSectionDivider)

            if experiences.count >= 5 {
                ExperienceSearchBar(text: $searchText)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }

            if isLoading && experiences.isEmpty {
                NearbyRowSkeletonList()
            } else if experiences.isEmpty {
                // US-050: empty Nearby list. Announce on appear so VoiceOver
                // users learn the list is empty rather than thinking the sheet
                // froze; a visible row keeps the state legible to everyone.
                EmptySheetListView(
                    isNowFilter: isNowFilter,
                    onExploreElsewhere: onExploreElsewhere,
                    suggestedCityName: suggestedCityName,
                    onSwitchToSuggestedCity: onSwitchToSuggestedCity
                )
            } else if !filteredExperiences.isEmpty {
                LazyVStack(spacing: 10) {
                    ForEach(filteredExperiences) { exp in
                        // Resolve the live "best now / closing soon" chip state for
                        // EVERY row from the shared clock — not just in Now sort.
                        // The chip is the app's most decision-relevant, perishable
                        // signal; hiding it in the distance/smart/soloScore sorts
                        // meant a traveler browsing by distance couldn't tell a
                        // nearby spot was in its golden hour (or closing in minutes)
                        // without opening it. A nil `minutesLeft` means "not best
                        // now", so the row keeps its plain form.
                        let chipState = BestNowChipState.resolve(for: exp, at: clock.tick)
                        let openNow = chipState.minutesLeft != nil
                        NearbyExperienceRow(
                            experience: exp,
                            isSmartPick: sortMode == .smart && smartPickIds.contains(exp.id),
                            distanceMeters: distance(to: exp),
                            isOpenNow: openNow,
                            bestNowChipState: openNow ? chipState : nil,
                            onTap: { onSelectExperience(exp) },
                            onLongPress: onLongPressExperience.map { handler in { handler(exp) } },
                            onAskSolo: onAskSoloExperience.map { handler in { handler(exp) } }
                        )
                    }
                }
                .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: sortMode)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
            } else if !searchText.isEmpty {
                SearchEmptyView(query: searchText)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }
        }
        .padding(.top, 8)
    }

    private var filteredExperiences: [Experience] {
        let sorted = sortedExperiences
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return sorted }
        return sorted.filter { exp in
            exp.shortName.lowercased().contains(query)
            || exp.title.lowercased().contains(query)
            || exp.oneLiner.lowercased().contains(query)
            || exp.category.rawValue.lowercased().contains(query)
        }
    }

    private var sortedExperiences: [Experience] {
        switch sortMode {
        case .smart:
            let smartSet = Set(smartPickIds)
            let picks = smartPickIds.compactMap { id in experiences.first { $0.id == id } }
            let rest = experiences
                .filter { !smartSet.contains($0.id) }
                .sorted { distance(to: $0) ?? .infinity < distance(to: $1) ?? .infinity }
            return picks + rest
        case .distance:
            return experiences.sorted { distance(to: $0) ?? .infinity < distance(to: $1) ?? .infinity }
        case .soloScore:
            return experiences.sorted { $0.soloScore.overall > $1.soloScore.overall }
        case .now:
            let now = clock.tick
            return experiences.sorted { lhs, rhs in
                let lhsNow = isOpenNow(lhs, at: now)
                let rhsNow = isOpenNow(rhs, at: now)
                if lhsNow != rhsNow { return lhsNow }
                return distance(to: lhs) ?? .infinity < distance(to: rhs) ?? .infinity
            }
        }
    }

    /// True when `experience` is genuinely at its best at `date`.
    ///
    /// Uses `minutesLeftInBestWindow` (the same source the visible chip reads)
    /// rather than a bare "current hour ∈ bestTimes" check, so weekday- and
    /// season-scoped windows and midnight-wrapping windows are honored — a
    /// Saturday-only sunset window no longer floats to the top of the Now sort
    /// (or shows a "Best now" chip) on a weekday.
    private func isOpenNow(_ experience: Experience, at date: Date) -> Bool {
        experience.minutesLeftInBestWindow(at: date) != nil
    }

    private func distance(to experience: Experience) -> Double? {
        guard let ref = referenceCoordinate,
              let coord = experience.coordinate else { return nil }
        let from = CLLocation(latitude: ref.latitude, longitude: ref.longitude)
        let to = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        return from.distance(from: to)
    }
}

// MARK: - NearbyRowSkeletonList

struct NearbyRowSkeletonList: View {
    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                NearbyRowSkeleton()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(NSLocalizedString("skeleton.loading", comment: "Loading")))
        .accessibilityAddTraits(.updatesFrequently)
        .allowsHitTesting(false)
    }
}

private struct NearbyRowSkeleton: View {
    @State private var shimmerPhase: CGFloat = -1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(shimmerFill)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerFill)
                    .frame(height: 14)
                    .frame(maxWidth: .infinity)
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerFill)
                    .frame(width: 120, height: 10)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .systemGray6))
        )
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.0
            }
        }
    }

    private var shimmerFill: some ShapeStyle {
        let base = Color(uiColor: .systemGray5)
        let highlight = Color.white.opacity(0.6)
        let center = (shimmerPhase + 1) / 2
        return LinearGradient(
            stops: [
                .init(color: base, location: max(0, center - 0.3)),
                .init(color: highlight, location: center),
                .init(color: base, location: min(1, center + 0.3)),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - EmptySheetListView

/// US-050: Empty-state row for the BottomInfoSheet's Nearby list. When no
/// experiences are visible we show a localized message AND post a VoiceOver
/// announcement on appear, so VoiceOver users know the list is genuinely empty
/// instead of assuming the UI froze.
struct EmptySheetListView: View {
    /// Localized text used both for the on-screen label and the VoiceOver
    /// announcement. Exposed via the same key the test asserts on.
    static let announcementKey = "a11y.empty.nearby"

    var isNowFilter: Bool = false

    /// When non-nil, renders an 'Explore another area' CTA that fires this
    /// callback on tap (after a selection haptic). Omit in previews / tests
    /// where no map action is wired up.
    var onExploreElsewhere: (() -> Void)? = nil

    /// When non-nil, shows a "Try [city]" CTA so users in empty cities can
    /// one-tap jump to a city that has seed data.
    var suggestedCityName: String? = nil
    var onSwitchToSuggestedCity: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var localizedEmptyText: String {
        if isNowFilter && Self.isLateNight {
            return NSLocalizedString("empty.now.latenight", comment: "Now filter empty at night")
        }
        return NSLocalizedString(Self.announcementKey, comment: "Announced when the Nearby list is empty")
    }

    private var hasSuggestedCity: Bool {
        suggestedCityName != nil && onSwitchToSuggestedCity != nil
    }

    static var isLateNight: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 23 || hour < 6
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                if isNowFilter && Self.isLateNight {
                    Image(systemName: "moon.zzz.fill")
                        .font(.title2)
                        .foregroundStyle(CT.sunGold)
                        .scaleEffect(breathing ? 1.08 : 1.0)
                        .opacity(breathing ? 0.7 : 1.0)
                    Text(NSLocalizedString("empty.now.latenight.headline", comment: "Late night Now empty headline"))
                        .font(.headline)
                        .foregroundStyle(CT.fgPrimary)
                        .multilineTextAlignment(.center)
                    Text(NSLocalizedString("empty.now.latenight.subtitle", comment: "Late night Now empty subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(CT.fgMuted)
                        .multilineTextAlignment(.center)
                } else if isNowFilter {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .scaleEffect(breathing ? 1.08 : 1.0)
                        .opacity(breathing ? 0.7 : 1.0)
                    Text(NSLocalizedString("empty.now.headline", comment: "Now filter empty headline"))
                        .font(.headline)
                        .foregroundStyle(CT.fgPrimary)
                        .multilineTextAlignment(.center)
                    Text(NSLocalizedString("empty.now.subtitle", comment: "Now filter empty subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(CT.fgMuted)
                        .multilineTextAlignment(.center)
                } else {
                    Image(systemName: "mappin.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .scaleEffect(breathing ? 1.08 : 1.0)
                        .opacity(breathing ? 0.7 : 1.0)
                    Text(NSLocalizedString("empty.nearby.headline", comment: "Empty Nearby headline"))
                        .font(.headline)
                        .foregroundStyle(CT.fgPrimary)
                        .multilineTextAlignment(.center)
                    if hasSuggestedCity {
                        Text(NSLocalizedString("empty.nearby.subtitle.nocity", comment: "Empty Nearby subtitle when city has no data"))
                            .font(.subheadline)
                            .foregroundStyle(CT.fgMuted)
                            .multilineTextAlignment(.center)
                    } else {
                        Text(NSLocalizedString("empty.nearby.subtitle", comment: "Empty Nearby supporting subline"))
                            .font(.subheadline)
                            .foregroundStyle(CT.fgMuted)
                            .multilineTextAlignment(.center)
                    }
                }
            }

            VStack(spacing: 10) {
                if let cityName = suggestedCityName, let switchCity = onSwitchToSuggestedCity {
                    Button {
                        #if canImport(UIKit)
                        Haptics.impact(.medium)
                        #endif
                        switchCity()
                    } label: {
                        Label(
                            String(format: NSLocalizedString("empty.nearby.cta.city", comment: "CTA to switch to a city with data"), cityName),
                            systemImage: "airplane.departure"
                        )
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 11)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CT.accent)
                    .accessibilityHint(Text(String(format: NSLocalizedString("empty.nearby.a11y.city.hint", comment: "Accessibility hint for city switch CTA"), cityName)))
                }

                if let explore = onExploreElsewhere {
                    Button {
                        #if canImport(UIKit)
                        Haptics.selection()
                        #endif
                        explore()
                    } label: {
                        Label(
                            NSLocalizedString("empty.nearby.cta", comment: "CTA to zoom map out when Nearby list is empty"),
                            systemImage: "arrow.up.left.and.arrow.down.right"
                        )
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(Text(NSLocalizedString("empty.nearby.cta", comment: "CTA to zoom map out when Nearby list is empty")))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .onAppear {
            #if canImport(UIKit)
            UIAccessibility.post(notification: .announcement, argument: localizedEmptyText)
            #endif
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced {
                withAnimation(.default) { breathing = false }
            } else {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
        }
    }
}

// MARK: - Experience search bar

private struct ExperienceSearchBar: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField(
                NSLocalizedString("search.experiences.placeholder", comment: "Search placeholder"),
                text: $text
            )
            .font(.subheadline)
            .focused($isFocused)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(Text(NSLocalizedString("search.clear", comment: "Clear search")))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
        )
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Search empty result

private struct SearchEmptyView: View {
    let query: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(String(
                format: NSLocalizedString("search.empty.title", comment: "No results for query"),
                query
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}
