import SwiftUI
import SwiftData

/// Create or edit an Itinerary.
///
/// Pass an existing `Itinerary` to edit it; omit to create a new one. New
/// itineraries are prefilled with a localized suggested title, the source
/// experience's city, and the current date. Editing never overwrites saved
/// values. The store is injected so previews can supply an in-memory container.
///
/// `onSaved` receives the exact itinerary that was persisted. It runs only
/// after the write succeeds, letting `AddToItinerarySheet` pin the source
/// experience without guessing or timing hacks. When `onSaved` is nil the form
/// dismisses itself on success.
public struct ItineraryFormView: View {
    let store: ItineraryStore
    let editing: Itinerary?
    let sourceCityCode: String?
    let pinnedExperienceIds: [String]
    let embedInNavigationStack: Bool
    let onSaved: ((Itinerary) -> Void)?
    let onCancel: (() -> Void)?
    @State private var showingCityPicker = false

    @Environment(ExperienceService.self) private var experienceService
    @Environment(\.dismiss) private var dismiss

    @State private var model: ItineraryCreationFormModel

    // MARK: - Init

    public init(
        store: ItineraryStore,
        editing: Itinerary? = nil,
        sourceCityCode: String? = nil,
        pinnedExperienceIds: [String] = [],
        embedInNavigationStack: Bool = true,
        now: Date = Date(),
        onSaved: ((Itinerary) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.store = store
        self.editing = editing
        self.sourceCityCode = sourceCityCode
        self.pinnedExperienceIds = pinnedExperienceIds
        self.embedInNavigationStack = embedInNavigationStack
        self.onSaved = onSaved
        self.onCancel = onCancel

        let draft = ItineraryCreationRules.initialDraft(
            editing: editing,
            sourceCityCode: sourceCityCode,
            now: now,
            suggestedTitle: Self.suggestedTitle(now: now)
        )
        _model = State(initialValue: ItineraryCreationFormModel(
            flow: ItineraryCreationFlow(store: store),
            editing: editing,
            pinnedExperienceIds: pinnedExperienceIds,
            draft: draft
        ))
    }

    // MARK: - Derived

    private var isEditing: Bool { editing != nil }

    private var availableCities: [(code: String, name: String)] {
        var seen = Set<String>()
        return experienceService.allExperiences.compactMap { exp -> (code: String, name: String)? in
            let code = exp.location.cityCode
            guard seen.insert(code).inserted else { return nil }
            let canonical = MapViewModel.cityCodeAliases[code.lowercased()] ?? code
            return (code, MapViewModel.cityNameMap[canonical] ?? MapViewModel.cityNameMap[code] ?? code)
        }.sorted { $0.name < $1.name }
    }

    private func cityDisplayName(for code: String) -> String {
        guard !code.isEmpty else {
            return NSLocalizedString("itinerary.form.city.picker.title", comment: "Choose City placeholder")
        }
        let canonical = MapViewModel.cityCodeAliases[code.lowercased()] ?? code.lowercased()
        return availableCities.first(where: { MapViewModel.cityCodeMatches($0.code, selected: code) })?.name
            ?? MapViewModel.cityNameMap[canonical] ?? code
    }

    /// Localized, date-stamped suggestion for a brand-new itinerary.
    private static func suggestedTitle(now: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let dateText = formatter.string(from: now)
        return String(
            format: NSLocalizedString(
                "itinerary.form.suggestedTitle",
                comment: "Editable suggested title for a new itinerary, with the current date"
            ),
            dateText
        )
    }

    // MARK: - Body

    public var body: some View {
        @Bindable var model = model
        Group {
            if embedInNavigationStack {
                NavigationStack {
                    formContent(model: $model)
                }
            } else {
                formContent(model: $model)
            }
        }
    }

    // MARK: - Form

    @ViewBuilder
    private func formContent(model: Bindable<ItineraryCreationFormModel>) -> some View {
        Form {
            basicsSection(model: model)
            datesSection(model: model)
            companionSection(model: model)
            noteSection(model: model)

            if model.wrappedValue.endBeforeStart {
                Section {
                    Text(NSLocalizedString(
                        "itinerary.form.validation.endBeforeStart",
                        comment: "End before start validation error"
                    ))
                    .foregroundStyle(CT.savedRed)
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
            // `.cancellationAction` / `.confirmationAction` let the system
            // place Cancel (leading) and Save (trailing) per-platform
            // convention, instead of hard-coding topBarLeading/Trailing.
            ToolbarItem(placement: .cancellationAction) {
                Button(NSLocalizedString("itinerary.form.action.cancel", comment: "Cancel")) {
                    model.wrappedValue.cancel()
                    if let onCancel { onCancel() } else { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(NSLocalizedString("itinerary.form.action.save", comment: "Save")) {
                    save()
                }
                .fontWeight(.semibold)
                .disabled(!model.wrappedValue.isValid)
            }
        }
        .navigationDestination(isPresented: $showingCityPicker) {
            ItineraryCityPickerView(
                cities: availableCities,
                selectedCode: model.draft.cityCode,
                onSelect: { showingCityPicker = false }
            )
        }
        // Block accidental swipe-to-dismiss while there are unsaved edits; the
        // explicit Cancel stays the deliberate exit. This matters when the form
        // is itself presented as a sheet (ItineraryListView); when it is pushed
        // inside another stack the modifier is a harmless no-op.
        .interactiveDismissDisabled(model.wrappedValue.isDirty)
        .alert(
            NSLocalizedString("itinerary.form.save.error.title", comment: "Save failure alert title"),
            isPresented: Binding(
                get: { model.wrappedValue.saveErrorMessage != nil },
                set: { if !$0 { model.wrappedValue.clearSaveError() } }
            )
        ) {
            Button(NSLocalizedString("common.ok", comment: "OK")) {
                model.wrappedValue.clearSaveError()
            }
        } message: {
            if let message = model.wrappedValue.saveErrorMessage {
                Text(message)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func basicsSection(model: Bindable<ItineraryCreationFormModel>) -> some View {
        Section(NSLocalizedString("itinerary.form.section.basics", comment: "Trip details section header")) {
            HStack {
                Text(NSLocalizedString("itinerary.form.field.title", comment: "Title field label"))
                TextField(
                    NSLocalizedString("itinerary.form.field.title.placeholder", comment: "Title placeholder"),
                    text: model.draft.title
                )
                .multilineTextAlignment(.trailing)
            }

            Button { showingCityPicker = true } label: {
                HStack {
                    Text(NSLocalizedString("itinerary.form.field.city", comment: "City field label"))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(cityDisplayName(for: model.wrappedValue.draft.cityCode))
                        .foregroundStyle(model.wrappedValue.draft.cityCode.isEmpty ? .secondary : .primary)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func datesSection(model: Bindable<ItineraryCreationFormModel>) -> some View {
        Section(NSLocalizedString("itinerary.form.section.dates", comment: "Dates section header")) {
            DatePicker(
                NSLocalizedString("itinerary.form.field.startDate", comment: "Start date picker label"),
                selection: model.draft.startDate,
                displayedComponents: .date
            )
            .onChange(of: model.wrappedValue.draft.startDate) { _, newStart in
                if model.wrappedValue.draft.endDate < newStart {
                    model.wrappedValue.draft.endDate = newStart
                }
            }

            DatePicker(
                NSLocalizedString("itinerary.form.field.endDate", comment: "End date picker label"),
                selection: model.draft.endDate,
                in: model.wrappedValue.draft.startDate...,
                displayedComponents: .date
            )
        }
    }

    @ViewBuilder
    private func companionSection(model: Bindable<ItineraryCreationFormModel>) -> some View {
        Section(NSLocalizedString("itinerary.form.section.companion", comment: "Companion mode section header")) {
            Toggle(
                NSLocalizedString("itinerary.form.field.openToCompanions", comment: "Open to companions toggle"),
                isOn: model.draft.openToCompanions
            )
        }
    }

    @ViewBuilder
    private func noteSection(model: Bindable<ItineraryCreationFormModel>) -> some View {
        Section {
            TextField(
                NSLocalizedString("itinerary.form.field.note.placeholder", comment: "Notes placeholder"),
                text: model.draft.note,
                axis: .vertical
            )
            .lineLimit(3...6)
        } header: {
            Text(NSLocalizedString("itinerary.form.field.note", comment: "Notes section header"))
        }
    }

    // MARK: - Save

    private func save() {
        // `saveAndNotify` only invokes the callback after the store write
        // succeeded, so a failure leaves the form open with recoverable
        // feedback instead of silently pinning anything.
        let saved = model.saveAndNotify { itinerary in
            onSaved?(itinerary)
        }
        guard saved != nil else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // A caller-provided `onSaved` owns the next step (e.g. dismissing the
        // whole add-to-itinerary sheet); otherwise the form dismisses itself.
        if onSaved == nil {
            dismiss()
        }
    }
}

// MARK: - City picker

/// Searchable city list, pushed inside the form's navigation stack so city
/// selection never nests a modal on top of the create/edit form.
private struct ItineraryCityPickerView: View {
    let cities: [(code: String, name: String)]
    @Binding var selectedCode: String
    let onSelect: () -> Void
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
        List(filtered, id: \.code) { city in
            Button {
                selectedCode = city.code
                onSelect()
            } label: {
                HStack {
                    Text(city.name)
                        .foregroundStyle(.primary)
                    Spacer()
                    if MapViewModel.cityCodeMatches(city.code, selected: selectedCode) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(CT.accent)
                            .font(.body.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
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
    }
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
