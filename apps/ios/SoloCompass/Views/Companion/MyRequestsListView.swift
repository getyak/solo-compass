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
    private let remoteProvider: @MainActor () -> any RouteCompanionRemote

    @State private var refreshToken: UUID = UUID()
    @State private var pulse = false
    @State private var showDiscover = false
    @State private var celebratedRequestIds: Set<String> = []
    @State private var poppedRequestIds: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        storeProvider: @escaping () -> RouteStore = { RouteStore() },
        remoteProvider: (@MainActor () -> any RouteCompanionRemote)? = nil
    ) {
        self.storeProvider = storeProvider
        self.remoteProvider = remoteProvider ?? { @MainActor in
            makeRouteCompanionRemote(context: ModelContext(SoloCompassModelContainer.shared))
        }
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
        .navigationDestination(isPresented: $showDiscover) {
            DiscoverRecruitingRoutesView()
        }
        .onReceive(NotificationCenter.default.publisher(for: RouteStore.didChange)) { _ in
            refreshToken = UUID()
        }
    }

    // MARK: - List

    private var requestList: some View {
        let requests = myRequests
        let pending = requests.filter { $0.1.status == .pending }.count
        return VStack(spacing: 0) {
            List {
                ForEach(requests, id: \.1.id) { route, request in
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
                                .tint(CT.warningText)
                            }
                        }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                await refresh()
            }

            Text(String(format: NSLocalizedString(
                "my.requests.count",
                comment: "Footer showing total and pending request counts"
            ), requests.count, pending))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentTransition(.numericText())
            .animation(.easeInOut, value: requests.count)
        }
    }

    // MARK: - Refresh

    @MainActor
    private func refresh() async {
        let remote = remoteProvider()
        do {
            _ = try await remote.fetchRecruitingRoutes(cityCode: "")
        } catch is NotImplementedError {
            // local-only mode — no-op
        } catch {
            // network errors silently ignored; local data still current
        }
        refreshToken = UUID()
        Haptics.impact(.light)
    }

    // MARK: - Row

    private func row(route: Route, request: JoinRequest) -> some View {
        NavigationLink {
            RouteDetailView(route: route)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                RouteCard(route: route)
                    .padding(.horizontal, -16)

                statusChip(for: request.status, requestId: request.id.rawValue)
                    .padding(.leading, 54)
                    .padding(.bottom, 4)
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }

    // MARK: - Status chip

    @ViewBuilder
    private func statusChip(for status: JoinRequestStatus, requestId: String) -> some View {
        let (label, color, symbol) = chipAttributes(for: status)
        let isPending = status == .pending
        let isAccepted = status == .accepted
        let isPopped = poppedRequestIds.contains(requestId)
        let celebrateLabel = isAccepted && !celebratedRequestIds.contains(requestId)
            ? NSLocalizedString("my.requests.status.accepted.celebrate", comment: "Celebratory accepted chip accessibility label")
            : label
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .accessibilityHidden(true)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.15), in: Capsule())
        .shadow(color: isAccepted && isPopped ? color.opacity(0.45) : .clear, radius: 6, x: 0, y: 0)
        .scaleEffect(isAccepted && !reduceMotion ? (isPopped ? 1.0 : 0.6) : 1.0)
        .opacity(isPending && !reduceMotion ? (pulse ? 1.0 : 0.6) : 1.0)
        .animation(
            isPending && !reduceMotion
                ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
                : .none,
            value: pulse
        )
        .accessibilityLabel(celebrateLabel)
        .onAppear {
            if isPending {
                guard !reduceMotion, !pulse else { return }
                pulse = true
            } else if isAccepted {
                if !celebratedRequestIds.contains(requestId) {
                    celebratedRequestIds.insert(requestId)
                    Haptics.notify(.success)
                }
                guard !reduceMotion, !poppedRequestIds.contains(requestId) else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                    poppedRequestIds.insert(requestId)
                }
            }
        }
    }

    private func chipAttributes(for status: JoinRequestStatus) -> (label: String, color: Color, symbol: String) {
        switch status {
        case .pending:
            return (
                NSLocalizedString("my.requests.status.pending", comment: "Pending status chip"),
                CT.warningText,
                "clock.fill"
            )
        case .accepted:
            return (
                NSLocalizedString("my.requests.status.accepted", comment: "Accepted status chip"),
                CT.verifiedGreen,
                "checkmark.circle.fill"
            )
        case .declined:
            return (
                NSLocalizedString("my.requests.status.declined", comment: "Declined status chip"),
                Color.secondary,
                "xmark.circle.fill"
            )
        case .withdrawn:
            return (
                NSLocalizedString("my.requests.status.withdrawn", comment: "Withdrawn status chip"),
                Color.secondary,
                "arrow.uturn.backward.circle.fill"
            )
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        EmptyMyRequestsView(onDiscover: { showDiscover = true })
    }

    // MARK: - Withdraw

    private func withdraw(request: JoinRequest, from route: Route) {
        Task { @MainActor in
            let remote = remoteProvider()
            do {
                try await remote.withdraw(request, route: route)
            } catch is NotImplementedError {
                localWithdraw(request: request, from: route)
                return
            } catch {
                return
            }
            refreshToken = UUID()
        }
    }

    private func localWithdraw(request: JoinRequest, from route: Route) {
        let store = storeProvider()
        var updated = route
        guard var companion = updated.companion else {
            SentryService.capture(
                message: "MyRequestsListView.localWithdraw: route.companion was nil; no-op",
                context: ["routeId": route.id.rawValue]
            )
            return
        }
        guard let idx = companion.joinRequests.firstIndex(where: { $0.id == request.id }) else { return }
        companion.joinRequests[idx].status = .withdrawn
        updated.companion = companion
        store.save(updated)
        refreshToken = UUID()
    }
}

// MARK: - Empty state view

private struct EmptyMyRequestsView: View {
    var onDiscover: (() -> Void)? = nil

    var body: some View {
        SoloEmptyState(
            systemImage: "paperplane.fill",
            title: NSLocalizedString(
                "my.requests.empty",
                comment: "Empty state — no join requests sent yet"
            ),
            message: NSLocalizedString(
                "my.requests.empty.hint",
                comment: "Empty state hint — explains how to send a join request"
            ),
            actionTitle: onDiscover.map { _ in
                NSLocalizedString("my.requests.empty.cta", comment: "Discover recruiting routes CTA")
            },
            action: onDiscover.map { discover in
                { Haptics.selection(); discover() }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .navigationTitle(NSLocalizedString("settings.companion.requests", comment: "My recruitment requests title"))
            .navigationBarTitleDisplayMode(.large)
    }
}

#Preview("EmptyMyRequestsView — standalone") {
    EmptyMyRequestsView(onDiscover: {})
}
