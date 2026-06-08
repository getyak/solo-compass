import SwiftUI

/// AddFriendButton — a small, self-contained "add this person as a friend"
/// control reused across companion surfaces (US-015).
///
/// The button reads the live relationship between the current user and
/// `recipientId` from `FriendService.shared` and renders one of three states:
///
/// - `.none`     → "Add Friend" (tappable; sends a request with `source`)
/// - `.pending`  → "Pending"    (disabled; a request is already outstanding)
/// - `.accepted` → "Friends"    (disabled; already friends)
///
/// `source` is threaded straight into `FriendService.sendRequest(source:)` so
/// anti-abuse weighting can distinguish a companion-chat add (`.companionChat`)
/// from a route-group add (`.routeGroup`). The view observes the shared
/// `FriendService` so the label flips to "Pending" the moment the request is
/// recorded, and to "Friends" if a mutual-pending request auto-accepts.
struct AddFriendButton: View {
    /// The user to befriend.
    let recipientId: String
    /// Where the add originated — drives anti-abuse weighting server-side.
    let source: FriendRequestSource

    /// Visual size. Companion chat menu uses `.inline`; the group-route member
    /// rows use the compact `.compact` chip.
    var style: Style = .compact

    /// Shared relationship layer. Observed so the label updates after a send.
    /// Injectable for tests (defaults to the app-wide singleton).
    private var friendService: FriendService

    @State private var isSending = false

    enum Style {
        /// A compact capsule chip (member-row trailing accessory).
        case compact
        /// A `Label` for use inside a `Menu` / dock context.
        case inline
    }

    init(
        recipientId: String,
        source: FriendRequestSource,
        style: Style = .compact,
        service: FriendService = .shared
    ) {
        self.recipientId = recipientId
        self.source = source
        self.style = style
        self.friendService = service
    }

    private var relation: FriendRelationState {
        friendService.relationState(with: recipientId)
    }

    private var isActionable: Bool { relation == .none && !isSending }

    var body: some View {
        Button(action: send) {
            label
        }
        .buttonStyle(.plain)
        .disabled(!isActionable)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var label: some View {
        switch style {
        case .compact:
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(isActionable ? CT.accent : CT.fgMuted)
            .background(
                Capsule().fill(isActionable ? CT.accentSoft : CT.surfaceSunken)
            )
            .overlay(
                Capsule().stroke(
                    isActionable ? CT.accentBorder : CT.borderSubtle,
                    lineWidth: 1
                )
            )
        case .inline:
            Label(title, systemImage: systemImage)
        }
    }

    private var title: String {
        switch relation {
        case .accepted:
            return NSLocalizedString(
                "friend.add.state.friends",
                comment: "Already friends — button label"
            )
        case .pending:
            return NSLocalizedString(
                "friend.add.state.pending",
                comment: "Friend request pending — button label"
            )
        case .none, .blocked:
            return NSLocalizedString(
                "friend.add.state.add",
                comment: "Add friend — button label"
            )
        }
    }

    private var systemImage: String {
        switch relation {
        case .accepted: return "checkmark.circle.fill"
        case .pending: return "clock.fill"
        case .none, .blocked: return "person.badge.plus"
        }
    }

    private var accessibilityLabel: String {
        switch relation {
        case .accepted:
            return NSLocalizedString("friend.add.state.friends", comment: "Already friends")
        case .pending:
            return NSLocalizedString("friend.add.state.pending", comment: "Request pending")
        case .none, .blocked:
            return NSLocalizedString("friend.add.state.add", comment: "Add friend")
        }
    }

    private func send() {
        guard isActionable else { return }
        isSending = true
        Task {
            _ = await friendService.sendRequest(to: recipientId, source: source)
            isSending = false
        }
    }
}

// MARK: - Preview

#Preview("Add Friend states") {
    VStack(alignment: .leading, spacing: 16) {
        AddFriendButton(
            recipientId: "user_preview_x",
            source: .companionChat,
            style: .compact
        )
        AddFriendButton(
            recipientId: "user_preview_y",
            source: .routeGroup,
            style: .inline
        )
    }
    .padding()
}
