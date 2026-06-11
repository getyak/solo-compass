import SwiftUI

/// Moderation queue — the admin / moderator surface for safety reports.
///
/// Lists every `CompanionReport` (the 0012 RLS policy grants moderators/admins
/// full-table read; plain users can't reach this screen — the MeSheet entry is
/// gated on `AdminService.canModerate`). Each row shows who reported whom and
/// why, and offers two actions: **Ban** the target user and **Resolve** the
/// report (mark handled). Both route through the `moderate-action` Edge
/// Function via `AdminService`.
///
/// Purely presentational + dispatch; all I/O lives in `AdminService`.
public struct ModerationView: View {
    @State private var service: AdminService
    @State private var inFlightId: String?

    private let autoRefresh: Bool

    public init(service: AdminService = .shared, autoRefresh: Bool = true) {
        _service = State(initialValue: service)
        self.autoRefresh = autoRefresh
    }

    private var unresolved: [CompanionReport] {
        service.reports.filter { $0.resolvedAt == nil }
    }

    private var resolved: [CompanionReport] {
        service.reports.filter { $0.resolvedAt != nil }
    }

    public var body: some View {
        Group {
            if service.isLoading && service.reports.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if service.reports.isEmpty {
                ContentUnavailableView(
                    NSLocalizedString("moderation.empty.title", comment: "No reports title"),
                    systemImage: "checkmark.shield",
                    description: Text(NSLocalizedString("moderation.empty.message", comment: "No reports message"))
                )
            } else {
                queueList
            }
        }
        .navigationTitle(NSLocalizedString("moderation.title", comment: "Moderation queue title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if autoRefresh {
                await service.refreshRole()
                await service.refreshReports()
            }
        }
        .refreshable { await service.refreshReports() }
        .overlay(alignment: .bottom) {
            if let error = service.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red, in: Capsule())
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: service.lastError)
    }

    private var queueList: some View {
        List {
            if !unresolved.isEmpty {
                Section(NSLocalizedString("moderation.section.open", comment: "Open reports section")) {
                    ForEach(unresolved, id: \.id.rawValue) { report in
                        ReportRow(report: report, isResolved: false)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    act(.ban(targetUserId: report.targetUserId), id: report.id.rawValue)
                                } label: {
                                    Label(NSLocalizedString("moderation.action.ban", comment: "Ban user"), systemImage: "hand.raised.fill")
                                }
                                Button {
                                    act(.resolveReport(reportId: report.id.rawValue), id: report.id.rawValue)
                                } label: {
                                    Label(NSLocalizedString("moderation.action.resolve", comment: "Resolve report"), systemImage: "checkmark")
                                }
                                .tint(.green)
                            }
                    }
                }
            }

            if !resolved.isEmpty {
                Section(NSLocalizedString("moderation.section.resolved", comment: "Resolved reports section")) {
                    ForEach(resolved, id: \.id.rawValue) { report in
                        ReportRow(report: report, isResolved: true)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .disabled(inFlightId != nil)
    }

    private func act(_ action: AdminService.ModerationAction, id: String) {
        inFlightId = id
        Haptics.impact(.medium)
        Task {
            await service.perform(action)
            inFlightId = nil
        }
    }
}

// MARK: - Row

private struct ReportRow: View {
    let report: CompanionReport
    let isResolved: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: reasonIcon)
                    .foregroundStyle(isResolved ? Color.secondary : Color.orange)
                Text(reasonLabel)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                if isResolved {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            Text(String(
                format: NSLocalizedString("moderation.row.target", comment: "Reported user id: %@"),
                UserDirectory.displayName(forId: report.targetUserId)
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let details = report.details, !details.isEmpty {
                Text(details)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
            }

            Text(report.createdAt)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
        .opacity(isResolved ? 0.55 : 1.0)
    }

    private var reasonLabel: String {
        switch report.reason {
        case .spam:                  return NSLocalizedString("moderation.reason.spam", comment: "Spam")
        case .harassment:            return NSLocalizedString("moderation.reason.harassment", comment: "Harassment")
        case .inappropriate_content: return NSLocalizedString("moderation.reason.inappropriate", comment: "Inappropriate content")
        case .fake_profile:          return NSLocalizedString("moderation.reason.fakeProfile", comment: "Fake profile")
        case .other:                 return NSLocalizedString("moderation.reason.other", comment: "Other")
        }
    }

    private var reasonIcon: String {
        switch report.reason {
        case .spam:                  return "envelope.badge.shield.half.filled"
        case .harassment:            return "exclamationmark.bubble.fill"
        case .inappropriate_content: return "eye.trianglebadge.exclamationmark.fill"
        case .fake_profile:          return "person.crop.circle.badge.xmark"
        case .other:                 return "flag.fill"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ModerationView(autoRefresh: false)
    }
}
