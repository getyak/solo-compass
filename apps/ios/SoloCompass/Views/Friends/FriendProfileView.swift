import SwiftUI

/// FriendProfileView — read-only profile of *another* user (US-009).
///
/// Mirrors the `MyProfileEditView` (a.k.a. `CompanionProfileView`) identity
/// layout — large emoji on a warm gradient, handle, bio, languages with
/// flags — but presents it as a non-editable card so the viewer can decide to
/// add / invite / message the person.
///
/// The view is intentionally driven by a plain value (`FriendProfileData`) plus
/// a `FriendRelationState`, so it is previewable and unit-testable without
/// wiring into `FriendService`. Callers resolve the relation (via
/// `FriendService.relationState(with:)`) and the public profile, then hand both
/// in along with the action callbacks.
public struct FriendProfileView: View {
    /// The other user's public identity + trust signals.
    public let profile: FriendProfileData
    /// Relationship between the current user and this profile's owner.
    public let relation: FriendRelationState

    /// Non-friend → "Add Friend".
    public var onAddFriend: () -> Void
    /// Friend → "Message".
    public var onMessage: () -> Void
    /// Friend → "Invite to meetup".
    public var onInvite: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        profile: FriendProfileData,
        relation: FriendRelationState,
        onAddFriend: @escaping () -> Void = {},
        onMessage: @escaping () -> Void = {},
        onInvite: @escaping () -> Void = {}
    ) {
        self.profile = profile
        self.relation = relation
        self.onAddFriend = onAddFriend
        self.onMessage = onMessage
        self.onInvite = onInvite
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            CT.bgWarm.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    header
                    if !profile.bio.isEmpty {
                        bioCard
                    }
                    if !profile.languages.isEmpty {
                        languagesCard
                    }
                    trustStatRow
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                // Leave room so the fixed dock never covers content.
                .padding(.bottom, dockHeight + sheetPeekClearance + 24)
            }

            actionDock
        }
    }

    // MARK: - Header (large emoji on gradient + handle)

    private var header: some View {
        VStack(spacing: 12) {
            Text(profile.avatarEmoji)
                .font(.system(size: 72))
                .frame(width: 120, height: 120)
                .background(
                    Circle().fill(CT.surfaceWhite.opacity(0.5))
                )
                .overlay(
                    Circle().stroke(CT.surfaceWhite.opacity(0.7), lineWidth: 2)
                )
                .accessibilityHidden(true)

            Text(profile.displayHandle.isEmpty
                 ? NSLocalizedString("friend.profile.handle.placeholder", comment: "Fallback when a friend has no handle")
                 : profile.displayHandle)
                .font(.title2.weight(.bold))
                .foregroundStyle(CT.fgPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            LinearGradient(
                colors: [CT.sunGoldSoft, CT.accentSoft],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Bio

    private var bioCard: some View {
        fixedCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("friend.profile.bio.header", comment: "Bio card header"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CT.fgMuted)
                Text(profile.bio)
                    .font(.body)
                    .foregroundStyle(CT.fgPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Languages with flags

    private var languagesCard: some View {
        fixedCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("friend.profile.languages.header", comment: "Languages card header"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CT.fgMuted)
                FlowRow(spacing: 8) {
                    ForEach(profile.languages, id: \.self) { code in
                        languageChip(code)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func languageChip(_ code: String) -> some View {
        HStack(spacing: 6) {
            Text(LanguageDisplay.flag(for: code))
            Text(LanguageDisplay.name(for: code))
                .font(.subheadline)
                .foregroundStyle(CT.fgPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(CT.surfaceSunken)
        )
    }

    // MARK: - Trust-signal stat row

    private var trustStatRow: some View {
        fixedCard {
            HStack(spacing: 0) {
                statItem(
                    value: profile.placesWalked,
                    label: NSLocalizedString("friend.profile.stat.placesWalked", comment: "Places walked stat label")
                )
                statDivider
                statItem(
                    value: profile.routesJoined,
                    label: NSLocalizedString("friend.profile.stat.routesJoined", comment: "Routes joined stat label")
                )
                statDivider
                statItem(
                    value: profile.friendCount,
                    label: NSLocalizedString("friend.profile.stat.friends", comment: "Friend count stat label")
                )
            }
        }
    }

    private func statItem(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title3.weight(.bold))
                .foregroundStyle(CT.fgPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(CT.fgMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(CT.borderSubtle)
            .frame(width: 1, height: 32)
    }

    // MARK: - Bottom fixed action dock

    /// Approximate dock content height (button + padding), used to size the
    /// scroll-content bottom inset.
    private var dockHeight: CGFloat { 56 }

    /// Mirrors `CompassMapView.sheetPeekClearance` so the dock clears the map's
    /// bottom sheet peek when this profile is presented over the map.
    private var sheetPeekClearance: CGFloat {
        let traits = UITraitCollection(
            preferredContentSizeCategory: dynamicTypeSize.uiContentSizeCategory
        )
        return BottomSheetDetent.peekHeight(for: traits)
    }

    @ViewBuilder
    private var actionDock: some View {
        VStack(spacing: 10) {
            switch relation {
            case .accepted:
                HStack(spacing: 12) {
                    dockButton(
                        title: NSLocalizedString("friend.profile.action.message", comment: "Message a friend"),
                        systemImage: "bubble.left.and.bubble.right.fill",
                        prominent: true,
                        action: onMessage
                    )
                    dockButton(
                        title: NSLocalizedString("friend.profile.action.invite", comment: "Invite a friend to a meetup"),
                        systemImage: "person.2.fill",
                        prominent: false,
                        action: onInvite
                    )
                }
            case .none, .pending, .blocked:
                dockButton(
                    title: relation == .pending
                        ? NSLocalizedString("friend.profile.action.requestPending", comment: "Friend request already pending")
                        : NSLocalizedString("friend.profile.action.addFriend", comment: "Add friend"),
                    systemImage: relation == .pending ? "clock.fill" : "person.badge.plus",
                    prominent: true,
                    enabled: relation == .none,
                    action: onAddFriend
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, sheetPeekClearance + 12)
        .frame(maxWidth: .infinity)
        .background(
            CT.surfaceWhite
                .overlay(alignment: .top) {
                    Rectangle().fill(CT.borderSubtle).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func dockButton(
        title: String,
        systemImage: String,
        prominent: Bool,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(prominent ? CT.surfaceWhite : CT.accent)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(prominent ? CT.accent : CT.accentSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(prominent ? Color.clear : CT.accentBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
    }

    // MARK: - Shared fixed light card container

    @ViewBuilder
    private func fixedCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(CT.surfaceWhite)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(CT.borderSubtle, lineWidth: 1)
            )
    }
}

// MARK: - FriendProfileData

/// Read-only view model for another user's profile. Pure value type so the
/// view can be previewed and tested without `FriendService`/`CompanionService`.
public struct FriendProfileData: Equatable, Sendable {
    public let userId: String
    public let displayHandle: String
    public let avatarEmoji: String
    public let bio: String
    public let languages: [String]
    /// Trust signal: experiences walked.
    public let placesWalked: Int
    /// Trust signal: companion routes joined / completed.
    public let routesJoined: Int
    /// Trust signal: number of confirmed friends (shown by default).
    public let friendCount: Int

    public init(
        userId: String,
        displayHandle: String,
        avatarEmoji: String,
        bio: String,
        languages: [String],
        placesWalked: Int,
        routesJoined: Int,
        friendCount: Int
    ) {
        self.userId = userId
        self.displayHandle = displayHandle
        self.avatarEmoji = avatarEmoji
        self.bio = bio
        self.languages = languages
        self.placesWalked = placesWalked
        self.routesJoined = routesJoined
        self.friendCount = friendCount
    }
}

// MARK: - LanguageDisplay (flag + localized name for ISO codes)

/// Maps ISO 639-1 language codes to a representative flag emoji and a localized
/// language name. Kept local to the friends profile surface; the flag is a
/// best-effort visual hint, not a country claim.
enum LanguageDisplay {
    private static let flags: [String: String] = [
        "en": "🇬🇧", "zh": "🇨🇳", "ja": "🇯🇵", "ko": "🇰🇷",
        "es": "🇪🇸", "fr": "🇫🇷", "de": "🇩🇪", "pt": "🇵🇹",
        "it": "🇮🇹", "th": "🇹🇭", "ar": "🇸🇦", "hi": "🇮🇳",
        "ru": "🇷🇺", "nl": "🇳🇱", "tr": "🇹🇷", "vi": "🇻🇳",
    ]

    static func flag(for code: String) -> String {
        flags[code.lowercased()] ?? "🏳️"
    }

    static func name(for code: String) -> String {
        let lower = code.lowercased()
        if let localized = Locale.current.localizedString(forLanguageCode: lower) {
            return localized.capitalized
        }
        return code.uppercased()
    }
}

// MARK: - FlowRow (wrapping HStack for language chips)

/// Minimal wrapping layout so language chips flow onto multiple lines instead
/// of clipping. Uses SwiftUI `Layout` (iOS 16+).
private struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var rowWidth: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, !(rows.last?.isEmpty ?? true) {
                rows.append([])
                rowWidth = 0
            }
            rows[rows.count - 1].append(size)
            rowWidth += size.width + spacing
        }
        let height = rows.reduce(0) { acc, row in
            acc + (row.map(\.height).max() ?? 0) + spacing
        } - spacing
        return CGSize(width: maxWidth == .infinity ? rowWidth : maxWidth, height: max(0, height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Previews

#Preview("Non-friend") {
    FriendProfileView(
        profile: .previewSample,
        relation: .none
    )
}

#Preview("Friend") {
    FriendProfileView(
        profile: .previewSample,
        relation: .accepted
    )
}

#Preview("Pending") {
    FriendProfileView(
        profile: .previewSample,
        relation: .pending
    )
}

extension FriendProfileData {
    static let previewSample = FriendProfileData(
        userId: "user_preview_b",
        displayHandle: "wanderlust_mei",
        avatarEmoji: "🌊",
        bio: "Solo traveler, 12 countries. Coffee shops and hidden temples. Always up for a sunrise hike.",
        languages: ["en", "zh", "ja"],
        placesWalked: 47,
        routesJoined: 8,
        friendCount: 23
    )
}
