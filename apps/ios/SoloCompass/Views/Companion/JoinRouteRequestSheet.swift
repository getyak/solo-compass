import SwiftUI

// MARK: - PaceMatch

/// Relative pace preference when joining a route.
enum PaceMatch: String, CaseIterable {
    case slower   // 慢于宿主
    case matching // 匹配
    case faster   // 快于宿主

    var label: String {
        switch self {
        case .slower:   return NSLocalizedString("join.pace.slower", comment: "慢于宿主")
        case .matching: return NSLocalizedString("join.pace.matching", comment: "匹配")
        case .faster:   return NSLocalizedString("join.pace.faster", comment: "快于宿主")
        }
    }
}

// MARK: - JoinRouteRequestSheet

/// Sheet for submitting a join request to a route.
///
/// Acceptance criteria (US-031):
/// - Pinned RouteCard at top (non-scrolling).
/// - Pace-match segmented picker (慢于宿主 / 匹配 / 快于宿主).
/// - Message TextEditor (placeholder '向主理人介绍自己...').
/// - Submit disabled when message.count < 10 OR pace not chosen.
/// - On submit: appends JoinRequest to route.companion.joinRequests via RouteStore.save.
/// - Dismisses on success with a light haptic.
struct JoinRouteRequestSheet: View {
    let route: Route

    @Environment(\.dismiss) private var dismiss

    @State private var selectedPace: PaceMatch? = nil
    @State private var message = ""
    @State private var isSubmitting = false

    private var isSubmitEnabled: Bool {
        selectedPace != nil && message.count >= 10 && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                pinnedRouteCard
                Divider()
                formContent
            }
            .navigationTitle(NSLocalizedString("join.sheet.title", comment: "申请加入"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("common.cancel", comment: "Cancel")) {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Pinned route card

    private var pinnedRouteCard: some View {
        RouteCard(route: route)
            .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Scrollable form

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pacePicker
                messageEditor
                submitButton
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Pace picker

    private var pacePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("join.pace.label", comment: "配速匹配"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Picker(
                NSLocalizedString("join.pace.label", comment: "配速匹配"),
                selection: $selectedPace
            ) {
                Text(NSLocalizedString("join.pace.placeholder", comment: "请选择")).tag(Optional<PaceMatch>.none)
                ForEach(PaceMatch.allCases, id: \.self) { pace in
                    Text(pace.label).tag(Optional(pace))
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Message editor

    private var messageEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("join.message.label", comment: "自我介绍"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $message)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                if message.isEmpty {
                    Text(NSLocalizedString("join.message.placeholder", comment: "向主理人介绍自己..."))
                        .foregroundStyle(Color(.placeholderText))
                        .padding(.top, 16)
                        .padding(.leading, 13)
                        .allowsHitTesting(false)
                }
            }

            Text("\(message.count) / 10+")
                .font(.caption)
                .foregroundStyle(message.count < 10 ? Color(.secondaryLabel) : Color.green)
        }
    }

    // MARK: - Submit button

    private var submitButton: some View {
        Button(action: submit) {
            Text(NSLocalizedString("join.submit", comment: "提交申请"))
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(submitBackground)
                .foregroundStyle(isSubmitEnabled ? Color(.systemBackground) : Color(.tertiaryLabel))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(!isSubmitEnabled)
        .accessibilityLabel(NSLocalizedString("join.submit", comment: "提交申请"))
    }

    @ViewBuilder
    private var submitBackground: some View {
        if isSubmitEnabled {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemGray4))
        }
    }

    // MARK: - Submit action

    @MainActor
    private func submit() {
        guard let pace = selectedPace, message.count >= 10 else { return }
        isSubmitting = true

        let deviceId = DeviceIdentityService.shared.deviceID
        let iso8601 = ISO8601DateFormatter().string(from: Date())
        let request = JoinRequest(
            id: JoinRequestId(rawValue: UUID().uuidString),
            requesterId: deviceId,
            message: "\(pace.rawValue): \(message)",
            status: .pending,
            createdAt: iso8601
        )

        var updated = route
        if updated.companion != nil {
            updated.companion!.joinRequests.append(request)
        }
        RouteStore().save(updated)

        Haptics.impact(.light)
        dismiss()
    }
}

// MARK: - Preview

#Preview("JoinRouteRequestSheet") {
    let companion = RouteCompanion(
        status: .open,
        hostId: "maya",
        departureWindow: DepartureWindow(startDate: "2026-06-10", to: "2026-06-12", time: "morning"),
        departureLabel: "Jun 10–12 · morning",
        maxMembers: 4,
        confirmedMembers: [],
        joinRequests: [],
        hostMessage: "Looking for easy-going folks who enjoy slow mornings."
    )
    let route = Route(
        id: RouteId(rawValue: "r_preview"),
        title: "Mekong Sunset Walk",
        summary: "Dawn at the river.",
        experienceIds: ["e1", "e2"],
        cityCode: "VTE",
        region: "Riverfront",
        estimatedDuration: 90,
        distanceMeters: 1200,
        pace: .relaxed,
        tags: ["nature"],
        source: .editorial,
        companion: companion
    )
    JoinRouteRequestSheet(route: route)
}
