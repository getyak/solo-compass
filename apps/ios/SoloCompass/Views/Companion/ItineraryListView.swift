import SwiftUI
import SwiftData

/// List of the user's saved itineraries, ordered by creation date (newest first).
public struct ItineraryListView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let store: ItineraryStore

    @State private var itineraries: [Itinerary] = []
    @State private var showingCreateForm = false

    /// Production init using the shared on-disk container.
    public init() {
        self.store = ItineraryStore()
    }

    /// Testable/preview init accepting an injected store.
    init(store: ItineraryStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Group {
                if itineraries.isEmpty {
                    EmptyItineraryView()
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                } else {
                    List(itineraries) { itinerary in
                        NavigationLink(
                            destination: ItineraryDetailView(itinerary: itinerary, store: store)
                        ) {
                            ItineraryRow(itinerary: itinerary)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                delete(itinerary)
                            } label: {
                                Label(
                                    NSLocalizedString("itinerary.action.delete", comment: "Delete itinerary"),
                                    systemImage: "trash"
                                )
                            }
                        }
                    }
                    .listStyle(.plain)
                    .animation(.easeInOut, value: itineraries.count)
                }
            }
            .animation(.easeInOut, value: itineraries.isEmpty)
            .navigationTitle(NSLocalizedString("itinerary.list.title", comment: "My Itineraries nav title"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCreateForm = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(NSLocalizedString("itinerary.action.create.a11y", comment: "Create new itinerary"))
                }
            }
            .sheet(isPresented: $showingCreateForm, onDismiss: loadItineraries) {
                ItineraryFormView(store: store)
            }
        }
        .onAppear(perform: loadItineraries)
    }

    private func loadItineraries() {
        itineraries = store.loadAll()
    }

    private func delete(_ itinerary: Itinerary) {
        try? store.delete(id: itinerary.id)
        withAnimation(.easeInOut) {
            itineraries.removeAll { $0.id == itinerary.id }
        }
    }
}

// MARK: - Row

private struct ItineraryRow: View {
    let itinerary: Itinerary

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private var dateRangeText: String {
        guard
            let start = iso8601Date(itinerary.startDate),
            let end = iso8601Date(itinerary.endDate)
        else { return "\(itinerary.startDate) – \(itinerary.endDate)" }
        return "\(Self.dateFormatter.string(from: start)) – \(Self.dateFormatter.string(from: end))"
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "map")
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(itinerary.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(itinerary.cityCode)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(dateRangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(String(
                    format: NSLocalizedString("itinerary.experienceCount", comment: "N experiences"),
                    itinerary.experienceIds.count
                ))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 1)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(
            "\(itinerary.title), \(itinerary.cityCode), \(dateRangeText)"
        ))
    }
}

// MARK: - Empty state

private struct EmptyItineraryView: View {
    @State private var isBreathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "map.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
                    .scaleEffect(isBreathing ? 1.08 : 0.94)
                    .opacity(isBreathing ? 1.0 : 0.7)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                        value: isBreathing
                    )
            }
            Text(NSLocalizedString("itinerary.empty.title", comment: "No itineraries yet"))
                .font(.headline)
            Text(NSLocalizedString("itinerary.empty.hint", comment: "Tap + to plan your first trip"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !isBreathing, !reduceMotion else { return }
            isBreathing = true
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

#Preview("With itineraries") {
    let container = SoloCompassModelContainer.makeInMemory()
    let store = ItineraryStore(context: ModelContext(container))
    try? store.save(.sample)
    try? store.save(Itinerary(
        id: ItineraryId(rawValue: "itin_preview_2"),
        ownerId: "user_preview",
        title: "Kyoto Autumn",
        cityCode: "KYT",
        startDate: "2026-11-01",
        endDate: "2026-11-07",
        experienceIds: ["exp_1", "exp_2", "exp_3"],
        openToCompanions: false,
        createdAt: "2026-02-01T09:00:00Z",
        updatedAt: "2026-02-01T09:00:00Z"
    ))
    return ItineraryListView(store: store)
        .environment(ExperienceService(seed: []))
        .environment(UserPreferences())
}

#Preview("Empty state") {
    ItineraryListView(store: ItineraryStore(context: ModelContext(SoloCompassModelContainer.makeInMemory())))
        .environment(ExperienceService(seed: []))
        .environment(UserPreferences())
}
