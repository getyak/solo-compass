import SwiftUI

/// Detail view for a single itinerary.
/// Shows all fields: title, city, dates, note, companion toggle, and pinned experiences.
/// Supports drag-to-reorder and "Import from Favorites".
public struct ItineraryDetailView: View {
    let itinerary: Itinerary

    @Environment(UserPreferences.self) private var preferences

    private let store: ItineraryStore
    @State private var experienceIds: [String]
    @State private var showingImportConfirm = false
    @State private var importedCount: Int?

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
    }

    private var formattedStart: String {
        guard let d = iso8601Date(itinerary.startDate) else { return itinerary.startDate }
        return Self.dateFormatter.string(from: d)
    }

    private var formattedEnd: String {
        guard let d = iso8601Date(itinerary.endDate) else { return itinerary.endDate }
        return Self.dateFormatter.string(from: d)
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

            // MARK: Companion section
            Section(NSLocalizedString("itinerary.detail.companion.header", comment: "Companions section header")) {
                HStack {
                    Image(systemName: itinerary.openToCompanions ? "person.2.fill" : "person.fill")
                        .foregroundStyle(itinerary.openToCompanions ? Color.accentColor : .secondary)
                        .frame(width: 24)
                    Text(
                        itinerary.openToCompanions
                        ? NSLocalizedString("itinerary.detail.companion.open", comment: "Open to companions")
                        : NSLocalizedString("itinerary.detail.companion.solo", comment: "Going solo")
                    )
                    .font(.body)
                    .foregroundStyle(.primary)
                }
            }

            // MARK: Experiences section (drag-to-reorder)
            Section {
                if experienceIds.isEmpty {
                    Text(NSLocalizedString("itinerary.detail.experiences.empty", comment: "No experiences pinned yet"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(experienceIds, id: \.self) { expId in
                        HStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(Color.accentColor)
                            Text(expId)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
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
        .overlay(alignment: .bottom) {
            if let count = importedCount {
                importedToast(count: count)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Actions

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
            experienceIds: ["exp_001", "exp_002", "exp_003"],
            note: "Focus on cherry blossom spots and quiet cafes.",
            openToCompanions: true,
            createdAt: "2026-01-15T09:00:00Z",
            updatedAt: "2026-01-15T09:00:00Z"
        ))
    }
    .environment(UserPreferences())
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
}
