import SwiftUI
import MapKit
import CoreLocation

/// Rich location picker that replaces `CityPickerSheet`.
/// Three tabs: Cities (browse / search preset + custom cities), Search
/// (forward geocoding via MKLocalSearch + save-as-city flow), Map
/// (drag-a-pin or type coordinates + save-as-city flow).
struct LocationPickerSheet: View {
    @Bindable var viewModel: MapViewModel
    /// City OS v2: when provided (flag on), the selected city gains a
    /// Live/Plan/Recall mode control + rows carry a small mode tag. nil keeps
    /// the sheet exactly as it shipped.
    let cityOSStore: CityOSStore?
    let onDismiss: () -> Void

    @State private var state: LocationPickerState
    @State private var searchService = LocationSearchService()
    @State private var searchDebounceTask: Task<Void, Never>? = nil
    @State private var userLocation: CLLocation?
    @State private var customCityStore = CustomCityStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(viewModel: MapViewModel, cityOSStore: CityOSStore? = nil, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.cityOSStore = cityOSStore
        self.onDismiss = onDismiss
        let initial = viewModel.customCoordinates ?? viewModel.defaultCenterForSelectedCity
        self._state = State(initialValue: LocationPickerState(initialCoordinate: initial))
    }

    var body: some View {
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
                ToolbarItem(placement: .topBarLeading) {
                    if state.selectedTab == .cities {
                        Button {
                            state.selectedTab = .search
                        } label: {
                            Image(systemName: "plus")
                                .accessibilityLabel(NSLocalizedString("locationPicker.cities.addCity", comment: "Add custom city"))
                        }
                    }
                }
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
        // Save-city alert for Search tab
        .alert(
            NSLocalizedString("locationPicker.search.saveCity.title", comment: "Save as custom city"),
            isPresented: $bs.isShowingSaveSearchAlert
        ) {
            TextField(
                NSLocalizedString("locationPicker.search.saveCity.namePlaceholder", comment: "City name"),
                text: $bs.saveNameText
            )
            Button(NSLocalizedString("locationPicker.search.saveCity.save", comment: "Save")) {
                confirmSaveSearchResult()
            }
            Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) {
                state.pendingSaveItem = nil
            }
        } message: {
            Text(NSLocalizedString("locationPicker.search.saveCity.message", comment: "This city will appear in your Cities list."))
        }
        // Save-city alert for Map tab
        .alert(
            NSLocalizedString("locationPicker.map.saveCity.title", comment: "Name this location"),
            isPresented: $bs.isShowingSaveMapAlert
        ) {
            TextField(
                NSLocalizedString("locationPicker.map.saveCity.namePlaceholder", comment: "Location name"),
                text: $bs.mapSaveNameText
            )
            Button(NSLocalizedString("locationPicker.map.saveCity.save", comment: "Save & Set")) {
                confirmSaveMapLocation()
            }
            Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("locationPicker.map.saveCity.message", comment: "Saved cities appear in your Cities list for quick access."))
        }
    }

    // MARK: - Cities Tab

    @ViewBuilder
    private func citiesContent(bs: Bindable<LocationPickerState>) -> some View {
        List {
            // City OS v2: mode control for the currently selected city, so the
            // traveler can flip Live / Plan / Recall (the aggregation context).
            if let store = cityOSStore, let selected = viewModel.selectedCity {
                Section(NSLocalizedString("cityos.picker.mode.section", comment: "City mode section title")) {
                    CityModePicker(
                        mode: store.mode(for: selected),
                        onSelect: { newMode in
                            commitHaptic()
                            store.setMode(newMode, for: selected)
                        }
                    )
                }
            }

            // "All Cities" row
            Button {
                commitHaptic()
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

            // Seed-derived cities
            let seed = filteredCities
            if !seed.isEmpty {
                Section(NSLocalizedString("locationPicker.cities.section.places", comment: "Places with experiences")) {
                    ForEach(seed, id: \.code) { city in
                        Button {
                            commitHaptic()
                            viewModel.selectCity(city.code)
                            onDismiss()
                        } label: {
                            CityRow(
                                name: city.name,
                                icon: "mappin",
                                experienceCount: viewModel.experienceCount(for: city.code),
                                distanceLabel: distanceLabel(for: city.center),
                                isSelected: viewModel.selectedCity == city.code
                            )
                        }
                    }
                }
            }

            // Custom saved cities
            let custom = filteredCustomCities
            if !custom.isEmpty {
                Section(NSLocalizedString("locationPicker.cities.section.saved", comment: "Saved locations")) {
                    ForEach(custom) { saved in
                        Button {
                            commitHaptic()
                            viewModel.selectCustomLocation(
                                coordinate: saved.coordinate,
                                label: saved.name,
                                cityCode: saved.id
                            )
                            onDismiss()
                        } label: {
                            CityRow(
                                name: saved.name,
                                icon: "pin.fill",
                                experienceCount: nil,
                                distanceLabel: distanceLabel(for: saved.coordinate),
                                isSelected: viewModel.selectedCity == saved.id
                            )
                        }
                    }
                    .onDelete { offsets in
                        let idsToDelete = offsets.map { custom[$0].id }
                        for id in idsToDelete { customCityStore.remove(id: id) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(
            text: bs.citySearchQuery,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("locationPicker.cities.searchPrompt", comment: "Search cities")
        )
        .animation(.easeInOut(duration: 0.2), value: customCityStore.cities.count)
    }

    private var filteredCities: [(code: String, name: String, center: CLLocationCoordinate2D)] {
        let cities = sortedCities
        guard !state.citySearchQuery.isEmpty else { return cities }
        let query = state.citySearchQuery.lowercased()
        return cities.filter { $0.name.lowercased().contains(query) }
    }

    private var filteredCustomCities: [SavedCity] {
        let all = customCityStore.cities
        guard !state.citySearchQuery.isEmpty else { return all }
        let query = state.citySearchQuery.lowercased()
        return all.filter { $0.name.lowercased().contains(query) }
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

            if state.searchSaveConfirmed {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(NSLocalizedString("locationPicker.search.saveCity.confirmed", comment: "City saved!"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                }
                .padding(.vertical, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

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
                    .swipeActions(edge: .trailing) {
                        Button {
                            promptSaveSearchResult(item)
                        } label: {
                            Label(
                                NSLocalizedString("locationPicker.search.saveCity.swipe", comment: "Save city"),
                                systemImage: "pin.fill"
                            )
                        }
                        .tint(.indigo)
                    }
                }
                .listStyle(.plain)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: state.searchSaveConfirmed)
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
                    } else if state.mapSaveConfirmed {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.title3)
                                .symbolEffect(.bounce, value: reduceMotion ? false : state.mapSaveConfirmed)
                            Text(NSLocalizedString("locationPicker.map.saveCity.confirmed", comment: "Location saved!"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                        .transition(.scale.combined(with: .opacity))
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
                .animation(.easeInOut(duration: 0.3), value: state.mapSaveConfirmed)

                VStack(spacing: 10) {
                    // Primary: save + set
                    Button {
                        promptSaveMapLocation()
                    } label: {
                        Label(
                            NSLocalizedString("locationPicker.map.saveAndSet", comment: "Save & set this location"),
                            systemImage: "pin.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal, 16)

                    // Secondary: just use it without saving
                    Button {
                        commitMapLocation()
                    } label: {
                        Text(NSLocalizedString("locationPicker.map.setLocation", comment: "Use without saving"))
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 24)
            }
            .padding(.top, 12)
        }
    }

    // MARK: - Actions

    private func commitHaptic() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    private func successHaptic() { UINotificationFeedbackGenerator().notificationOccurred(.success) }

    private func selectSearchResult(_ item: MKMapItem) {
        commitHaptic()
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

    private func promptSaveSearchResult(_ item: MKMapItem) {
        let name = item.name
            ?? item.placemark.locality
            ?? item.placemark.administrativeArea
            ?? ""
        state.pendingSaveItem = item
        state.saveNameText = name
        state.isShowingSaveSearchAlert = true
    }

    private func confirmSaveSearchResult() {
        guard let item = state.pendingSaveItem else { return }
        let name = state.saveNameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let coord = item.placemark.coordinate
        let city = SavedCity(
            id: "custom_\(UUID().uuidString)",
            name: name,
            latitude: coord.latitude,
            longitude: coord.longitude,
            countryCode: item.placemark.countryCode,
            dateAdded: Date()
        )
        customCityStore.add(city)
        state.pendingSaveItem = nil
        successHaptic()

        withAnimation { state.searchSaveConfirmed = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { state.searchSaveConfirmed = false }
        }
    }

    private func promptSaveMapLocation() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let name = state.resolvedCityName
            ?? String(format: "%.4f, %.4f", state.pinCoordinate.latitude, state.pinCoordinate.longitude)
        state.mapSaveNameText = name
        state.isShowingSaveMapAlert = true
    }

    private func confirmSaveMapLocation() {
        let name = state.mapSaveNameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let coord = state.pinCoordinate
        let city = SavedCity(
            id: "custom_\(UUID().uuidString)",
            name: name,
            latitude: coord.latitude,
            longitude: coord.longitude,
            countryCode: nil,
            dateAdded: Date()
        )
        customCityStore.add(city)
        successHaptic()

        withAnimation { state.mapSaveConfirmed = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            viewModel.selectCustomLocation(coordinate: coord, label: name, cityCode: city.id)
            onDismiss()
        }
    }

    private func commitMapLocation() {
        commitHaptic()
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
    let icon: String
    let experienceCount: Int?
    let distanceLabel: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(experienceCount != nil ? Color.accentColor : Color.indigo)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let count = experienceCount {
                    Text(String(
                        format: NSLocalizedString("city.experienceCount", comment: "Experience count in city"),
                        count
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else {
                    Text(NSLocalizedString("locationPicker.cities.saved.subtitle", comment: "Saved location"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
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

// MARK: - CityModePicker (City OS v2)

/// A compact Live / Plan / Recall segmented control for the selected city.
/// Live = 在此城 (warm), Plan = 计划 (cool blue), Recall = 回顾 (muted). Mode is
/// the aggregation context, not a filter — switching it re-frames the whole
/// city surface (PRD §4.1).
private struct CityModePicker: View {
    let mode: CityMode
    let onSelect: (CityMode) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(CityMode.allCases, id: \.self) { candidate in
                Button {
                    onSelect(candidate)
                } label: {
                    Text(Self.label(for: candidate))
                        .font(CT.body(13, mode == candidate ? .semibold : .regular))
                        .foregroundStyle(mode == candidate ? .white : Self.tint(for: candidate))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(mode == candidate ? Self.tint(for: candidate) : Self.tint(for: candidate).opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == candidate ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.vertical, 2)
    }

    private static func label(for mode: CityMode) -> String {
        switch mode {
        case .live:   return NSLocalizedString("cityos.mode.live.tag", comment: "在此城")
        case .plan:   return NSLocalizedString("cityos.mode.plan.tag", comment: "计划")
        case .recall: return NSLocalizedString("cityos.mode.recall.tag", comment: "回顾")
        }
    }

    private static func tint(for mode: CityMode) -> Color {
        switch mode {
        case .live:   return CT.sunGoldDeep
        case .plan:   return CT.modePlanBlue
        case .recall: return CT.fgMuted
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
