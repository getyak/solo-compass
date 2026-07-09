import SwiftUI

/// Sheet that lets a user report or block another user (US-014).
///
/// Can be opened from any companion surface: a post row in discovery,
/// a request in the inbox, or a message in chat. The caller provides
/// the `targetUserId` of the user being reported/blocked.
///
/// Report writes to `companion_reports` (user can never read others' reports).
/// Block writes to `companion_blocks`; the Edge Function excludes both sides
/// from all discovery queries.
public struct ReportBlockSheet: View {
    let targetUserId: String
    /// Display label for the target (e.g., their emoji handle). Shown in UI only.
    let targetLabel: String
    /// Called on successful block so the parent can dismiss or refresh.
    var onBlocked: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var service: CompanionService
    @State private var selectedReason: CompanionReportReason = .spam
    @State private var details = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var showBlockConfirm = false
    @State private var errorMessage: String?

    public init(
        targetUserId: String,
        targetLabel: String,
        service: CompanionService = .shared,
        onBlocked: (() -> Void)? = nil
    ) {
        self.targetUserId = targetUserId
        self.targetLabel = targetLabel
        self.onBlocked = onBlocked
        _service = State(initialValue: service)
    }

    public var body: some View {
        NavigationStack {
            Form {
                reasonSection
                detailsSection
                submitSection
                blockSection
            }
            .navigationTitle(NSLocalizedString("companion.report.title", comment: "Report sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("action.cancel", comment: "Cancel")) {
                        dismiss()
                    }
                }
            }
            .disabled(isSubmitting)
            .alert(
                NSLocalizedString("companion.report.success.title", comment: "Report success title"),
                isPresented: $showSuccess
            ) {
                Button(NSLocalizedString("action.ok", comment: "OK")) { dismiss() }
            } message: {
                Text(NSLocalizedString("companion.report.success.message", comment: "Report success message"))
            }
            .alert(
                NSLocalizedString("companion.report.error.title", comment: "Report error title"),
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button(NSLocalizedString("action.ok", comment: "OK")) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .confirmationDialog(
                NSLocalizedString("companion.block.confirm.title", comment: "Block confirm title"),
                isPresented: $showBlockConfirm,
                titleVisibility: .visible
            ) {
                Button(
                    NSLocalizedString("companion.block.confirm.action", comment: "Block button"),
                    role: .destructive
                ) {
                    Task { await confirmBlock() }
                }
                Button(NSLocalizedString("action.cancel", comment: "Cancel"), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("companion.block.confirm.message", comment: "Block confirm message"))
            }
        }
    }

    // MARK: - Sections

    private var reasonSection: some View {
        Section(NSLocalizedString("companion.report.reason.header", comment: "Reason header")) {
            ForEach(CompanionReportReason.allCases, id: \.self) { reason in
                HStack {
                    Text(reason.displayName)
                    Spacer()
                    if selectedReason == reason {
                        Image(systemName: "checkmark")
                            .foregroundStyle(CT.accent)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { selectedReason = reason }
            }
        }
    }

    private var detailsSection: some View {
        Section(NSLocalizedString("companion.report.details.header", comment: "Details header")) {
            TextField(
                NSLocalizedString("companion.report.details.placeholder", comment: "Details placeholder"),
                text: $details,
                axis: .vertical
            )
            .lineLimit(3...6)
        }
    }

    private var submitSection: some View {
        Section {
            Button {
                Task { await submitReport() }
            } label: {
                HStack {
                    Spacer()
                    if isSubmitting {
                        ProgressView()
                            .padding(.trailing, 4)
                        Text(NSLocalizedString("companion.report.submitting", comment: "Submitting label"))
                    } else {
                        Text(NSLocalizedString("companion.report.submit", comment: "Submit button"))
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .disabled(isSubmitting)
        }
    }

    private var blockSection: some View {
        Section {
            Button(role: .destructive) {
                showBlockConfirm = true
            } label: {
                HStack {
                    Spacer()
                    Text(NSLocalizedString("companion.block.title", comment: "Block user button"))
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
        } footer: {
            Text(
                String(
                    format: NSLocalizedString("companion.block.confirm.message", comment: "Block info footer"),
                    targetLabel
                )
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func submitReport() async {
        isSubmitting = true
        defer { isSubmitting = false }

        let result = await service.reportUser(
            targetUserId: targetUserId,
            reason: selectedReason,
            details: details.isEmpty ? nil : details
        )

        switch result {
        case .success:
            showSuccess = true
        case .failure(let err):
            errorMessage = err.localizedDescription
        }
    }

    private func confirmBlock() async {
        isSubmitting = true
        defer { isSubmitting = false }

        let result = await service.blockUser(blockedId: targetUserId)
        switch result {
        case .success:
            onBlocked?()
            dismiss()
        case .failure(let err):
            errorMessage = err.localizedDescription
        }
    }
}

// MARK: - CompanionReportReason display

extension CompanionReportReason: CaseIterable {
    public static var allCases: [CompanionReportReason] {
        [.spam, .harassment, .inappropriate_content, .fake_profile, .other]
    }

    var displayName: String {
        switch self {
        case .spam:
            return NSLocalizedString("companion.report.reason.spam", comment: "Spam reason")
        case .harassment:
            return NSLocalizedString("companion.report.reason.harassment", comment: "Harassment reason")
        case .inappropriate_content:
            return NSLocalizedString("companion.report.reason.inappropriate_content", comment: "Inappropriate content reason")
        case .fake_profile:
            return NSLocalizedString("companion.report.reason.fake_profile", comment: "Fake profile reason")
        case .other:
            return NSLocalizedString("companion.report.reason.other", comment: "Other reason")
        }
    }
}

// MARK: - Preview

#Preview("Report sheet") {
    ReportBlockSheet(
        targetUserId: "user_bad",
        targetLabel: "🦁"
    )
}
