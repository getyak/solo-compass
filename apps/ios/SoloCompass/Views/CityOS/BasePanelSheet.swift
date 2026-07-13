import SwiftUI
import CoreLocation

/// 游民基地面板 — the page behind `BaseCard`. One sheet, four faces
/// (`BaseFace`): the section list is derived from the face so information
/// enters and leaves with the lifecycle — visa prep dominates before the trip
/// and shrinks to a countdown ring once you live there; events and work spots
/// do the reverse. Sections with no data render nothing (no empty stubs).
///
/// The panel is deliberately dumb: every mutation and every hop to a deeper
/// surface (kit, live events, a map pin) is a closure supplied by
/// `CompassMapView`, so this view stays previewable and testable in isolation.
struct BasePanelSheet: View {
    let face: BaseFace
    let cityName: String
    /// City centre for the weather fetch; nil quietly hides the weather row.
    let cityCenter: CLLocationCoordinate2D?
    /// Personal countdown — nil until the traveler confirms an entry date.
    let daysStayed: Int?
    let visaDaysRemaining: Int?
    let taxDaysRemaining: Int?
    let kit: [CityKitItem]
    let events: [CityEvent]
    let workSpots: [Experience]
    let kitDone: Int
    let recallVisited: Int
    let recallPending: Int
    let nextPendingName: String?

    /// Hops into deeper surfaces. The panel dismisses itself first; the owner
    /// presents the follow-up sheet from `onDismiss` (single-presenter rule).
    let onOpenKit: (CityKitItem.Kind?) -> Void
    let onOpenLive: () -> Void
    let onSelectExperience: (Experience) -> Void
    let onVerifyNext: () -> Void
    let onDismiss: () -> Void
    /// Plan face: opens the chat with a prefilled research question, so the
    /// pre-trip page never dead-ends even when the server kit / weather have
    /// nothing for this city yet. nil hides the row (old call sites, tests).
    var onAskSolo: ((String) -> Void)? = nil

    /// Previews / snapshot tests only: bypasses the network fetch so the
    /// weather row renders deterministically. nil (production) fetches live.
    var previewWeather: WeatherSnapshot? = nil

    @Environment(\.colorScheme) private var colorScheme
    /// Fetched on appear; nil (loading or failed) hides the weather row —
    /// the panel never blocks on the network.
    @State private var weather: WeatherSnapshot?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    hero
                    switch face {
                    case .plan:
                        visaPolicySection
                        weatherSection
                        workSection
                        kitSection
                        askSoloSection
                    case .arrive:
                        entrySection
                        kitSection
                        weatherSection
                        workSection
                    case .live:
                        countdownSection
                        workSection
                        eventsSection
                        weatherSection
                    case .recall:
                        recallSection
                        kitSection
                    }
                }
                .padding(16)
            }
            .background(pageBackground.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("cityos.base.panel.title", comment: "基地 sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "Done")) { onDismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { await loadWeather() }
    }

    // MARK: - Hero

    /// City identity block: face tag, big city name, one-line register, and —
    /// once the entry date is confirmed — the large countdown ring.
    private var hero: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(face.tagText)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(face.tagColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3.5)
                    .background(Capsule().fill(face.tagColor.opacity(0.12)))
                Text(cityName)
                    .ctDisplay(26, .bold)
                    .foregroundStyle(primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(NSLocalizedString("cityos.base.subtitle.\(face.rawValue)", comment: "Base face subtitle"))
                    .ctBody(13)
                    .foregroundStyle(CT.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            // Ring only on the two in-stay faces — a Recall hero counting
            // down a visa the traveler already left behind is stale noise.
            if face.showsCountdown, let visaDaysRemaining, let daysStayed {
                BaseCountdownRing(
                    remaining: visaDaysRemaining,
                    total: max(visaDaysRemaining + daysStayed, 1),
                    size: 64
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(heroFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 0.5)
        )
    }

    // MARK: - Visa / entry / countdown sections

    /// Plan face: the city's visa policy from the kit — server-provided copy,
    /// never an invented number. Hidden when the city has no visa kit row.
    @ViewBuilder
    private var visaPolicySection: some View {
        if let visaItem = kit.first(where: { $0.kind == .visa }) {
            SectionCard(title: NSLocalizedString("cityos.base.section.visa", comment: "签证")) {
                PanelRow(
                    symbol: "doc.text",
                    tint: CT.modePlanBlue,
                    title: visaItem.name,
                    subtitle: visaItem.main,
                    badge: visaItem.action?.visaDays.map {
                        String(format: NSLocalizedString("cityos.base.visa.policy", comment: "签证 %d 天"), $0)
                    },
                    action: { hop { onOpenKit(.visa) } }
                )
            }
        }
    }

    /// Plan face: the always-there doorway. The visa-policy and weather rows
    /// are data-gated (they hide rather than stub), so a city the server
    /// doesn't know yet could leave the pre-trip page nearly empty — this row
    /// hands the research question to the agent instead of dead-ending.
    @ViewBuilder
    private var askSoloSection: some View {
        if let onAskSolo {
            SectionCard(title: NSLocalizedString("cityos.base.section.ask", comment: "还想知道什么")) {
                PanelRow(
                    symbol: "sparkles",
                    tint: CT.accent,
                    title: NSLocalizedString("cityos.base.ask.title", comment: "签证、天气、值不值得去"),
                    subtitle: NSLocalizedString("cityos.base.ask.hint", comment: "问 Solo，即刻回答"),
                    badge: nil,
                    action: {
                        hop {
                            onAskSolo(String(
                                format: NSLocalizedString("cityos.base.ask.prompt", comment: "prefilled research question, %@ = city"),
                                cityName
                            ))
                        }
                    }
                )
            }
        }
    }

    /// Arrive face: the one-tap start of the honest countdown. Once the entry
    /// date exists this flips to the countdown row automatically.
    @ViewBuilder
    private var entrySection: some View {
        SectionCard(title: NSLocalizedString("cityos.base.section.visa", comment: "签证")) {
            if visaDaysRemaining != nil {
                countdownRow
            } else {
                PanelRow(
                    symbol: "calendar.badge.plus",
                    tint: CT.sunGoldDeep,
                    title: NSLocalizedString("cityos.base.visa.setEntry", comment: "设置入境日期"),
                    subtitle: NSLocalizedString("cityos.base.visa.setEntry.hint", comment: "确认入境日期后开始倒数"),
                    badge: nil,
                    action: { hop { onOpenKit(.visa) } }
                )
            }
        }
    }

    /// Live face: the countdown plus the 183-day tax line, both self-computed
    /// checkable numbers. Hidden entirely until the entry date is confirmed —
    /// the honesty gate.
    @ViewBuilder
    private var countdownSection: some View {
        if visaDaysRemaining != nil {
            SectionCard(title: NSLocalizedString("cityos.base.section.visa", comment: "签证")) {
                countdownRow
            }
        }
    }

    @ViewBuilder
    private var countdownRow: some View {
        if let visaDaysRemaining, let daysStayed {
            PanelRow(
                symbol: "hourglass",
                tint: visaDaysRemaining <= 7 ? CT.warningText : CT.accent,
                title: String(
                    format: NSLocalizedString("cityos.base.visa.remaining", comment: "签证剩 %d 天"),
                    max(visaDaysRemaining, 0)
                ),
                subtitle: taxDaysRemaining.map {
                    String(format: NSLocalizedString("cityos.base.tax", comment: "距 183 天税务线 %d 天"), $0)
                } ?? String(
                    format: NSLocalizedString("cityos.base.day", comment: "第 %d 天"),
                    daysStayed
                ),
                badge: nil,
                action: { hop { onOpenKit(.visa) } }
            )
        }
    }

    // MARK: - Weather

    /// Current weather at the city centre — works for a city you haven't
    /// left for yet, which is the whole point of the Plan face. Loading or
    /// failure states render nothing rather than a spinner or a stub.
    @ViewBuilder
    private var weatherSection: some View {
        if let weather {
            SectionCard(title: NSLocalizedString("cityos.base.section.weather", comment: "天气")) {
                PanelRow(
                    symbol: weatherSymbol(weather.condition),
                    tint: CT.sunGoldDeep,
                    title: String(
                        format: NSLocalizedString("cityos.base.weather.temp", comment: "%d°C · condition"),
                        Int(weather.tempC.rounded()),
                        NSLocalizedString("weather.condition.\(weather.condition.rawValue)", comment: "condition")
                    ),
                    subtitle: String(
                        format: NSLocalizedString("cityos.base.weather.precip", comment: "降水 %d%%"),
                        weather.precipChancePct
                    ),
                    badge: nil,
                    action: nil
                )
            }
        }
    }

    // MARK: - Work

    /// Top work-ready spots (`MapViewModel.isWorkReady`). Tapping a row hops
    /// back to the map with that pin selected — the panel points, the map
    /// leads. Hidden when the city has no work-ready data yet.
    @ViewBuilder
    private var workSection: some View {
        if !workSpots.isEmpty {
            SectionCard(title: NSLocalizedString("cityos.base.section.work", comment: "办公")) {
                VStack(spacing: 2) {
                    ForEach(workSpots) { spot in
                        PanelRow(
                            symbol: spot.category == .work ? "laptopcomputer" : "cup.and.saucer.fill",
                            tint: CT.accent,
                            title: spot.shortName,
                            subtitle: workBadges(spot),
                            badge: String(format: "%.1f", spot.soloScore.overall),
                            action: { hop { onSelectExperience(spot) } }
                        )
                    }
                }
            }
        }
    }

    /// "wifi · 插座" style amenity line built from the highlights that made the
    /// spot qualify. Empty for explicit `.work` category spots (already implied).
    private func workBadges(_ spot: Experience) -> String? {
        let labels = spot.highlights
            .filter { $0.kind == .wifi || $0.kind == .power }
            .map(\.label)
        return labels.isEmpty ? nil : labels.joined(separator: " · ")
    }

    // MARK: - Events

    @ViewBuilder
    private var eventsSection: some View {
        if !events.isEmpty {
            SectionCard(
                title: NSLocalizedString("cityos.base.section.events", comment: "本周活动"),
                trailing: (
                    NSLocalizedString("cityos.base.events.more", comment: "查看全部"),
                    { hop(onOpenLive) }
                )
            ) {
                VStack(spacing: 2) {
                    ForEach(events.prefix(3)) { event in
                        PanelRow(
                            symbol: "calendar",
                            tint: event.limitedLabel != nil ? CT.eventLimited : CT.accent,
                            title: event.name,
                            subtitle: event.whenLabel,
                            badge: event.limitedLabel,
                            action: { hop(onOpenLive) }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Kit

    /// Landing-kit preview: progress plus the doorway row. The full kit
    /// (with links, todos, the visa self-compute) stays in `KitSheet` — this
    /// row is the doorway, not a copy.
    @ViewBuilder
    private var kitSection: some View {
        if !kit.isEmpty {
            SectionCard(title: NSLocalizedString("cityos.base.section.kit", comment: "落地包")) {
                PanelRow(
                    symbol: "shippingbox.fill",
                    tint: CT.accent,
                    title: face == .plan
                        ? NSLocalizedString("cityos.kit.title.plan", comment: "行前清单")
                        : NSLocalizedString("cityos.kit.title", comment: "落地包"),
                    subtitle: String(
                        format: NSLocalizedString("cityos.base.kit.progress", comment: "行前 %1$d/%2$d"),
                        kitDone, kit.count
                    ),
                    badge: nil,
                    action: { hop { onOpenKit(nil) } }
                )
            }
        }
    }

    // MARK: - Recall

    private var recallSection: some View {
        SectionCard(title: NSLocalizedString("cityos.base.section.recall", comment: "回顾")) {
            PanelRow(
                symbol: "eye",
                tint: CT.fgMuted,
                title: String(
                    format: NSLocalizedString("cityos.base.recall.stats", comment: "去过 %1$d · 待印证 %2$d"),
                    recallVisited, recallPending
                ),
                subtitle: nextPendingName.map {
                    String(format: NSLocalizedString("cityos.mode.recall.verify.cta", comment: "印证「%@」"), $0)
                },
                badge: nil,
                action: recallPending > 0 ? { hop(onVerifyNext) } : nil
            )
        }
    }

    // MARK: - Helpers

    /// Row-tap wrapper: haptic + the owner-supplied hop. The owner dismisses
    /// this sheet and queues the follow-up surface, so two sheets never fight
    /// over one presenter.
    private func hop(_ action: @escaping () -> Void) {
        Haptics.impact(.light)
        action()
    }

    private func loadWeather() async {
        if let previewWeather {
            weather = previewWeather
            return
        }
        guard let cityCenter else { return }
        let service = WeatherService()
        weather = try? await service.current(at: cityCenter)
    }

    private func weatherSymbol(_ condition: WeatherCondition) -> String {
        switch condition {
        case .clear:        return "sun.max.fill"
        case .partlyCloudy: return "cloud.sun.fill"
        case .cloudy:       return "cloud.fill"
        case .rain:         return "cloud.rain.fill"
        case .storm:        return "cloud.bolt.rain.fill"
        case .snow:         return "cloud.snow.fill"
        case .fog:          return "cloud.fog.fill"
        }
    }

    private var pageBackground: Color {
        colorScheme == .dark ? CT.warmSheetDark : CT.surfaceSunken
    }
    private var heroFill: Color { colorScheme == .dark ? CT.warmCardDark : CT.surfaceWhite }
    private var borderColor: Color { colorScheme == .dark ? CT.warmBorderDark : CT.borderSubtle }
    private var primaryText: Color { colorScheme == .dark ? CT.fgPrimaryDark : CT.fgPrimary }
}

// MARK: - SectionCard

/// A warm card wrapping one panel section: small-caps header, optional
/// trailing text action, content below.
private struct SectionCard<Content: View>: View {
    let title: String
    var trailing: (String, () -> Void)?
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    init(
        title: String,
        trailing: (String, () -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(CT.fgSubtle)
                Spacer()
                if let trailing {
                    Button {
                        trailing.1()
                    } label: {
                        Text(trailing.0)
                            .ctBody(12.5, .semibold)
                            .foregroundStyle(CT.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 0.5)
        )
    }

    private var cardFill: Color { colorScheme == .dark ? CT.warmCardDark : CT.surfaceWhite }
    private var borderColor: Color { colorScheme == .dark ? CT.warmBorderDark : CT.borderSubtle }
}

// MARK: - PanelRow

/// One row inside a section: icon tile, title/subtitle, optional mono badge,
/// chevron when tappable. Rows with `action == nil` render as plain facts.
private struct PanelRow: View {
    let symbol: String
    let tint: Color
    let title: String
    var subtitle: String?
    var badge: String?
    var action: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let action {
            Button(action: action) { rowBody }
                .buttonStyle(PressableButtonStyle(pressedScale: 0.98))
        } else {
            rowBody
        }
    }

    private var rowBody: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.10)))
            VStack(alignment: .leading, spacing: 2.5) {
                Text(title)
                    .ctBody(14.5, .semibold)
                    .foregroundStyle(primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let subtitle {
                    Text(subtitle)
                        .ctBody(12.5)
                        .foregroundStyle(CT.fgMuted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
            if let badge {
                Text(badge)
                    .ctMono(12, .semibold)
                    .foregroundStyle(CT.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(CT.accentSoft))
            }
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CT.fgSubtle)
            }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    private var primaryText: Color { colorScheme == .dark ? CT.fgPrimaryDark : CT.fgPrimary }
}
