import SwiftUI
import SwiftData

/// List of the user's saved itineraries, ordered by creation date (newest first).
public struct ItineraryListView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let store: ItineraryStore

    @State private var itineraries: [Itinerary] = []
    @State private var showingCreateForm = false
    @State private var lastDeleted: Itinerary?
    @State private var undoDismissTask: Task<Void, Never>?
    @State private var undoProgress: CGFloat = 1
    @State private var undoDragOffset: CGFloat = 0
    @State private var undoDragCrossedThreshold = false

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
                    EmptyItineraryView(onCreate: { showingCreateForm = true })
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
                    .refreshable { await MainActor.run { loadItineraries() } }
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
        .overlay(alignment: .bottom) {
            if lastDeleted != nil {
                undoBar
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 16)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut, value: lastDeleted != nil)
        .onChange(of: lastDeleted == nil) { _, isNil in
            if isNil { undoDragOffset = 0 }
        }
    }

    private func loadItineraries() {
        Haptics.impact(.light)
        itineraries = store.loadAll()
    }

    private func delete(_ itinerary: Itinerary) {
        let captured = itinerary
        try? store.delete(id: itinerary.id)
        withAnimation(reduceMotion ? nil : .easeInOut) {
            itineraries.removeAll { $0.id == itinerary.id }
        }
        Haptics.notify(.warning)
        undoProgress = 1
        undoDragOffset = 0
        lastDeleted = captured
        undoDismissTask?.cancel()
        undoDismissTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(reduceMotion ? nil : .easeInOut) {
                    lastDeleted = nil
                }
            }
        }
    }

    private func performUndo() {
        guard let saved = lastDeleted else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        undoDismissTask?.cancel()
        undoDismissTask = nil
        try? store.save(saved)
        withAnimation(reduceMotion ? nil : .easeInOut) {
            lastDeleted = nil
        }
        loadItineraries()
    }

    private var undoBar: some View {
        ZStack(alignment: .bottom) {
            HStack {
                Text(String(
                    format: NSLocalizedString("itinerary.undo.named", comment: "Removed named itinerary undo banner"),
                    lastDeleted?.title ?? ""
                ))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                Spacer()
                Button {
                    performUndo()
                } label: {
                    Text(NSLocalizedString("action.undo", comment: "Undo action"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)

            if !reduceMotion {
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * undoProgress, height: 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 2)
                .padding(.horizontal, 2)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .offset(y: undoDragOffset)
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    undoDragOffset = max(0, gesture.translation.height * 0.85)
                    let overThreshold = gesture.translation.height > 80
                    if overThreshold && !undoDragCrossedThreshold {
                        undoDragCrossedThreshold = true
                        Haptics.selection()
                    } else if !overThreshold && undoDragCrossedThreshold {
                        undoDragCrossedThreshold = false
                    }
                }
                .onEnded { gesture in
                    undoDragCrossedThreshold = false
                    if gesture.translation.height > 80 {
                        Haptics.impact(.soft)
                        withAnimation(.easeOut(duration: 0.2)) { undoDragOffset = 300 }
                        undoDismissTask?.cancel()
                        undoDismissTask = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation(.easeInOut) { lastDeleted = nil }
                            undoDragOffset = 0
                        }
                    } else {
                        withAnimation(.spring(response: 0.3)) { undoDragOffset = 0 }
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(String(
            format: NSLocalizedString("itinerary.undo.named.a11y", comment: "Accessibility label for itinerary undo banner"),
            lastDeleted?.title ?? ""
        )))
        .accessibilityAction(named: Text(NSLocalizedString("action.undo", comment: "Undo action"))) {
            performUndo()
        }
        .onAppear {
            undoProgress = 1
            undoDragOffset = 0
            if !reduceMotion {
                withAnimation(.linear(duration: 4)) {
                    undoProgress = 0
                }
            }
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
    var onCreate: (() -> Void)? = nil

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
            if let onCreate {
                Button {
                    Haptics.selection()
                    onCreate()
                } label: {
                    Label(NSLocalizedString("itinerary.empty.cta", comment: "Plan a trip button in empty itinerary state"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.top, 4)
            }
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
    EmptyItineraryView(onCreate: { })
}

#Preview("Empty state — no CTA") {
    EmptyItineraryView()
}
