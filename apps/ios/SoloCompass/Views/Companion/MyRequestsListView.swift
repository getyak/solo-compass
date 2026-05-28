import SwiftUI
import SwiftData

// MARK: - MyRequestsListView

/// US-033: Applicant view of own pending join requests.
///
/// Data source: RouteStore.all() → filter routes with a companion slot →
/// for each route, collect JoinRequests where requesterId == deviceId.
/// Each row shows a RouteCard thumbnail, a status chip, a View Route chevron,
/// and (if pending) a swipe-to-withdraw action.
public struct MyRequestsListView: View {

    /// Injected for testability; defaults to a live RouteStore in production.
    private let storeProvider: () -> RouteStore

    @State private var refreshToken: UUID = UUID()

    public init(storeProvider: @escaping () -> RouteStore = { RouteStore() }) {
        self.storeProvider = storeProvider
    }

    private var deviceId: String {
        DeviceIdentityService.shared.deviceID
    }

    // (Route, JoinRequest) pairs where requesterId == deviceId.
    private var myRequests: [(Route, JoinRequest)] {
        _ = refreshToken
        let store = storeProvider()
        return store.all().flatMap { route -> [(Route, JoinRequest)] in
            guard let companion = route.companion else { return [] }
            return companion.joinRequests
                .filter { $0.requesterId == deviceId }
                .map { (route, $0) }
        }
    }

    public var body: some View {
        Group {
            if myRequests.isEmpty {
                emptyState
            } else {
                requestList
            }
        }
        .navigationTitle(NSLocalizedString(
            "settings.companion.requests",
            comment: "My recruitment requests title"
        ))
        .navigationBarTitleDisplayMode(.large)
        .onReceive(NotificationCenter.default.publisher(for: RouteStore.didChange)) { _ in
            refreshToken = UUID()
        }
    }

    // MARK: - List

    private var requestList: some View {
        List {
            ForEach(myRequests, id: \.1.id) { route, request in
                row(route: route, request: request)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if request.status == .pending {
                            Button(role: .destructive) {
                                withdraw(request: request, from: route)
                            } label: {
                                Label(
                                    NSLocalizedString(
                                        "my.requests.withdraw",
                                        comment: "Swipe action — withdraw join request"
                                    ),
                                    systemImage: "arrow.uturn.backward"
                                )
                            }
                            .tint(.orange)
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Row

    private func row(route: Route, request: JoinRequest) -> some View {
        NavigationLink {
            RouteDetailView(route: route)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                RouteCard(route: route)
                    .padding(.horizontal, -16)

                statusChip(for: request.status)
                    .padding(.leading, 54)
                    .padding(.bottom, 4)
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }

    // MARK: - Status chip

    @ViewBuilder
    private func statusChip(for status: JoinRequestStatus) -> some View {
        let (label, color) = chipAttributes(for: status)
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }

    private func chipAttributes(for status: JoinRequestStatus) -> (String, Color) {
        switch status {
        case .pending:
            return (
                NSLocalizedString("my.requests.status.pending", comment: "Pending status chip"),
                Color.orange
            )
        case .accepted:
            return (
                NSLocalizedString("my.requests.status.accepted", comment: "Accepted status chip"),
                Color.green
            )
        case .declined:
            return (
                NSLocalizedString("my.requests.status.declined", comment: "Declined status chip"),
                Color.secondary
            )
        case .withdrawn:
            return (
                NSLocalizedString("my.requests.status.withdrawn", comment: "Withdrawn status chip"),
                Color.secondary
            )
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        List {
            Text(NSLocalizedString(
                "my.requests.empty",
                comment: "Empty state — no join requests sent yet"
            ))
            .foregroundStyle(.secondary)
            .font(.subheadline)
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Withdraw

    private func withdraw(request: JoinRequest, from route: Route) {
        let store = storeProvider()
        var updated = route
        guard let idx = updated.companion?.joinRequests.firstIndex(where: { $0.id == request.id }) else { return }
        updated.companion!.joinRequests[idx].status = .withdrawn
        store.save(updated)
    }
}

// MARK: - Preview

#Preview("MyRequestsListView — with requests") {
    let container = SoloCompassModelContainer.makeInMemory()
    let store = RouteStore(context: ModelContext(container))
    let companion = RouteCompanion(
        status: .open,
        hostId: "maya",
        departureWindow: DepartureWindow(startDate: "2026-06-10", to: "2026-06-12", time: "morning"),
        departureLabel: "Jun 10–12 · morning",
        maxMembers: 4,
        joinRequests: [
            JoinRequest(
                id: JoinRequestId(rawValue: "req-1"),
                requesterId: DeviceIdentityService.shared.deviceID,
                message: "matching: Hi, I'm an easy-going traveler!",
                status: .pending,
                createdAt: ISO8601DateFormatter().string(from: Date())
            ),
            JoinRequest(
                id: JoinRequestId(rawValue: "req-2"),
                requesterId: DeviceIdentityService.shared.deviceID,
                message: "slower: Love slow mornings.",
                status: .accepted,
                createdAt: ISO8601DateFormatter().string(from: Date())
            ),
        ]
    )
    let route = Route(
        id: RouteId(rawValue: "r_preview"),
        title: "Mekong Sunset Walk",
        summary: "Dawn at the river.",
        experienceIds: ["e1", "e2"],
        cityCode: "VTE",
        region: "Riverfront",
        estimatedDuration: 90,
        distanceMeters: 1200,
        pace: .relaxed,
        tags: ["nature"],
        source: .editorial,
        companion: companion
    )
    store.save(route)
    return NavigationStack {
        MyRequestsListView(storeProvider: { store })
    }
}

#Preview("MyRequestsListView — empty") {
    let container = SoloCompassModelContainer.makeInMemory()
    let store = RouteStore(context: ModelContext(container))
    NavigationStack {
        MyRequestsListView(storeProvider: { store })
    }
}
