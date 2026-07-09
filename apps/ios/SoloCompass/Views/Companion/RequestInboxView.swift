import SwiftUI

/// Inbox showing pending companion requests addressed to the current user.
///
/// US-012: Users can accept (→ creates Conversation) or decline requests.
/// Accepted requests open a Conversation; declined requests are removed with
/// no further action. Declining shows an undo bar for a few seconds before
/// the decline is committed to CompanionService.
public struct RequestInboxView: View {
    @State private var service: CompanionService
    @State private var acceptedConversation: Conversation?
    @State private var showingAcceptedConfirm = false
    @State private var reportTarget: CompanionRequest?
    @State private var errorMessage: String?
    @State private var pulse = false
    @State private var lastDeclined: CompanionRequest?
    @State private var undoDismissTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn

    private var undoDismissSeconds: Double { voiceOverOn ? 12 : 4 }

    public init(service: CompanionService = .shared) {
        _service = State(initialValue: service)
    }

    private var pendingCount: Int {
        service.inboxRequests.filter { $0.status == .pending }.count
    }

    public var body: some View {
        Group {
            if service.isLoading {
                ScrollView {
                    CompanionSkeletonList(rows: 5)
                }
            } else if let error = service.lastError {
                errorView(message: error)
            } else if service.inboxRequests.isEmpty {
                EmptyInboxView()
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
            } else {
                requestList
            }
        }
        .navigationTitle(NSLocalizedString("companion.inbox.title", comment: "Inbox nav title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if pendingCount > 0 {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 4) {
                        Image(systemName: "bell.badge.fill")
                            .accessibilityHidden(true)
                        Text(String(format: NSLocalizedString("companion.inbox.pending.count", comment: "Pending request count pill"), pendingCount))
                            .contentTransition(.numericText())
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CT.warningText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(CT.warningSoft, in: Capsule())
                    .opacity(!reduceMotion ? (pulse ? 1.0 : 0.65) : 1.0)
                    .animation(
                        !reduceMotion ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true) : .none,
                        value: pulse
                    )
                    .animation(.easeInOut, value: pendingCount)
                    .accessibilityLabel(String(format: NSLocalizedString("companion.inbox.pending.count.a11y", comment: "VoiceOver: pending requests count"), pendingCount))
                    .onAppear {
                        guard !pulse, !reduceMotion else { return }
                        pulse = true
                    }
                }
            }
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
            if lastDeclined != nil {
                undoBar
                    .transition(reduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 16)
            }
        }
        .animation(.easeInOut, value: lastDeclined != nil)
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

    private func errorView(message: String) -> some View {
        ContentUnavailableView {
            Label(
                NSLocalizedString("companion.inbox.error.title", comment: "Inbox error title"),
                systemImage: "exclamationmark.triangle"
            )
        } description: {
            Text(message)
        } actions: {
            Button {
                Haptics.impact(.light)
                Task { await service.fetchInbox() }
            } label: {
                Label(
                    NSLocalizedString("companion.inbox.error.retry", comment: "Retry button"),
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint(NSLocalizedString("companion.inbox.error.retry.hint", comment: "Retry accessibility hint"))
        }
    }

    private var requestList: some View {
        List(service.inboxRequests) { request in
            RequestRow(
                request: request,
                onAccept: {
                    Task { await acceptRequest(request) }
                },
                onDecline: {
                    declineWithUndo(request)
                },
                onReport: {
                    reportTarget = request
                }
            )
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await service.fetchInbox()
        }
    }

    // MARK: - Actions

    private func acceptRequest(_ request: CompanionRequest) async {
        let result = await service.acceptRequest(request)
        switch result {
        case .success(let conversation):
            acceptedConversation = conversation
            showingAcceptedConfirm = true
            Haptics.notify(.success)
        case .failure(let err):
            errorMessage = err.localizedDescription
            Haptics.notify(.error)
            Task {
                try? await Task.sleep(for: .seconds(3))
                errorMessage = nil
            }
        }
    }

    private func declineWithUndo(_ request: CompanionRequest) {
        // Cancel any in-flight dismiss from a prior decline
        undoDismissTask?.cancel()
        // If there was already a pending decline, commit it immediately
        if let previous = lastDeclined {
            Task { await service.declineRequest(previous) }
        }
        // Optimistically remove from inbox
        withAnimation(.easeInOut) {
            service.inboxRequests.removeAll { $0.id == request.id }
        }
        lastDeclined = request
        UIAccessibility.post(
            notification: .announcement,
            argument: NSLocalizedString("companion.inbox.declined.announcement", comment: "VoiceOver: request declined, undo available")
        )
        let dismissSeconds = undoDismissSeconds
        undoDismissTask = Task {
            try? await Task.sleep(for: .seconds(dismissSeconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut) { lastDeclined = nil }
            }
            await service.declineRequest(request)
        }
    }

    private func performUndo() {
        guard let request = lastDeclined else { return }
        undoDismissTask?.cancel()
        undoDismissTask = nil
        Haptics.impact(.light)
        withAnimation(.easeInOut) {
            // Re-insert sorted by createdAt descending (same order as fetchInbox)
            var requests = service.inboxRequests
            requests.append(request)
            service.inboxRequests = requests.sorted { $0.createdAt > $1.createdAt }
            lastDeclined = nil
        }
    }

    private var undoBar: some View {
        HStack {
            Text(NSLocalizedString("companion.inbox.declined.undo", comment: "Request declined undo banner"))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
            Button {
                performUndo()
            } label: {
                Text(NSLocalizedString("action.undo", comment: "Undo action"))
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(NSLocalizedString("companion.inbox.declined.undo", comment: "Request declined undo banner")))
        .accessibilityAction(named: Text(NSLocalizedString("action.undo", comment: "Undo action"))) {
            performUndo()
        }
    }
}

// MARK: - EmptyInboxView

private struct EmptyInboxView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(CT.accent.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "tray")
                    .font(.system(size: 40))
                    .foregroundStyle(CT.accent.opacity(0.7))
                    .scaleEffect(isBreathing ? 1.08 : 0.94)
                    .opacity(isBreathing ? 1.0 : 0.7)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                        value: isBreathing
                    )
            }
            Text(NSLocalizedString("companion.inbox.empty.title", comment: "Empty inbox title"))
                .font(.headline)
            Text(NSLocalizedString("companion.inbox.empty.description", comment: "Empty inbox description"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .onAppear {
            guard !isBreathing, !reduceMotion else { return }
            isBreathing = true
        }
    }
}

// MARK: - RequestRow

private struct RequestRow: View {
    let request: CompanionRequest
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onReport: () -> Void

    private static let isoFormatter: ISO8601DateFormatter = ISO8601DateFormatter()
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
    private static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private func relativeString(_ iso: String) -> String? {
        guard let date = Self.isoFormatter.date(from: iso) else { return nil }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: .now)
    }

    private func absoluteString(_ iso: String) -> String {
        guard let date = Self.isoFormatter.date(from: iso) else { return iso }
        return Self.absoluteFormatter.string(from: date)
    }

    var body: some View {
        let relative = relativeString(request.createdAt) ?? request.createdAt
        let absolute = absoluteString(request.createdAt)
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
                Text(relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel(
                        String(
                            format: NSLocalizedString("companion.inbox.request.received", comment: "VoiceOver: exact received date"),
                            absolute
                        )
                    )
                    .accessibilityValue(absolute)
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
    let service = CompanionService()
    service.inboxRequests = []
    return NavigationStack {
        RequestInboxView(service: service)
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

#Preview("Load error") {
    let service = CompanionService()
    service.lastError = NSLocalizedString("companion.inbox.error.load", comment: "Inbox load error")
    return NavigationStack {
        RequestInboxView(service: service)
    }
}
