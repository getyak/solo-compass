import SwiftUI

/// Nomad OS B1-d: the "who's nearby" row on the Today home (design
/// nomad-os-b1-today-home-20260719 §2 ③).
///
/// A compact, horizontal preview of anonymized companion posts in the current
/// city — emoji avatars stacked with a one-line count — that taps through to
/// the full `DiscoverListView`. It reads `CompanionService.discoverPosts` and
/// is gated entirely behind `FeatureFlags.companion`:
///
///   - flag off              → the row does not render at all (no dead button;
///     `fetchDiscovery` also self-gates and returns []).
///   - flag on, has posts    → avatar stack + count + chevron → DiscoverListView.
///   - flag on, no posts yet  → a "be the first" invite, never a dead end
///     (design §2 ③, echoing the nomad-entry零数据 lesson).
///
/// The map's own companion layer stays behind its separate, still-off
/// `companionLayerEnabled` flag; this row talks only to the real discovery
/// fetch, so it shows real people or an honest empty state — not a control that
/// never does anything.
struct TodayNearbyRow: View {
    let cityCode: String?

    @Environment(CompanionService.self) private var companion
    @State private var didLoad = false

    var body: some View {
        // Master gate: the whole social surface is off unless companion is on.
        if FeatureFlags.companion, let cityCode, !cityCode.isEmpty {
            content(cityCode: cityCode)
                .task(id: cityCode) { await load(cityCode: cityCode) }
        }
    }

    @ViewBuilder
    private func content(cityCode: String) -> some View {
        let posts = companion.discoverPosts
        if posts.isEmpty {
            // Honest empty state — an invite, not a dead end.
            NavigationLink(value: NearbyDestination(cityCode: cityCode)) {
                rowShell {
                    HStack(spacing: Space.md) {
                        Image(systemName: "person.2.badge.plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(CT.accent)
                        Text(NSLocalizedString(
                            "today.nearby.beFirst",
                            comment: "No nomads registered here yet — be the first"
                        ))
                        .ctBody(14, .medium)
                        .foregroundStyle(CT.textMutedAdaptive)
                        Spacer(minLength: 0)
                        chevron
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: NearbyDestination(cityCode: cityCode)) {
                rowShell {
                    HStack(spacing: Space.md) {
                        avatarStack(posts: posts)
                        Text(String(
                            format: NSLocalizedString(
                                "today.nearby.count",
                                comment: "%d nomads nearby in this city"
                            ),
                            posts.count
                        ))
                        .ctBody(14, .semibold)
                        .foregroundStyle(CT.textPrimaryAdaptive)
                        Spacer(minLength: 0)
                        chevron
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Pieces

    private func avatarStack(posts: [DiscoverPost]) -> some View {
        // Show up to 4 emoji avatars, overlapped. `handle` is an emoji, never a
        // real name or user id (DiscoverPost contract).
        let shown = Array(posts.prefix(4))
        return HStack(spacing: -Space.sm) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { _, post in
                Text(post.handle)
                    .font(.system(size: 20))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(CT.pageAdaptive))
                    .overlay(Circle().strokeBorder(CT.borderSubtle, lineWidth: 1))
            }
        }
        .accessibilityHidden(true)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(CT.fgSubtle)
    }

    private func rowShell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(Space.lg)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(CT.cardAdaptive)
            )
            .padding(.horizontal, Space.xl)
    }

    private func load(cityCode: String) async {
        // Idempotent per city — `.task(id:)` re-fires on city change.
        await companion.fetchDiscovery(
            params: CompanionDiscoverParams(cityCode: cityCode, mode: .nearby)
        )
        didLoad = true
    }
}

/// Navigation payload for the Today → full discovery push. A dedicated type
/// keeps the destination unambiguous in the Today navigation stack.
struct NearbyDestination: Hashable {
    let cityCode: String
}
