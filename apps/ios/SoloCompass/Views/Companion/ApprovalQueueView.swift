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
    /// US-020: presents the friend picker that pulls friends straight into
    /// confirmedMembers (no approval).
    @State private var showInviteFriends = false

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
        .toolbar {
            // US-020: host-only entry to invite friends straight into the route
            // (no approval). Stranger requests above still flow through accept.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.impact(.light)
                    showInviteFriends = true
                } label: {
                    Label(
                        NSLocalizedString("invite.friends.button", comment: "Invite friends button"),
                        systemImage: "person.badge.plus"
                    )
                }
                .accessibilityLabel(NSLocalizedString(
                    "invite.friends.button.a11y",
                    comment: "VoiceOver: invite friends into route"
                ))
            }
        }
        .sheet(isPresented: $showInviteFriends, onDismiss: reloadRoute) {
            InviteFriendsSheet(route: routeState, contextProvider: contextProvider)
        }
        .onReceive(NotificationCenter.default.publisher(for: RouteStore.didChange)) { note in
            guard let routeId = note.userInfo?["routeId"] as? String,
                  routeId == route.id.rawValue else { return }
            reloadRoute()
        }
    }

    /// Re-read the route row and bump the refresh token — shared by the
    /// RouteStore change publisher and the invite sheet's dismiss.
    private func reloadRoute() {
        let ctx = contextProvider()
        let store = RouteStore(context: ctx)
        if let updated = store.get(route.id) {
            routeState = updated
        }
        refreshToken = UUID()
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

            ApprovalQueueView.trustSignalRow(for: user)

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

    // MARK: - Trust signals (US-032)

    /// Three micro-stats sourced from the requester profile object:
    /// opt-in badge, walked count, and group (trips) count. When a stat is
    /// unknown — e.g. the profile is missing or the field is absent — the
    /// stat shows "—" rather than fabricating a value.
    @ViewBuilder
    static func trustSignalRow(for user: SeedUser?) -> some View {
        HStack(spacing: 12) {
            optInBadge(user?.optedIn)

            microStat(
                systemImage: "figure.walk",
                value: user.map { String($0.walked.count) } ?? Self.unknownValue,
                accessibilityLabelKey: "approval.queue.signal.walked.a11y"
            )

            microStat(
                systemImage: "person.2.fill",
                value: user.map { String($0.trips) } ?? Self.unknownValue,
                accessibilityLabelKey: "approval.queue.signal.group.a11y"
            )
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// Placeholder shown for any stat we don't actually know.
    static let unknownValue = "—"

    /// Resolves the opt-in badge's label and tint. Split out of the
    /// `@ViewBuilder` below so that builder's body stays a single view
    /// expression — a leading `let` + `switch` makes the result builder infer
    /// `()` and fail to conform to `View`.
    private static func optInBadgeStyle(_ optedIn: Bool?) -> (text: String, color: Color) {
        switch optedIn {
        case .some(true):
            return (NSLocalizedString("approval.queue.signal.optin.yes", comment: "Opt-in badge — opted in"), .green)
        case .some(false):
            return (NSLocalizedString("approval.queue.signal.optin.no", comment: "Opt-in badge — not opted in"), .secondary)
        case .none:
            return (unknownValue, .secondary)
        }
    }

    private static func optInBadge(_ optedIn: Bool?) -> some View {
        let (text, color) = optInBadgeStyle(optedIn)
        return HStack(spacing: 4) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.15), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(
            format: NSLocalizedString("approval.queue.signal.optin.a11y", comment: "Opt-in status accessibility label"),
            text
        ))
    }

    @ViewBuilder
    private static func microStat(
        systemImage: String,
        value: String,
        accessibilityLabelKey: String
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(
            format: NSLocalizedString(accessibilityLabelKey, comment: "Trust signal accessibility label"),
            value
        ))
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
        let routeStore = RouteStore(context: ctx)
        let convStore = ConversationStore(context: ctx)
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

        if companion.confirmedMembers.count >= companion.maxMembers,
           let closed = try? RouteCompanionStateMachine.transition(state: companion.status, event: .reachMax) {
            companion.status = closed
        }

        let now = ISO8601DateFormatter().string(from: Date())

        if wasOpen && newStatus == .forming && companion.groupConversationId == nil {
            // First accept: create group conversation atomically with the route update.
            let convId = ConversationId(rawValue: UUID().uuidString)
            let conversation = Conversation(
                id: convId,
                requestId: CompanionRequestId(rawValue: request.id.rawValue),
                participantIds: [companion.hostId, request.requesterId],
                type: .groupRoute,
                routeId: route.id.rawValue,
                createdAt: now,
                updatedAt: now
            )
            companion.groupConversationId = convId.rawValue
            updated.companion = companion
            routeStore.saveWithContext(updated)
            convStore.saveWithContext(conversation)
            try? routeStore.commitContext()
        } else if let existingConvIdStr = companion.groupConversationId,
                  let existingConv = convStore.get(ConversationId(rawValue: existingConvIdStr)) {
            // Subsequent accept: append to existing group conversation.
            var participants = existingConv.participantIds
            if !participants.contains(request.requesterId) {
                participants.append(request.requesterId)
            }
            let updatedConv = Conversation(
                id: existingConv.id,
                requestId: existingConv.requestId,
                participantIds: participants,
                type: existingConv.type,
                routeId: existingConv.routeId,
                lastMessageAt: existingConv.lastMessageAt,
                createdAt: existingConv.createdAt,
                updatedAt: now
            )
            updated.companion = companion
            routeStore.saveWithContext(updated)
            convStore.saveWithContext(updatedConv)
            try? routeStore.commitContext()
        } else {
            updated.companion = companion
            routeStore.save(updated)
        }

        routeState = updated

        // US-026: when this accept closes the group (成团), start a departure
        // countdown Live Activity if the departure time parses to a real clock
        // time. A vague hint like "morning" can't drive a live timer, so we skip
        // it rather than invent a fake countdown.
        if companion.status == .closed {
            startCountdownActivity(for: companion, routeTitle: updated.title)
        }
    }

    /// Map a closed companion slot onto a countdown Live Activity. Resolves
    /// `departureWindow.time` ("HH:mm") to today's instant and builds the member
    /// avatar stack from confirmed members (host first).
    private func startCountdownActivity(for companion: RouteCompanion, routeTitle: String) {
        guard let departure = Self.nextDeparture(from: companion.departureWindow.time) else { return }

        let memberIds = ([companion.hostId] + companion.confirmedMembers)
            .reduce(into: [String]()) { acc, id in if !acc.contains(id) { acc.append(id) } }
        let initials = memberIds.map { id -> String in
            let name = UserDirectory.displayName(forId: id)
            return String(name.prefix(1)).uppercased()
        }
        let summary = memberIds.map { UserDirectory.displayName(forId: $0) }
            .joined(separator: " · ")

        LiveActivityService.shared.startCountdown(
            groupTitle: routeTitle,
            meetPointName: companion.departureLabel.isEmpty ? routeTitle : companion.departureLabel,
            departureDate: departure,
            memberInitials: initials,
            memberSummary: summary
        )

        // US-026: also schedule a time-sensitive departure reminder 30 min before
        // the group sets off (the design's "30 分钟后集合" banner). Local-only, so
        // it nudges this device's owner — cross-device social pushes await APNs.
        let meetLabel = companion.departureLabel.isEmpty ? routeTitle : companion.departureLabel
        Task {
            await NotificationService.shared.scheduleDepartureReminder(
                routeId: route.id.rawValue,
                title: NSLocalizedString("notification.departure.title", comment: "Departure reminder title"),
                body: String(
                    format: NSLocalizedString("notification.departure.body", comment: "Departure reminder body — meet point"),
                    meetLabel
                ),
                fireDate: departure.addingTimeInterval(-30 * 60)
            )
        }
    }

    /// Parse a "HH:mm" departure hint into the next occurrence of that time
    /// (today if still ahead, otherwise tomorrow). Returns nil for non-clock
    /// hints like "morning".
    private static func nextDeparture(from time: String) -> Date? {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        let cal = Calendar.current
        let now = Date()
        guard let today = cal.date(bySettingHour: h, minute: m, second: 0, of: now) else { return nil }
        return today > now ? today : cal.date(byAdding: .day, value: 1, to: today)
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
        guard var companion = updated.companion else {
            SentryService.capture(
                message: "ApprovalQueueView.localDecline: route.companion was nil; no-op",
                context: ["routeId": routeState.id.rawValue]
            )
            return
        }
        guard let idx = companion.joinRequests.firstIndex(where: { $0.id == request.id }) else { return }
        companion.joinRequests[idx].status = .declined
        updated.companion = companion
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
            // Unknown requester (not in the directory) → all three stats show "—".
            JoinRequest(
                id: JoinRequestId(rawValue: "req-3"),
                requesterId: "stranger",
                message: "faster: New here — would love to join!",
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
    return NavigationStack {
        ApprovalQueueView(route: route, contextProvider: { ctx })
    }
}
