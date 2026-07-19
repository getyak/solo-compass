import SwiftUI

/// Nomad OS B1-f: the one-shot "your map has a new home" banner at the top of
/// the Today home.
///
/// When `FeatureFlags.todayHome` flips on for an existing user, their app root
/// changes from the map to this vertical Today flow — the map is now a layer
/// you pull up. That's a meaningful shift in where things live, so the first
/// time Today appears we show a single calm banner explaining it, with an
/// explicit dismiss. It is deliberately NOT a modal or a coach overlay: it
/// never blocks the day, and once dismissed it never returns.
///
/// "First time" is a one-shot `UserDefaults` flag rather than a new-vs-returning
/// user check — a fresh install that met Today through onboarding still gets one
/// quiet orientation to the pull-up gesture, and nobody sees it twice. The flag
/// is read once into `@State` so tapping dismiss animates the banner away in the
/// same render pass that persists the flag.
struct TodayNewHomeBanner: View {
    /// UserDefaults key: set true the first time the banner is dismissed (or
    /// auto-suppressed because it was already seen). Never reset.
    static let seenKey = "solo.today.newHomeBannerSeen"

    private let defaults: UserDefaults
    @State private var visible: Bool

    /// - Parameter defaults: injectable for tests; production uses `.standard`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Start hidden if already seen, so a returning user never flashes it.
        _visible = State(initialValue: !defaults.bool(forKey: Self.seenKey))
    }

    var body: some View {
        if visible {
            HStack(alignment: .top, spacing: Space.md) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CT.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString(
                        "today.newHome.title",
                        comment: "Banner: the map has a new home (Today)"
                    ))
                    .ctBody(14, .semibold)
                    .foregroundStyle(CT.textPrimaryAdaptive)

                    Text(NSLocalizedString(
                        "today.newHome.subtitle",
                        comment: "Banner: pull down any time to get back to the map"
                    ))
                    .ctBody(12)
                    .foregroundStyle(CT.textMutedAdaptive)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CT.fgSubtle)
                        .padding(6)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(NSLocalizedString(
                    "today.newHome.dismiss",
                    comment: "Dismiss the new-home banner"
                )))
            }
            .padding(Space.lg)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(CT.accent.opacity(0.10))
            )
            .padding(.horizontal, Space.xl)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func dismiss() {
        defaults.set(true, forKey: Self.seenKey)
        withAnimation(.easeInOut(duration: 0.25)) {
            visible = false
        }
    }
}

#Preview {
    // Force-visible preview via an ephemeral suite with the flag unset.
    TodayNewHomeBanner(defaults: UserDefaults(suiteName: "preview-new-home")!)
}
