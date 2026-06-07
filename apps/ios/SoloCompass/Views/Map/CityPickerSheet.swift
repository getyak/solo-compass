import SwiftUI
import CoreLocation

/// Bottom sheet for selecting a city (or "All Cities").
/// Displayed when the user taps the city pill in the top-left of the map.
/// US-019: Rows show experience count and distance from user location.
public struct CityPickerSheet: View {
    @Bindable var viewModel: MapViewModel
    let onDismiss: () -> Void
    @State private var userLocation: CLLocation?
    @State private var justSelectedCode: String? = nil
    @State private var citySearchText = ""

    private func selectCity(_ code: String?) {
        Haptics.impact(.light)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            justSelectedCode = code ?? "all"
            viewModel.selectCity(code)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            onDismiss()
        }
    }

    private var nearestCity: (code: String, name: String, center: CLLocationCoordinate2D)? {
        guard userLocation != nil else { return nil }
        return sortedCities.first
    }

    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.availableCities.isEmpty {
                    CityEmptyStateView()
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                } else {
                    let filtered = filteredSortedCities
                    if filtered.isEmpty {
                        ContentUnavailableView.search(text: citySearchText)
                    } else {
                        VStack(spacing: 0) {
                            if citySearchText.trimmingCharacters(in: .whitespaces).isEmpty,
                               !viewModel.availableCities.isEmpty,
                               let nearest = nearestCity {
                                CityPickerHeader(
                                    cityName: nearest.name,
                                    distanceLabel: distanceLabel(for: nearest.center),
                                    proximityColor: proximity(for: nearest.center)?.color ?? Color(.tertiaryLabel),
                                    experienceCount: viewModel.experienceCount(for: nearest.code),
                                    onTapNearest: { selectCity(nearest.code) }
                                )
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                            }
                        List {
                            // "All Cities" option — hidden while a search query is active
                            if citySearchText.trimmingCharacters(in: .whitespaces).isEmpty {
                                Button {
                                    selectCity(nil)
                                } label: {
                                    HStack {
                                        Text(NSLocalizedString("city.all", comment: "All cities option"))
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if viewModel.selectedCity == nil {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.tint)
                                                .font(.body.weight(.semibold))
                                                .scaleEffect(justSelectedCode == "all" ? 1.3 : 1.0)
                                                .symbolEffect(.bounce, value: justSelectedCode)
                                        }
                                    }
                                }
                            }

                            // US-019: Sort by distance ascending, then alphabetical
                            ForEach(filtered, id: \.code) { city in
                                let prox = proximity(for: city.center)
                                let expCount = viewModel.experienceCount(for: city.code)
                                let distLabel = distanceLabel(for: city.center)
                                Button {
                                    selectCity(city.code)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(city.name)
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                            Text(String(
                                                format: NSLocalizedString("city.experienceCount", comment: "Experience count in city"),
                                                expCount
                                            ))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            if viewModel.selectedCity == city.code {
                                                Image(systemName: "checkmark")
                                                    .foregroundStyle(.tint)
                                                    .font(.body.weight(.semibold))
                                                    .scaleEffect(justSelectedCode == city.code ? 1.3 : 1.0)
                                                    .symbolEffect(.bounce, value: justSelectedCode)
                                            }
                                            HStack(spacing: 3) {
                                                if let prox {
                                                    Circle()
                                                        .fill(prox.color)
                                                        .frame(width: 7, height: 7)
                                                        .accessibilityHidden(true)
                                                }
                                                Text(distLabel)
                                                    .font(.caption)
                                                    .monospacedDigit()
                                            }
                                            .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel({
                                    let countStr = String(format: NSLocalizedString("city.experienceCount", comment: "Experience count in city"), expCount)
                                    let awayFmt = NSLocalizedString("city.distanceAway.a11y", comment: "Distance away accessibility label")
                                    let distA11y = String(format: awayFmt, distLabel)
                                    if let prox {
                                        return Text("\(city.name), \(countStr), \(distA11y), \(prox.a11yWord)")
                                    }
                                    return Text("\(city.name), \(countStr), \(distA11y)")
                                }())
                            }
                        }
                        } // VStack
                    }
                }
            }
            .searchable(
                text: $citySearchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: NSLocalizedString("city.search.prompt", comment: "Search cities prompt")
            )
            .animation(.easeInOut, value: viewModel.availableCities.isEmpty)
            .navigationTitle(NSLocalizedString("city.picker.title", comment: "City picker sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("common.cancel", comment: "Cancel")) {
                        onDismiss()
                    }
                }
            }
            .onAppear {
                // Capture user location once for sorting
                userLocation = LocationService.shared.currentLocation
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var filteredSortedCities: [(code: String, name: String, center: CLLocationCoordinate2D)] {
        let query = citySearchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return sortedCities }
        return sortedCities.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var sortedCities: [(code: String, name: String, center: CLLocationCoordinate2D)] {
        guard let userLoc = userLocation else {
            return viewModel.availableCities.sorted { $0.name < $1.name }
        }
        return viewModel.availableCities.sorted { a, b in
            let locA = CLLocation(latitude: a.center.latitude, longitude: a.center.longitude)
            let locB = CLLocation(latitude: b.center.latitude, longitude: b.center.longitude)
            let dA = userLoc.distance(from: locA)
            let dB = userLoc.distance(from: locB)
            if abs(dA - dB) < 1_000 { return a.name < b.name }
            return dA < dB
        }
    }

    private enum CityProximity {
        case near, mid, far

        static func from(meters: CLLocationDistance) -> CityProximity {
            if meters <= 25_000 { return .near }
            if meters <= 150_000 { return .mid }
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

    private func proximity(for coord: CLLocationCoordinate2D) -> CityProximity? {
        guard let userLoc = userLocation else { return nil }
        let cityLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        return CityProximity.from(meters: userLoc.distance(from: cityLoc))
    }

    private func distanceLabel(for coord: CLLocationCoordinate2D) -> String {
        guard let userLoc = userLocation else {
            return NSLocalizedString("city.distanceUnknown", comment: "Distance unknown")
        }
        let cityLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let km = userLoc.distance(from: cityLoc) / 1_000
        if Locale.current.measurementSystem == .us {
            let mi = km * 0.621371
            return String(format: NSLocalizedString("city.distanceAway.mi", comment: ""), mi)
        }
        return String(format: NSLocalizedString("city.distanceAway", comment: ""), km)
    }
}

private struct CityPickerHeader: View {
    let cityName: String
    let distanceLabel: String
    let proximityColor: Color
    let experienceCount: Int
    var onTapNearest: (() -> Void)? = nil

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

    private var nudgeLabel: String {
        String(
            format: NSLocalizedString("city.header.nearest", comment: "Nearest city nudge"),
            cityName
        ) + " · \(distanceLabel) · " + String(
            format: NSLocalizedString("city.experienceCount", comment: "Experience count in city"),
            experienceCount
        )
    }

    @ViewBuilder
    private var nudgeCapsule: some View {
        // Capsule color derives from proximity so dot, text, chevron, and tint read as one honest signal.
        HStack(spacing: 4) {
            Circle()
                .fill(proximityColor)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(nudgeLabel)
                .font(.caption2)
                .foregroundStyle(proximityColor)
            Image(systemName: "chevron.right.circle.fill")
                .font(.caption2)
                .foregroundStyle(proximityColor)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(proximityColor.opacity(0.12), in: Capsule())
        .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(greeting)
                .font(.headline)
                .foregroundStyle(.primary)

            if let onTap = onTapNearest {
                Button {
                    onTap()
                } label: {
                    nudgeCapsule
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    String(
                        format: NSLocalizedString("city.header.nearest.a11y", comment: "Nearest city capsule accessibility label"),
                        cityName, distanceLabel, experienceCount
                    )
                )
                .accessibilityHint(NSLocalizedString("city.header.nearest.hint", comment: "Selects the closest discovered city"))
                .accessibilityAddTraits(.isButton)
            } else {
                nudgeCapsule
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(nudgeLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : (reduceMotion ? 0 : 6))
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.3)) { appeared = true }
            }
        }
    }
}

private struct CityEmptyStateView: View {
    @State private var isBreathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "map.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
                    .scaleEffect(isBreathing ? 1.08 : 0.94)
                    .opacity(isBreathing ? 1.0 : 0.7)
                    // Guard on the modifier itself, not just in onAppear — otherwise
                    // a re-appear could still animate when reduce-motion is on.
                    .animation(reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: isBreathing)
            }
            Text(NSLocalizedString("city.empty.title", comment: "No cities yet"))
                .font(.headline)
            Text(NSLocalizedString("city.empty.hint", comment: "Cities appear as you explore the map"))
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

#Preview("With cities") {
    CityPickerSheet(
        viewModel: MapViewModel(
            locationService: LocationService.shared,
            experienceService: ExperienceService(),
            aiService: AIService(),
            preferences: UserPreferences()
        ),
        onDismiss: {}
    )
}

#Preview("Empty state — no discovered cities") {
    CityPickerSheet(
        viewModel: MapViewModel(
            locationService: LocationService.shared,
            experienceService: ExperienceService(),
            aiService: AIService(),
            preferences: UserPreferences()
        ),
        onDismiss: {}
    )
}

#Preview("Search — no matches") {
    let sheet = CityPickerSheet(
        viewModel: MapViewModel(
            locationService: LocationService.shared,
            experienceService: ExperienceService(),
            aiService: AIService(),
            preferences: UserPreferences()
        ),
        onDismiss: {}
    )
    return sheet
}
