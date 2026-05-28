import SwiftUI
import SwiftData

// MARK: - ApprovalQueueView

/// US-034: Host view of pending join requests for a single route.
///
/// Shows each requester's avatar, handle, blurb, trust line, message, and
/// pace-match chip. Host can accept (→ state machine transition + confirmedMembers)
/// or decline (→ set status .declined) each request.
public struct ApprovalQueueView: View {
    let route: Route

    private let contextProvider: () -> ModelContext
    private let remoteProvider: @MainActor () -> any RouteCompanionRemote

    @State private var routeState: Route
    @State private var refreshToken: UUID = UUID()

    public init(
        route: Route,
        contextProvider: @escaping () -> ModelContext = {
            ModelContext(SoloCompassModelContainer.shared)
        },
        remoteProvider: (@MainActor () -> any RouteCompanionRemote)? = nil
    ) {
        self.route = route
        self._routeState = State(initialValue: route)
        self.contextProvider = contextProvider
        self.remoteProvider = remoteProvider ?? { @MainActor in
            makeRouteCompanionRemote(context: ModelContext(SoloCompassModelContainer.shared))
        }
    }

    private var pendingRequests: [JoinRequest] {
        _ = refreshToken
        return routeState.companion?.joinRequests.filter { $0.status == .pending } ?? []
    }

    public var body: some View {
        Group {
            if pendingRequests.isEmpty {
                emptyState
            } else {
                requestList
            }
        }
        .navigationTitle(NSLocalizedString(
            "approval.queue.title",
            comment: "Approval queue nav title"
        ))
        .navigationBarTitleDisplayMode(.large)
        .onReceive(NotificationCenter.default.publisher(for: RouteStore.didChange)) { note in
            guard let routeId = note.userInfo?["routeId"] as? String,
                  routeId == route.id.rawValue else { return }
            let ctx = contextProvider()
            let store = RouteStore(context: ctx)
            if let updated = store.get(route.id) {
                routeState = updated
            }
            refreshToken = UUID()
        }
    }

    // MARK: - List

    private var requestList: some View {
        List {
            ForEach(pendingRequests) { request in
                requestRow(request)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Row

    private func requestRow(_ request: JoinRequest) -> some View {
        let user = UserDirectory.shared.user(handle: request.requesterId)
        let walked = user?.walked.count ?? 0
        let trips = user?.trips ?? 0
        let blurb = user?.blurb ?? ""
        let paceChip = paceFromMessage(request.message)
        let cleanMessage = messageBody(request.message)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(UserDirectory.color(forId: request.requesterId))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Text(String(request.requesterId.prefix(1)).uppercased())
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(request.requesterId)")
                        .font(.subheadline.weight(.semibold))
                    if !blurb.isEmpty {
                        Text(blurb)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()

                if let chip = paceChip {
                    paceChipView(chip)
                }
            }

            Text(String(
                format: NSLocalizedString(
                    "approval.queue.trust.line",
                    comment: "Trust signal: walked N routes · M trips"
                ),
                walked,
                trips
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            if !cleanMessage.isEmpty {
                Text(cleanMessage)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Button {
                    decline(request)
                } label: {
                    Text(NSLocalizedString("approval.queue.decline", comment: "Decline button"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)

                Button {
                    accept(request)
                } label: {
                    Text(NSLocalizedString("approval.queue.accept", comment: "Accept button"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Pace chip

    @ViewBuilder
    private func paceChipView(_ pace: String) -> some View {
        let (label, color) = paceChipAttributes(pace)
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }

    private func paceChipAttributes(_ pace: String) -> (String, Color) {
        switch pace {
        case "slower":
            return (NSLocalizedString("join.pace.slower", comment: "慢于宿主"), Color.blue)
        case "faster":
            return (NSLocalizedString("join.pace.faster", comment: "快于宿主"), Color.orange)
        default:
            return (NSLocalizedString("join.pace.matching", comment: "匹配"), Color.green)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        List {
            Text(NSLocalizedString(
                "approval.queue.empty",
                comment: "Empty state — no pending requests"
            ))
            .foregroundStyle(.secondary)
            .font(.subheadline)
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Actions

    private func accept(_ request: JoinRequest) {
        Task { @MainActor in
            let remote = remoteProvider()
            do {
                try await remote.accept(request, route: routeState)
            } catch is NotImplementedError {
                localAccept(request)
                return
            } catch {
                return
            }
            let ctx = contextProvider()
            let store = RouteStore(context: ctx)
            if let updated = store.get(route.id) {
                routeState = updated
                refreshToken = UUID()
            }
        }
    }

    private func localAccept(_ request: JoinRequest) {
        let ctx = contextProvider()
        let store = RouteStore(context: ctx)
        var updated = routeState
        guard var companion = updated.companion,
              let idx = companion.joinRequests.firstIndex(where: { $0.id == request.id }) else { return }

        let wasOpen = companion.status == .open
        let event: CompanionEvent = wasOpen ? .acceptFirst : .acceptAdditional
        let newStatus = (try? RouteCompanionStateMachine.transition(state: companion.status, event: event))
            ?? companion.status

        companion.joinRequests[idx].status = .accepted
        companion.confirmedMembers.append(request.requesterId)
        companion.status = newStatus

        // Assign groupConversationId the first time status becomes .forming.
        if wasOpen && newStatus == .forming && companion.groupConversationId == nil {
            companion.groupConversationId = UUID().uuidString
        }

        if companion.confirmedMembers.count >= companion.maxMembers,
           let closed = try? RouteCompanionStateMachine.transition(state: companion.status, event: .reachMax) {
            companion.status = closed
        }

        updated.companion = companion
        routeState = updated
        store.save(updated)
    }

    private func decline(_ request: JoinRequest) {
        Task { @MainActor in
            let remote = remoteProvider()
            do {
                try await remote.decline(request, route: routeState)
            } catch is NotImplementedError {
                localDecline(request)
                return
            } catch {
                return
            }
            let ctx = contextProvider()
            let store = RouteStore(context: ctx)
            if let updated = store.get(route.id) {
                routeState = updated
                refreshToken = UUID()
            }
        }
    }

    private func localDecline(_ request: JoinRequest) {
        let ctx = contextProvider()
        let store = RouteStore(context: ctx)
        var updated = routeState
        guard let idx = updated.companion?.joinRequests.firstIndex(where: { $0.id == request.id }) else { return }
        updated.companion!.joinRequests[idx].status = .declined
        routeState = updated
        store.save(updated)
    }

    // MARK: - Message parsing

    private func paceFromMessage(_ message: String) -> String? {
        let parts = message.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let key = parts[0].trimmingCharacters(in: .whitespaces)
        return PaceMatch.allCases.map(\.rawValue).contains(key) ? key : nil
    }

    private func messageBody(_ message: String) -> String {
        let parts = message.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return message }
        return parts[1].trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Preview

#Preview("ApprovalQueueView — with pending requests") {
    let container = SoloCompassModelContainer.makeInMemory()
    let ctx = ModelContext(container)
    let store = RouteStore(context: ctx)
    let companion = RouteCompanion(
        status: .open,
        hostId: DeviceIdentityService.shared.deviceID,
        departureWindow: DepartureWindow(startDate: "2026-07-01", to: "2026-07-03", time: "morning"),
        departureLabel: "Jul 1–3 · morning",
        maxMembers: 4,
        joinRequests: [
            JoinRequest(
                id: JoinRequestId(rawValue: "req-1"),
                requesterId: "maya",
                message: "matching: Hi, I'm an easy-going traveler who loves sunsets!",
                status: .pending,
                createdAt: ISO8601DateFormatter().string(from: Date())
            ),
            JoinRequest(
                id: JoinRequestId(rawValue: "req-2"),
                requesterId: "lin",
                message: "slower: Love slow mornings and coffee stops along the way.",
                status: .pending,
                createdAt: ISO8601DateFormatter().string(from: Date())
            ),
        ]
    )
    let route = Route(
        id: RouteId(rawValue: "mekong-sunset"),
        title: "Mekong Sunset Walk",
        summary: "Dawn at the river, dusk by the ferry.",
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
    NavigationStack {
        ApprovalQueueView(route: route, contextProvider: { ctx })
    }
}

#Preview("ApprovalQueueView — empty") {
    let container = SoloCompassModelContainer.makeInMemory()
    let ctx = ModelContext(container)
    let store = RouteStore(context: ctx)
    let companion = RouteCompanion(
        status: .open,
        hostId: DeviceIdentityService.shared.deviceID,
        departureWindow: DepartureWindow(startDate: "2026-07-01", to: "2026-07-03", time: "morning"),
        departureLabel: "Jul 1–3 · morning",
        maxMembers: 4
    )
    let route = Route(
        id: RouteId(rawValue: "mekong-sunset"),
        title: "Mekong Sunset Walk",
        summary: "Dawn at the river.",
        experienceIds: ["e1", "e2"],
        cityCode: "VTE",
        region: "Riverfront",
        estimatedDuration: 90,
        distanceMeters: 1200,
        pace: .relaxed,
        tags: [],
        source: .editorial,
        companion: companion
    )
    store.save(route)
    NavigationStack {
        ApprovalQueueView(route: route, contextProvider: { ctx })
    }
}
