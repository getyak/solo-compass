import SwiftUI

/// Companion discovery list — shows anonymized companion posts from the
/// companion-discover Edge Function.
///
/// US-011: Each row shows emoji handle, blurb, dates, and categories.
/// No real user identities or coordinates are displayed.
/// US-012: Each row has a "Send request" button that opens the request sheet.
public struct DiscoverListView: View {
    let cityCode: String

    @Environment(UserPreferences.self) private var preferences
    @State private var service: CompanionService
    @State private var selectedPost: DiscoverPost?
    /// US-016: post tapped to open the trust-gated [Add Friend] detail.
    @State private var addFriendTarget: DiscoverPost?
    @State private var sentRequestIds: Set<String> = []
    @State private var reportTarget: DiscoverPost?
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var showPostSheet = false

    public init(cityCode: String, service: CompanionService = .shared) {
        self.cityCode = cityCode
        _service = State(initialValue: service)
    }

    public var body: some View {
        Group {
            if service.isLoading {
                loadingView
            } else if let error = service.lastError {
                errorView(message: error)
            } else if service.discoverPosts.isEmpty {
                emptyStateView
            } else {
                postList
            }
        }
        .navigationTitle(NSLocalizedString("companion.discover.title", comment: "Discover nav title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await loadPosts() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(NSLocalizedString("companion.discover.refresh.a11y", comment: "Refresh accessibility label"))
            }
        }
        .task { await loadPosts() }
        .overlay(alignment: .bottom) {
            if let msg = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(msg)
                        .font(.subheadline)
                        .lineLimit(2)
                }
                .foregroundStyle(CT.savedRed)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityLabel(msg)
            }
        }
        .animation(.easeInOut, value: errorMessage)
        .overlay(alignment: .bottom) {
            if let msg = successMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(msg)
                        .font(.subheadline)
                        .lineLimit(2)
                }
                .foregroundStyle(CT.verifiedGreen)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityLabel(msg)
            }
        }
        .animation(.easeInOut, value: successMessage)
        .sheet(item: $selectedPost) { post in
            SendRequestSheet(post: post) { note in
                Task { await sendRequest(to: post, note: note) }
            }
        }
        .sheet(isPresented: $showPostSheet) {
            OpenForCompanionsSheet(itinerary: Self.newAvailabilityItinerary(cityCode: cityCode))
        }
        .sheet(item: $reportTarget) { post in
            ReportBlockSheet(
                targetUserId: post.id,
                targetLabel: post.handle
            ) {
                // Remove blocked post from the list immediately.
                service.discoverPosts.removeAll { $0.id == post.id }
            }
        }
        .sheet(item: $addFriendTarget) { post in
            DiscoverPostDetailView(post: post)
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        ScrollView {
            CompanionSkeletonList(rows: 5)
        }
    }

    private func errorView(message: String) -> some View {
        ContentUnavailableView {
            Label(
                NSLocalizedString("companion.discover.error.title", comment: "Error title"),
                systemImage: "exclamationmark.triangle"
            )
        } description: {
            Text(message)
        } actions: {
            Button {
                Haptics.impact(.light)
                Task { await loadPosts() }
            } label: {
                Label(
                    NSLocalizedString("companion.discover.error.retry", comment: "Retry button"),
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint(NSLocalizedString("companion.discover.error.retry.hint", comment: "Retry accessibility hint"))
        }
    }

    private var emptyStateView: some View {
        EmptyCompanionState(onPostTapped: { showPostSheet = true })
    }

    private var postList: some View {
        List {
            ForEach(Array(service.discoverPosts.enumerated()), id: \.element.id) { index, post in
                DiscoverPostRow(
                    post: post,
                    index: index,
                    hasSentRequest: sentRequestIds.contains(post.id),
                    onSendRequest: { selectedPost = post },
                    onReport: { reportTarget = post },
                    onAddFriend: { addFriendTarget = post }
                )
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await loadPosts() }
    }

    // MARK: - Actions

    private static func newAvailabilityItinerary(cityCode: String) -> Itinerary {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        let now = Date()
        let startDate = fmt.string(from: now)
        let endDate = fmt.string(from: now.addingTimeInterval(86400 * 7))
        let isoFmt = ISO8601DateFormatter()
        let ts = isoFmt.string(from: now)
        return Itinerary(
            id: ItineraryId(rawValue: "cta_\(cityCode)_\(UUID().uuidString)"),
            ownerId: DeviceIdentityService.shared.deviceID,
            title: cityCode,
            cityCode: cityCode,
            startDate: startDate,
            endDate: endDate,
            experienceIds: [],
            note: nil,
            openToCompanions: true,
            createdAt: ts,
            updatedAt: ts
        )
    }

    private func loadPosts() async {
        Haptics.impact(.light)
        let params = CompanionDiscoverParams(cityCode: cityCode)
        await service.fetchDiscovery(params: params)
    }

    private func sendRequest(to post: DiscoverPost, note: String?) async {
        // The post's real author_id is not exposed in DiscoverPost (anonymized).
        // We pass the post id; the Edge Function/backend resolves the recipient.
        // For local-first mode (companion FF off), sendRequest is a no-op.
        let result = await service.sendRequest(
            postId: CompanionPostId(rawValue: post.id),
            recipientId: post.id, // placeholder — resolved server-side
            note: note
        )
        switch result {
        case .success:
            withAnimation(.easeInOut) { sentRequestIds.insert(post.id) }
            Haptics.notify(.success)
            let msg = NSLocalizedString("companion.request.sent.confirm", comment: "Companion request sent confirmation toast")
            successMessage = msg
            UIAccessibility.post(notification: .announcement, argument: msg)
            Task {
                try? await Task.sleep(for: .seconds(3))
                successMessage = nil
            }
        case .failure(let err):
            errorMessage = err.localizedDescription
            Haptics.notify(.error)
            Task {
                try? await Task.sleep(for: .seconds(3))
                errorMessage = nil
            }
        }
    }
}

// MARK: - EmptyCompanionState

private struct EmptyCompanionState: View {
    let onPostTapped: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(CT.accent.opacity(pulse ? 0.6 : 0.35))
                    .frame(width: 80, height: 80)
                    .scaleEffect(pulse ? 1.08 : 0.9)

                Image(systemName: "person.2.slash")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(CT.accent)
            }
            .onAppear {
                if reduceMotion {
                    pulse = true
                    appeared = true
                } else {
                    withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                    withAnimation(.easeOut(duration: 0.4)) {
                        appeared = true
                    }
                }
            }

            VStack(spacing: 8) {
                Text(NSLocalizedString("companion.discover.empty.title", comment: "No companions found title"))
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text(NSLocalizedString("companion.discover.empty.description", comment: "No companions found description"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 6)
                    .animation(reduceMotion ? .none : .easeOut(duration: 0.4).delay(0.1), value: appeared)
            }

            VStack(spacing: 12) {
                Text(NSLocalizedString("companion.discover.coldstart.tip", comment: "Cold start tip"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    Haptics.impact(.light)
                    onPostTapped()
                } label: {
                    Text(NSLocalizedString("companion.discover.empty.cta", comment: "Post your availability CTA"))
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint(NSLocalizedString("companion.discover.empty.cta.hint", comment: "Post your availability accessibility hint"))
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 6)
            .animation(reduceMotion ? .none : .easeOut(duration: 0.4).delay(0.2), value: appeared)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - DiscoverPostRow

private struct DiscoverPostRow: View {
    let post: DiscoverPost
    let index: Int
    let hasSentRequest: Bool
    let onSendRequest: () -> Void
    let onReport: () -> Void
    /// US-016: open the trust-gated [Add Friend] detail for this post.
    let onAddFriend: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var pressed = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Text(post.handle)
                    .font(.system(size: 36))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(post.blurb)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(3)

                    if let from = post.activeFrom, let to = post.activeTo {
                        Text(formattedDateRange(from: from, to: to))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !post.categories.isEmpty {
                categoryPills
            }

            HStack(spacing: 8) {
                sendButton
                addFriendButton
            }
        }
        .padding(.vertical, 4)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.3).delay(min(Double(index) * 0.05, 0.4))) {
                    appeared = true
                }
            }
        }
        .contextMenu {
            Button {
                onAddFriend()
            } label: {
                Label(
                    NSLocalizedString("friend.add.state.add", comment: "Add friend menu item"),
                    systemImage: "person.badge.plus"
                )
            }
            Button(role: .destructive) {
                onReport()
            } label: {
                Label(
                    NSLocalizedString("companion.report.block.menu", comment: "Report or block menu item"),
                    systemImage: "flag"
                )
            }
        }
    }

    private var categoryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(post.categories, id: \.self) { cat in
                    Text(cat.capitalized)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(CT.accent.opacity(0.12))
                        )
                        .foregroundStyle(CT.accent)
                }
            }
        }
    }

    private var sendButton: some View {
        Button {
            Haptics.selection()
            onSendRequest()
        } label: {
            Label(
                hasSentRequest
                    ? NSLocalizedString("companion.request.sent", comment: "Request already sent")
                    : NSLocalizedString("companion.request.send", comment: "Send companion request"),
                systemImage: hasSentRequest ? "checkmark.circle.fill" : "person.badge.plus"
            )
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(hasSentRequest ? .green : CT.accent)
        .disabled(hasSentRequest)
        .scaleEffect(pressed ? 0.96 : 1)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !reduceMotion, !pressed else { return }
                    withAnimation(.easeOut(duration: 0.12)) { pressed = true }
                }
                .onEnded { _ in
                    guard !reduceMotion else { return }
                    withAnimation(.easeOut(duration: 0.12)) { pressed = false }
                }
        )
    }

    /// US-016: opens the trust-gated [Add Friend] detail for this post.
    private var addFriendButton: some View {
        Button {
            Haptics.selection()
            onAddFriend()
        } label: {
            Label(
                NSLocalizedString("friend.add.state.add", comment: "Add friend"),
                systemImage: "person.badge.plus"
            )
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(CT.accent)
    }

    private func formattedDateRange(from: String, to: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        guard let fromDate = f.date(from: from), let toDate = f.date(from: to) else {
            return "\(from) – \(to)"
        }
        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .none
        return "\(display.string(from: fromDate)) – \(display.string(from: toDate))"
    }
}

// MARK: - Preview

#Preview("With posts") {
    NavigationStack {
        DiscoverListView(cityCode: "TYO")
    }
    .environment(UserPreferences())
}

#Preview("Empty state") {
    NavigationStack {
        DiscoverListView(cityCode: "DPS")
    }
    .environment(UserPreferences())
}

#Preview("Loading skeleton") {
    NavigationStack {
        ScrollView {
            CompanionSkeletonList(rows: 5)
        }
        .navigationTitle(NSLocalizedString("companion.discover.title", comment: "Discover nav title"))
        .navigationBarTitleDisplayMode(.large)
    }
    .environment(UserPreferences())
}
