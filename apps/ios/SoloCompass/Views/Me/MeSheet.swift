import SwiftUI

/// US-007: the personal hub reachable from the map.
///
/// A top-right emoji avatar bubble on `CompassMapView` (`MapAvatarBubble`)
/// presents this sheet. It hosts the user's profile header plus the four
/// social/identity entry points — Friends, Messages, Companion, Settings —
/// inside its own `NavigationStack` so each pushes a detail view.
///
/// Settings keeps its own `NavigationStack`, so it is presented as a nested
/// sheet rather than pushed (two stacked stacks would double the nav bar).
struct MeSheet: View {
    /// Whether the avatar showed a pending-request dot when this sheet opened.
    /// Surfaced as a badge on the Friends row so the hub mirrors the bubble.
    var pendingRequestCount: Int = 0

    /// US-024: when the hub is opened from a tapped `message` push, this carries
    /// the target conversation id. On appear we push the Messages list (which
    /// auto-opens the matching ChatView). `nil` for any other entry point.
    var deepLinkConversationId: String? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(UserPreferences.self) private var preferences
    @State private var showingSettings = false
    /// Programmatic nav path so a `message` deep link can push the Messages hub.
    @State private var path: [MeDestination] = []

    /// Destinations reachable programmatically (deep links). Row taps still use
    /// inline `NavigationLink`s; only the message deep link drives `path`.
    private enum MeDestination: Hashable {
        case messages(deepLinkConversationId: String?)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ProfileHeader(
                        favoritedCount: preferences.favoritedExperiences.count,
                        exploredCount: preferences.completedExperiences.count
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    NavigationLink {
                        FriendsHubView()
                    } label: {
                        MeRow(
                            systemImage: "person.2.fill",
                            title: NSLocalizedString("me.friends", comment: "Friends hub row"),
                            badge: pendingRequestCount
                        )
                    }
                    NavigationLink {
                        // US-017: unified inbox — friend DMs + companion 1:1 +
                        // route group chats, time-sorted in a single list.
                        ConversationListView()
                    } label: {
                        MeRow(
                            systemImage: "bubble.left.and.bubble.right.fill",
                            title: NSLocalizedString("me.messages", comment: "Messages hub row")
                        )
                    }
                    NavigationLink {
                        CompanionProfileView()
                    } label: {
                        MeRow(
                            systemImage: "figure.2.arms.open",
                            title: NSLocalizedString("me.companion", comment: "Companion hub row")
                        )
                    }
                }

                Section {
                    Button {
                        showingSettings = true
                    } label: {
                        MeRow(
                            systemImage: "gearshape.fill",
                            title: NSLocalizedString("me.settings", comment: "Settings hub row")
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(NSLocalizedString("me.title", comment: "Personal hub title"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: MeDestination.self) { destination in
                switch destination {
                case .messages(let conversationId):
                    ConversationListView(deepLinkConversationId: conversationId)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "Done")) { dismiss() }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(onClose: { showingSettings = false })
            }
            .onAppear {
                // US-024: a tapped message push routes straight into the Messages
                // hub, which then auto-opens the matching ChatView.
                if let conversationId = deepLinkConversationId, path.isEmpty {
                    path = [.messages(deepLinkConversationId: conversationId)]
                }
            }
        }
    }
}

// MARK: - Ring avatar

private struct RingAvatar: View {
    let favoritedCount: Int
    let exploredCount: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedFraction: CGFloat = 0

    private var targetFraction: CGFloat {
        guard favoritedCount > 0 else { return 0 }
        return CGFloat(min(exploredCount, favoritedCount)) / CGFloat(favoritedCount)
    }

    private var showRing: Bool { favoritedCount > 0 }

    var body: some View {
        ZStack {
            Text(CompanionProfile.sample.avatarEmoji)
                .font(.system(size: 40))
                .frame(width: 64, height: 64)
                .background(Circle().fill(CT.accentSoft))

            if showRing {
                Circle()
                    .stroke(CT.accent.opacity(0.15), lineWidth: 3)
                    .frame(width: 72, height: 72)
                Circle()
                    .trim(from: 0, to: animatedFraction)
                    .stroke(CT.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 72, height: 72)
            }
        }
        .accessibilityLabel(Text(CompanionProfile.sample.avatarEmoji))
        .accessibilityValue(showRing ? Text(
            String(format: NSLocalizedString("me.profile.progress.a11y", comment: "Profile progress ring accessibility value"),
                   min(exploredCount, favoritedCount), favoritedCount)
        ) : Text(""))
        .onAppear {
            let target = targetFraction
            if reduceMotion {
                animatedFraction = target
            } else {
                withAnimation(.easeInOut(duration: 0.6)) { animatedFraction = target }
            }
        }
        .onChange(of: exploredCount) { _, _ in
            let target = targetFraction
            if reduceMotion {
                animatedFraction = target
            } else {
                withAnimation(.easeInOut(duration: 0.6)) { animatedFraction = target }
            }
        }
        .onChange(of: favoritedCount) { _, _ in
            let target = targetFraction
            if reduceMotion {
                animatedFraction = target
            } else {
                withAnimation(.easeInOut(duration: 0.6)) { animatedFraction = target }
            }
        }
    }
}

// MARK: - Profile header

/// Lightweight identity card. US-007 only needs an entry point, so the header
/// renders the local default identity (emoji + name) rather than a fetched
/// backend profile — richer profile editing lands in a later story.
private struct ProfileHeader: View {
    let favoritedCount: Int
    let exploredCount: Int

    var body: some View {
        HStack(spacing: 14) {
            RingAvatar(favoritedCount: favoritedCount, exploredCount: exploredCount)

            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("me.profile.name", comment: "Default profile display name"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(CT.fgPrimary)
                Text(NSLocalizedString("me.profile.subtitle", comment: "Profile subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(CT.fgSubtle)
                HStack(spacing: 12) {
                    StatPill(
                        target: favoritedCount,
                        caption: NSLocalizedString("me.stats.saved", comment: "Saved experiences stat label")
                    )
                    StatPill(
                        target: exploredCount,
                        caption: NSLocalizedString("me.stats.explored", comment: "Explored experiences stat label")
                    )
                }
                .padding(.top, 4)
            }
            Spacer()
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
    }
}

// MARK: - Stat pill

private struct StatPill: View {
    let target: Int
    let caption: String

    @State private var shown: Int = 0
    @State private var pop: Bool = false
    @State private var rollTask: Task<Void, Never>? = nil
    /// True after the initial onAppear roll completes so onChange can fire haptics.
    @State private var initialRollDone: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            Text("\(shown)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(CT.fgPrimary)
                .contentTransition(.numericText())
                .scaleEffect(pop ? 1.18 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: pop)
            Text(caption)
                .font(.caption)
                .foregroundStyle(CT.fgSubtle)
        }
        .onAppear {
            if reduceMotion {
                shown = target
                initialRollDone = true
            } else {
                startRoll(to: target, markDoneOnLanding: true)
            }
        }
        .onChange(of: target) { old, new in
            if reduceMotion {
                shown = new
                return
            }
            startRoll(to: new, markDoneOnLanding: false)
            // Haptic only on genuine increases that happen after the initial appear roll.
            if new > old, initialRollDone {
                #if canImport(UIKit)
                Haptics.selection()
                #endif
            }
        }
    }

    private func startRoll(to newTarget: Int, markDoneOnLanding: Bool) {
        rollTask?.cancel()
        rollTask = Task {
            await roll(to: newTarget, markDoneOnLanding: markDoneOnLanding)
        }
    }

    private func roll(to newTarget: Int, markDoneOnLanding: Bool) async {
        let start = shown
        let delta = abs(newTarget - start)
        let steps = min(delta, 20)
        guard steps > 0 else {
            shown = newTarget
            if markDoneOnLanding { initialRollDone = true }
            return
        }
        for step in 1...steps {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: 30_000_000)
            guard !Task.isCancelled else { return }
            shown = start + (newTarget - start) * step / steps
        }
        shown = newTarget
        if markDoneOnLanding { initialRollDone = true }
        // Spring scale-pop on landing.
        pop = true
        try? await Task.sleep(nanoseconds: 350_000_000)
        pop = false
    }
}

// MARK: - Friends hub (placeholder list within the Me stack)

/// Minimal friends overview pushed from the hub. Lists confirmed friends and
/// surfaces incoming requests; the dedicated friends-management UI arrives in a
/// later FRD. Kept self-contained so US-007 wires the entry point end-to-end.
private struct FriendsHubView: View {
    @State private var service = FriendService.shared
    @State private var showingAddFriend = false

    var body: some View {
        Group {
            if service.friends.isEmpty && service.incomingRequests.isEmpty {
                emptyState
            } else {
                friendList
            }
        }
        .navigationTitle(NSLocalizedString("me.friends", comment: "Friends"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await service.refresh() }
        .sheet(isPresented: $showingAddFriend) {
            AddFriendSheet()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                NSLocalizedString("me.friends.empty.title", comment: "Friends empty state title"),
                systemImage: "person.2.slash"
            )
        } description: {
            Text(NSLocalizedString("me.friends.empty.description", comment: "Friends empty state description"))
        } actions: {
            Button {
                Haptics.impact(.light)
                showingAddFriend = true
            } label: {
                Text(NSLocalizedString("me.friends.empty.cta", comment: "Add a friend CTA"))
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var friendList: some View {
        List {
            if !service.incomingRequests.isEmpty {
                Section(NSLocalizedString("me.friends.incoming", comment: "Incoming friend requests")) {
                    ForEach(service.incomingRequests, id: \.id) { req in
                        Text(req.requesterId)
                            .font(.subheadline)
                            .foregroundStyle(CT.fgPrimary)
                    }
                }
            }
            Section(NSLocalizedString("me.friends.list", comment: "Friends list")) {
                ForEach(service.friends, id: \.id) { friendship in
                    Text(friendship.userHighId)
                        .font(.subheadline)
                        .foregroundStyle(CT.fgPrimary)
                }
            }
        }
    }
}

// MARK: - FriendsHubView Preview

#Preview("Friends empty state") {
    NavigationStack {
        FriendsHubView()
    }
}

// MARK: - Row

private struct MeRow: View {
    let systemImage: String
    let title: String
    var badge: Int = 0

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(CT.accent)
                .frame(width: 28)
            Text(title)
                .font(.body)
                .foregroundStyle(CT.fgPrimary)
            Spacer()
            if badge > 0 {
                Text("\(badge)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.red))
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Map avatar bubble

/// US-007: the top-right entry point into `MeSheet`. Lives in the map's
/// safe-area overlay (never the status bar). Shows a red dot when there are
/// pending friend requests so the hub is discoverable at a glance.
struct MapAvatarBubble: View {
    let hasPendingRequests: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Text(CompanionProfile.sample.avatarEmoji)
                    .font(.system(size: 22))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.regularMaterial))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)

                if hasPendingRequests {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .offset(x: 2, y: -2)
                }
            }
        }
        .accessibilityLabel(Text(NSLocalizedString("me.avatar.a11y", comment: "Open personal hub")))
        .accessibilityValue(
            hasPendingRequests
                ? Text(NSLocalizedString("me.avatar.a11y.pending", comment: "Pending friend requests"))
                : Text("")
        )
        .accessibilityIdentifier("mapAvatarBubble")
    }
}

#Preview("MeSheet") {
    MeSheet(pendingRequestCount: 2)
        .environment(UserPreferences())
}

#Preview("RingAvatar states") {
    HStack(spacing: 24) {
        RingAvatar(favoritedCount: 0, exploredCount: 0)   // no ring
        RingAvatar(favoritedCount: 5, exploredCount: 0)   // 0%
        RingAvatar(favoritedCount: 5, exploredCount: 2)   // 40%
        RingAvatar(favoritedCount: 5, exploredCount: 5)   // 100%
    }
    .padding()
}

#Preview("Avatar bubble") {
    HStack(spacing: 20) {
        MapAvatarBubble(hasPendingRequests: false, action: {})
        MapAvatarBubble(hasPendingRequests: true, action: {})
    }
    .padding()
}
