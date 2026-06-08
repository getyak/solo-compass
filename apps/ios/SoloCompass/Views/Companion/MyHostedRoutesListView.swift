import SwiftUI
import SwiftData

// MARK: - MyHostedRoutesListView

/// US-034: Host view of all routes where companion.hostId == deviceId.
/// Each row pushes into ApprovalQueueView for that route.
public struct MyHostedRoutesListView: View {

    private let storeProvider: () -> RouteStore
    private let contextProvider: () -> ModelContext
    var onCreateRoute: (() -> Void)? = nil

    @State private var refreshToken: UUID = UUID()

    public init(
        storeProvider: @escaping () -> RouteStore = { RouteStore() },
        contextProvider: @escaping () -> ModelContext = {
            ModelContext(SoloCompassModelContainer.shared)
        },
        onCreateRoute: (() -> Void)? = nil
    ) {
        self.storeProvider = storeProvider
        self.contextProvider = contextProvider
        self.onCreateRoute = onCreateRoute
    }

    private var deviceId: String {
        DeviceIdentityService.shared.deviceID
    }

    private var hostedRoutes: [Route] {
        _ = refreshToken
        return storeProvider().all().filter { $0.companion?.hostId == deviceId }
    }

    public var body: some View {
        Group {
            if hostedRoutes.isEmpty {
                HostedRoutesEmptyState(onCreateRoute: onCreateRoute)
            } else {
                routeList
            }
        }
        .navigationTitle(NSLocalizedString(
            "my.hosted.routes.title",
            comment: "My Hosted Routes nav title"
        ))
        .navigationBarTitleDisplayMode(.large)
        .onReceive(NotificationCenter.default.publisher(for: RouteStore.didChange)) { _ in
            refreshToken = UUID()
        }
    }

    // MARK: - List

    private var routeList: some View {
        List {
            ForEach(hostedRoutes) { route in
                NavigationLink {
                    ApprovalQueueView(route: route, contextProvider: contextProvider)
                } label: {
                    routeRow(route)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        }
        .listStyle(.insetGrouped)
    }

    private func routeRow(_ route: Route) -> some View {
        let companion = route.companion
        let pendingCount = companion?.joinRequests.filter { $0.status == .pending }.count ?? 0

        return HStack(spacing: 12) {
            Image(systemName: "map.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.teal, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(route.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if let label = companion?.departureLabel {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if pendingCount > 0 {
                Text("\(pendingCount)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.orange, in: Capsule())
            }
        }
    }

}

// MARK: - HostedRoutesEmptyState

private struct HostedRoutesEmptyState: View {
    var onCreateRoute: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.teal.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "map.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.teal.opacity(0.7))
                    .scaleEffect(isBreathing ? 1.08 : 0.94)
                    .opacity(isBreathing ? 1.0 : 0.7)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: isBreathing)
                    .accessibilityHidden(true)
            }
            Text(NSLocalizedString("my.hosted.routes.empty.title", comment: "No hosted routes yet"))
                .font(.headline)
            Text(NSLocalizedString("my.hosted.routes.empty.hint", comment: "Hint to create a route"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let onCreateRoute {
                Button {
                    Haptics.selection()
                    onCreateRoute()
                } label: {
                    Label(NSLocalizedString("my.hosted.routes.empty.cta", comment: "Create a route button in empty hosted routes state"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.top, 4)
                .accessibilityLabel(Text(NSLocalizedString("my.hosted.routes.empty.cta", comment: "Create a route button in empty hosted routes state")))
            }
        }
        .padding(32)
        .onAppear {
            guard !isBreathing, !reduceMotion else { return }
            isBreathing = true
        }
    }
}

// MARK: - Preview

#Preview("MyHostedRoutesListView — with routes") {
    let container = SoloCompassModelContainer.makeInMemory()
    let ctx = ModelContext(container)
    let store = RouteStore(context: ctx)
    let deviceId = DeviceIdentityService.shared.deviceID
    let companion = RouteCompanion(
        status: .open,
        hostId: deviceId,
        departureWindow: DepartureWindow(startDate: "2026-07-01", to: "2026-07-03", time: "morning"),
        departureLabel: "Jul 1–3 · morning",
        maxMembers: 4,
        joinRequests: [
            JoinRequest(
                id: JoinRequestId(rawValue: "req-1"),
                requesterId: "maya",
                message: "matching: Hi, I love sunsets!",
                status: .pending,
                createdAt: ISO8601DateFormatter().string(from: Date())
            ),
            JoinRequest(
                id: JoinRequestId(rawValue: "req-2"),
                requesterId: "lin",
                message: "slower: Love slow mornings.",
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
    return NavigationStack {
        MyHostedRoutesListView(storeProvider: { store }, contextProvider: { ctx })
    }
}

#Preview("MyHostedRoutesListView — empty") {
    let container = SoloCompassModelContainer.makeInMemory()
    let store = RouteStore(context: ModelContext(container))
    NavigationStack {
        MyHostedRoutesListView(storeProvider: { store }, onCreateRoute: {})
    }
}
