import SwiftUI

/// Inbox showing pending companion requests addressed to the current user.
///
/// US-012: Users can accept (→ creates Conversation) or decline requests.
/// Accepted requests open a Conversation; declined requests are removed with
/// no further action.
public struct RequestInboxView: View {
    @State private var service: CompanionService
    @State private var acceptedConversation: Conversation?
    @State private var showingAcceptedConfirm = false
    @State private var reportTarget: CompanionRequest?
    @State private var errorMessage: String?

    public init(service: CompanionService = .shared) {
        _service = State(initialValue: service)
    }

    public var body: some View {
        Group {
            if service.isLoading {
                ScrollView {
                    CompanionSkeletonList(rows: 5)
                }
            } else if service.inboxRequests.isEmpty {
                emptyStateView
            } else {
                requestList
            }
        }
        .navigationTitle(NSLocalizedString("companion.inbox.title", comment: "Inbox nav title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await service.fetchInbox() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(NSLocalizedString("companion.inbox.refresh.a11y", comment: "Refresh inbox"))
            }
        }
        .task { await service.fetchInbox() }
        .alert(
            NSLocalizedString("companion.inbox.accepted.title", comment: "Request accepted alert title"),
            isPresented: $showingAcceptedConfirm
        ) {
            Button(NSLocalizedString("action.ok", comment: "OK")) {}
        } message: {
            Text(NSLocalizedString("companion.inbox.accepted.message", comment: "Request accepted alert message"))
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
        .sheet(item: $reportTarget) { request in
            ReportBlockSheet(
                targetUserId: request.requesterId,
                targetLabel: request.requesterId
            ) {
                service.inboxRequests.removeAll { $0.requesterId == request.requesterId }
            }
        }
    }

    // MARK: - Subviews

    private var emptyStateView: some View {
        ContentUnavailableView(
            NSLocalizedString("companion.inbox.empty.title", comment: "Empty inbox title"),
            systemImage: "tray",
            description: Text(NSLocalizedString("companion.inbox.empty.description", comment: "Empty inbox description"))
        )
    }

    private var requestList: some View {
        List(service.inboxRequests) { request in
            RequestRow(
                request: request,
                onAccept: {
                    Task { await acceptRequest(request) }
                },
                onDecline: {
                    Task { await service.declineRequest(request) }
                },
                onReport: {
                    reportTarget = request
                }
            )
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Actions

    private func acceptRequest(_ request: CompanionRequest) async {
        let result = await service.acceptRequest(request)
        switch result {
        case .success(let conversation):
            acceptedConversation = conversation
            showingAcceptedConfirm = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
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

// MARK: - RequestRow

private struct RequestRow: View {
    let request: CompanionRequest
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onReport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("companion.inbox.request.from", comment: "Request from label"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(request.requesterId)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
                Spacer()
                Text(formattedDate(request.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let note = request.note, !note.isEmpty {
                Text(note)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .padding(.horizontal, 4)
            }

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    onDecline()
                } label: {
                    Text(NSLocalizedString("companion.request.decline", comment: "Decline button"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    onAccept()
                } label: {
                    Text(NSLocalizedString("companion.request.accept", comment: "Accept button"))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button(role: .destructive) {
                onReport()
            } label: {
                Label(
                    NSLocalizedString("companion.report.block.menu", comment: "Report or block"),
                    systemImage: "flag"
                )
            }
        }
    }

    private func formattedDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        guard let date = f.date(from: iso) else { return iso }
        let display = DateFormatter()
        display.dateStyle = .short
        display.timeStyle = .none
        return display.string(from: date)
    }
}

// MARK: - Preview

#Preview("With requests") {
    let service = CompanionService()
    service.inboxRequests = [
        CompanionRequest(
            id: CompanionRequestId(rawValue: "creq_01"),
            postId: CompanionPostId(rawValue: "cpost_01"),
            requesterId: "traveler_abc",
            recipientId: "me",
            status: .pending,
            note: "Hey! I'll also be in Tokyo then. Would love to explore hidden coffee shops together.",
            createdAt: "2026-02-01T10:00:00Z",
            updatedAt: "2026-02-01T10:00:00Z"
        ),
        CompanionRequest(
            id: CompanionRequestId(rawValue: "creq_02"),
            postId: CompanionPostId(rawValue: "cpost_02"),
            requesterId: "traveler_xyz",
            recipientId: "me",
            status: .pending,
            note: nil,
            createdAt: "2026-02-03T08:00:00Z",
            updatedAt: "2026-02-03T08:00:00Z"
        ),
    ]
    return NavigationStack {
        RequestInboxView(service: service)
    }
}

#Preview("Empty inbox") {
    NavigationStack {
        RequestInboxView()
    }
}

#Preview("Loading skeleton") {
    NavigationStack {
        ScrollView {
            CompanionSkeletonList(rows: 5)
        }
        .navigationTitle(NSLocalizedString("companion.inbox.title", comment: "Inbox nav title"))
        .navigationBarTitleDisplayMode(.large)
    }
}
