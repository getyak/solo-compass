import SwiftUI

// MARK: - RoutesSection

/// '路线' section rendered inside BottomInfoSheet above 附近.
/// Shows RouteStore.nearby routes. When isNowFilter is true only bestNow routes appear.
struct RoutesSection: View {
    let routes: [Route]
    let isNowFilter: Bool
    let onSelectRoute: (Route) -> Void
    /// Optional CTA invoked by the warm cold-start placeholder card when the Now
    /// section has zero real routes. Wired by the parent to the same code path
    /// as `CreateRouteEntryCard` so users get a single, predictable route-build
    /// flow. When `nil` the placeholder degrades to a static hint (no button).
    var onProposeRoute: (() -> Void)? = nil

    private var displayed: [Route] {
        // Now-context uses the runtime check (derived from bestStartHour) so the
        // 此刻適合 section surfaces routes inside their window — the static
        // `bestNow` seed flag is all-false today, which would empty the section.
        isNowFilter ? routes.filter { $0.isBestNow() } : routes
    }

    var body: some View {
        let items = displayed
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    // US-036: Routes is the first section, so its header omits the
                    // leading inset divider (the sheet must not open with a rule).
                    // RouteCard now carries its own card chrome (.sc-route-card:
                    // white fill, border, shadow), so rows are separated by 10pt
                    // spacing rather than full-bleed dividers.
                    //
                    // In now-context the section gets a dedicated golden header
                    // (sparkles + 「路線 · 此刻適合」+ AI · NOW), mirroring the
                    // 此刻精選 AI region — see styles.css `.sc-section-label .lhs.now`.
                    if isNowFilter {
                        RouteNowSectionHeader()
                    } else {
                        SheetSectionSeparator(titleKey: "sheet.section.routes", showsDivider: false)
                    }
                    ForEach(items) { route in
                        Button { onSelectRoute(route) } label: {
                            RouteCard(route: route, nowContext: isNowFilter)
                        }
                        // PressableButtonStyle drives the press-scale via the
                        // system tap recognizer. RouteCard no longer owns a local
                        // zero-distance DragGesture (which swallowed the tap inside
                        // this ScrollView — see RouteCard), so the tap now reaches
                        // this Button's action and opens the route detail.
                        .buttonStyle(PressableButtonStyle(pressedScale: 0.985))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            } else if isNowFilter {
                // Direction 3 — Cold start in Now mode: no nearby routes yet
                // (RouteStore still loading, or simply none in window). Surface a
                // single warm-amber placeholder card that proposes
                // "今天的一条路线 · 让 Solo 为你拼一条" and routes its CTA through
                // the same `create route` flow as CreateRouteEntryCard (wired by
                // CompassMapView). The card disappears the moment a real route
                // arrives because `items` is no longer empty.
                VStack(alignment: .leading, spacing: 10) {
                    RouteNowSectionHeader()
                    NowEmptyRoutePlaceholder(onTap: onProposeRoute)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - NowEmptyRoutePlaceholder

/// Warm-amber cold-start card for the Now routes section when there are no
/// nearby routes yet. Friend-voice copy ("今天的一条路线 · 让 Solo 为你拼一条")
/// and a single primary CTA that reuses the existing `create route` action —
/// no new orchestration is introduced.
///
/// Palette: CT.sunGoldSoft → CT.sunGoldDeep gradient on a soft amber surface,
/// matching the warm-amber dock language used in ExperienceDetailView.
struct NowEmptyRoutePlaceholder: View {
    let onTap: (() -> Void)?

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [CT.sunGoldSoft, CT.sunGoldDeep],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(NSLocalizedString(
                        "routes.now.empty.title",
                        comment: "Warm cold-start placeholder when Now routes are empty"
                    ))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CT.sunGoldDeep)
                    Text(NSLocalizedString(
                        "routes.now.empty.cta",
                        comment: "CTA on the warm cold-start placeholder — let Solo build a route"
                    ))
                    .font(.caption)
                    .foregroundStyle(CT.fgMuted)
                    .lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CT.sunGoldDeep.opacity(0.7))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(CT.sunGoldSoft.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(CT.sunGoldDeep.opacity(0.25), lineWidth: 1)
            )
        }
        // Match CreateRouteEntryCard's press feedback so the warm placeholder
        // feels like a first-class member of the routes stack — and so the tap
        // is not swallowed by BottomInfoSheet's ScrollView (see
        // [[project_dead_fab_sheet_wiring]] kin).
        .buttonStyle(PressableButtonStyle(pressedScale: 0.985))
        .disabled(onTap == nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(NSLocalizedString(
            "routes.now.empty.title",
            comment: "Warm cold-start placeholder when Now routes are empty"
        )))
        .accessibilityHint(Text(NSLocalizedString(
            "routes.now.empty.cta",
            comment: "CTA on the warm cold-start placeholder — let Solo build a route"
        )))
    }
}

// MARK: - RouteNowSectionHeader

/// Dedicated golden header for the 路线 section in now-context.
///
/// Mirrors styles.css `.sc-section-label` with the `.lhs.now` treatment and the
/// 此刻精選 AI region: left → sparkles + 「路線 · 此刻適合」(uppercase display,
/// sun-gold-deep), right → mono `AI · NOW` badge in fg-subtle.
struct RouteNowSectionHeader: View {
    var body: some View {
        HStack(alignment: .center) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CT.sunGoldDeep)
                Text(NSLocalizedString("sheet.section.routes.now", comment: "路線 · 此刻適合 section header"))
                    .font(CT.display(11, .bold))
                    .tracking(1.3)
                    .textCase(.uppercase)
                    .foregroundStyle(CT.sunGoldDeep)
            }
            Spacer(minLength: 8)
            Text(verbatim: "AI · NOW")
                .font(CT.mono(11, .regular))
                .tracking(0.4)
                .foregroundStyle(CT.fgSubtle)
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
