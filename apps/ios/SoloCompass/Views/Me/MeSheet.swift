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

    @Environment(\.dismiss) private var dismiss
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ProfileHeader()
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
                        RequestInboxView()
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "Done")) { dismiss() }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(onClose: { showingSettings = false })
            }
        }
    }
}

// MARK: - Profile header

/// Lightweight identity card. US-007 only needs an entry point, so the header
/// renders the local default identity (emoji + name) rather than a fetched
/// backend profile — richer profile editing lands in a later story.
private struct ProfileHeader: View {
    var body: some View {
        HStack(spacing: 14) {
            Text(CompanionProfile.sample.avatarEmoji)
                .font(.system(size: 40))
                .frame(width: 64, height: 64)
                .background(Circle().fill(CT.accentSoft))

            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("me.profile.name", comment: "Default profile display name"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(CT.fgPrimary)
                Text(NSLocalizedString("me.profile.subtitle", comment: "Profile subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(CT.fgSubtle)
            }
            Spacer()
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
    }
}

// MARK: - Friends hub (placeholder list within the Me stack)

/// Minimal friends overview pushed from the hub. Lists confirmed friends and
/// surfaces incoming requests; the dedicated friends-management UI arrives in a
/// later FRD. Kept self-contained so US-007 wires the entry point end-to-end.
private struct FriendsHubView: View {
    @State private var service = FriendService.shared

    var body: some View {
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
                if service.friends.isEmpty {
                    Text(NSLocalizedString("me.friends.empty", comment: "No friends yet"))
                        .font(.subheadline)
                        .foregroundStyle(CT.fgSubtle)
                } else {
                    ForEach(service.friends, id: \.id) { friendship in
                        Text(friendship.userHighId)
                            .font(.subheadline)
                            .foregroundStyle(CT.fgPrimary)
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("me.friends", comment: "Friends"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await service.refresh() }
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
}

#Preview("Avatar bubble") {
    HStack(spacing: 20) {
        MapAvatarBubble(hasPendingRequests: false, action: {})
        MapAvatarBubble(hasPendingRequests: true, action: {})
    }
    .padding()
}
