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

    private var countdownLineColor: Color {
        guard !reduceMotion else { return CT.accent }
        if #available(iOS 18, *) {
            return CT.accent.mix(with: .orange, by: 1 - undoProgress)
        } else {
            return CT.accent
        }
    }

    private var undoBar: some View {
        ZStack(alignment: .bottom) {
            Button {
                performUndo()
            } label: {
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
                    Text(NSLocalizedString("action.undo", comment: "Undo action"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CT.accent)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !reduceMotion {
                GeometryReader { geo in
                    Capsule()
                        .fill(countdownLineColor)
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

// MARK: - TripStatus

private enum TripStatus {
    case active
    case today
    case soon(Int)
    case upcoming(Int)
    case past

    static func from(startDate: String, endDate: String, now: Date = Date()) -> TripStatus {
        guard
            let start = iso8601Date(startDate),
            let end = iso8601Date(endDate)
        else { return .upcoming(0) }

        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let startDay = cal.startOfDay(for: start)
        let endDay = cal.startOfDay(for: end)

        if today >= startDay && today <= endDay {
            if startDay == today { return .today }
            return .active
        }
        if today > endDay { return .past }

        let daysUntil = cal.dateComponents([.day], from: today, to: startDay).day ?? 0
        if daysUntil <= 7 { return .soon(daysUntil) }
        return .upcoming(daysUntil)
    }

    var label: String {
        switch self {
        case .active:
            return NSLocalizedString("itinerary.status.active", comment: "Trip status: active now")
        case .today:
            return NSLocalizedString("itinerary.status.today", comment: "Trip status: starts today")
        case .soon(let d):
            return String(format: NSLocalizedString("itinerary.status.soon", comment: "Trip status: in N days (≤7)"), d)
        case .upcoming(let d):
            return String(format: NSLocalizedString("itinerary.status.upcoming", comment: "Trip status: in N days (>7)"), d)
        case .past:
            return NSLocalizedString("itinerary.status.past", comment: "Trip status: past")
        }
    }

    var color: Color {
        switch self {
        case .active, .today: return .green
        case .soon: return CT.accent
        case .upcoming, .past: return Color(.tertiaryLabel)
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

    private var tripStatus: TripStatus {
        TripStatus.from(startDate: itinerary.startDate, endDate: itinerary.endDate)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(CT.accent.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "map")
                    .font(.body)
                    .foregroundStyle(CT.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(itinerary.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(itinerary.cityCode)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Text(dateRangeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    let status = tripStatus
                    Text(status.label)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(status.color.opacity(0.15), in: Capsule())
                        .foregroundStyle(status.color)
                        .accessibilityHidden(true)
                }

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
            "\(itinerary.title), \(itinerary.cityCode), \(dateRangeText), \(tripStatus.label)"
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
                    .fill(CT.accent.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "map.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(CT.accent.opacity(0.7))
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
    // Active now: spans today (2026-06-02)
    try? store.save(Itinerary(
        id: ItineraryId(rawValue: "itin_preview_active"),
        ownerId: "user_preview",
        title: "Tokyo Spring 2026",
        cityCode: "TYO",
        startDate: "2026-05-30",
        endDate: "2026-06-05",
        experienceIds: [],
        note: "Focus on cherry blossom spots and quiet cafes.",
        openToCompanions: true,
        createdAt: "2026-01-15T09:00:00Z",
        updatedAt: "2026-01-15T09:00:00Z"
    ))
    // Upcoming: starts in 10 days (2026-06-12), shows gray "In 10 days" pill
    try? store.save(Itinerary(
        id: ItineraryId(rawValue: "itin_preview_2"),
        ownerId: "user_preview",
        title: "Kyoto Autumn",
        cityCode: "KYT",
        startDate: "2026-06-12",
        endDate: "2026-06-18",
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
