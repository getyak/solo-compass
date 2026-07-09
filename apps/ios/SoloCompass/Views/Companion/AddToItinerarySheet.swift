import SwiftUI
import SwiftData

/// Sheet that lets the user pin an experience to one of their saved itineraries,
/// or create a new itinerary and pin it in one step.
public struct AddToItinerarySheet: View {
    let experienceId: String
    let experienceTitle: String
    /// Called after a successful add, with the itinerary that was updated.
    /// The sheet dismisses itself before invoking this.
    var onSuccess: ((Itinerary) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(ExperienceService.self) private var experienceService

    private let store: ItineraryStore
    @State private var itineraries: [Itinerary] = []
    @State private var showingCreateForm = false
    @State private var addedToId: ItineraryId?
    @State private var errorMessage: String?

    public init(
        experienceId: String,
        experienceTitle: String,
        store: ItineraryStore = ItineraryStore(),
        onSuccess: ((Itinerary) -> Void)? = nil
    ) {
        self.experienceId = experienceId
        self.experienceTitle = experienceTitle
        self.store = store
        self.onSuccess = onSuccess
    }

    public var body: some View {
        NavigationStack {
            Group {
                if itineraries.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            ForEach(itineraries) { itin in
                                itineraryRow(itin)
                            }
                        }
                        Section {
                            createNewRow
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(NSLocalizedString("itinerary.addTo.title", comment: "Add to Itinerary sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("common.cancel", comment: "Cancel")) { dismiss() }
                }
            }
            .sheet(isPresented: $showingCreateForm, onDismiss: {
                reload()
                // If a new itinerary was created, try to pin the experience into it.
                if let newest = store.loadAll().first {
                    addExperience(to: newest)
                }
            }) {
                ItineraryFormView(store: store)
                    .environment(experienceService)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear(perform: reload)
        .alert(
            NSLocalizedString("itinerary.addTo.error.title", comment: "Error alert title when pinning fails"),
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button(NSLocalizedString("common.ok", comment: "OK")) { errorMessage = nil }
        } message: {
            if let msg = errorMessage { Text(msg) }
        }
    }

    // MARK: - Rows

    private func itineraryRow(_ itin: Itinerary) -> some View {
        let alreadyAdded = itin.experienceIds.contains(experienceId)
        let wasJustAdded = addedToId == itin.id

        return Button {
            guard !alreadyAdded else { return }
            addExperience(to: itin)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(CT.accent.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: alreadyAdded ? "checkmark" : "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(alreadyAdded ? CT.verifiedGreen : CT.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(itin.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(itin.cityCode)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if wasJustAdded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(CT.verifiedGreen)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(alreadyAdded)
        .accessibilityLabel(Text(alreadyAdded
            ? String(format: NSLocalizedString("itinerary.addTo.alreadyAdded", comment: "Already in itinerary"), itin.title)
            : String(format: NSLocalizedString("itinerary.addTo.addToNamed", comment: "Add to itinerary name"), itin.title)
        ))
    }

    private var createNewRow: some View {
        Button {
            showingCreateForm = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: "plus.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(NSLocalizedString("itinerary.addTo.createNew", comment: "Create new itinerary option"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "map")
                .font(.system(size: 40))
                .foregroundStyle(CT.accent.opacity(0.6))
            Text(NSLocalizedString("itinerary.addTo.noItineraries", comment: "No itineraries empty state"))
                .font(.headline)
            Text(NSLocalizedString("itinerary.addTo.noItineraries.hint", comment: "Create one hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showingCreateForm = true
            } label: {
                Text(NSLocalizedString("itinerary.addTo.createFirst", comment: "Create first itinerary CTA"))
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(CT.accent))
                    .foregroundStyle(.white)
            }
        }
        .padding(32)
        .sheet(isPresented: $showingCreateForm, onDismiss: {
            reload()
            if let newest = store.loadAll().first {
                addExperience(to: newest)
            }
        }) {
            ItineraryFormView(store: store)
                .environment(experienceService)
        }
    }

    // MARK: - Helpers

    private func reload() {
        itineraries = store.loadAll()
    }

    private func addExperience(to itin: Itinerary) {
        do {
            try store.addExperience(experienceId, to: itin.id)
            Haptics.notify(.success)
            withAnimation { addedToId = itin.id }
            reload()
            // Capture the updated itinerary for the success callback.
            let updated = store.load(id: itin.id) ?? itin
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onSuccess?(updated)
                }
            }
        } catch {
            Haptics.notify(.error)
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Preview

#Preview {
    let container = SoloCompassModelContainer.makeInMemory()
    let store = ItineraryStore(context: ModelContext(container))
    try? store.save(.sample)
    return AddToItinerarySheet(
        experienceId: "exp_preview",
        experienceTitle: "Doi Suthep Temple",
        store: store
    )
    .environment(ExperienceService(seed: ExperienceService.hardcodedSeed))
}
