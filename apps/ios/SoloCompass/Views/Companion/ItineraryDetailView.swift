import SwiftUI

/// Detail view for a single itinerary.
/// Shows all fields: title, city, dates, note, companion toggle, and pinned experiences.
/// Supports drag-to-reorder and "Import from Favorites".
///
/// US-010: the companion toggle is interactive — enabling it prompts for a blurb
/// and categories, then creates a CompanionPost. Disabling it removes the post.
/// When the user's companion visibility is .off, the toggle is blocked with guidance.
public struct ItineraryDetailView: View {
    let itinerary: Itinerary

    @Environment(UserPreferences.self) private var preferences
    @Environment(ExperienceService.self) private var experienceService

    private let store: ItineraryStore
    @State private var experienceIds: [String]
    @State private var openToCompanions: Bool
    @State private var showingImportConfirm = false
    @State private var importedCount: Int?

    // Companion post flow (US-010)
    @State private var showingCompanionPostSheet = false
    @State private var showingVisibilityOffAlert = false
    @State private var showingRemovePostConfirm = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

    public init(itinerary: Itinerary, store: ItineraryStore = ItineraryStore()) {
        self.itinerary = itinerary
        self.store = store
        _experienceIds = State(initialValue: itinerary.experienceIds)
        _openToCompanions = State(initialValue: itinerary.openToCompanions)
    }

    private var formattedStart: String {
        guard let d = iso8601Date(itinerary.startDate) else { return itinerary.startDate }
        return Self.dateFormatter.string(from: d)
    }

    private var formattedEnd: String {
        guard let d = iso8601Date(itinerary.endDate) else { return itinerary.endDate }
        return Self.dateFormatter.string(from: d)
    }

    private var activePost: CompanionPost? {
        preferences.activeCompanionPosts[itinerary.id.rawValue]
    }

    public var body: some View {
        List {
            // MARK: Header section
            Section {
                LabeledDetailRow(
                    label: NSLocalizedString("itinerary.detail.city", comment: "City label"),
                    value: itinerary.cityCode
                )
                LabeledDetailRow(
                    label: NSLocalizedString("itinerary.detail.startDate", comment: "Start date label"),
                    value: formattedStart
                )
                LabeledDetailRow(
                    label: NSLocalizedString("itinerary.detail.endDate", comment: "End date label"),
                    value: formattedEnd
                )
            }

            // MARK: Note section
            if let note = itinerary.note, !note.isEmpty {
                Section(NSLocalizedString("itinerary.detail.note.header", comment: "Notes section header")) {
                    Text(note)
                        .font(.body)
                        .foregroundStyle(.primary)
                }
            }

            // MARK: Companion section (US-010)
            companionSection

            // MARK: Experiences section (drag-to-reorder)
            Section {
                if experienceIds.isEmpty {
                    Text(NSLocalizedString("itinerary.detail.experiences.empty", comment: "No experiences pinned yet"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(experienceIds, id: \.self) { expId in
                        experienceRow(expId)
                    }
                    .onMove(perform: moveExperience)
                }
            } header: {
                HStack {
                    Text(String(
                        format: NSLocalizedString("itinerary.detail.experiences.header", comment: "Experiences header with count"),
                        experienceIds.count
                    ))
                    Spacer()
                    if !preferences.favoritedExperiences.isEmpty {
                        Button {
                            showingImportConfirm = true
                        } label: {
                            Text(NSLocalizedString("itinerary.detail.importFavorites", comment: "Import from favorites button"))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(itinerary.title)
        .navigationBarTitleDisplayMode(.large)
        .environment(\.editMode, .constant(.active))
        .confirmationDialog(
            NSLocalizedString("itinerary.detail.importFavorites.confirm.title", comment: "Import favorites confirm title"),
            isPresented: $showingImportConfirm,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("itinerary.detail.importFavorites.confirm.action", comment: "Import confirm action")) {
                importFavorites()
            }
            Button(NSLocalizedString("action.cancel", comment: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(
                format: NSLocalizedString("itinerary.detail.importFavorites.confirm.message", comment: "Import favorites confirm message"),
                preferences.favoritedExperiences.count
            ))
        }
        .alert(
            NSLocalizedString("companion.post.visibilityOff.title", comment: "Visibility off alert title"),
            isPresented: $showingVisibilityOffAlert
        ) {
            Button(NSLocalizedString("companion.post.visibilityOff.action", comment: "Open profile settings")) {
                // In a full navigation stack this would push CompanionProfileView.
                // For Phase 2 the user can navigate there from Settings.
            }
            Button(NSLocalizedString("action.cancel", comment: "Cancel"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("companion.post.visibilityOff.message", comment: "Visibility off alert message"))
        }
        .sheet(isPresented: $showingCompanionPostSheet) {
            CompanionPostCreationSheet(itinerary: itinerary) { post in
                activateCompanionPost(post)
            }
        }
        .overlay(alignment: .bottom) {
            if let count = importedCount {
                importedToast(count: count)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Experience row

    @ViewBuilder
    private func experienceRow(_ expId: String) -> some View {
        if let exp = experienceService.getExperience(id: expId) {
            HStack(spacing: 12) {
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                ZStack {
                    Circle()
                        .fill(exp.category.color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: exp.category.symbol)
                        .font(.footnote)
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
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("\(exp.title), \(exp.oneLiner)"))
        } else {
            HStack(spacing: 12) {
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(.secondary)
                Text(NSLocalizedString("itinerary.detail.experience.unavailable", comment: "Unavailable experience fallback"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Companion section

    @ViewBuilder
    private var companionSection: some View {
        Section {
            // Interactive toggle (US-010)
            Toggle(
                NSLocalizedString("companion.post.openToCompanions", comment: "Open to companions toggle"),
                isOn: openToCompanionsBinding
            )
            .tint(.accentColor)

            // Show post blurb when active
            if let post = activePost {
                VStack(alignment: .leading, spacing: 4) {
                    Text(post.blurb)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !post.categories.isEmpty {
                        Text(post.categories.map(\.rawValue).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
            }
        } footer: {
            if openToCompanions {
                Text(NSLocalizedString("companion.post.openToCompanions.footer", comment: "Open to companions footer"))
                    .font(.caption)
            }
        }
    }

    private var openToCompanionsBinding: Binding<Bool> {
        Binding(
            get: { openToCompanions },
            set: { newValue in
                if newValue {
                    // Block if visibility is off
                    guard preferences.companionVisibility != .off else {
                        showingVisibilityOffAlert = true
                        return
                    }
                    // Show blurb+categories sheet
                    showingCompanionPostSheet = true
                } else {
                    removeCompanionPost()
                }
            }
        )
    }

    // MARK: - Actions

    private func activateCompanionPost(_ post: CompanionPost) {
        openToCompanions = true
        preferences.activeCompanionPosts[itinerary.id.rawValue] = post
        // Persist openToCompanions on the itinerary value
        let now = ISO8601DateFormatter().string(from: Date())
        let updated = Itinerary(
            id: itinerary.id,
            ownerId: itinerary.ownerId,
            title: itinerary.title,
            cityCode: itinerary.cityCode,
            startDate: itinerary.startDate,
            endDate: itinerary.endDate,
            experienceIds: itinerary.experienceIds,
            note: itinerary.note,
            openToCompanions: true,
            createdAt: itinerary.createdAt,
            updatedAt: now
        )
        try? store.update(updated)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func removeCompanionPost() {
        openToCompanions = false
        preferences.activeCompanionPosts.removeValue(forKey: itinerary.id.rawValue)
        let now = ISO8601DateFormatter().string(from: Date())
        let updated = Itinerary(
            id: itinerary.id,
            ownerId: itinerary.ownerId,
            title: itinerary.title,
            cityCode: itinerary.cityCode,
            startDate: itinerary.startDate,
            endDate: itinerary.endDate,
            experienceIds: itinerary.experienceIds,
            note: itinerary.note,
            openToCompanions: false,
            createdAt: itinerary.createdAt,
            updatedAt: now
        )
        try? store.update(updated)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func moveExperience(from source: IndexSet, to destination: Int) {
        var ids = experienceIds
        ids.move(fromOffsets: source, toOffset: destination)
        experienceIds = ids
        try? store.reorderExperiences(ids, in: itinerary.id)
    }

    private func importFavorites() {
        let favIds = preferences.favoritedExperiences
        guard let count = try? store.importFavorites(favIds, into: itinerary.id), count > 0 else { return }
        experienceIds = store.load(id: itinerary.id)?.experienceIds ?? experienceIds
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { importedCount = count }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { importedCount = nil }
        }
    }

    private func importedToast(count: Int) -> some View {
        Text(String(
            format: NSLocalizedString("itinerary.detail.importFavorites.toast", comment: "Import favorites success toast"),
            count
        ))
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color(.systemBackground)).shadow(radius: 4))
        .foregroundStyle(.primary)
    }
}

// MARK: - Companion post creation sheet (US-010)

/// Sheet for entering blurb + categories before enabling the companion post.
private struct CompanionPostCreationSheet: View {
    let itinerary: Itinerary
    let onConfirm: (CompanionPost) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var blurb = ""
    @State private var selectedCategories: Set<ExperienceCategory> = []

    private var isValid: Bool { !blurb.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        NSLocalizedString("companion.post.blurb.placeholder", comment: "Blurb placeholder"),
                        text: $blurb,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                    .onChange(of: blurb) { _, new in
                        if new.count > 280 { blurb = String(new.prefix(280)) }
                    }
                } header: {
                    Text(NSLocalizedString("companion.post.blurb.header", comment: "Blurb section header"))
                }

                Section {
                    ForEach(ExperienceCategory.allCases, id: \.self) { cat in
                        Button {
                            if selectedCategories.contains(cat) {
                                selectedCategories.remove(cat)
                            } else {
                                selectedCategories.insert(cat)
                            }
                        } label: {
                            HStack {
                                Text(cat.rawValue.capitalized)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedCategories.contains(cat) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                        .font(.footnote.weight(.semibold))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(NSLocalizedString("companion.post.categories.header", comment: "Categories section header"))
                }
            }
            .navigationTitle(NSLocalizedString("companion.post.openToCompanions", comment: "Sheet nav title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("action.cancel", comment: "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("itinerary.form.action.save", comment: "Save")) {
                        confirm()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func confirm() {
        let now = ISO8601DateFormatter().string(from: Date())
        let post = CompanionPost(
            id: CompanionPostId(rawValue: UUID().uuidString),
            authorId: "local",
            mode: .itinerary,
            itineraryId: itinerary.id,
            blurb: blurb.trimmingCharacters(in: .whitespaces),
            categories: Array(selectedCategories),
            cityCode: itinerary.cityCode,
            activeFrom: itinerary.startDate,
            activeTo: itinerary.endDate,
            createdAt: now,
            updatedAt: now
        )
        onConfirm(post)
        dismiss()
    }
}

// MARK: - Subviews

private struct LabeledDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Helpers

private func iso8601Date(_ string: String) -> Date? {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(identifier: "UTC")
    return f.date(from: string)
}

// MARK: - Preview

#Preview("With note and experiences") {
    NavigationStack {
        ItineraryDetailView(itinerary: Itinerary(
            id: ItineraryId(rawValue: "itin_preview"),
            ownerId: "user_preview",
            title: "Tokyo Spring 2026",
            cityCode: "TYO",
            startDate: "2026-04-01",
            endDate: "2026-04-10",
            experienceIds: ["exp_cmi_suan_dok_sunset", "exp_cmi_nimman_coffee", "exp_cmi_bookstore_work"],
            note: "Focus on cherry blossom spots and quiet cafes.",
            openToCompanions: true,
            createdAt: "2026-01-15T09:00:00Z",
            updatedAt: "2026-01-15T09:00:00Z"
        ))
    }
    .environment(UserPreferences())
    .environment(ExperienceService(seed: ExperienceService.hardcodedSeed))
}

#Preview("Open to companions, no experiences") {
    NavigationStack {
        ItineraryDetailView(itinerary: Itinerary(
            id: ItineraryId(rawValue: "itin_preview_b"),
            ownerId: "user_preview",
            title: "Bali Retreat",
            cityCode: "DPS",
            startDate: "2026-06-10",
            endDate: "2026-06-20",
            experienceIds: [],
            note: nil,
            openToCompanions: true,
            createdAt: "2026-03-01T09:00:00Z",
            updatedAt: "2026-03-01T09:00:00Z"
        ))
    }
    .environment(UserPreferences())
    .environment(ExperienceService(seed: ExperienceService.hardcodedSeed))
}

#Preview("Visibility off — toggle blocked") {
    let prefs = UserPreferences()
    prefs.companionVisibility = .off
    return NavigationStack {
        ItineraryDetailView(itinerary: Itinerary(
            id: ItineraryId(rawValue: "itin_preview_c"),
            ownerId: "user_preview",
            title: "Seoul Week",
            cityCode: "SEL",
            startDate: "2026-09-01",
            endDate: "2026-09-07",
            experienceIds: [],
            note: nil,
            openToCompanions: false,
            createdAt: "2026-05-01T09:00:00Z",
            updatedAt: "2026-05-01T09:00:00Z"
        ))
    }
    .environment(prefs)
    .environment(ExperienceService(seed: ExperienceService.hardcodedSeed))
}
