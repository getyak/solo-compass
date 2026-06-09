import SwiftUI
import CoreLocation

enum FavSort { case recent, nearest }

/// List of favorited experiences sorted by most-recently-added.
/// Presented as a sheet from SettingsView or via the map settings button.
public struct FavoritesListView: View {
    @Environment(ExperienceService.self) private var experienceService
    @Environment(UserPreferences.self) private var preferences
    @Environment(LocationService.self) private var locationService
    @Environment(BestNowClock.self) private var bestNowClock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn
    /// Tapping a favorite jumps straight to the detail sheet.
    let onSelectExperience: (Experience) -> Void
    /// Long-pressing a favorite floats the quick preview card instead.
    var onLongPressExperience: ((Experience) -> Void)? = nil
    var onExplore: (() -> Void)? = nil

    @State private var lastUnfavorited: (id: String, title: String, date: Date)?
    @State private var undoDismissTask: Task<Void, Never>?
    @State private var animatePulse = false
    @State private var undoProgress: CGFloat = 1
    @State private var undoDragOffset: CGFloat = 0
    @State private var undoDragCrossedThreshold = false
    @State private var searchText = ""
    @State private var sortMode: FavSort = .recent
    @State private var showSwipeHint = false
    @State private var hintDismissTask: Task<Void, Never>?
    @AppStorage("favorites.swipeHintSeen") private var swipeHintSeen = false
    @State private var ringDidCelebrate = false
    @State private var showRemainingOnly = false
    @State private var prioritizeGoodNow = false
    @State private var celebrationTrigger = 0
    @State private var searchAnnounceTask: Task<Void, Never>?
    @State private var justCompletedId: String?
    @State private var completionClearTask: Task<Void, Never>?

    private var undoDismissSeconds: Double { voiceOverOn ? 12 : 4 }

    private enum Proximity {
        case near, mid, far

        static func from(meters: CLLocationDistance) -> Proximity {
            if meters <= 1000 { return .near }
            if meters <= 5000 { return .mid }
            return .far
        }

        var color: Color {
            switch self {
            case .near: return .green
            case .mid: return .orange
            case .far: return Color(.tertiaryLabel)
            }
        }

        var a11yWord: String {
            switch self {
            case .near: return NSLocalizedString("favorites.proximity.near", comment: "Proximity: walkable")
            case .mid: return NSLocalizedString("favorites.proximity.mid", comment: "Proximity: short ride")
            case .far: return NSLocalizedString("favorites.proximity.far", comment: "Proximity: far away")
            }
        }
    }

    private func distanceMeters(for exp: Experience) -> CLLocationDistance? {
        guard let coord = exp.coordinate, locationService.currentLocation != nil else { return nil }
        let d = locationService.distance(to: coord)
        return d < .greatestFiniteMagnitude ? d : nil
    }

    private func proximity(for exp: Experience) -> Proximity? {
        guard let meters = distanceMeters(for: exp) else { return nil }
        return Proximity.from(meters: meters)
    }
    private var sortedFavorites: [Experience] {
        let ids = preferences.favoritedExperiences
        let experiences = ids.compactMap { experienceService.getExperience(id: $0) }
        let base: [Experience]
        switch sortMode {
        case .recent:
            base = experiences.sorted { lhs, rhs in
                let lDate = preferences.favoritedAt[lhs.id] ?? .distantPast
                let rDate = preferences.favoritedAt[rhs.id] ?? .distantPast
                return lDate > rDate
            }
        case .nearest:
            base = experiences.sorted { lhs, rhs in
                let lDist = distanceMeters(for: lhs) ?? .greatestFiniteMagnitude
                let rDist = distanceMeters(for: rhs) ?? .greatestFiniteMagnitude
                if lDist != rDist { return lDist < rDist }
                let lDate = preferences.favoritedAt[lhs.id] ?? .distantPast
                let rDate = preferences.favoritedAt[rhs.id] ?? .distantPast
                return lDate > rDate
            }
        }
        guard prioritizeGoodNow else { return base }
        let good = base.filter { !preferences.completedExperiences.contains($0.id) && $0.isBestNow() && !$0.bestTimes.isEmpty }
        let rest = base.filter { exp in !good.contains(where: { $0.id == exp.id }) }
        return good + rest
    }

    private static let kilometersFormatter: MeasurementFormatter = {
        let f = MeasurementFormatter()
        f.unitOptions = .providedUnit
        f.numberFormatter.maximumFractionDigits = 1
        f.numberFormatter.minimumFractionDigits = 1
        return f
    }()

    private static let walkThresholdMeters = 1500.0
    private static let walkMetersPerMin = 80.0

    private func distanceInfo(for experience: Experience) -> (text: String, symbol: String)? {
        guard let userLocation = LocationService.shared.currentLocation,
              let coord = experience.coordinate else { return nil }
        let meters = userLocation.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
        if meters < Self.walkThresholdMeters {
            let minutes = Int((meters / Self.walkMetersPerMin).rounded(.up))
            let label: String
            if minutes < 1 {
                label = NSLocalizedString("card.distance.walkSub1", comment: "Distance less than 1 min walk")
            } else {
                label = String(format: NSLocalizedString("card.distance.walk", comment: "Distance in walk minutes"), minutes)
            }
            return (label, "figure.walk")
        } else {
            if Locale.current.measurementSystem == .us {
                let mi = (meters / 1000) * 0.621371
                let text = String(format: NSLocalizedString("favorites.distance.mi", comment: "Distance in miles"), mi)
                return (text, "location.fill")
            }
            let measurement = Measurement(value: meters / 1000, unit: UnitLength.kilometers)
            return (Self.kilometersFormatter.string(from: measurement), "location.fill")
        }
    }

    private var filteredFavorites: [Experience] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let afterSearch: [Experience]
        if query.isEmpty {
            afterSearch = sortedFavorites
        } else {
            afterSearch = sortedFavorites.filter {
                $0.title.localizedCaseInsensitiveContains(query) ||
                $0.oneLiner.localizedCaseInsensitiveContains(query)
            }
        }
        guard showRemainingOnly else { return afterSearch }
        return afterSearch.filter { !preferences.completedExperiences.contains($0.id) }
    }

    private var nearbyCount: Int {
        sortedFavorites.filter { proximity(for: $0) == .near }.count
    }

    private var nearestFavorite: Experience? {
        sortedFavorites
            .filter { distanceMeters(for: $0) != nil }
            .min(by: { (distanceMeters(for: $0) ?? .greatestFiniteMagnitude) < (distanceMeters(for: $1) ?? .greatestFiniteMagnitude) })
    }

    private var goodNowCount: Int {
        sortedFavorites.filter { exp in
            guard !exp.bestTimes.isEmpty else { return false }
            return !preferences.completedExperiences.contains(exp.id) && exp.isBestNow()
        }.count
    }

    @ViewBuilder
    private func walkBudgetChipContent(mins: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "figure.walk")
                .accessibilityHidden(true)
            Text(String(format: NSLocalizedString("favorites.nearby.walkBudget", comment: "Walk budget chip: ~Xm on foot"), mins))
        }
        .font(.caption2)
        .foregroundStyle(Color.green)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.green.opacity(0.12), in: Capsule())
        .animation(.easeInOut, value: nearbyWalkMinutesTotal)
        .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
    }

    private var nearbyWalkMinutesTotal: Int? {
        guard locationService.currentLocation != nil else { return nil }
        let total = sortedFavorites
            .filter { proximity(for: $0) == .near }
            .compactMap { distanceMeters(for: $0) }
            .reduce(0) { $0 + Int(($1 / Self.walkMetersPerMin).rounded(.up)) }
        return total > 0 ? total : nil
    }

    private var completedCount: Int {
        sortedFavorites.filter { preferences.completedExperiences.contains($0.id) }.count
    }

    private var momentumLine: String? {
        let favIds = preferences.favoritedExperiences
        let completedFavIds = favIds.filter { preferences.completedExperiences.contains($0) }
        let cutoff = Date().addingTimeInterval(-86_400)
        let recentlyDone = completedFavIds
            .compactMap { id -> (id: String, date: Date)? in
                guard let date = preferences.visitHistory[id], date >= cutoff else { return nil }
                return (id: id, date: date)
            }
            .max(by: { $0.date < $1.date })

        if let done = recentlyDone,
           let exp = experienceService.getExperience(id: done.id) {
            return String(
                format: NSLocalizedString("favorites.momentum.justDid", comment: "Momentum: recently completed favorite"),
                exp.title
            )
        }

        if let nearest = nearestFavorite {
            return String(
                format: NSLocalizedString("favorites.momentum.closest", comment: "Momentum: nearest favorite nudge"),
                nearest.title
            )
        }

        return nil
    }

    public var body: some View {
        NavigationStack {
            Group {
                if sortedFavorites.isEmpty && lastUnfavorited == nil {
                    EmptyFavoritesView(onExplore: onExplore)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                } else if filteredFavorites.isEmpty && showRemainingOnly && searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    AllRemainingDoneView(onShowAll: {
                        Haptics.selection()
                        withAnimation(reduceMotion ? nil : .easeInOut) { showRemainingOnly = false }
                    })
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
                } else if filteredFavorites.isEmpty {
                    NoSearchResultsView(
                        query: searchText,
                        onClear: { searchText = "" },
                        goodNowCount: goodNowCount,
                        onShowGoodNow: goodNowCount > 0 ? {
                            searchText = ""
                            prioritizeGoodNow = true
                        } : nil
                    )
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
                } else {
                    VStack(spacing: 0) {
                        if sortedFavorites.count > 0 {
                            FavoritesJourneyHeader(
                                total: sortedFavorites.count,
                                completed: completedCount,
                                nearbyCount: nearbyCount,
                                onTapNearby: locationService.currentLocation != nil && nearbyCount > 0 ? {
                                    Haptics.selection()
                                    withAnimation(reduceMotion ? nil : .easeInOut) { sortMode = .nearest }
                                } : nil,
                                momentumLine: momentumLine,
                                closestTitle: locationService.currentLocation != nil && nearbyCount == 0 ? nearestFavorite?.title : nil,
                                closestDistanceText: locationService.currentLocation != nil && nearbyCount == 0 ? nearestFavorite.flatMap { distanceInfo(for: $0)?.text } : nil,
                                closestProximityColor: locationService.currentLocation != nil && nearbyCount == 0 ? nearestFavorite.flatMap { proximity(for: $0)?.color } : nil,
                                onTapClosest: locationService.currentLocation != nil && nearbyCount == 0 && nearestFavorite != nil ? {
                                    Haptics.selection()
                                    withAnimation(reduceMotion ? nil : .easeInOut) { sortMode = .nearest }
                                } : nil,
                                goodNowCount: goodNowCount,
                                onTapGoodNow: goodNowCount > 0 ? {
                                    Haptics.selection()
                                    withAnimation(reduceMotion ? nil : .easeInOut) { prioritizeGoodNow = true }
                                } : nil
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                            // Footer reflects the active search filter when one is present.
                            let countLabel: String = {
                                let query = searchText.trimmingCharacters(in: .whitespaces)
                                if query.isEmpty {
                                    return String(format: NSLocalizedString("favorites.count", comment: "N saved"), sortedFavorites.count)
                                } else {
                                    return String(format: NSLocalizedString("favorites.count.matching", comment: "M of N matching"), filteredFavorites.count, sortedFavorites.count)
                                }
                            }()
                            let showNearbyChip = locationService.currentLocation != nil
                                && nearbyCount > 0
                                && searchText.trimmingCharacters(in: .whitespaces).isEmpty
                            let showCompletedChip = completedCount > 0
                                && searchText.trimmingCharacters(in: .whitespaces).isEmpty
                            HStack(spacing: 8) {
                                Text(countLabel)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .animation(.easeInOut, value: filteredFavorites.count)
                                    .contentTransition(.numericText())
                                Spacer()
                                if showCompletedChip {
                                    let isAllDone = completedCount == sortedFavorites.count
                                    let ringView = CompletionRing(
                                        done: completedCount,
                                        total: sortedFavorites.count,
                                        didCelebrate: $ringDidCelebrate
                                    )
                                    if isAllDone {
                                        ringView
                                            .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
                                    } else {
                                        Button {
                                            Haptics.selection()
                                            withAnimation(reduceMotion ? nil : .easeInOut) {
                                                showRemainingOnly.toggle()
                                            }
                                        } label: {
                                            ringView
                                                .padding(.horizontal, showRemainingOnly ? 6 : 0)
                                                .padding(.vertical, showRemainingOnly ? 4 : 0)
                                                .background(
                                                    showRemainingOnly
                                                        ? Color.green.opacity(0.12)
                                                        : Color.clear,
                                                    in: Capsule()
                                                )
                                                .animation(reduceMotion ? nil : .easeInOut, value: showRemainingOnly)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(
                                            showRemainingOnly
                                                ? NSLocalizedString("favorites.remaining.active.a11y", comment: "Completion ring active filter accessibility label")
                                                : NSLocalizedString("favorites.remaining.show.a11y", comment: "Completion ring show remaining accessibility label")
                                        )
                                        .accessibilityHint(NSLocalizedString("favorites.remaining.hint", comment: "Completion ring accessibility hint"))
                                        .accessibilityAddTraits(.isButton)
                                        .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
                                    }
                                }
                                if showNearbyChip {
                                    Button {
                                        Haptics.selection()
                                        withAnimation(reduceMotion ? nil : .easeInOut) {
                                            sortMode = .nearest
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(Color.green)
                                                .frame(width: 7, height: 7)
                                                .accessibilityHidden(true)
                                            Text(String(format: NSLocalizedString("favorites.nearby.count", comment: "N nearby chip"), nearbyCount))
                                                .font(.caption2)
                                                .foregroundStyle(Color.green)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.green.opacity(0.12), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(String(format: NSLocalizedString("favorites.nearby.count.a11y", comment: "N nearby chip accessibility label"), nearbyCount))
                                    .accessibilityHint(NSLocalizedString("favorites.nearby.hint", comment: "Nearby chip sorts by distance"))
                                    .accessibilityAddTraits(.isButton)
                                    .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))

                                    if let mins = nearbyWalkMinutesTotal {
                                        if let nearest = nearestFavorite,
                                           let coord = nearest.coordinate,
                                           let app = NavigationLauncher.availableApps().first {
                                            Button {
                                                Haptics.impact(.light)
                                                NavigationLauncher.open(app: app, coordinate: coord, name: nearest.title)
                                            } label: {
                                                walkBudgetChipContent(mins: mins)
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel(String(format: NSLocalizedString("favorites.nearby.walkBudget.start.a11y", comment: "Walk to nearest favorite button accessibility label"), nearest.title, mins))
                                            .accessibilityAddTraits(.isButton)
                                        } else {
                                            walkBudgetChipContent(mins: mins)
                                                .accessibilityLabel(String(format: NSLocalizedString("favorites.nearby.walkBudget.a11y", comment: "Walk budget chip accessibility label"), mins))
                                        }
                                    }

                                    let availableApps = NavigationLauncher.availableApps()
                                    if let nearest = nearestFavorite,
                                       let app = availableApps.first {
                                        Button {
                                            Haptics.impact(.light)
                                            guard let coord = nearest.coordinate else { return }
                                            NavigationLauncher.open(app: app, coordinate: coord, name: nearest.title)
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                                    .accessibilityHidden(true)
                                                Text(NSLocalizedString("favorites.nearby.go", comment: "Go button: launch directions to nearest favorite"))
                                            }
                                            .font(.caption2)
                                            .foregroundStyle(Color.green)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Color.green.opacity(0.12), in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(String(format: NSLocalizedString("favorites.nearby.go.a11y", comment: "Directions to nearest favorite accessibility label"), nearest.title))
                                        .accessibilityHint(NSLocalizedString("favorites.nearby.go.hint", comment: "Go button accessibility hint"))
                                        .accessibilityAddTraits(.isButton)
                                        .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .animation(reduceMotion ? nil : .easeInOut, value: showNearbyChip)
                            .animation(reduceMotion ? nil : .easeInOut, value: showCompletedChip)
                            .animation(.easeInOut, value: nearbyCount)
                        }

                        List {
                            if locationService.currentLocation != nil {
                                Section {
                                    Picker(NSLocalizedString("favorites.sort.label", comment: "Sort favorites"),
                                           selection: $sortMode.animation(reduceMotion ? nil : .easeInOut)) {
                                        Text(NSLocalizedString("favorites.sort.recent", comment: "Sort by recency"))
                                            .tag(FavSort.recent)
                                        Text(NSLocalizedString("favorites.sort.nearest", comment: "Sort by distance"))
                                            .tag(FavSort.nearest)
                                    }
                                    .pickerStyle(.segmented)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                }
                            }
                            ForEach(filteredFavorites) { exp in
                                favoriteRow(exp)
                            }
                        }
                        .listStyle(.plain)
                        .animation(.easeInOut, value: filteredFavorites.count)
                        .animation(reduceMotion ? nil : .easeInOut, value: sortMode)
                        .overlay(alignment: .top) {
                            if showSwipeHint {
                                SwipeHintCapsuleView()
                                    .transition(.move(edge: .top).combined(with: .opacity))
                                    .padding(.top, 8)
                            }
                        }
                        .onAppear {
                            guard !swipeHintSeen, !sortedFavorites.isEmpty else { return }
                            withAnimation(.easeOut) { showSwipeHint = true }
                            swipeHintSeen = true
                            hintDismissTask = Task {
                                try? await Task.sleep(for: .seconds(2.5))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    withAnimation(.easeIn) { showSwipeHint = false }
                                }
                            }
                        }
                        .onDisappear {
                            hintDismissTask?.cancel()
                            completionClearTask?.cancel()
                            justCompletedId = nil
                        }
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut, value: sortedFavorites.isEmpty)
            .animation(.easeInOut, value: filteredFavorites.isEmpty)
            .navigationTitle(NSLocalizedString("favorites.title", comment: "Favorites list title"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(NSLocalizedString("favorites.search.prompt", comment: "Search favorites"))
            )
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .overlay(alignment: .center) {
            CompletionCelebrationView(trigger: celebrationTrigger)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            if lastUnfavorited != nil {
                undoBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 16)
            }
        }
        .animation(.easeInOut, value: lastUnfavorited != nil)
        .onChange(of: lastUnfavorited == nil) { _, isNil in
            if isNil { undoDragOffset = 0 }
        }
        .onChange(of: completedCount) { _, _ in
            let allDone = completedCount == sortedFavorites.count
            let remainingCount = sortedFavorites.filter { !preferences.completedExperiences.contains($0.id) }.count
            if showRemainingOnly && (allDone || remainingCount == 0) {
                withAnimation(reduceMotion ? nil : .easeInOut) { showRemainingOnly = false }
            }
        }
        .onChange(of: goodNowCount) { _, newCount in
            if newCount == 0 && prioritizeGoodNow {
                withAnimation(reduceMotion ? nil : .easeInOut) { prioritizeGoodNow = false }
            }
        }
        .onChange(of: searchText) { _, newValue in
            let query = newValue.trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else {
                searchAnnounceTask?.cancel()
                searchAnnounceTask = nil
                return
            }
            searchAnnounceTask?.cancel()
            searchAnnounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                guard UIAccessibility.isVoiceOverRunning else { return }
                let count = filteredFavorites.count
                let message: String
                if count > 0 {
                    message = String(format: NSLocalizedString("favorites.search.resultCount.a11y", comment: "VoiceOver search result count in favorites: %d matching favorites"), count)
                } else {
                    message = String(format: NSLocalizedString("favorites.search.noResults.a11y", comment: "VoiceOver no results announcement in favorites: No favorites match <query>"), query)
                }
                UIAccessibility.post(notification: .announcement, argument: message)
            }
        }
    }
}

private struct FavoritesJourneyHeader: View {
    let total: Int
    let completed: Int
    let nearbyCount: Int
    var onTapNearby: (() -> Void)? = nil
    var momentumLine: String? = nil
    var closestTitle: String? = nil
    var closestDistanceText: String? = nil
    var closestProximityColor: Color? = nil
    var onTapClosest: (() -> Void)? = nil
    var goodNowCount: Int = 0
    var onTapGoodNow: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 5 {
            return NSLocalizedString("favorites.greeting.night", comment: "Late-night greeting in favorites header")
        } else if hour < 12 {
            return NSLocalizedString("favorites.greeting.morning", comment: "Morning greeting in favorites header")
        } else if hour < 17 {
            return NSLocalizedString("favorites.greeting.afternoon", comment: "Afternoon greeting in favorites header")
        } else {
            return NSLocalizedString("favorites.greeting.evening", comment: "Evening greeting in favorites header")
        }
    }

    private var journeySummary: String {
        if completed == total {
            return NSLocalizedString("favorites.journey.allDone", comment: "All favorites explored")
        } else if completed > 0 {
            return String(format: NSLocalizedString("favorites.journey.progress", comment: "N of M explored"), completed, total)
        } else {
            return String(format: NSLocalizedString("favorites.journey.awaiting", comment: "N places waiting"), total)
        }
    }

    @ViewBuilder
    private var goodNowNudge: some View {
        if goodNowCount > 0 {
            let label = String(format: NSLocalizedString("favorites.journey.goodNow", comment: "N favorites great right now nudge"), goodNowCount)
            let pillContent = HStack(spacing: 4) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.caption2)
                    .foregroundStyle(Color.green)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(Color.green)
                if onTapGoodNow != nil {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.green)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.12), in: Capsule())
            .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))

            if let onTap = onTapGoodNow {
                Button {
                    onTap()
                } label: {
                    pillContent
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(format: NSLocalizedString("favorites.journey.goodNow.a11y", comment: "Good now nudge button accessibility label"), goodNowCount))
                .accessibilityHint(NSLocalizedString("favorites.journey.goodNow.hint", comment: "Good now nudge sorts those favorites to top"))
                .accessibilityAddTraits(.isButton)
            } else {
                pillContent
                    .accessibilityLabel(String(format: NSLocalizedString("favorites.journey.goodNow.a11y", comment: "Good now nudge accessibility label"), goodNowCount))
            }
        }
    }

    @ViewBuilder
    private var nearbyNudge: some View {
        if nearbyCount > 0 {
            let label = String(format: NSLocalizedString("favorites.journey.nearbyNow", comment: "N favorites within walking distance nudge"), nearbyCount)
            let nudgeContent = HStack(spacing: 4) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(Color.green)
                if onTapNearby != nil {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.green)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, onTapNearby != nil ? 8 : 0)
            .padding(.vertical, onTapNearby != nil ? 4 : 0)
            .background(onTapNearby != nil ? Color.green.opacity(0.12) : Color.clear, in: Capsule())
            .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))

            if let onTap = onTapNearby {
                Button {
                    onTap()
                } label: {
                    nudgeContent
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(format: NSLocalizedString("favorites.journey.nearbyNow.a11y", comment: "Nearby nudge button accessibility label"), nearbyCount))
                .accessibilityHint(NSLocalizedString("favorites.journey.nearbyNow.hint", comment: "Nearby nudge button sorts by distance hint"))
            } else {
                nudgeContent
                    .accessibilityLabel(label)
            }
        }
    }

    @ViewBuilder
    private var closestNudge: some View {
        if nearbyCount == 0,
           let title = closestTitle,
           let distanceText = closestDistanceText {
            let dotColor = closestProximityColor ?? Color(.tertiaryLabel)
            let pillContent = HStack(spacing: 4) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(dotColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(dotColor)
                    .accessibilityHidden(true)
                Text(distanceText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(dotColor)
                if onTapClosest != nil {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(dotColor)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, onTapClosest != nil ? 8 : 0)
            .padding(.vertical, onTapClosest != nil ? 4 : 0)
            .background(onTapClosest != nil ? dotColor.opacity(0.12) : Color.clear, in: Capsule())
            .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))

            let a11yLabel = String(
                format: NSLocalizedString("favorites.journey.closest.a11y", comment: "Closest nudge accessibility label"),
                title,
                distanceText
            )

            if let onTap = onTapClosest {
                Button {
                    onTap()
                } label: {
                    pillContent
                }
                .buttonStyle(.plain)
                .accessibilityLabel(a11yLabel)
                .accessibilityHint(NSLocalizedString("favorites.journey.closest.hint", comment: "Closest nudge sorts by distance hint"))
            } else {
                pillContent
                    .accessibilityLabel(a11yLabel)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(greeting)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(journeySummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.easeInOut, value: completed)
                .animation(.easeInOut, value: total)
            if total > 0 {
                JourneyProgressBar(completed: completed, total: total)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
            }
            goodNowNudge
                .animation(reduceMotion ? nil : .easeInOut, value: goodNowCount)
            nearbyNudge
                .animation(reduceMotion ? nil : .easeInOut, value: nearbyCount)
            closestNudge
                .animation(reduceMotion ? nil : .easeInOut, value: nearbyCount)
            if let line = momentumLine {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(.easeInOut, value: line)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : (reduceMotion ? 0 : 6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : (reduceMotion ? 0 : 6))
        .accessibilityElement(children: .combine)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.3)) { appeared = true }
            }
        }
    }
}

private struct JourneyProgressBar: View {
    let completed: Int
    let total: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedFraction: CGFloat = 0
    @State private var didCompletionSweep = false
    @State private var sweepPhase: CGFloat = -1
    @State private var fillScaleY: CGFloat = 1
    @State private var didHalfwayPulse = false
    @State private var tickPulse = false
    @State private var lastMilestone: Int = 0
    @State private var glowOpacity: CGFloat = 0

    private var targetFraction: CGFloat {
        total > 0 ? CGFloat(completed) / CGFloat(total) : 0
    }

    private var isAllDone: Bool { total > 0 && completed == total }
    private var isPastHalfway: Bool { total > 0 && Double(completed) / Double(total) >= 0.5 }

    private func firePulse() {
        guard !didHalfwayPulse && !isAllDone else { return }
        didHalfwayPulse = true
        Haptics.impact(.soft)
        UIAccessibility.post(
            notification: .announcement,
            argument: String(format: NSLocalizedString("favorites.journey.halfway", comment: "VoiceOver halfway milestone announcement"), completed, total)
        )
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.18, dampingFraction: 0.45)) {
            fillScaleY = 1.18
        }
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
            tickPulse = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.6)) {
                fillScaleY = 1
            }
            tickPulse = false
        }
    }

    private func currentMilestone() -> Int {
        Int(targetFraction * 4)
    }

    private func handleMilestoneCheck() {
        let newMilestone = currentMilestone()
        guard newMilestone > lastMilestone, completed < total else { return }
        lastMilestone = newMilestone
        Haptics.impact(.light)
        let pct = newMilestone * 25
        let announcement = String(
            format: NSLocalizedString("favorites.journey.milestone.a11y", comment: "VoiceOver milestone announcement in journey progress bar"),
            pct
        )
        UIAccessibility.post(notification: .announcement, argument: announcement)
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.15)) { glowOpacity = 0.6 }
        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            withAnimation(.easeIn(duration: 0.35)) { glowOpacity = 0 }
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.green.opacity(0.15))
                    .frame(height: 4)
                if total >= 2 {
                    Capsule()
                        .fill(
                            isPastHalfway
                                ? Color.green
                                : Color.green.opacity(0.25)
                        )
                        .frame(width: 2, height: 8)
                        .offset(x: geo.size.width * 0.5 - 1)
                        .frame(height: 4, alignment: .center)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: isPastHalfway)
                        .scaleEffect(tickPulse ? 1.6 : 1.0)
                        .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.5), value: tickPulse)
                        .accessibilityHidden(true)
                }
                Capsule()
                    .fill(isAllDone ? Color.green : Color.green.opacity(0.75))
                    .frame(width: geo.size.width * animatedFraction, height: 4)
                    .scaleEffect(x: 1, y: fillScaleY, anchor: .center)
                    .shadow(
                        color: isAllDone ? Color.green.opacity(0.4) : Color.clear,
                        radius: 3
                    )
                    .overlay(alignment: .leading) {
                        if isAllDone && !reduceMotion {
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .white.opacity(0.6), location: 0.5),
                                    .init(color: .clear, location: 1),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: geo.size.width * 0.4, height: 4)
                            .clipShape(Capsule())
                            .offset(x: geo.size.width * sweepPhase)
                            .allowsHitTesting(false)
                        }
                    }
                    .clipShape(Capsule())
                if glowOpacity > 0 {
                    Capsule()
                        .fill(Color.green.opacity(glowOpacity))
                        .frame(width: geo.size.width * animatedFraction, height: 4)
                        .blur(radius: 3)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: 4)
        .onAppear {
            lastMilestone = currentMilestone()
            if reduceMotion {
                animatedFraction = targetFraction
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    animatedFraction = targetFraction
                }
            }
            if isAllDone && !reduceMotion {
                fireSweep(width: 0)
            }
        }
        .onChange(of: completed) { _, _ in
            if reduceMotion {
                animatedFraction = targetFraction
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    animatedFraction = targetFraction
                }
            }
            if !isAllDone {
                didCompletionSweep = false
            }
            if isAllDone && !reduceMotion {
                fireSweep(width: 0)
            }
            if isPastHalfway {
                firePulse()
            } else {
                didHalfwayPulse = false
            }
            handleMilestoneCheck()
        }
        .onChange(of: total) { _, _ in
            if reduceMotion {
                animatedFraction = targetFraction
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    animatedFraction = targetFraction
                }
            }
        }
    }

    private func fireSweep(width: CGFloat) {
        guard !didCompletionSweep else { return }
        didCompletionSweep = true
        sweepPhase = -1
        withAnimation(.easeInOut(duration: 0.7).delay(0.15)) {
            sweepPhase = 1.4
        }
        withAnimation(.spring(response: 0.18, dampingFraction: 0.45).delay(0.1)) {
            fillScaleY = 1.25
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.6)) {
                fillScaleY = 1
            }
        }
    }
}

private struct CompletionRing: View {
    let done: Int
    let total: Int
    @Binding var didCelebrate: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedFraction: CGFloat = 0
    @State private var bloomScale: CGFloat = 1
    @State private var celebrationBurst = 0

    private var isAllDone: Bool { total > 0 && done == total }
    private var fraction: CGFloat { total > 0 ? CGFloat(done) / CGFloat(total) : 0 }
    private var pctLabel: String { String(format: "%.0f%%", fraction * 100) }
    private var a11yLabel: String {
        isAllDone
            ? NSLocalizedString("favorites.completed.allDone.a11y", comment: "All favorites completed accessibility label")
            : String(format: NSLocalizedString("favorites.completed.count.a11y", comment: "N of M done chip accessibility label"), done, total)
    }

    var body: some View {
        ZStack {
            HeartBurstView(trigger: celebrationBurst)
            Circle()
                .stroke(Color.green.opacity(0.15), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: animatedFraction)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if isAllDone {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.green)
                    .scaleEffect(bloomScale)
            } else {
                Text(pctLabel)
                    .font(.system(size: 7, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.green)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .easeInOut, value: done)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityLabel(a11yLabel)
        .accessibilityValue(pctLabel)
        .onAppear {
            let target = fraction
            if reduceMotion {
                animatedFraction = target
            } else {
                withAnimation(.easeInOut(duration: 0.5)) { animatedFraction = target }
            }
            if isAllDone && !didCelebrate {
                triggerCelebration()
            }
        }
        .onChange(of: done) { _, _ in
            let target = fraction
            if reduceMotion {
                animatedFraction = target
            } else {
                withAnimation(.easeInOut(duration: 0.5)) { animatedFraction = target }
            }
            if isAllDone && !didCelebrate {
                triggerCelebration()
            }
        }
    }

    private func triggerCelebration() {
        didCelebrate = true
        Haptics.notify(.success)
        celebrationBurst += 1
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.15)) { bloomScale = 1.15 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeIn(duration: 0.15)) { bloomScale = 1 }
        }
    }
}

private struct EmptyFavoritesView: View {
    var onExplore: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn
    @State private var isBreathing = false
    @State private var tipIndex = 0
    @State private var rotateTask: Task<Void, Never>?

    private var tips: [String] {
        [
            NSLocalizedString("favorites.empty.tip1", comment: "Empty favorites tip 1"),
            NSLocalizedString("favorites.empty.tip2", comment: "Empty favorites tip 2"),
            NSLocalizedString("favorites.empty.tip3", comment: "Empty favorites tip 3"),
            NSLocalizedString("favorites.empty.tip4", comment: "Empty favorites tip 4"),
        ]
    }

    private func advanceTip() {
        tipIndex = (tipIndex + 1) % tips.count
        Haptics.selection()
        UIAccessibility.post(notification: .announcement, argument: tips[tipIndex])
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.pink.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "heart.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.pink.opacity(0.7))
                    .scaleEffect(isBreathing ? 1.08 : 0.94)
                    .opacity(isBreathing ? 1.0 : 0.7)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: isBreathing)
                    .accessibilityHidden(true)
            }
            Text(NSLocalizedString("favorites.empty.title", comment: "No favorites yet"))
                .font(.headline)
            Button {
                advanceTip()
            } label: {
                Text(tips[tipIndex])
                    .id(tipIndex)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 36)
                    .transition(.opacity)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: tipIndex)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tips[tipIndex])
            .accessibilityHint(NSLocalizedString("favorites.empty.tip.hint", comment: "Hint to advance to the next tip"))
            HStack(spacing: 6) {
                ForEach(0..<tips.count, id: \.self) { index in
                    Circle()
                        .fill(index == tipIndex ? Color.primary : Color.primary.opacity(0.2))
                        .frame(width: 6, height: 6)
                        .animation(reduceMotion ? nil : .easeInOut, value: tipIndex)
                }
            }
            .accessibilityHidden(true)
            if let onExplore {
                Button {
                    Haptics.selection()
                    onExplore()
                } label: {
                    Label(NSLocalizedString("favorites.empty.cta", comment: "Explore the map button in empty favorites state"), systemImage: "map")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.top, 4)
            }
        }
        .padding(32)
        .accessibilityElement(children: .combine)
        .onAppear {
            guard !isBreathing, !reduceMotion else { return }
            isBreathing = true
            rotateTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard !voiceOverOn else { return }
                        withAnimation { tipIndex = (tipIndex + 1) % tips.count }
                        UIAccessibility.post(notification: .announcement, argument: tips[tipIndex])
                    }
                }
            }
        }
        .onDisappear {
            rotateTask?.cancel()
        }
    }
}

private struct AllRemainingDoneView: View {
    let onShowAll: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.green)
                .accessibilityHidden(true)
            Text(NSLocalizedString("favorites.remaining.allDone.title", comment: "All remaining favorites done title"))
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(NSLocalizedString("favorites.remaining.allDone.hint", comment: "All remaining favorites done caption"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                onShowAll()
            } label: {
                Label(NSLocalizedString("favorites.remaining.allDone.cta", comment: "Show all favorites button in all-done state"), systemImage: "heart.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .padding(.top, 4)
        }
        .padding(32)
        .scaleEffect(appeared ? 1 : 0.85)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            guard !reduceMotion else {
                appeared = true
                return
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                appeared = true
            }
        }
    }
}

private struct NoSearchResultsView: View {
    let query: String
    let onClear: () -> Void
    var goodNowCount: Int = 0
    var onShowGoodNow: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(String(format: NSLocalizedString("favorites.search.noResults", comment: "No matches for search query"), query))
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(NSLocalizedString("favorites.search.noResults.hint", comment: "Hint to try different word or clear search"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Haptics.selection()
                withAnimation { onClear() }
            } label: {
                Label(NSLocalizedString("favorites.search.clear", comment: "Clear search button"), systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityHint(NSLocalizedString("favorites.search.clear.hint", comment: "Clears the search field and shows all favorites"))
            if goodNowCount > 0, let onShowGoodNow {
                Button {
                    Haptics.selection()
                    withAnimation(reduceMotion ? nil : .easeInOut) {
                        onShowGoodNow()
                    }
                } label: {
                    Label(
                        String(format: NSLocalizedString("favorites.search.goodNow.cta", comment: "Good-now CTA in no-results view: N great right now"), goodNowCount),
                        systemImage: "clock.badge.checkmark"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(String(format: NSLocalizedString("favorites.search.goodNow.cta.a11y", comment: "Good-now CTA accessibility label: N favorites great right now"), goodNowCount))
                .accessibilityHint(NSLocalizedString("favorites.journey.goodNow.hint", comment: "Good now nudge sorts those favorites to the top of the list"))
            }
        }
        .padding(32)
        .scaleEffect(appeared ? 1 : 0.85)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            guard !reduceMotion else {
                appeared = true
                return
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                appeared = true
            }
        }
    }
}

/// Internal (not `private`) so `FavoritesBounceAvailabilityTest` can construct
/// it via `@testable import`. The `.bounce` repeating symbol effect below is
/// gated behind `if #available(iOS 18, *)` because `IndefiniteSymbolEffect`
/// (`.repeating`) is iOS 18+; on iOS 17 the bare label renders instead.
struct SwipeHintCapsuleView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        label
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }

    @ViewBuilder
    private var label: some View {
        let base = Label(
            NSLocalizedString("favorites.swipe.hint", comment: "Swipe left to remove"),
            systemImage: "hand.draw"
        )
        if reduceMotion {
            base
        } else if #available(iOS 18, *) {
            base.symbolEffect(.bounce, options: .repeating.speed(0.6))
        } else {
            base
        }
    }
}

private extension FavoritesListView {

    var undoBar: some View {
        ZStack(alignment: .bottom) {
            Button {
                performUndo()
            } label: {
                HStack {
                    Text(String(format: NSLocalizedString("favorites.undo.named", comment: "Removed named experience undo banner"), lastUnfavorited?.title ?? ""))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Text(NSLocalizedString("action.undo", comment: "Undo action"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !reduceMotion {
                GeometryReader { geo in
                    Capsule()
                        .fill(countdownLineColor)
                        .frame(width: geo.size.width * undoProgress, height: 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 2)
                .padding(.horizontal, 2)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .offset(y: undoDragOffset)
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    undoDragOffset = max(0, gesture.translation.height * 0.85)
                    let overThreshold = gesture.translation.height > 80
                    if overThreshold && !undoDragCrossedThreshold {
                        undoDragCrossedThreshold = true
                        Haptics.selection()
                    } else if !overThreshold && undoDragCrossedThreshold {
                        undoDragCrossedThreshold = false
                    }
                }
                .onEnded { gesture in
                    undoDragCrossedThreshold = false
                    if gesture.translation.height > 80 {
                        Haptics.impact(.soft)
                        withAnimation(.easeOut(duration: 0.2)) { undoDragOffset = 300 }
                        undoDismissTask?.cancel()
                        undoDismissTask = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation(.easeInOut) { lastUnfavorited = nil }
                            undoDragOffset = 0
                        }
                    } else {
                        withAnimation(.spring(response: 0.3)) { undoDragOffset = 0 }
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(String(format: NSLocalizedString("favorites.undo.named", comment: "Removed named experience undo banner"), lastUnfavorited?.title ?? "")))
        .accessibilityHint(Text(NSLocalizedString("favorites.undo.tapHint", comment: "Double tap to restore removed favorite")))
        .accessibilityAction(named: Text(NSLocalizedString("action.undo", comment: "Undo action"))) {
            performUndo()
        }
        .onAppear {
            undoProgress = 1
            undoDragOffset = 0
            if !reduceMotion && !voiceOverOn {
                withAnimation(.linear(duration: undoDismissSeconds)) {
                    undoProgress = 0
                }
            }
        }
    }

    private var countdownLineColor: Color {
        guard !reduceMotion else { return .accentColor }
        if #available(iOS 18, *) {
            return Color.accentColor.mix(with: .orange, by: 1 - undoProgress)
        } else {
            return .accentColor
        }
    }

    private func performUndo() {
        guard let saved = lastUnfavorited else { return }
        Haptics.impact(.light)
        undoDismissTask?.cancel()
        undoDismissTask = nil
        undoProgress = 1
        withAnimation(.easeInOut) {
            preferences.toggleFavorite(saved.id, at: saved.date)
            lastUnfavorited = nil
        }
    }

    private func isGoodNow(_ exp: Experience, at date: Date) -> Bool {
        guard !exp.bestTimes.isEmpty else { return false }
        return exp.isBestNow(at: date)
    }

    @ViewBuilder
    func favoriteRow(_ exp: Experience) -> some View {
        let now = bestNowClock.tick
        let distInfo = distanceInfo(for: exp)
        let prox = proximity(for: exp)
        let isDone = preferences.completedExperiences.contains(exp.id)
        let goodNow = !isDone && isGoodNow(exp, at: now)
        let minutesLeft = goodNow ? exp.minutesLeftInBestWindow(at: now) : nil
        let closingSoon = (minutesLeft ?? .max) <= 45
        let bestHint = (!isDone && !goodNow) ? exp.bestTimeHint() : nil
        Button {
            Haptics.selection()
            onSelectExperience(exp)   // tap → open detail directly
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(exp.category.color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: exp.category.symbol)
                        .font(.body)
                        .foregroundStyle(exp.category.color)
                    if isDone {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.green)
                            .background(Circle().fill(Color.white).padding(2))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .accessibilityHidden(true)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(exp.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(exp.oneLiner)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if let distInfo {
                        HStack(spacing: 3) {
                            if let prox {
                                Circle()
                                    .fill(prox.color)
                                    .frame(width: 7, height: 7)
                                    .accessibilityHidden(true)
                            }
                            Label(distInfo.text, systemImage: distInfo.symbol)
                                .font(.caption2)
                                .monospacedDigit()
                        }
                        .foregroundStyle(.tertiary)
                        .padding(.top, 1)
                    }
                    if goodNow {
                        if closingSoon, let mins = minutesLeft {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.badge.exclamationmark")
                                    .accessibilityHidden(true)
                                Text(String(format: NSLocalizedString("favorites.row.closingSoon", comment: "Closing soon pill in favorites row"), mins))
                            }
                            .font(.caption2)
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                            .padding(.top, 2)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
                            .accessibilityHidden(true)
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.badge.checkmark")
                                    .accessibilityHidden(true)
                                Text(NSLocalizedString("favorites.row.goodNow", comment: "Good time now pill in favorites row"))
                            }
                            .font(.caption2)
                            .foregroundStyle(exp.category.color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(exp.category.color.opacity(0.12), in: Capsule())
                            .padding(.top, 2)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
                            .accessibilityHidden(true)
                        }
                    } else if let hint = bestHint {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .accessibilityHidden(true)
                            Text(String(format: NSLocalizedString("favorites.row.bestAt", comment: "Best at time pill in favorites row"), hint))
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                        .padding(.top, 2)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
                        .accessibilityHidden(true)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .overlay {
                RowCompletionFlourish(isActive: justCompletedId == exp.id)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableRowStyle(reduceMotion: reduceMotion))
        // Long-press floats the quick preview card; the tap opens detail. Inside a
        // List row, a high-priority long-press gesture coexists with the row's
        // tap without being swallowed by scroll or swipe-action recognizers.
        .modifier(LongPressCardModifier(onLongPress: onLongPressExperience.map { handler in { handler(exp) } }))
        .accessibilityAction(named: Text(NSLocalizedString("experience.card.preview.a11y", comment: "Preview action: float the quick preview card"))) {
            onLongPressExperience?(exp)
        }
        .accessibilityLabel({
            let doneWord = isDone ? ", \(NSLocalizedString("favorites.row.done.a11y", comment: "Completed row suffix"))" : ""
            let timingWord: String = {
                if goodNow {
                    if closingSoon, let mins = minutesLeft {
                        return ", \(String(format: NSLocalizedString("favorites.row.closingSoon.a11y", comment: "Closing soon accessibility suffix"), mins))"
                    }
                    return ", \(NSLocalizedString("favorites.row.goodNow.a11y", comment: "Good time now accessibility suffix"))"
                }
                return ""
            }()
            let bestAtWord: String = {
                guard let hint = bestHint else { return "" }
                return ", \(String(format: NSLocalizedString("favorites.row.bestAt.a11y", comment: "Best at time accessibility suffix"), hint))"
            }()
            if let distInfo {
                let awayFmt = NSLocalizedString("favorites.row.distance.a11y", comment: "Distance away accessibility label")
                let distLabel = String(format: awayFmt, distInfo.text)
                if let prox {
                    return Text("\(exp.title), \(exp.oneLiner), \(distLabel), \(prox.a11yWord)\(doneWord)\(timingWord)\(bestAtWord)")
                }
                return Text("\(exp.title), \(exp.oneLiner), \(distLabel)\(doneWord)\(timingWord)\(bestAtWord)")
            }
            return Text("\(exp.title), \(exp.oneLiner)\(doneWord)\(timingWord)\(bestAtWord)")
        }())
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Haptics.notify(.warning)
                let savedDate = preferences.favoritedAt[exp.id] ?? Date()
                let expId = exp.id
                let expTitle = exp.title
                undoProgress = 1
                withAnimation(.easeInOut) {
                    preferences.toggleFavorite(expId)
                }
                lastUnfavorited = (id: expId, title: expTitle, date: savedDate)
                UIAccessibility.post(
                    notification: .announcement,
                    argument: String(format: NSLocalizedString("favorites.undo.announcement", comment: "VoiceOver announcement after unfavoriting"), expTitle)
                )
                undoDismissTask?.cancel()
                let dismissSeconds = undoDismissSeconds
                undoDismissTask = Task {
                    try? await Task.sleep(for: .seconds(dismissSeconds))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        withAnimation(.easeInOut) {
                            lastUnfavorited = nil
                        }
                    }
                }
            } label: {
                Label(NSLocalizedString("action.unfavorite", comment: "Remove from favorites"),
                      systemImage: "heart.slash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                if isDone {
                    Haptics.selection()
                    withAnimation(.easeInOut) {
                        preferences.completedExperiences.remove(exp.id)
                        preferences.visitHistory.removeValue(forKey: exp.id)
                    }
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: NSLocalizedString("favorites.row.markNotVisited.announcement", comment: "VoiceOver announcement after marking as not visited")
                    )
                } else {
                    withAnimation(.easeInOut) {
                        preferences.markCompleted(exp.id)
                    }
                    celebrationTrigger += 1
                    let completedId = exp.id
                    justCompletedId = completedId
                    completionClearTask?.cancel()
                    completionClearTask = Task {
                        try? await Task.sleep(for: .milliseconds(700))
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            if justCompletedId == completedId { justCompletedId = nil }
                        }
                    }
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: String(format: NSLocalizedString("favorites.row.markVisited.announcement", comment: "VoiceOver announcement after marking as visited"), exp.title)
                    )
                }
            } label: {
                Label(
                    isDone
                        ? NSLocalizedString("favorites.row.markNotVisited", comment: "Swipe action to un-complete a favorite")
                        : NSLocalizedString("favorites.row.markVisited", comment: "Swipe action to mark a favorite as visited"),
                    systemImage: isDone ? "arrow.uturn.backward" : "checkmark.circle"
                )
            }
            .tint(.green)
        }
        .modifier(DirectionsSwipeModifier(exp: exp))
        .accessibilityAction(named: Text(isDone
            ? NSLocalizedString("favorites.row.markNotVisited", comment: "Swipe action to un-complete a favorite")
            : NSLocalizedString("favorites.row.markVisited", comment: "Swipe action to mark a favorite as visited")
        )) {
            if isDone {
                Haptics.selection()
                preferences.completedExperiences.remove(exp.id)
                preferences.visitHistory.removeValue(forKey: exp.id)
                UIAccessibility.post(
                    notification: .announcement,
                    argument: NSLocalizedString("favorites.row.markNotVisited.announcement", comment: "VoiceOver announcement after marking as not visited")
                )
            } else {
                preferences.markCompleted(exp.id)
                celebrationTrigger += 1
                let completedId = exp.id
                justCompletedId = completedId
                completionClearTask?.cancel()
                completionClearTask = Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        if justCompletedId == completedId { justCompletedId = nil }
                    }
                }
                UIAccessibility.post(
                    notification: .announcement,
                    argument: String(format: NSLocalizedString("favorites.row.markVisited.announcement", comment: "VoiceOver announcement after marking as visited"), exp.title)
                )
            }
        }
        .accessibilityAction(named: Text(NSLocalizedString("favorites.row.directions", comment: "Directions accessibility action"))) {
            guard let coord = exp.coordinate,
                  let app = NavigationLauncher.availableApps().first else { return }
            Haptics.impact(.light)
            NavigationLauncher.open(app: app, coordinate: coord, name: exp.title)
        }
    }
}

/// Full-row decorative overlay fired when a favorite is marked visited.
/// Blooms a green checkmark over the 44-pt icon circle and sweeps a soft
/// green shimmer left-to-right across the row. Fully gated behind Reduce Motion
/// (both effects are skipped). All elements are `accessibilityHidden`.
private struct RowCompletionFlourish: View {
    /// Increment to trigger one flourish cycle. Matches the justCompletedId
    /// pattern — caller sets this to a new value to fire, then clears after ~0.7s.
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var bloomScale: CGFloat = 0.2
    @State private var sweepPhase: CGFloat = -1
    @State private var showOverlay = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                if showOverlay && !reduceMotion {
                    // Left-to-right green sweep across full row width
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: Color.green.opacity(0.18), location: 0.5),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.5, height: geo.size.height)
                    .offset(x: geo.size.width * sweepPhase)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)

                    // Bloom checkmark centred over the 44-pt icon circle (leading inset ~22pt)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.green)
                        .scaleEffect(bloomScale)
                        .frame(width: 44, height: 44)
                        .offset(x: 0, y: 0)
                        .frame(maxHeight: .infinity)
                        .accessibilityHidden(true)
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: isActive) { _, active in
            if active && !reduceMotion {
                showOverlay = true
                bloomScale = 0.2
                sweepPhase = -1
                // Two-spring bloom: 0.2 → 1.15 → 1.0 (mirrors CompletionRing.triggerCelebration)
                withAnimation(.spring(response: 0.18, dampingFraction: 0.45)) {
                    bloomScale = 1.15
                }
                withAnimation(.spring(response: 0.2, dampingFraction: 0.6).delay(0.18)) {
                    bloomScale = 1.0
                }
                // Left-to-right sweep over ~0.6s
                withAnimation(.easeInOut(duration: 0.6).delay(0.05)) {
                    sweepPhase = 1.4
                }
            } else if !active {
                showOverlay = false
                bloomScale = 0.2
                sweepPhase = -1
            }
        }
    }
}

private struct PressableRowStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect((!reduceMotion && configuration.isPressed) ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

private struct DirectionsSwipeModifier: ViewModifier {
    let exp: Experience

    func body(content: Content) -> some View {
        let coord = exp.coordinate
        let firstApp = NavigationLauncher.availableApps().first
        if let coord, let app = firstApp {
            content.swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    Haptics.impact(.light)
                    NavigationLauncher.open(app: app, coordinate: coord, name: exp.title)
                } label: {
                    Label(
                        NSLocalizedString("favorites.row.directions", comment: "Directions swipe action"),
                        systemImage: "arrow.triangle.turn.up.right.diamond.fill"
                    )
                }
                .tint(.accentColor)
            }
        } else {
            content
        }
    }
}

#Preview("JourneyProgressBar — 100% sweep") {
    struct SweepDemo: View {
        @State private var completed = 4
        let total = 5

        var body: some View {
            VStack(spacing: 24) {
                JourneyProgressBar(completed: completed, total: total)
                    .padding(.horizontal, 24)
                HStack(spacing: 16) {
                    Button("−1") { if completed > 0 { completed -= 1 } }
                        .buttonStyle(.bordered)
                    Text("\(completed)/\(total)")
                        .monospacedDigit()
                    Button("+1") { if completed < total { completed += 1 } }
                        .buttonStyle(.borderedProminent)
                }
                Text("Tap +1 to reach 100% and watch the shimmer sweep")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding()
        }
    }
    return SweepDemo()
}

#Preview {
    FavoritesListView(onSelectExperience: { _ in })
        .environment(ExperienceService())
        .environment(UserPreferences())
        .environment(LocationService.shared)
        .environment(BestNowClock.shared)
}
