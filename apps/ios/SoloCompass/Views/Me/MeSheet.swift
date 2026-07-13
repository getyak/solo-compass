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
    @Environment(\.modelContext) private var modelContext
    @State private var showingSettings = false
    /// P1.3 #132: top-level archive/me segmented switch. Defaults to `.me`
    /// so the existing entry-point UX is unchanged on first launch.
    @State private var topTab: TopTab = .me

    /// Two top-level sections inside MeSheet. Archive surfaces the new
    /// Travel Archive (P1.1 #111); Me keeps the existing profile + social +
    /// settings hub intact.
    private enum TopTab: String, CaseIterable, Identifiable {
        case archive
        case me
        var id: String { rawValue }
        var label: String {
            switch self {
            case .archive: return NSLocalizedString("me.tab.archive", comment: "Top-tab label for travel archive")
            case .me:      return NSLocalizedString("me.tab.me", comment: "Top-tab label for the personal hub")
            }
        }
    }
    /// Platform role gate for the moderation entry. Refreshed on appear; the
    /// admin/moderator section only renders once `canModerate` is true.
    @State private var admin = AdminService.shared
    /// Programmatic nav path so a `message` deep link can push the Messages hub.
    @State private var path: [MeDestination] = []

    /// Destinations reachable programmatically (deep links). Row taps still use
    /// inline `NavigationLink`s; only the message deep link drives `path`.
    private enum MeDestination: Hashable {
        case messages(deepLinkConversationId: String?)
        case friends
    }

    var body: some View {
        NavigationStack(path: $path) {
            // P1.3 #132: archive | me segmented switch sits above the existing
            // hub. The Me list is unchanged inside .me; Archive (P1.1 #111)
            // takes the same NavigationStack slot in .archive.
            VStack(spacing: 0) {
                Picker("", selection: $topTab) {
                    ForEach(TopTab.allCases) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if topTab == .archive {
                    ArchiveView(modelContainer: modelContext.container)
                } else {
                    List {
                Section {
                    // One-tap to edit profile — previously buried under
                    // Companion Hub → My Profile (3 taps). NavigationLink wraps
                    // the whole header so the avatar/name/stats area is the
                    // hit-target; .plain buttonStyle suppresses the chevron
                    // so the identity-card look is unchanged.
                    NavigationLink {
                        MyProfileEditView()
                    } label: {
                        ProfileHeader(
                            favoritedCount: preferences.favoritedExperiences.count,
                            exploredCount: preferences.completedExperiences.count
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                // Subscription status banner — shows trial progress for
                // mid-trial users, Pro renewal date for paying users, and
                // the "start free month" CTA for free users. Tappable in
                // every state: routes to PaywallView (handles its own
                // mid-trial vs upsell rendering).
                Section {
                    EntitlementBanner()
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }

                if preferences.favoritedExperiences.isEmpty {
                    Section {
                        MeEmptyStateCard()
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
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

                // Moderation — only visible to platform moderators/admins.
                // `canModerate` is false until `admin.refreshRole()` lands, so a
                // plain user never sees this section.
                if admin.canModerate {
                    Section(NSLocalizedString("me.admin.section", comment: "Admin tools section")) {
                        NavigationLink {
                            ModerationView()
                        } label: {
                            MeRow(
                                systemImage: "shield.lefthalf.filled",
                                title: NSLocalizedString("me.moderation", comment: "Moderation queue row"),
                                badge: admin.reports.filter { $0.resolvedAt == nil }.count
                            )
                        }
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
                    } // close List
                } // close else
            } // close VStack
            .navigationTitle(NSLocalizedString("me.title", comment: "Personal hub title"))
            .navigationBarTitleDisplayMode(.inline)
            .task {
                // Resolve the platform role so the moderation section can appear.
                // Cheap + cached; a non-moderator just gets `.user` back.
                await admin.refreshRole()
                if admin.canModerate { await admin.refreshReports() }
            }
            .navigationDestination(for: MeDestination.self) { destination in
                switch destination {
                case .messages(let conversationId):
                    ConversationListView(deepLinkConversationId: conversationId)
                case .friends:
                    FriendsHubView()
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
                #if DEBUG
                // Visual-verification entry point: `-openFriends` pushes the
                // Friends hub on appear so its inline add-by-code search can be
                // screenshotted without an unreliable simulator tap.
                if ProcessInfo.processInfo.arguments.contains("-openFriends"), path.isEmpty {
                    path = [.friends]
                }
                // Goal-audit entry point: `-openArchive` flips the top segmented
                // switch to the Archive tab so simctl screenshot can capture the
                // Rituals hub without a tap on the Picker chip.
                if ProcessInfo.processInfo.arguments.contains("-openArchive") {
                    topTab = .archive
                }
                if ProcessInfo.processInfo.arguments.contains("-openSettings") {
                    showingSettings = true
                }
                #endif
            }
        }
    }
}

// MARK: - Ring avatar

private struct RingAvatar: View {
    let favoritedCount: Int
    let exploredCount: Int
    /// Diameter of the inner emoji bubble; the progress ring sits 8pt outside it.
    var size: CGFloat = 64

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedFraction: CGFloat = 0

    private var targetFraction: CGFloat {
        guard favoritedCount > 0 else { return 0 }
        return CGFloat(min(exploredCount, favoritedCount)) / CGFloat(favoritedCount)
    }

    private var showRing: Bool { favoritedCount > 0 }
    private var ringSize: CGFloat { size + 8 }
    private var ringWidth: CGFloat { size >= 80 ? 4 : 3 }

    var body: some View {
        ZStack {
            Text(CompanionProfile.sample.avatarEmoji)
                .font(.system(size: size * 0.55))
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(CT.accentSoft)
                        .overlay(Circle().stroke(CT.surfaceWhite, lineWidth: 2))
                )
                .shadow(color: CT.accent.opacity(0.12), radius: 6, y: 3)

            if showRing {
                Circle()
                    .stroke(CT.accent.opacity(0.15), lineWidth: ringWidth)
                    .frame(width: ringSize, height: ringSize)
                Circle()
                    .trim(from: 0, to: animatedFraction)
                    .stroke(CT.accent, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: ringSize, height: ringSize)
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
        VStack(spacing: 16) {
            RingAvatar(
                favoritedCount: favoritedCount,
                exploredCount: exploredCount,
                size: 88
            )
            .padding(.top, 4)

            VStack(spacing: 4) {
                Text(NSLocalizedString("me.profile.name", comment: "Default profile display name"))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(CT.fgPrimary)
                Text(NSLocalizedString("me.profile.subtitle", comment: "Profile subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(CT.fgMuted)
            }

            // Twin stat tiles, split by a hairline divider so the two metrics read
            // as one balanced unit rather than two floating pills.
            HStack(spacing: 0) {
                StatTile(
                    target: favoritedCount,
                    caption: NSLocalizedString("me.stats.saved", comment: "Saved experiences stat label")
                )
                Rectangle()
                    .fill(CT.borderSubtle)
                    .frame(width: 1, height: 36)
                StatTile(
                    target: exploredCount,
                    caption: NSLocalizedString("me.stats.explored", comment: "Explored experiences stat label")
                )
            }
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(CT.surfaceWhite)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(CT.borderSubtle, lineWidth: 1)
                    )
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [CT.accentSoft, CT.surfaceWhite],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(CT.accentBorder, lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

// MARK: - Stat pill

private struct StatTile: View {
    let target: Int
    let caption: String

    @State private var shown: Int = 0
    @State private var pop: Bool = false
    @State private var rollTask: Task<Void, Never>? = nil
    /// True after the initial onAppear roll completes so onChange can fire haptics.
    @State private var initialRollDone: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 2) {
            Text("\(shown)")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(CT.accent)
                .contentTransition(.numericText())
                .scaleEffect(pop ? 1.18 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: pop)
            Text(caption)
                .font(.caption)
                .foregroundStyle(CT.fgMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(target) \(caption)"))
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

// `FriendsHubView` (pushed from the Friends row above) now lives in its own
// file — Views/Friends/FriendsHubView.swift — where the add-by-code search is
// inlined at the top of the page instead of behind a separate AddFriendSheet.

// MARK: - Row

private struct MeRow: View {
    let systemImage: String
    let title: String
    var badge: Int = 0

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? CT.sunGoldSoft : CT.accent)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(colorScheme == .dark ? CT.warmSunkenDark : CT.accentSoft)
                )
            Text(title)
                .font(.body)
                .foregroundStyle(colorScheme == .dark ? CT.fgPrimaryDark : CT.fgPrimary)
            Spacer()
            if badge > 0 {
                Text("\(badge)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(CT.savedRed))
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Empty-state guidance

private struct MeEmptyStateCard: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "map.fill")
                .font(.system(size: 36))
                .foregroundStyle(CT.accent)

            Text(NSLocalizedString("me.empty.title", comment: "Empty state title"))
                .font(.headline)
                .multilineTextAlignment(.center)

            Text(NSLocalizedString("me.empty.subtitle", comment: "Empty state subtitle"))
                .font(.subheadline)
                .foregroundStyle(colorScheme == .dark ? CT.fgMutedDark : CT.fgMuted)
                .multilineTextAlignment(.center)

            Button {
                dismiss()
            } label: {
                Text(NSLocalizedString("me.empty.cta", comment: "Back to map CTA"))
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(CT.accent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? CT.warmCardDark : CT.surfaceWhite)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(CT.borderSubtle, lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
                    // Plain thin material, NOT glassSurface: this bubble floats over the
                    // raw map in the top overlay row, and glass surfaces are forbidden
                    // over the map (markers scroll under it → sunGold vibrancy fringe).
                    // Thin material was the goal (regular too heavy) without glass.
                    .background(.thinMaterial, in: Circle())
                    .elevation(.card)

                if hasPendingRequests {
                    Circle()
                        .fill(CT.savedRed)
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
        RingAvatar(favoritedCount: 0, exploredCount: 0, size: 88)   // no ring
        RingAvatar(favoritedCount: 5, exploredCount: 0, size: 88)   // 0%
        RingAvatar(favoritedCount: 5, exploredCount: 2, size: 88)   // 40%
        RingAvatar(favoritedCount: 5, exploredCount: 5, size: 88)   // 100%
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
