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
    @State private var requestSentPostId: String?
    @State private var reportTarget: DiscoverPost?
    @State private var errorMessage: String?

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
        .sheet(item: $selectedPost) { post in
            SendRequestSheet(post: post) { note in
                Task { await sendRequest(to: post, note: note) }
            }
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
    }

    // MARK: - Subviews

    private var loadingView: some View {
        ScrollView {
            CompanionSkeletonList(rows: 5)
        }
    }

    private func errorView(message: String) -> some View {
        ContentUnavailableView(
            NSLocalizedString("companion.discover.error.title", comment: "Error title"),
            systemImage: "exclamationmark.triangle",
            description: Text(message)
        )
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label(
                NSLocalizedString("companion.discover.empty.title", comment: "No companions found title"),
                systemImage: "person.2.slash"
            )
        } description: {
            Text(NSLocalizedString("companion.discover.empty.description", comment: "No companions found description"))
        } actions: {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("companion.discover.coldstart.tip", comment: "Cold start tip"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var postList: some View {
        List(service.discoverPosts) { post in
            DiscoverPostRow(
                post: post,
                hasSentRequest: requestSentPostId == post.id,
                onSendRequest: { selectedPost = post },
                onReport: { reportTarget = post }
            )
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Actions

    private func loadPosts() async {
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
            requestSentPostId = post.id
        case .failure(let err):
            errorMessage = err.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            Task {
                try? await Task.sleep(for: .seconds(3))
                errorMessage = nil
            }
        }
    }
}

// MARK: - DiscoverPostRow

private struct DiscoverPostRow: View {
    let post: DiscoverPost
    let hasSentRequest: Bool
    let onSendRequest: () -> Void
    let onReport: () -> Void

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

            sendButton
        }
        .padding(.vertical, 4)
        .contextMenu {
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
                            Capsule().fill(Color.accentColor.opacity(0.12))
                        )
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private var sendButton: some View {
        Button {
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
        .tint(hasSentRequest ? .green : .accentColor)
        .disabled(hasSentRequest)
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
