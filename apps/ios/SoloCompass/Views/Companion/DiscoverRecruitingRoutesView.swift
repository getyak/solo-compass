import SwiftUI
import SwiftData

/// US-032: Browse recruiting routes ranked by departure-soon + verified + city-match.
///
/// Data source: RouteStore.all() filtered to .open or .forming companion slots.
/// Sort: departure-within-7-days (weight 3) + verified (weight 2) + city-match (weight 1).
public struct DiscoverRecruitingRoutesView: View {
    @Environment(UserPreferences.self) private var preferences

    /// Injected for testability; defaults to a live RouteStore in production.
    private let storeProvider: () -> RouteStore

    /// Optional current city code used for the city-match scoring weight.
    var currentCityCode: String?

    public init(
        currentCityCode: String? = nil,
        storeProvider: @escaping () -> RouteStore = { RouteStore() }
    ) {
        self.currentCityCode = currentCityCode
        self.storeProvider = storeProvider
    }

    // Computed once per body evaluation — the store fetch is cheap.
    private var sortedRoutes: [Route] {
        let store = storeProvider()
        let recruiting = store.all().filter {
            $0.companion?.status == .open || $0.companion?.status == .forming
        }
        return recruiting.sorted { score($0) > score($1) }
    }

    public var body: some View {
        Group {
            if sortedRoutes.isEmpty {
                emptyState
            } else {
                routeList
            }
        }
        .navigationTitle(
            NSLocalizedString("discover.recruiting.title", comment: "Discover Recruiting Routes nav title")
        )
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Subviews

    private var routeList: some View {
        // A plain ScrollView + LazyVStack of self-chromed RouteCards (matching the
        // bottom-sheet routes section) rather than an inset-grouped List. The old
        // List wrapped each already-carded RouteCard in a second grouped-cell
        // background and used a -16 negative-inset hack to claw the card back to
        // full width — a fragile double-card look. RouteCard already surfaces the
        // recruit slot (host · N/M · departure · 查看), so the separate slot chip
        // is dropped as redundant.
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(sortedRoutes) { route in
                    NavigationLink {
                        RouteDetailView(route: route)
                    } label: {
                        RouteCard(route: route, companionOn: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(CT.bgWarm)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                NSLocalizedString(
                    "discover.recruiting.empty.title",
                    comment: "Empty state title — no recruiting routes"
                ),
                systemImage: "map"
            )
        } description: {
            Text(
                NSLocalizedString(
                    "discover.recruiting.empty.description",
                    comment: "Empty state description"
                )
            )
        } actions: {
            Button {
                // Stub — wired up in a later story.
            } label: {
                Text(
                    NSLocalizedString(
                        "discover.recruiting.empty.create",
                        comment: "Empty state secondary action — start your own route"
                    )
                )
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Composite scoring

    /// Returns a composite score for sorting.
    /// departure-within-7-days: weight 3
    /// verified: weight 2
    /// city-matches-current-city: weight 1
    private func score(_ route: Route) -> Int {
        var points = 0

        if let companion = route.companion {
            if departureWithin7Days(companion.departureWindow) {
                points += 3
            }
        }

        if route.verification.status == .verified {
            points += 2
        }

        if let city = currentCityCode, route.cityCode == city {
            points += 1
        }

        return points
    }

    private func departureWithin7Days(_ window: DepartureWindow) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        guard let fromDate = formatter.date(from: window.from) else { return false }
        let now = Date()
        let sevenDaysOut = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        return fromDate >= now && fromDate <= sevenDaysOut
    }
}

// MARK: - Preview

#Preview("With recruiting routes") {
    let container = try! ModelContainer(for: RouteRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    let store = RouteStore(context: context)

    let mekong = Route(
        id: RouteId(rawValue: "mekong-sunset"),
        title: "Mekong Sunset",
        summary: "Promenade along the river at golden hour.",
        experienceIds: ["exp_vte_mekong_riverside_sunset"],
        cityCode: "VTE",
        region: "Riverfront",
        estimatedDuration: 90,
        distanceMeters: 1200,
        pace: .relaxed,
        tags: ["sunset", "river"],
        source: .editorial,
        verification: RouteVerification(status: .walkedBy, walkedByCount: 12, walkedBy: ["maya"]),
        companion: RouteCompanion(
            status: .open,
            hostId: "maya",
            departureWindow: DepartureWindow(
                startDate: ISO8601DateFormatter().string(from: Date().addingTimeInterval(3 * 86400)).prefix(10).description,
                to: ISO8601DateFormatter().string(from: Date().addingTimeInterval(5 * 86400)).prefix(10).description,
                time: "17:00"
            ),
            departureLabel: "Early June evenings",
            maxMembers: 4,
            confirmedMembers: ["maya", "lin"]
        )
    )

    let coffee = Route(
        id: RouteId(rawValue: "slow-coffee-day"),
        title: "Slow Coffee Day",
        summary: "Old quarter cloisters then Bolaven beans.",
        experienceIds: ["exp_vte_wat_si_saket_morning", "exp_vte_slow_coffee_dao"],
        cityCode: "VTE",
        region: "Old Quarter",
        estimatedDuration: 180,
        distanceMeters: 1800,
        pace: .relaxed,
        tags: ["coffee"],
        source: .editorial,
        verification: RouteVerification(status: .proposed, walkedByCount: 0, walkedBy: []),
        companion: RouteCompanion(
            status: .forming,
            hostId: "lin",
            departureWindow: DepartureWindow(
                startDate: "2026-06-07",
                to: "2026-06-08",
                time: "morning"
            ),
            departureLabel: "Weekend mornings",
            maxMembers: 4,
            confirmedMembers: ["lin", "tomas", "ren"]
        )
    )

    store.save(mekong)
    store.save(coffee)

    return NavigationStack {
        DiscoverRecruitingRoutesView(
            currentCityCode: "VTE",
            storeProvider: { store }
        )
    }
    .modelContainer(container)
    .environment(UserPreferences())
}

#Preview("Empty state") {
    NavigationStack {
        DiscoverRecruitingRoutesView(
            currentCityCode: "TYO",
            storeProvider: { RouteStore(context: ModelContext(try! ModelContainer(for: RouteRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))) }
        )
    }
    .environment(UserPreferences())
}
