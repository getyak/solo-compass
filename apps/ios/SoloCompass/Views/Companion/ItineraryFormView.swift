import SwiftUI
import SwiftData

/// Create or edit an Itinerary.
///
/// Pass an existing `Itinerary` to edit it; omit to create a new one.
/// The store is injected so previews can supply an in-memory container.
public struct ItineraryFormView: View {
    let store: ItineraryStore
    let editing: Itinerary?

    @Environment(ExperienceService.self) private var experienceService
    @Environment(\.dismiss) private var dismiss

    // MARK: - Form state

    @State private var title: String
    @State private var selectedCityCode: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var note: String
    @State private var openToCompanions: Bool

    @State private var showingCityPicker = false
    @State private var showingValidationError = false

    // MARK: - Init

    public init(store: ItineraryStore, editing: Itinerary? = nil) {
        self.store = store
        self.editing = editing
        let start = iso8601DateOrToday(editing?.startDate)
        let end = iso8601DateOrToday(editing?.endDate) ?? start
        _title = State(initialValue: editing?.title ?? "")
        _selectedCityCode = State(initialValue: editing?.cityCode ?? "")
        _startDate = State(initialValue: start ?? Date())
        _endDate = State(initialValue: end)
        _note = State(initialValue: editing?.note ?? "")
        _openToCompanions = State(initialValue: editing?.openToCompanions ?? false)
    }

    // MARK: - Derived

    private var isEditing: Bool { editing != nil }

    private var availableCities: [(code: String, name: String)] {
        var seen = Set<String>()
        return experienceService.allExperiences.compactMap { exp -> (code: String, name: String)? in
            let code = exp.location.cityCode
            guard seen.insert(code).inserted else { return nil }
            return (code, code)
        }.sorted { $0.name < $1.name }
    }

    private var selectedCityName: String {
        availableCities.first(where: { $0.code == selectedCityCode })?.name ?? selectedCityCode
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !selectedCityCode.isEmpty &&
        endDate >= startDate
    }

    private var endBeforeStart: Bool { endDate < startDate }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            Form {
                Section(NSLocalizedString("itinerary.form.section.basics", comment: "Trip details section header")) {
                    HStack {
                        Text(NSLocalizedString("itinerary.form.field.title", comment: "Title field label"))
                        TextField(
                            NSLocalizedString("itinerary.form.field.title.placeholder", comment: "Title placeholder"),
                            text: $title
                        )
                        .multilineTextAlignment(.trailing)
                    }

                    Button {
                        showingCityPicker = true
                    } label: {
                        HStack {
                            Text(NSLocalizedString("itinerary.form.field.city", comment: "City field label"))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(selectedCityCode.isEmpty
                                 ? NSLocalizedString("itinerary.form.city.picker.title", comment: "Choose City placeholder")
                                 : selectedCityName
                            )
                            .foregroundStyle(selectedCityCode.isEmpty ? .secondary : .primary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section(NSLocalizedString("itinerary.form.section.dates", comment: "Dates section header")) {
                    DatePicker(
                        NSLocalizedString("itinerary.form.field.startDate", comment: "Start date picker label"),
                        selection: $startDate,
                        displayedComponents: .date
                    )
                    .onChange(of: startDate) { _, newStart in
                        if endDate < newStart {
                            endDate = newStart
                        }
                    }

                    DatePicker(
                        NSLocalizedString("itinerary.form.field.endDate", comment: "End date picker label"),
                        selection: $endDate,
                        in: startDate...,
                        displayedComponents: .date
                    )
                }

                Section(NSLocalizedString("itinerary.form.section.companion", comment: "Companion mode section header")) {
                    Toggle(
                        NSLocalizedString("itinerary.form.field.openToCompanions", comment: "Open to companions toggle"),
                        isOn: $openToCompanions
                    )
                }

                Section {
                    TextField(
                        NSLocalizedString("itinerary.form.field.note.placeholder", comment: "Notes placeholder"),
                        text: $note,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                } header: {
                    Text(NSLocalizedString("itinerary.form.field.note", comment: "Notes section header"))
                }

                if endBeforeStart {
                    Section {
                        Text(NSLocalizedString(
                            "itinerary.form.validation.endBeforeStart",
                            comment: "End before start validation error"
                        ))
                        .foregroundStyle(.red)
                        .font(.caption)
                    }
                }
            }
            .navigationTitle(NSLocalizedString(
                isEditing ? "itinerary.form.edit.title" : "itinerary.form.create.title",
                comment: "Form nav title"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("itinerary.form.action.cancel", comment: "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("itinerary.form.action.save", comment: "Save")) {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showingCityPicker) {
                ItineraryCityPickerSheet(
                    cities: availableCities,
                    selectedCode: $selectedCityCode
                )
            }
        }
    }

    // MARK: - Save

    private func save() {
        guard isValid else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        let itin = Itinerary(
            id: editing?.id ?? ItineraryId(rawValue: UUID().uuidString),
            ownerId: editing?.ownerId ?? "local",
            title: title.trimmingCharacters(in: .whitespaces),
            cityCode: selectedCityCode,
            startDate: dateToISO8601(startDate),
            endDate: dateToISO8601(endDate),
            experienceIds: editing?.experienceIds ?? [],
            note: note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note.trimmingCharacters(in: .whitespaces),
            openToCompanions: openToCompanions,
            createdAt: editing?.createdAt ?? now,
            updatedAt: now
        )
        if isEditing {
            try? store.update(itin)
        } else {
            try? store.save(itin)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismiss()
    }
}

// MARK: - City picker sheet

private struct ItineraryCityPickerSheet: View {
    let cities: [(code: String, name: String)]
    @Binding var selectedCode: String
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private var filtered: [(code: String, name: String)] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return cities }
        return cities.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            $0.code.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered, id: \.code) { city in
                Button {
                    selectedCode = city.code
                    dismiss()
                } label: {
                    HStack {
                        Text(city.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedCode == city.code {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                                .font(.body.weight(.semibold))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(NSLocalizedString("locationPicker.cities.searchPrompt", comment: "Search cities"))
            )
            .navigationTitle(NSLocalizedString("itinerary.form.city.picker.title", comment: "Choose City sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("common.cancel", comment: "Cancel")) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Helpers

private func iso8601DateOrToday(_ string: String?) -> Date? {
    guard let string else { return nil }
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(identifier: "UTC")
    return f.date(from: string)
}

private func dateToISO8601(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(identifier: "UTC")
    return f.string(from: date)
}

// MARK: - Preview

#Preview("Create") {
    let container = SoloCompassModelContainer.makeInMemory()
    let store = ItineraryStore(context: ModelContext(container))
    return ItineraryFormView(store: store)
        .environment(ExperienceService(seed: []))
}

#Preview("Edit") {
    let container = SoloCompassModelContainer.makeInMemory()
    let store = ItineraryStore(context: ModelContext(container))
    return ItineraryFormView(store: store, editing: .sample)
        .environment(ExperienceService(seed: []))
}
