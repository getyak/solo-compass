import SwiftUI
import CoreLocation

enum FavSort { case recent, nearest }

/// List of favorited experiences sorted by most-recently-added.
/// Presented as a sheet from SettingsView or via the map settings button.
public struct FavoritesListView: View {
    @Environment(ExperienceService.self) private var experienceService
    @Environment(UserPreferences.self) private var preferences
    @Environment(LocationService.self) private var locationService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onSelectExperience: (Experience) -> Void

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
        switch sortMode {
        case .recent:
            return experiences.sorted { lhs, rhs in
                let lDate = preferences.favoritedAt[lhs.id] ?? .distantPast
                let rDate = preferences.favoritedAt[rhs.id] ?? .distantPast
                return lDate > rDate
            }
        case .nearest:
            return experiences.sorted { lhs, rhs in
                let lDist = distanceMeters(for: lhs) ?? .greatestFiniteMagnitude
                let rDist = distanceMeters(for: rhs) ?? .greatestFiniteMagnitude
                if lDist != rDist { return lDist < rDist }
                let lDate = preferences.favoritedAt[lhs.id] ?? .distantPast
                let rDate = preferences.favoritedAt[rhs.id] ?? .distantPast
                return lDate > rDate
            }
        }
    }

    private static let metersFormatter: MeasurementFormatter = {
        let f = MeasurementFormatter()
        f.unitOptions = .providedUnit
        f.numberFormatter.maximumFractionDigits = 0
        return f
    }()

    private static let kilometersFormatter: MeasurementFormatter = {
        let f = MeasurementFormatter()
        f.unitOptions = .providedUnit
        f.numberFormatter.maximumFractionDigits = 1
        f.numberFormatter.minimumFractionDigits = 1
        return f
    }()

    private func distanceString(for experience: Experience) -> String? {
        guard let userLocation = LocationService.shared.currentLocation,
              let coord = experience.coordinate else { return nil }
        let meters = userLocation.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
        if meters < 1000 {
            let rounded = (meters / 50).rounded() * 50
            let measurement = Measurement(value: max(50, rounded), unit: UnitLength.meters)
            return Self.metersFormatter.string(from: measurement)
        } else {
            let measurement = Measurement(value: meters / 1000, unit: UnitLength.kilometers)
            return Self.kilometersFormatter.string(from: measurement)
        }
    }

    private var filteredFavorites: [Experience] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return sortedFavorites }
        return sortedFavorites.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.oneLiner.localizedCaseInsensitiveContains(query)
        }
    }

    public var body: some View {
        NavigationStack {
            Group {
                if sortedFavorites.isEmpty && lastUnfavorited == nil {
                    EmptyFavoritesView()
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                } else if filteredFavorites.isEmpty {
                    NoSearchResultsView(query: searchText, onClear: { searchText = "" })
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
                } else {
                    VStack(spacing: 0) {
                        if sortedFavorites.count > 0 {
                            // Footer reflects the active search filter when one is present.
                            let countLabel: String = {
                                let query = searchText.trimmingCharacters(in: .whitespaces)
                                if query.isEmpty {
                                    return String(format: NSLocalizedString("favorites.count", comment: "N saved"), sortedFavorites.count)
                                } else {
                                    return String(format: NSLocalizedString("favorites.count.matching", comment: "M of N matching"), filteredFavorites.count, sortedFavorites.count)
                                }
                            }()
                            Text(countLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .animation(.easeInOut, value: filteredFavorites.count)
                            .contentTransition(.numericText())
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
    }
}

private struct EmptyFavoritesView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

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
            }
            Text(NSLocalizedString("favorites.empty.title", comment: "No favorites yet"))
                .font(.headline)
            Text(NSLocalizedString("favorites.empty.hint", comment: "Tap the heart on any experience"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .onAppear {
            guard !isBreathing, !reduceMotion else { return }
            isBreathing = true
        }
    }
}

private struct NoSearchResultsView: View {
    let query: String
    let onClear: () -> Void

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

private struct SwipeHintCapsuleView: View {
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
        } else {
            base.symbolEffect(.bounce, options: .repeating.speed(0.6))
        }
    }
}

private extension FavoritesListView {

    var undoBar: some View {
        ZStack(alignment: .bottom) {
            HStack {
                Text(String(format: NSLocalizedString("favorites.undo.named", comment: "Removed named experience undo banner"), lastUnfavorited?.title ?? ""))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Button {
                    performUndo()
                } label: {
                    Text(NSLocalizedString("action.undo", comment: "Undo action"))
                        .font(.subheadline.weight(.semibold))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)

            if !reduceMotion {
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.accentColor)
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
        .accessibilityHint(Text(NSLocalizedString("favorites.undo.swipeHint", comment: "Swipe down to dismiss undo bar")))
        .accessibilityAction(named: Text(NSLocalizedString("action.undo", comment: "Undo action"))) {
            performUndo()
        }
        .onAppear {
            undoProgress = 1
            undoDragOffset = 0
            if !reduceMotion {
                withAnimation(.linear(duration: 4)) {
                    undoProgress = 0
                }
            }
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

    @ViewBuilder
    func favoriteRow(_ exp: Experience) -> some View {
        let distStr = distanceString(for: exp)
        let prox = proximity(for: exp)
        Button {
            onSelectExperience(exp)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(exp.category.color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: exp.category.symbol)
                        .font(.body)
                        .foregroundStyle(exp.category.color)
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
                    if let distStr {
                        HStack(spacing: 3) {
                            if let prox {
                                Circle()
                                    .fill(prox.color)
                                    .frame(width: 7, height: 7)
                                    .accessibilityHidden(true)
                            }
                            Text(distStr)
                                .font(.caption2)
                                .monospacedDigit()
                        }
                        .foregroundStyle(.tertiary)
                        .padding(.top, 1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel({
            if let distStr {
                let awayFmt = NSLocalizedString("favorites.row.distance.a11y", comment: "Distance away accessibility label")
                let distLabel = String(format: awayFmt, distStr)
                if let prox {
                    return Text("\(exp.title), \(exp.oneLiner), \(distLabel), \(prox.a11yWord)")
                }
                return Text("\(exp.title), \(exp.oneLiner), \(distLabel)")
            }
            return Text("\(exp.title), \(exp.oneLiner)")
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
                undoDismissTask?.cancel()
                undoDismissTask = Task {
                    try? await Task.sleep(for: .seconds(4))
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
        .modifier(DirectionsSwipeModifier(exp: exp))
        .accessibilityAction(named: Text(NSLocalizedString("favorites.row.directions", comment: "Directions accessibility action"))) {
            guard let coord = exp.coordinate,
                  let app = NavigationLauncher.availableApps().first else { return }
            Haptics.impact(.light)
            NavigationLauncher.open(app: app, coordinate: coord, name: exp.title)
        }
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

#Preview {
    FavoritesListView(onSelectExperience: { _ in })
        .environment(ExperienceService())
        .environment(UserPreferences())
        .environment(LocationService.shared)
}
