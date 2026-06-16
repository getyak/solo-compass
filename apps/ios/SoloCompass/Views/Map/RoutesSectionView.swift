import SwiftUI

// MARK: - RoutesSection

/// '路线' section rendered inside BottomInfoSheet above 附近.
/// Shows RouteStore.nearby routes. When isNowFilter is true only bestNow routes appear.
struct RoutesSection: View {
    let routes: [Route]
    let isNowFilter: Bool
    let onSelectRoute: (Route) -> Void

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
            }
        }
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
