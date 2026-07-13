import SwiftUI
import SwiftData

// MARK: - InviteFriendsSheet

/// US-020: Host pulls friends straight into a recruiting route — no approval.
///
/// Unlike the stranger path (`JoinRouteRequestSheet` → `ApprovalQueueView`,
/// where a join request waits for the host's accept), a friend the host picks
/// here lands directly in `confirmedMembers`. The host is the only gate: there
/// is no request, no pending state, and no acceptance step on the invitee's
/// side. The invited friend simply receives a local "you're in" notification.
///
/// The actual membership mutation reuses the exact same group-conversation and
/// state-machine wiring as `ApprovalQueueView.localAccept` (create the group on
/// the first member, append participants thereafter, drive the companion status
/// machine, and cap at `maxMembers`) — minus the join-request bookkeeping.
public struct InviteFriendsSheet: View {
    let route: Route

    private let contextProvider: () -> ModelContext
    private let friendService: FriendService

    /// User ids the host has selected to invite this session.
    @State private var selected: Set<String> = []
    @State private var isSending = false
    @Environment(\.dismiss) private var dismiss

    public init(
        route: Route,
        contextProvider: @escaping () -> ModelContext = {
            ModelContext(SoloCompassModelContainer.shared)
        },
        friendService: FriendService = .shared
    ) {
        self.route = route
        self.contextProvider = contextProvider
        self.friendService = friendService
    }

    private var currentUserId: String {
        SupabaseClient.shared.currentSession?.userId ?? "local"
    }

    /// Friends eligible to invite: every confirmed friend who isn't already a
    /// confirmed member of (or the host of) this route.
    private var invitableFriendIds: [String] {
        let alreadyIn = Set(route.companion?.confirmedMembers ?? [])
        let hostId = route.companion?.hostId
        return friendService.friends
            .map { $0.otherUserId(viewer: currentUserId) }
            .filter { !alreadyIn.contains($0) && $0 != hostId }
    }

    /// Remaining open seats — host can never overfill past `maxMembers`.
    private var remainingSeats: Int {
        guard let companion = route.companion else { return 0 }
        return max(0, companion.maxMembers - companion.confirmedMembers.count)
    }

    private var canInviteMore: Bool {
        selected.count < remainingSeats
    }

    public var body: some View {
        NavigationStack {
            Group {
                if invitableFriendIds.isEmpty {
                    emptyState
                } else {
                    friendPicker
                }
            }
            .navigationTitle(NSLocalizedString(
                "invite.friends.title",
                comment: "Invite friends into route — sheet title"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("action.cancel", comment: "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("invite.friends.send", comment: "Send invites")) {
                        Task { await invite() }
                    }
                    .disabled(selected.isEmpty || isSending)
                }
            }
        }
    }

    // MARK: - Picker

    private var friendPicker: some View {
        List {
            Section {
                ForEach(invitableFriendIds, id: \.self) { friendId in
                    friendRow(friendId)
                }
            } header: {
                Text(String(
                    format: NSLocalizedString(
                        "invite.friends.seats",
                        comment: "Remaining seats header"
                    ),
                    remainingSeats
                ))
            } footer: {
                Text(NSLocalizedString(
                    "invite.friends.footer",
                    comment: "Explains friends join directly with no approval"
                ))
            }
        }
        .listStyle(.insetGrouped)
    }

    private func friendRow(_ friendId: String) -> some View {
        let isSelected = selected.contains(friendId)
        // A friend can be tapped to select while seats remain; an already-
        // selected friend can always be deselected.
        let isEnabled = isSelected || canInviteMore

        return Button {
            toggle(friendId)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(UserDirectory.color(forId: friendId))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Text(String(friendId.prefix(1)).uppercased())
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                Text(friendId)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? CT.accent : Color.secondary)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func toggle(_ friendId: String) {
        Haptics.impact(.light)
        if selected.contains(friendId) {
            selected.remove(friendId)
        } else if canInviteMore {
            selected.insert(friendId)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        SoloEmptyState(
            systemImage: "person.2.slash",
            title: NSLocalizedString("invite.friends.empty.title", comment: "No invitable friends title"),
            message: NSLocalizedString(
                "invite.friends.empty.description",
                comment: "No invitable friends description"
            )
        )
    }

    // MARK: - Invite (direct → confirmedMembers, no approval)

    private func invite() async {
        guard !isSending, !selected.isEmpty else { return }
        isSending = true
        defer { isSending = false }

        let ids = Array(selected)
        let added = InviteFriendsSheet.confirmFriends(
            ids,
            into: route,
            contextProvider: contextProvider
        )

        if !added.isEmpty {
            Haptics.notify(.success)
            // US-020: the invited friend gets a local join notification. (Best
            // effort — membership is already persisted regardless.)
            let title = route.title
            let hostId = route.companion?.hostId ?? currentUserId
            let routeId = route.id.rawValue
            await NotificationService.shared.scheduleRouteJoinNotification(
                routeId: routeId,
                routeTitle: title,
                hostId: hostId
            )
        }
        dismiss()
    }

    /// Add `friendIds` straight into the route's `confirmedMembers` (no approval),
    /// creating or extending the group conversation and advancing the companion
    /// status machine — the same persistence path the host's accept uses, minus
    /// the join-request lifecycle.
    ///
    /// Returns the ids actually added (capped at the remaining seats), so the
    /// caller knows whether to fire the join notification.
    @discardableResult
    static func confirmFriends(
        _ friendIds: [String],
        into route: Route,
        contextProvider: () -> ModelContext
    ) -> [String] {
        let ctx = contextProvider()
        let routeStore = RouteStore(context: ctx)
        let convStore = ConversationStore(context: ctx)

        // Read the freshest route row so we don't clobber concurrent accepts.
        var updated = routeStore.get(route.id) ?? route
        guard var companion = updated.companion else { return [] }

        let existing = Set(companion.confirmedMembers)
        var added: [String] = []
        let now = ISO8601DateFormatter().string(from: Date())

        for friendId in friendIds {
            // Stop at capacity; never overfill past maxMembers.
            guard companion.confirmedMembers.count < companion.maxMembers else { break }
            guard !existing.contains(friendId),
                  !added.contains(friendId),
                  friendId != companion.hostId else { continue }

            let wasOpen = companion.status == .open
            let event: CompanionEvent = wasOpen ? .acceptFirst : .acceptAdditional
            let newStatus = (try? RouteCompanionStateMachine.transition(state: companion.status, event: event))
                ?? companion.status

            companion.confirmedMembers.append(friendId)
            companion.status = newStatus
            added.append(friendId)

            if companion.confirmedMembers.count >= companion.maxMembers,
               let closed = try? RouteCompanionStateMachine.transition(state: companion.status, event: .reachMax) {
                companion.status = closed
            }

            if wasOpen && newStatus == .forming && companion.groupConversationId == nil {
                // First member: create the group conversation atomically.
                let convId = ConversationId(rawValue: UUID().uuidString)
                let conversation = Conversation(
                    id: convId,
                    requestId: nil,
                    participantIds: [companion.hostId, friendId],
                    type: .groupRoute,
                    routeId: updated.id.rawValue,
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
                // Subsequent member: append to the existing group conversation so
                // group participants + Realtime stay in sync.
                var participants = existingConv.participantIds
                if !participants.contains(friendId) {
                    participants.append(friendId)
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
        }

        return added
    }
}

// MARK: - Preview

#Preview("InviteFriendsSheet — friends available") {
    let container = SoloCompassModelContainer.makeInMemory()
    let ctx = ModelContext(container)
    let store = RouteStore(context: ctx)
    let companion = RouteCompanion(
        status: .open,
        hostId: "local",
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

    let service = FriendService()
    service.friends = [
        Friendship(
            id: FriendshipId(rawValue: "fnd_01"),
            userLowId: "local",
            userHighId: "maya",
            initiatedBy: "local",
            conversationId: nil,
            acceptedAt: "2026-05-01T10:00:00Z",
            createdAt: "2026-05-01T10:00:00Z",
            updatedAt: "2026-05-01T10:00:00Z"
        ),
        Friendship(
            id: FriendshipId(rawValue: "fnd_02"),
            userLowId: "kenji",
            userHighId: "local",
            initiatedBy: "kenji",
            conversationId: nil,
            acceptedAt: "2026-05-02T10:00:00Z",
            createdAt: "2026-05-02T10:00:00Z",
            updatedAt: "2026-05-02T10:00:00Z"
        ),
    ]
    return InviteFriendsSheet(
        route: route,
        contextProvider: { ctx },
        friendService: service
    )
}
