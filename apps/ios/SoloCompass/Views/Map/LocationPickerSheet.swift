import SwiftUI
import MapKit
import CoreLocation

/// Rich location picker that replaces `CityPickerSheet`.
/// Three tabs: Cities (browse / search preset cities), Search (forward
/// geocoding via MKLocalSearch), Map (drag-a-pin or type coordinates).
struct LocationPickerSheet: View {
    @Bindable var viewModel: MapViewModel
    let onDismiss: () -> Void

    /// `@State` holds the `@Observable` state object.
    /// Bindings to its properties are created via `@Bindable` inside body.
    @State private var state: LocationPickerState
    @State private var searchService = LocationSearchService()
    @State private var searchDebounceTask: Task<Void, Never>? = nil
    @State private var userLocation: CLLocation?

    init(viewModel: MapViewModel, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        let initial = viewModel.customCoordinates ?? viewModel.defaultCenterForSelectedCity
        self._state = State(initialValue: LocationPickerState(initialCoordinate: initial))
    }

    var body: some View {
        // @Bindable gives us `$bs.*` bindings into the @Observable state object.
        @Bindable var bs = state
        NavigationStack {
            VStack(spacing: 0) {
                Picker(
                    NSLocalizedString("locationPicker.picker.a11y", comment: "Location type picker"),
                    selection: $bs.selectedTab
                ) {
                    ForEach(LocationPickerState.Tab.allCases, id: \.self) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()

                switch state.selectedTab {
                case .cities: citiesContent(bs: $bs)
                case .search: searchContent(bs: $bs)
                case .map:    mapContent(bs: $bs)
                }
            }
            .navigationTitle(NSLocalizedString("locationPicker.title", comment: "Location picker title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("common.cancel", comment: "Cancel")) {
                        onDismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            userLocation = LocationService.shared.currentLocation
        }
        .onDisappear {
            searchService.cancelAll()
            searchDebounceTask?.cancel()
        }
    }

    // MARK: - Cities Tab

    @ViewBuilder
    private func citiesContent(bs: Bindable<LocationPickerState>) -> some View {
        List {
            Button {
                viewModel.selectCity(nil)
                onDismiss()
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
                    }
                }
            }

            ForEach(filteredCities, id: \.code) { city in
                Button {
                    viewModel.selectCity(city.code)
                    onDismiss()
                } label: {
                    CityRow(
                        name: city.name,
                        experienceCount: viewModel.experienceCount(for: city.code),
                        distanceLabel: distanceLabel(for: city.center),
                        isSelected: viewModel.selectedCity == city.code
                    )
                }
            }
        }
        .listStyle(.plain)
        .searchable(
            text: bs.citySearchQuery,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("locationPicker.cities.searchPrompt", comment: "Search cities")
        )
    }

    private var filteredCities: [(code: String, name: String, center: CLLocationCoordinate2D)] {
        let cities = sortedCities
        guard !state.citySearchQuery.isEmpty else { return cities }
        let query = state.citySearchQuery.lowercased()
        return cities.filter { $0.name.lowercased().contains(query) }
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

    // MARK: - Search Tab

    @ViewBuilder
    private func searchContent(bs: Bindable<LocationPickerState>) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    NSLocalizedString("locationPicker.search.prompt", comment: "City, place, or address"),
                    text: bs.searchQuery
                )
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { triggerSearch() }
                .onChange(of: state.searchQuery) { _, _ in scheduleSearchDebounce() }

                if state.isSearching {
                    ProgressView().scaleEffect(0.8)
                } else if !state.searchQuery.isEmpty {
                    Button {
                        state.searchQuery = ""
                        state.searchResults = []
                        state.searchError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if let error = state.searchError {
                ContentUnavailableView(
                    NSLocalizedString("locationPicker.search.error.title", comment: "Search failed"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .padding(.top, 40)
            } else if state.searchResults.isEmpty && !state.isSearching && !state.searchQuery.isEmpty {
                ContentUnavailableView.search(text: state.searchQuery)
                    .padding(.top, 40)
            } else {
                List(state.searchResults, id: \.self) { item in
                    Button {
                        selectSearchResult(item)
                    } label: {
                        SearchResultRow(item: item)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Map Tab

    @ViewBuilder
    private func mapContent(bs: Bindable<LocationPickerState>) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                MapPinPickerView(
                    coordinate: state.pinCoordinate,
                    onCoordinateChanged: { coord in
                        state.updatePin(to: coord)
                        scheduleReverseGeocode()
                    }
                )
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                .padding(.horizontal, 16)

                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        CoordinateField(
                            label: NSLocalizedString("locationPicker.map.lat", comment: "Latitude field label"),
                            text: bs.manualLatText,
                            placeholder: "18.7877"
                        )
                        CoordinateField(
                            label: NSLocalizedString("locationPicker.map.lon", comment: "Longitude field label"),
                            text: bs.manualLonText,
                            placeholder: "98.9938"
                        )
                    }

                    Button {
                        applyCoordinateFields()
                    } label: {
                        Text(NSLocalizedString("locationPicker.map.applyCoords", comment: "Move pin to these coordinates"))
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
                .padding(.horizontal, 16)

                Group {
                    if state.isResolving {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7)
                            Text(NSLocalizedString("locationPicker.map.resolving", comment: "Resolving location name"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if let name = state.resolvedCityName {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                            Text(String(
                                format: NSLocalizedString("locationPicker.map.resolved", comment: "Resolved city: %@"),
                                name
                            ))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)

                Button {
                    commitMapLocation()
                } label: {
                    Text(NSLocalizedString("locationPicker.map.setLocation", comment: "Set this location on the map"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .padding(.top, 12)
        }
    }

    // MARK: - Actions

    private func selectSearchResult(_ item: MKMapItem) {
        let coord = item.placemark.coordinate
        let label = item.name
            ?? item.placemark.locality
            ?? item.placemark.administrativeArea
            ?? NSLocalizedString("locationPicker.custom.fallbackName", comment: "Custom location")
        viewModel.selectCustomLocation(
            coordinate: coord,
            label: label,
            cityCode: customCode(for: coord)
        )
        onDismiss()
    }

    private func commitMapLocation() {
        let coord = state.pinCoordinate
        let label = state.resolvedCityName
            ?? String(format: "%.4f, %.4f", coord.latitude, coord.longitude)
        viewModel.selectCustomLocation(
            coordinate: coord,
            label: label,
            cityCode: customCode(for: coord)
        )
        onDismiss()
    }

    private func applyCoordinateFields() {
        guard let coord = state.parsedCoordinate() else { return }
        state.updatePin(to: coord)
        scheduleReverseGeocode()
    }

    private func scheduleSearchDebounce() {
        searchDebounceTask?.cancel()
        guard !state.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            state.searchResults = []
            state.searchError = nil
            return
        }
        searchDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            triggerSearch()
        }
    }

    private func triggerSearch() {
        let query = state.searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        state.isSearching = true
        state.searchError = nil
        Task {
            do {
                let results = try await searchService.search(query)
                state.searchResults = results
            } catch {
                state.searchError = error.localizedDescription
            }
            state.isSearching = false
        }
    }

    private func scheduleReverseGeocode() {
        state.isResolving = true
        state.resolvedCityName = nil
        let coord = state.pinCoordinate
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            let geocoder = ReverseGeocodeService()
            let resolved = await geocoder.resolve(coordinate: coord)
            state.resolvedCityName = resolved?.name
            state.isResolving = false
        }
    }

    // MARK: - Helpers

    private func customCode(for coord: CLLocationCoordinate2D) -> String {
        String(format: "custom_%.4f_%.4f", coord.latitude, coord.longitude)
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

// MARK: - Subviews

private struct CityRow: View {
    let name: String
    let experienceCount: Int
    let distanceLabel: String
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(String(
                    format: NSLocalizedString("city.experienceCount", comment: "Experience count in city"),
                    experienceCount
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .font(.body.weight(.semibold))
                }
                Text(distanceLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
    }
}

private struct SearchResultRow: View {
    let item: MKMapItem

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.name ?? NSLocalizedString("locationPicker.custom.fallbackName", comment: "Custom location"))
                .font(.headline)
                .foregroundStyle(.primary)

            let subtitle = [item.placemark.locality, item.placemark.countryCode]
                .compactMap { $0 }
                .joined(separator: ", ")
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            let coord = item.placemark.coordinate
            Text(String(format: "%.4f, %.4f", coord.latitude, coord.longitude))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

private struct CoordinateField: View {
    let label: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
                .monospacedDigit()
                .autocorrectionDisabled()
        }
    }
}

// MARK: - Preview

#Preview {
    LocationPickerSheet(
        viewModel: MapViewModel(
            locationService: LocationService.shared,
            experienceService: ExperienceService(),
            aiService: AIService(),
            preferences: UserPreferences()
        ),
        onDismiss: {}
    )
}
