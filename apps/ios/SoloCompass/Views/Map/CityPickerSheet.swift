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

    private func selectCity(_ code: String?) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            justSelectedCode = code ?? "all"
            viewModel.selectCity(code)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            onDismiss()
        }
    }

    public var body: some View {
        NavigationStack {
            List {
                // "All Cities" option
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

                // US-019: Sort by distance ascending, then alphabetical
                ForEach(sortedCities, id: \.code) { city in
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
                                    viewModel.experienceCount(for: city.code)
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
                                Text(distanceLabel(for: city.center))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
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

#Preview {
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
