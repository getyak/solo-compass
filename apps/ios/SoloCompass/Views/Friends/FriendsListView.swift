import SwiftUI

/// US-010: One screen showing the current user's friends and the pending
/// requests addressed to them.
///
/// Structure mirrors `RequestInboxView` / `MyRequestsListView`:
/// - A top "pending requests" section (incoming) with [Accept] / [Decline]
///   per row.
/// - The friends list below (an avatar strip + a tappable list) where tapping
///   a friend opens `FriendProfileView`.
/// - Dedicated empty-state copy for "no friends" and "no requests".
///
/// All relationship I/O defers to `FriendService` (the persistent relationship
/// layer); this view is purely presentational + dispatch.
public struct FriendsListView: View {
    @State private var service: FriendService
    @State private var errorMessage: String?
    /// US-013: presents the AddFriendSheet (my shareable code + QR).
    @State private var showAddFriend = false

    /// When false, the on-appear `refresh()` is skipped. Production always uses
    /// the default (true); tests/previews pass false to render fixture-backed
    /// state that `refresh()` would otherwise clear.
    private let autoRefresh: Bool

    public init(service: FriendService = .shared, autoRefresh: Bool = true) {
        _service = State(initialValue: service)
        self.autoRefresh = autoRefresh
    }

    private var currentUserId: String {
        SupabaseClient.shared.currentSession?.userId ?? "local"
    }

    private var pendingCount: Int {
        service.incomingRequests.filter { $0.status == .pending }.count
    }

    public var body: some View {
        Group {
            if service.isLoading {
                ScrollView {
                    CompanionSkeletonList(rows: 5)
                }
            } else if let error = service.lastError {
                errorView(message: error)
            } else if service.friends.isEmpty && service.incomingRequests.isEmpty {
                EmptyFriendsView()
            } else {
                friendsList
            }
        }
        .navigationTitle(NSLocalizedString("friends.list.title", comment: "Friends list nav title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if pendingCount > 0 {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 4) {
                        Image(systemName: "bell.badge.fill")
                            .accessibilityHidden(true)
                        Text(String(format: NSLocalizedString("friends.list.pending.count", comment: "Pending request count pill"), pendingCount))
                            .contentTransition(.numericText())
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.15), in: Capsule())
                    .animation(.easeInOut, value: pendingCount)
                    .accessibilityLabel(String(format: NSLocalizedString("friends.list.pending.count.a11y", comment: "VoiceOver: pending requests count"), pendingCount))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.impact(.light)
                    showAddFriend = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
                .accessibilityLabel(NSLocalizedString("friends.add.open.a11y", comment: "Show my friend code"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await service.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(NSLocalizedString("friends.list.refresh.a11y", comment: "Refresh friends"))
            }
        }
        .task {
            guard autoRefresh else { return }
            await service.refresh()
        }
        .sheet(isPresented: $showAddFriend) {
            AddFriendSheet(service: service)
        }
        .overlay(alignment: .bottom) {
            if let msg = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(msg)
                        .font(.subheadline)
                        .lineLimit(2)
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityLabel(msg)
            }
        }
        .animation(.easeInOut, value: errorMessage)
    }

    // MARK: - Subviews

    private func errorView(message: String) -> some View {
        ContentUnavailableView {
            Label(
                NSLocalizedString("friends.list.error.title", comment: "Friends load error title"),
                systemImage: "exclamationmark.triangle"
            )
        } description: {
            Text(message)
        } actions: {
            Button {
                Haptics.impact(.light)
                Task { await service.refresh() }
            } label: {
                Label(
                    NSLocalizedString("friends.list.error.retry", comment: "Retry button"),
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var friendsList: some View {
        List {
            // Top section: incoming pending requests.
            if !service.incomingRequests.isEmpty {
                Section {
                    ForEach(service.incomingRequests) { request in
                        IncomingRequestRow(
                            request: request,
                            onAccept: { Task { await acceptRequest(request) } },
                            onDecline: { Task { await service.decline(request) } }
                        )
                    }
                } header: {
                    Text(NSLocalizedString("friends.list.requests.section", comment: "Pending requests section header"))
                }
            }

            // Friends section: avatar strip + list.
            Section {
                if service.friends.isEmpty {
                    Text(NSLocalizedString("friends.list.empty.friends", comment: "No friends yet inline copy"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                } else {
                    avatarStrip
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    ForEach(service.friends) { friendship in
                        let otherId = friendship.otherUserId(viewer: currentUserId)
                        NavigationLink {
                            FriendProfileContainer(
                                friendship: friendship,
                                profile: profileData(for: otherId),
                                service: service
                            )
                        } label: {
                            FriendRow(userId: otherId)
                        }
                    }
                }
            } header: {
                Text(NSLocalizedString("friends.list.friends.section", comment: "Friends section header"))
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await service.refresh() }
    }

    // MARK: - Avatar strip

    private var avatarStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(service.friends) { friendship in
                    let otherId = friendship.otherUserId(viewer: currentUserId)
                    NavigationLink {
                        FriendProfileContainer(
                            friendship: friendship,
                            profile: profileData(for: otherId),
                            service: service
                        )
                    } label: {
                        VStack(spacing: 4) {
                            Text(AvatarEmoji.emoji(for: otherId))
                                .font(.system(size: 32))
                                .frame(width: 56, height: 56)
                                .background(Circle().fill(Color.accentColor.opacity(0.12)))
                            Text(otherId)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: 64)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .accessibilityLabel(NSLocalizedString("friends.list.strip.a11y", comment: "VoiceOver: friend avatar strip"))
    }

    // MARK: - Helpers

    /// Build a minimal read-only profile from a user id. Trust signals default
    /// to zero until a richer profile fetch lands; the handle falls back to the
    /// raw id so the row is never blank.
    private func profileData(for userId: String) -> FriendProfileData {
        FriendProfileData(
            userId: userId,
            displayHandle: userId,
            avatarEmoji: AvatarEmoji.emoji(for: userId),
            bio: "",
            languages: [],
            placesWalked: 0,
            routesJoined: 0,
            friendCount: 0
        )
    }

    private func acceptRequest(_ request: FriendRequest) async {
        let result = await service.accept(request)
        if case .failure(let err) = result {
            errorMessage = err.localizedDescription
            Haptics.notify(.error)
            Task {
                try? await Task.sleep(for: .seconds(3))
                errorMessage = nil
            }
        } else {
            Haptics.notify(.success)
        }
    }
}

// MARK: - FriendProfileContainer

/// Wraps the pure, value-driven `FriendProfileView` with the `Friendship` + the
/// `FriendService` so the [Message] action can lazily open (or create) the
/// persistent `friendDirect` conversation and push the shared `ChatView` (US-012).
///
/// Keeping this container separate preserves `FriendProfileView`'s previewability
/// — that view stays a plain function of `FriendProfileData` + relation + callbacks.
private struct FriendProfileContainer: View {
    let friendship: Friendship
    let profile: FriendProfileData
    let service: FriendService

    @State private var conversation: Conversation?
    @State private var isOpening = false
    @State private var errorMessage: String?
    /// US-019: presents the meetup-invite composer (no trust gate).
    @State private var showInvite = false
    /// US-019: companion meetup invites bypass the discover trust gate.
    private let companion: CompanionService = .shared

    private var currentUserId: String? {
        SupabaseClient.shared.currentSession?.userId
    }

    private var otherUserId: String {
        friendship.otherUserId(viewer: currentUserId ?? "local")
    }

    var body: some View {
        FriendProfileView(
            profile: profile,
            relation: .accepted,
            onMessage: { Task { await openConversation() } },
            // US-019: invite an existing friend straight to a meetup. No
            // reporterWeight gate and no safety consent — those only guard
            // stranger requests from Discover.
            onInvite: { showInvite = true }
        )
        .sheet(isPresented: $showInvite) {
            SendRequestSheet(
                recipient: .init(
                    handle: profile.avatarEmoji,
                    blurb: profile.displayHandle
                ),
                source: .friend,
                onSend: { note in Task { await sendInvite(note: note) } }
            )
        }
        .overlay(alignment: .center) {
            if isOpening {
                ProgressView()
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .navigationDestination(item: $conversation) { conv in
            ChatView(
                conversation: conv,
                currentUserId: currentUserId,
                // friendDirect: blocking from the Report/Block menu also unfriends.
                onBlocked: {
                    Task { await service.unfriend(friendship, block: false) }
                }
            )
        }
        .alert(
            NSLocalizedString("friends.list.error.title", comment: "Friends error title"),
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button(NSLocalizedString("action.ok", comment: "OK")) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func openConversation() async {
        guard !isOpening else { return }
        isOpening = true
        defer { isOpening = false }
        let result = await service.openDirectConversation(with: friendship)
        switch result {
        case .success(let conv):
            conversation = conv
        case .failure(let err):
            errorMessage = err.localizedDescription
            Haptics.notify(.error)
        }
    }

    /// US-019: send a companion meetup request to an existing friend. This goes
    /// straight through `CompanionService.sendRequest` — deliberately skipping
    /// `FriendService.sendDiscoverRequest`'s reporterWeight gate and safety
    /// consent, which only guard stranger requests. Acceptance on the other
    /// side runs the existing `CompanionService.acceptRequest`, which builds the
    /// one-on-one conversation with a `requestId`.
    private func sendInvite(note: String?) async {
        // Invites have no originating discover post; synthesize a stable id so
        // the request row still carries a non-empty postId.
        let syntheticPostId = CompanionPostId(rawValue: "friend-invite:\(otherUserId)")
        let result = await companion.sendRequest(
            postId: syntheticPostId,
            recipientId: otherUserId,
            note: note
        )
        switch result {
        case .success:
            Haptics.notify(.success)
        case .failure(let err):
            errorMessage = err.localizedDescription
            Haptics.notify(.error)
        }
    }
}

// MARK: - AvatarEmoji (stable per-user emoji)

/// Deterministic emoji for a user id so the same friend always renders the same
/// avatar without a stored profile. Purely cosmetic.
private enum AvatarEmoji {
    private static let pool = ["🧭", "🌿", "🏔️", "🌊", "🦊", "🐢", "🦉", "🐬", "🌅", "🍃"]

    static func emoji(for userId: String) -> String {
        let idx = abs(userId.hashValue) % pool.count
        return pool[idx]
    }
}

// MARK: - IncomingRequestRow

private struct IncomingRequestRow: View {
    let request: FriendRequest
    let onAccept: () -> Void
    let onDecline: () -> Void

    private static let isoFormatter = ISO8601DateFormatter()
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var relative: String {
        guard let date = Self.isoFormatter.date(from: request.createdAt) else { return request.createdAt }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: .now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("friends.list.request.from", comment: "Request from label"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(request.requesterId)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
                Spacer()
                Text(relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let note = request.note, !note.isEmpty {
                Text(note)
                    .font(.body)
                    .lineLimit(4)
                    .padding(.horizontal, 4)
            }

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    onDecline()
                } label: {
                    Text(NSLocalizedString("friends.request.decline", comment: "Decline button"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    onAccept()
                } label: {
                    Text(NSLocalizedString("friends.request.accept", comment: "Accept button"))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - FriendRow

private struct FriendRow: View {
    let userId: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(userId)
                .font(.body)
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(format: NSLocalizedString("friends.list.friend.a11y", comment: "VoiceOver: friend row"), userId))
    }
}

// MARK: - EmptyFriendsView

private struct EmptyFriendsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "person.2")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
                    .scaleEffect(isBreathing ? 1.08 : 0.94)
                    .opacity(isBreathing ? 1.0 : 0.7)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                        value: isBreathing
                    )
            }
            Text(NSLocalizedString("friends.list.empty.title", comment: "Empty friends title"))
                .font(.headline)
            Text(NSLocalizedString("friends.list.empty.description", comment: "Empty friends description"))
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

// MARK: - Preview

#Preview("With friends + requests") {
    let service = FriendService()
    service.incomingRequests = [
        FriendRequest(
            id: FriendRequestId(rawValue: "freq_01"),
            requesterId: "traveler_abc",
            recipientId: "local",
            status: .pending,
            source: .companionChat,
            note: "We crossed paths in Tokyo — let's stay in touch!",
            expiresAt: "2026-07-01T10:00:00Z",
            createdAt: "2026-06-01T10:00:00Z",
            updatedAt: "2026-06-01T10:00:00Z"
        ),
    ]
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
    return NavigationStack {
        FriendsListView(service: service)
    }
}

#Preview("Empty") {
    let service = FriendService()
    service.friends = []
    service.incomingRequests = []
    return NavigationStack {
        FriendsListView(service: service)
    }
}
