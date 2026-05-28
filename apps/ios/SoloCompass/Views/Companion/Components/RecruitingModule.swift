import SwiftUI

// MARK: - ModuleStrength

/// Visual weight of the RecruitingModule card. Used for A/B testing without
/// a code refactor — persisted via UserPreferences.companionModuleStrength.
public enum ModuleStrength: String, Codable, CaseIterable {
    /// No accent fill — plain card with a 1pt separator border. Default.
    case restrained
    /// 3pt left sun-gold border + light cream background tint.
    case neutral
    /// Full warm sun-gold-soft background + bold primary CTA fill.
    case strong
}

// MARK: - RecruitingModule

/// Recruiting card shown inside a route detail view when the route has an
/// active companion slot. Renders nothing when `route.companion == nil`.
///
/// CTA label logic:
/// - viewerIsHost && pending requests   → 查看申请(n)
/// - hasMyRequest                       → 已申请 · 等待确认  (disabled)
/// - status == completed || closed      → 查看群聊
/// - status == open                     → 申请加入
/// - status == forming                  → 申请加入(最后 N 位)
public struct RecruitingModule: View {
    let route: Route
    let viewerIsHost: Bool
    let hasMyRequest: Bool
    var strength: ModuleStrength = .restrained
    let onRequestJoin: () -> Void
    let onViewRequests: () -> Void

    // Sun-gold accent shared across neutral and strong variants.
    private static let sunGold = Color(red: 0.95, green: 0.76, blue: 0.20)
    // Light cream tint for neutral background.
    private static let creamTint = Color(red: 1.0, green: 0.98, blue: 0.92)
    // Warm sun-gold-soft for strong background.
    private static let sunGoldSoft = Color(red: 1.0, green: 0.94, blue: 0.72)

    public var body: some View {
        if let companion = route.companion {
            cardContent(companion: companion)
        }
    }

    // MARK: - Card

    @ViewBuilder
    private func cardContent(companion: RouteCompanion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow(companion: companion)
            hostRow(hostId: companion.hostId)
            slotsRow(companion: companion)
            if let msg = companion.hostMessage, !msg.isEmpty {
                hostMessageView(msg)
            }
            ctaButton(companion: companion)
        }
        .padding(16)
        .background(cardBackground)
        .overlay(cardBorder)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Strength-based card styling

    @ViewBuilder
    private var cardBackground: some View {
        switch strength {
        case .restrained:
            Color(.systemBackground)
        case .neutral:
            Self.creamTint
        case .strong:
            Self.sunGoldSoft
        }
    }

    @ViewBuilder
    private var cardBorder: some View {
        switch strength {
        case .restrained:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.45), lineWidth: 1)
        case .neutral:
            HStack(spacing: 0) {
                Self.sunGold
                    .frame(width: 3)
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .strong:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Self.sunGold.opacity(0.6), lineWidth: 1)
        }
    }

    // MARK: - Header row: status capsule + departure label

    private func headerRow(companion: RouteCompanion) -> some View {
        HStack(spacing: 8) {
            statusCapsule(status: companion.status)
            Text(companion.departureLabel)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func statusCapsule(status: CompanionStatus) -> some View {
        Text(status.localizedLabel)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(status.toneColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(status.toneColor.opacity(0.12))
            )
    }

    // MARK: - Host row: 28pt color circle + handle + blurb

    private func hostRow(hostId: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(UserDirectory.color(forId: hostId))
                .frame(width: 28, height: 28)
                .overlay(
                    Text(String(hostId.prefix(1)).uppercased())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("@\(hostId)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let user = UserDirectory.shared.user(handle: hostId), !user.blurb.isEmpty {
                    Text(user.blurb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Slots row: filled avatars + empty outlined circles

    private func slotsRow(companion: RouteCompanion) -> some View {
        HStack(spacing: 6) {
            Text(NSLocalizedString("recruiting.slots.label", comment: "Slots label"))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                ForEach(0..<companion.maxMembers, id: \.self) { index in
                    if index < companion.confirmedMembers.count {
                        let memberId = companion.confirmedMembers[index]
                        filledSlot(id: memberId)
                    } else {
                        emptySlot
                    }
                }
            }

            Spacer(minLength: 0)

            Text(String(
                format: NSLocalizedString("recruiting.slots.count", comment: "%d/%d"),
                companion.confirmedMembers.count,
                companion.maxMembers
            ))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
        }
    }

    private func filledSlot(id: String) -> some View {
        Circle()
            .fill(UserDirectory.color(forId: id))
            .frame(width: 22, height: 22)
            .overlay(
                Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.5)
            )
    }

    private var emptySlot: some View {
        ZStack {
            Circle()
                .strokeBorder(Color(.separator), lineWidth: 1)
                .frame(width: 22, height: 22)
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color(.tertiaryLabel))
        }
    }

    // MARK: - Optional host message

    private func hostMessageView(_ message: String) -> some View {
        Text("\u{201C}\(message)\u{201D}")
            .font(.system(size: 13).italic())
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - CTA button

    private func ctaButton(companion: RouteCompanion) -> some View {
        let config = ctaConfig(companion: companion)
        return Button(action: config.action) {
            Text(config.label)
                .font(.system(size: 14, weight: strength == .strong ? .bold : .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(ctaBackground(isDisabled: config.isDisabled))
                .foregroundStyle(ctaForeground(isDisabled: config.isDisabled))
        }
        .disabled(config.isDisabled)
        .accessibilityLabel(config.label)
    }

    private func ctaBackground(isDisabled: Bool) -> some View {
        Group {
            if isDisabled {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.systemGray5))
            } else if strength == .strong {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Self.sunGold)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            }
        }
    }

    private func ctaForeground(isDisabled: Bool) -> Color {
        if isDisabled { return Color(.tertiaryLabel) }
        return strength == .strong ? Color(.systemBackground) : Color.accentColor
    }

    // MARK: - CTA config

    private struct CTAConfig {
        let label: String
        let isDisabled: Bool
        let action: () -> Void
    }

    private func ctaConfig(companion: RouteCompanion) -> CTAConfig {
        let pendingCount = companion.joinRequests.filter { $0.status == .pending }.count

        if viewerIsHost && pendingCount > 0 {
            let label = String(
                format: NSLocalizedString("recruiting.cta.viewRequests", comment: "查看申请(%d)"),
                pendingCount
            )
            return CTAConfig(label: label, isDisabled: false, action: onViewRequests)
        }

        if hasMyRequest {
            let label = NSLocalizedString("recruiting.cta.applied", comment: "已申请 · 等待确认")
            return CTAConfig(label: label, isDisabled: true, action: {})
        }

        switch companion.status {
        case .completed, .closed:
            let label = NSLocalizedString("recruiting.cta.viewChat", comment: "查看群聊")
            return CTAConfig(label: label, isDisabled: false, action: onRequestJoin)
        case .open:
            let label = NSLocalizedString("recruiting.cta.requestJoin", comment: "申请加入")
            return CTAConfig(label: label, isDisabled: false, action: onRequestJoin)
        case .forming:
            let remaining = companion.maxMembers - companion.confirmedMembers.count
            let label = String(
                format: NSLocalizedString("recruiting.cta.requestJoinForming", comment: "申请加入(最后 %d 位)"),
                remaining
            )
            return CTAConfig(label: label, isDisabled: false, action: onRequestJoin)
        }
    }
}

// MARK: - CompanionStatus tone + label

private extension CompanionStatus {
    var toneColor: Color {
        switch self {
        case .open:      return .green
        case .forming:   return .orange
        case .closed:    return Color(.systemGray)
        case .completed: return .blue
        }
    }

    var localizedLabel: String {
        switch self {
        case .open:      return NSLocalizedString("recruiting.status.open", comment: "open")
        case .forming:   return NSLocalizedString("recruiting.status.forming", comment: "forming")
        case .closed:    return NSLocalizedString("recruiting.status.closed", comment: "closed")
        case .completed: return NSLocalizedString("recruiting.status.completed", comment: "completed")
        }
    }
}

// MARK: - Previews

/// Shows all 3 ModuleStrength variants × status=open side-by-side.
#Preview("strength × open — all 3 variants") {
    ScrollView {
        VStack(spacing: 20) {
            Text("restrained (default)")
                .font(.caption).foregroundStyle(.secondary)
            RecruitingModule(
                route: .previewWithCompanion(status: .open),
                viewerIsHost: false,
                hasMyRequest: false,
                strength: .restrained,
                onRequestJoin: {},
                onViewRequests: {}
            )

            Text("neutral")
                .font(.caption).foregroundStyle(.secondary)
            RecruitingModule(
                route: .previewWithCompanion(status: .open),
                viewerIsHost: false,
                hasMyRequest: false,
                strength: .neutral,
                onRequestJoin: {},
                onViewRequests: {}
            )

            Text("strong")
                .font(.caption).foregroundStyle(.secondary)
            RecruitingModule(
                route: .previewWithCompanion(status: .open),
                viewerIsHost: false,
                hasMyRequest: false,
                strength: .strong,
                onRequestJoin: {},
                onViewRequests: {}
            )
        }
        .padding()
    }
    .background(Color(.secondarySystemBackground))
}

#Preview("status=open, viewer") {
    ScrollView {
        RecruitingModule(
            route: .previewWithCompanion(status: .open),
            viewerIsHost: false,
            hasMyRequest: false,
            onRequestJoin: {},
            onViewRequests: {}
        )
        .padding()
    }
    .background(Color(.secondarySystemBackground))
}

#Preview("status=open, hasMyRequest") {
    ScrollView {
        RecruitingModule(
            route: .previewWithCompanion(status: .open),
            viewerIsHost: false,
            hasMyRequest: true,
            onRequestJoin: {},
            onViewRequests: {}
        )
        .padding()
    }
    .background(Color(.secondarySystemBackground))
}

#Preview("status=forming, viewer") {
    ScrollView {
        RecruitingModule(
            route: .previewWithCompanion(status: .forming, confirmedMembers: ["maya", "leon"]),
            viewerIsHost: false,
            hasMyRequest: false,
            onRequestJoin: {},
            onViewRequests: {}
        )
        .padding()
    }
    .background(Color(.secondarySystemBackground))
}

#Preview("status=closed, viewer") {
    ScrollView {
        RecruitingModule(
            route: .previewWithCompanion(status: .closed, confirmedMembers: ["maya", "leon", "rina"]),
            viewerIsHost: false,
            hasMyRequest: false,
            onRequestJoin: {},
            onViewRequests: {}
        )
        .padding()
    }
    .background(Color(.secondarySystemBackground))
}

#Preview("status=completed, viewer") {
    ScrollView {
        RecruitingModule(
            route: .previewWithCompanion(status: .completed, confirmedMembers: ["maya", "leon", "rina", "tom"]),
            viewerIsHost: false,
            hasMyRequest: false,
            onRequestJoin: {},
            onViewRequests: {}
        )
        .padding()
    }
    .background(Color(.secondarySystemBackground))
}

#Preview("viewerIsHost, pending requests") {
    ScrollView {
        RecruitingModule(
            route: .previewWithCompanion(status: .open, pendingRequestCount: 3),
            viewerIsHost: true,
            hasMyRequest: false,
            onRequestJoin: {},
            onViewRequests: {}
        )
        .padding()
    }
    .background(Color(.secondarySystemBackground))
}

#Preview("viewerIsHost, no pending") {
    ScrollView {
        RecruitingModule(
            route: .previewWithCompanion(status: .forming),
            viewerIsHost: true,
            hasMyRequest: false,
            onRequestJoin: {},
            onViewRequests: {}
        )
        .padding()
    }
    .background(Color(.secondarySystemBackground))
}

#Preview("no companion — renders nothing") {
    VStack {
        Text("Nothing below:")
        RecruitingModule(
            route: Route(
                id: RouteId(rawValue: "r_nil"),
                title: "No companion route",
                summary: "",
                experienceIds: [],
                cityCode: "TST",
                region: "Test",
                estimatedDuration: 30,
                distanceMeters: 500,
                pace: .standard,
                source: .editorial
            ),
            viewerIsHost: false,
            hasMyRequest: false,
            onRequestJoin: {},
            onViewRequests: {}
        )
        Text("Nothing above.")
    }
    .padding()
}

// MARK: - Route preview helpers

private extension Route {
    static func previewWithCompanion(
        status: CompanionStatus,
        confirmedMembers: [String] = [],
        pendingRequestCount: Int = 0
    ) -> Route {
        let requests: [JoinRequest] = (0..<pendingRequestCount).map { i in
            JoinRequest(
                id: JoinRequestId(rawValue: "req_\(i)"),
                requesterId: "requester_\(i)",
                message: "Hi, can I join?",
                status: .pending,
                createdAt: "2026-05-01T09:00:00Z"
            )
        }
        let companion = RouteCompanion(
            status: status,
            hostId: "maya",
            departureWindow: DepartureWindow(startDate: "2026-06-10", to: "2026-06-12", time: "morning"),
            departureLabel: "Jun 10–12 · morning",
            maxMembers: 4,
            confirmedMembers: confirmedMembers,
            joinRequests: requests,
            hostMessage: "Looking for easy-going folks who enjoy slow mornings and street food."
        )
        return Route(
            id: RouteId(rawValue: "r_preview"),
            title: "Mekong Sunrise Walk",
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
    }
}
