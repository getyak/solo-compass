import SwiftUI
import CoreLocation

// Reports the hero title's minY in the named coordinate space so the scroll
// view can decide whether the title has scrolled out of view.
private struct HeroTitleOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

/// Full-screen scrollable detail. Renders every field of the Experience model
/// the user might want before going. Real Inconveniences are surfaced as
/// prominently as the recommendation — that is the product's brand.
public struct ExperienceDetailView: View {
    @State var viewModel: ExperienceDetailViewModel
    var onClose: () -> Void
    var onMarkDone: ((_ experience: Experience) -> Void)?
    /// US-004: When non-nil, render the "Ask Solo about this" button (subject
    /// to `viewModel.canAskSolo`). Tapping fires this with the current
    /// experience; the parent is responsible for opening ChatSheet bound to
    /// that experience via `VoiceAgentOrchestrator.rebindContext(_:)`.
    var onAskSolo: ((_ experience: Experience) -> Void)?
    /// When non-nil, nearby carousel cards are tappable — tapping one fires
    /// this closure so the parent can re-bind the detail sheet to the chosen
    /// experience. When nil the cards render as plain non-interactive views.
    var onSelectExperience: ((_ experience: Experience) -> Void)?

    @Environment(\.themeService) private var themeService
    @Environment(LocationService.self) private var locationService
    @State private var isShowingReport: Bool = false
    @State private var showingRadarTooltip: Bool = false
    @State private var exportMarkdown: String? = nil
    @State private var heartBurstTrigger = 0
    @State private var celebrationTrigger = 0
    @State private var celebrationMilestone: Int? = nil
    @State private var isShowingNavPicker = false
    @State private var isShowingAddToItinerary = false
    @State private var heroTitleVisible: Bool = true
    @State private var addedItineraryToast: Itinerary? = nil
    @State private var toastDismissTask: Task<Void, Never>? = nil
    @State private var itineraryToNavigate: Itinerary? = nil
    /// US-025: drives the paywall sheet when a free-tier user taps the gated
    /// "Ask Solo" CTA instead of leaving them on a dead toast.
    @State private var isShowingPaywall: Bool = false

    public init(
        viewModel: ExperienceDetailViewModel,
        onClose: @escaping () -> Void = {},
        onMarkDone: ((_ experience: Experience) -> Void)? = nil,
        onAskSolo: ((_ experience: Experience) -> Void)? = nil,
        onSelectExperience: ((_ experience: Experience) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onClose = onClose
        self.onMarkDone = onMarkDone
        self.onAskSolo = onAskSolo
        self.onSelectExperience = onSelectExperience
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroSection
                compassDirectionView
                askSoloSection
                if let coord = viewModel.experience.location.clCoordinate {
                    LocationCard(
                        coordinate: coord,
                        displayName: viewModel.experience.location.placeNameLocal
                            ?? viewModel.experience.location.placeNameRomanized
                            ?? viewModel.experience.title,
                        addressHint: viewModel.experience.location.addressHint
                    )
                    .environment(locationService)
                }
                whyItMattersSection
                aiInsightSection
                let hasOpeningHours = viewModel.experience.location.openingHours
                    .map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
                if !viewModel.experience.bestTimes.isEmpty || hasOpeningHours {
                    bestTimesSection
                }
                if !viewModel.experience.howTo.isEmpty {
                    howToSection
                }
                if !viewModel.experience.realInconveniences.isEmpty {
                    inconveniencesSection
                }
                // Skip the Solo Score for un-enriched OSM entries. Their score
                // is a flat 7.0 placeholder from skeletonExperience, not a real
                // estimate — showing it as "Solo Score (AI estimate)" misleads.
                if !(viewModel.experience.isFromOpenStreetMap && !viewModel.experience.isAIEnriched) {
                    soloScoreSection
                }
                if !viewModel.experience.sources.isEmpty {
                    sourcesSection
                }
                if !viewModel.nearbyExperiences.isEmpty {
                    nearbySection
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            // No manual bottom padding: `safeAreaInset(edge: .bottom)` reserves
            // the action bar's height automatically, so content can't scroll
            // behind it (was a hardcoded 80pt that under-reserved on devices
            // with a home indicator).
        }
        .coordinateSpace(name: "detailScroll")
        .onPreferenceChange(HeroTitleOffsetKey.self) { offset in
            let visible = offset > 0
            guard visible != heroTitleVisible else { return }
            if reduceMotion {
                heroTitleVisible = visible
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    heroTitleVisible = visible
                }
            }
        }
        .background(themeService.currentTheme.background)
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .navigationTitle(heroTitleVisible ? "" : viewModel.experience.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onClose) {
                    Image(systemName: "chevron.down")
                }
                .accessibilityLabel(Text(NSLocalizedString("action.close", comment: "Close detail sheet")))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        exportMarkdown = MarkdownExporter.export(viewModel.experience)
                    } label: {
                        Label(
                            NSLocalizedString("detail.exportNote", comment: "Export Markdown note"),
                            systemImage: "square.and.arrow.up"
                        )
                    }
                    Button(role: .destructive) {
                        isShowingReport = true
                    } label: {
                        Label(
                            NSLocalizedString("detail.report", comment: "Report an issue"),
                            systemImage: "exclamationmark.triangle"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(Text(NSLocalizedString("detail.more", comment: "More options")))
            }
        }
        .sheet(isPresented: $isShowingReport) {
            ReportIssueSheet(
                experience: viewModel.experience,
                onSubmit: { _, _ in isShowingReport = false },
                onCancel: { isShowingReport = false }
            )
        }
        .sheet(item: Binding(
            get: { exportMarkdown.map { ExportPayload(markdown: $0) } },
            set: { if $0 == nil { exportMarkdown = nil } }
        )) { payload in
            ShareSheet(
                experience: viewModel.experience,
                markdown: payload.markdown,
                notionURL: MarkdownExporter.notionWebClipperURL(title: viewModel.experience.title)
            )
        }
        .sheet(isPresented: $isShowingAddToItinerary) {
            AddToItinerarySheet(
                experienceId: viewModel.experience.id,
                experienceTitle: viewModel.experience.title,
                onSuccess: { itinerary in
                    showItineraryToast(itinerary)
                }
            )
            .environment(viewModel.experienceService)
        }
        .sheet(item: $itineraryToNavigate) { itin in
            NavigationStack {
                ItineraryDetailView(itinerary: itin)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(NSLocalizedString("common.close", comment: "Close")) {
                                itineraryToNavigate = nil
                            }
                        }
                    }
            }
        }
        // US-025: free-tier users tapping the gated "Ask Solo" CTA land here.
        // PaywallView inherits SubscriptionService from the environment chain
        // (injected at the app root). On unlock the sheet dismisses; the user
        // can then re-tap the now-enabled CTA to open chat.
        .sheet(isPresented: $isShowingPaywall) {
            NavigationStack {
                PaywallView(onUnlocked: { isShowingPaywall = false })
            }
            .accessibilityIdentifier("experience.askSolo.paywall")
        }
        .overlay(alignment: .bottom) {
            if let itin = addedItineraryToast {
                itineraryAddedToast(itin)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 96)
            }
        }
        .task {
            await viewModel.loadAIExplanation()
            await viewModel.loadRemoteSoloScore()
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.experience.isFromOpenStreetMap {
                let enriched = viewModel.experience.isAIEnriched
                let badgeKey = enriched ? "explore.aiBadge" : "explore.osmBadge"
                let badgeText = NSLocalizedString(badgeKey, comment: "Provenance badge")
                HStack(spacing: 6) {
                    Image(systemName: enriched ? "sparkles" : "mappin.and.ellipse")
                        .font(.caption2)
                    Text(badgeText)
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color(.tertiarySystemFill)))
                .accessibilityLabel(Text(badgeText))
            }
            HStack(spacing: 8) {
                Image(systemName: viewModel.experience.category.symbol)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Circle().fill(viewModel.experience.category.color))
                Text(viewModel.experience.category.localizedTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                Spacer()
                ConfidenceBadge(confidence: viewModel.experience.confidence, compact: false)
            }
            .fixedSize(horizontal: false, vertical: true)

            Text(viewModel.experience.title)
                .font(.title2.bold())
                .lineLimit(nil)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: HeroTitleOffsetKey.self,
                            value: geo.frame(in: .named("detailScroll")).minY
                        )
                    }
                )
                // VoiceOver: avoid double-announcing when the nav bar title mirrors this
                .accessibilityHidden(!heroTitleVisible)

            Text(viewModel.experience.oneLiner)
                .font(.body)
                .foregroundStyle(.secondary)

            if let local = viewModel.experience.location.placeNameLocal, !local.isEmpty {
                let romanized = viewModel.experience.location.placeNameRomanized
                HStack(spacing: 8) {
                    Text(romanized?.isEmpty == false ? "\(local) · \(romanized ?? "")" : local)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    distancePill
                }
            } else {
                distancePill
            }
        }
    }

    private func relativeBearing(to coord: CLLocationCoordinate2D) -> Double? {
        locationService.relativeBearing(to: coord)
    }

    private static func compassDirection(for degrees: Double) -> String {
        let directions = [
            NSLocalizedString("compass.N", comment: "North"),
            NSLocalizedString("compass.NE", comment: "Northeast"),
            NSLocalizedString("compass.E", comment: "East"),
            NSLocalizedString("compass.SE", comment: "Southeast"),
            NSLocalizedString("compass.S", comment: "South"),
            NSLocalizedString("compass.SW", comment: "Southwest"),
            NSLocalizedString("compass.W", comment: "West"),
            NSLocalizedString("compass.NW", comment: "Northwest"),
        ]
        let raw = Int((degrees / 45.0).rounded())
        let index = ((raw % 8) + 8) % 8
        return directions[index]
    }

    @ViewBuilder
    private var distancePill: some View {
        if locationService.currentLocation != nil,
           let coord = viewModel.experience.location.clCoordinate {
            let meters = locationService.distance(to: coord)
            if meters < .greatestFiniteMagnitude {
                let distStr = Self.formatDistance(meters)
                let awayStr = String(
                    format: NSLocalizedString("detail.distance.away", comment: "Distance away pill"),
                    distStr
                )
                let relBearing = relativeBearing(to: coord)
                HStack(spacing: 3) {
                    if let relBearing {
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 9))
                            .rotationEffect(.degrees(relBearing))
                            .animation(
                                reduceMotion ? nil : .easeInOut(duration: 0.25),
                                value: relBearing
                            )
                            .accessibilityHidden(true)
                    }
                    Image(systemName: "location.fill")
                        .font(.system(size: 9))
                    Text(awayStr)
                        .font(.caption2.monospacedDigit())
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color(.tertiarySystemFill)))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text({
                    var label = String(
                        format: NSLocalizedString("detail.distance.a11y", comment: "Distance accessibility label"),
                        distStr
                    )
                    if let relBearing {
                        let direction = Self.compassDirection(for: relBearing)
                        label += ". " + String(
                            format: NSLocalizedString("card.distance.bearing.a11y", comment: "Bearing direction accessibility"),
                            direction
                        )
                    }
                    return label
                }()))
            }
        }
    }

    // MARK: - Compass Direction Overlay

    /// Live compass ring that rotates to point toward the selected experience.
    /// Rendered only when a GPS fix is available — gracefully absent otherwise.
    @ViewBuilder
    private var compassDirectionView: some View {
        if locationService.currentLocation != nil,
           let coord = viewModel.experience.location.clCoordinate {
            let relBearing = relativeBearing(to: coord) ?? 0
            let distStr = Self.formatDistance(locationService.distance(to: coord))
            let cardinalDir = Self.compassDirection(for: relBearing)
            let a11yLabel = String(
                format: NSLocalizedString("compass.direction.a11y", comment: "Distance + cardinal direction accessibility label"),
                distStr,
                cardinalDir
            )
            CompassDirectionView(
                relBearing: relBearing,
                distanceString: distStr,
                cardinalDirection: cardinalDir,
                reduceMotion: reduceMotion
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(a11yLabel))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private static let metersFormatter: MeasurementFormatter = {
        let f = MeasurementFormatter()
        f.unitOptions = .providedUnit
        f.numberFormatter.maximumFractionDigits = 0
        return f
    }()

    private static let kilometersFormatter: MeasurementFormatter = {
        let f = MeasurementFormatter()
        f.unitOptions = .providedUnit
        f.numberFormatter.maximumFractionDigits = 1
        f.numberFormatter.minimumFractionDigits = 1
        return f
    }()

    private static func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            let rounded = (meters / 50).rounded() * 50
            let measurement = Measurement(value: max(50, rounded), unit: UnitLength.meters)
            return metersFormatter.string(from: measurement)
        } else {
            let measurement = Measurement(value: meters / 1000, unit: UnitLength.kilometers)
            return kilometersFormatter.string(from: measurement)
        }
    }

    // MARK: - Ask Solo (US-004 / US-025)

    /// US-025: routing for an "Ask Solo" tap. Pure so it's unit-testable
    /// without driving the live UI. When the user is entitled
    /// (`canAskSolo`), the chat opens; otherwise the paywall is presented.
    enum AskSoloAction: Equatable {
        case openChat
        case presentPaywall
    }

    /// Decide what a tap on the gated CTA should do. Free-tier users (no Pro
    /// entitlement and no local key) get the paywall, not a dead toast.
    static func askSoloAction(canAskSolo: Bool) -> AskSoloAction {
        canAskSolo ? .openChat : .presentPaywall
    }

    /// "Ask Solo about this" CTA. Rendered whenever the parent supplied
    /// `onAskSolo` (so a chat surface is reachable from this context). The
    /// entitlement gate now lives in the *tap handler*, not in visibility:
    ///   • entitled (`viewModel.canAskSolo`) → opens the scoped chat.
    ///   • free-tier → presents the paywall sheet (US-025).
    @ViewBuilder
    private var askSoloSection: some View {
        if let onAskSolo {
            Button {
                Haptics.impact(.light)
                switch Self.askSoloAction(canAskSolo: viewModel.canAskSolo) {
                case .openChat:
                    onAskSolo(viewModel.experience)
                case .presentPaywall:
                    isShowingPaywall = true
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.subheadline.weight(.semibold))
                    Text(NSLocalizedString(
                        "experience.askSolo.cta",
                        comment: "Open Solo chat scoped to this experience"
                    ))
                    .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.accentColor.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
                )
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("experience.askSolo.cta")
            .accessibilityLabel(Text(NSLocalizedString(
                "experience.askSolo.cta",
                comment: "Open Solo chat scoped to this experience"
            )))
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var whyItMattersSection: some View {
        let content = viewModel.experience.whyItMatters.trimmingCharacters(in: .whitespacesAndNewlines)
        let isLoading = viewModel.isLoadingWhyItMatters
        if isLoading || !content.isEmpty {
            sectionContainer(title: NSLocalizedString("section.whyItMatters", comment: "")) {
                if isLoading {
                    SkeletonView(lineCount: 3)
                        .id("whyItMatters-skeleton")
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                } else {
                    Text(content)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .id("whyItMatters-content")
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: isLoading)
        }
    }

    @ViewBuilder
    private var aiInsightSection: some View {
        let isLoading = viewModel.isLoadingAIExplanation
        if isLoading || viewModel.aiExplanation != nil {
            sectionContainer(title: NSLocalizedString("ai.explanation.title", comment: "AI Insight section title")) {
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(NSLocalizedString("ai.explanation.loading", comment: "AI insight loading indicator"))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .id("aiInsight-skeleton")
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                } else if let explanation = viewModel.aiExplanation {
                    Text(explanation)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .id("aiInsight-content")
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: isLoading)
        }
    }

    private var bestTimeStatusPill: some View {
        let isNow = viewModel.experience.isBestNow()
        let hint = viewModel.experience.bestTimeHint()
        let label: String
        let symbol: String
        let background: Color
        if isNow {
            label = NSLocalizedString("bestTimes.now.pill", comment: "Good time now pill")
            symbol = "clock.badge.checkmark"
            background = Color.green.opacity(0.15)
        } else if let hint {
            label = String(format: NSLocalizedString("bestTimes.next.pill", comment: "Better at time pill"), hint)
            symbol = "clock"
            background = Color(.tertiarySystemFill)
        } else {
            return AnyView(EmptyView())
        }
        let a11yLabel = isNow
            ? NSLocalizedString("timeline.now.good", comment: "")
            : NSLocalizedString("timeline.now.off", comment: "")
        return AnyView(
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.caption2.weight(.semibold))
                    .symbolEffect(.pulse, isActive: isNow && !reduceMotion)
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(isNow ? Color.green : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(background))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(a11yLabel))
        )
    }

    @ViewBuilder
    private var openingHoursRow: some View {
        if let raw = viewModel.experience.location.openingHours {
            let hours = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !hours.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "building.2")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(NSLocalizedString("location.openingHours", comment: "Posted hours label"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(hours)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text(String(
                        format: NSLocalizedString("location.openingHours.a11y", comment: "Posted hours accessibility label"),
                        hours
                    )))
                    Divider()
                }
            }
        }
    }

    private var bestTimesSection: some View {
        sectionContainer(title: NSLocalizedString("section.bestTimes", comment: "")) {
            VStack(alignment: .leading, spacing: 6) {
                openingHoursRow
                if !viewModel.experience.bestTimes.isEmpty {
                    HStack { Spacer(); bestTimeStatusPill }
                    BestTimesTimeline(experience: viewModel.experience)
                        .padding(.bottom, 4)
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        let currentHour = Calendar.current.component(.hour, from: context.date)
                        ForEach(viewModel.experience.bestTimes, id: \.self) { window in
                            let isActiveNow: Bool = {
                                let s = window.startHour, e = window.endHour
                                return s <= e
                                    ? currentHour >= s && currentHour < e
                                    : currentHour >= s || currentHour < e
                            }()
                            BestTimeWindowRow(
                                window: window,
                                isActiveNow: isActiveNow,
                                categoryColor: viewModel.experience.category.color,
                                formatWindow: format(window:),
                                reduceMotion: reduceMotion
                            )
                        }
                    }
                    let range = viewModel.experience.durationMinutes
                    Text(String(format: NSLocalizedString("section.duration", comment: ""), range.min, range.max))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var howToSection: some View {
        sectionContainer(title: NSLocalizedString("section.howTo", comment: "")) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(viewModel.experience.howTo) { step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(step.order)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(viewModel.experience.category.color))
                        Text(step.text)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func inconvenienceCategoryName(_ category: RealInconvenience.Category) -> String {
        let key = "inconvenience.category.\(category.rawValue)"
        return NSLocalizedString(key, comment: "Inconvenience category display name")
    }

    private func inconvenienceTint(_ category: RealInconvenience.Category) -> Color {
        switch category {
        case .safety, .scam:                            return .red
        case .crowds, .logistics, .weather,
             .etiquette, .other:                        return .orange
        }
    }

    private var inconveniencesSection: some View {
        sectionContainer(title: NSLocalizedString("section.inconveniences", comment: "")) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(viewModel.experience.realInconveniences) { item in
                    let severity = item.category.severity
                    let tint = severity.tintColor
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: item.category.symbol)
                                .foregroundStyle(tint)
                                .frame(width: 20)
                                .accessibilityHidden(true)
                            Text(inconvenienceCategoryName(item.category))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(tint)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(tint.opacity(severity.backgroundOpacity)))
                                .accessibilityHidden(true)
                        }
                        Text(item.text)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(tint.opacity(severity.backgroundOpacity))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(tint.opacity(0.25), lineWidth: 1)
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(String(
                        format: NSLocalizedString("inconvenience.a11y.prefix", comment: "Heads up: <category> — <text>"),
                        inconvenienceCategoryName(item.category),
                        item.text
                    )))
                }
            }
        }
    }

    private var soloScoreSection: some View {
        // Three-state cold-start UX. Use aggregated score from local survey
        // responses when available; otherwise the seed/AI value.
        let score = viewModel.displaySoloScore
        let count = score.basedOnCount
        let titleKey: String
        let subtitle: String?
        let isEstimate: Bool

        switch count {
        case 0:
            titleKey = "solo.section.estimate"
            subtitle = nil
            isEstimate = true
        case 1...2:
            titleKey = "solo.section.early"
            subtitle = String(
                format: NSLocalizedString("solo.basedOn.early", comment: "Based on N early reports"),
                count
            )
            isEstimate = false
        default:
            titleKey = "section.soloScore"
            subtitle = String(
                format: NSLocalizedString("solo.basedOn", comment: "Based on N solo travelers"),
                count
            )
            isEstimate = false
        }

        return sectionContainer(title: NSLocalizedString(titleKey, comment: "")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    SoloScoreBadge(score: score, style: .full)
                        .opacity(isEstimate ? 0.6 : 1.0)
                    if isEstimate {
                        Text(NSLocalizedString("solo.estimate.pill", comment: "AI estimate pill"))
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color(.tertiarySystemFill)))
                            .accessibilityLabel(Text(NSLocalizedString("solo.estimate.pill", comment: "")))
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // US-009: Radar chart replacing uniform progress bars
                SoloScoreRadarChart(score: score)
                    .padding(.horizontal, 16)
                    .opacity(isEstimate ? 0.7 : 1.0)
                Button {
                    Haptics.selection()
                    showingRadarTooltip.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .rotationEffect(reduceMotion ? .zero : (showingRadarTooltip ? .degrees(90) : .degrees(0)))
                            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: showingRadarTooltip)
                        Text(NSLocalizedString("solo.breakdown.toggle", comment: "Per-dimension scores disclosure toggle"))
                            .font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
                .accessibilityValue(Text(showingRadarTooltip
                    ? NSLocalizedString("solo.breakdown.expanded", comment: "Expanded accessibility value")
                    : NSLocalizedString("solo.breakdown.collapsed", comment: "Collapsed accessibility value")))
                .accessibilityHint(Text(NSLocalizedString("solo.breakdown.expand.hint", comment: "Accessibility hint for breakdown toggle")))
                if showingRadarTooltip {
                    radarDimensionBreakdown(score: score)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showingRadarTooltip)
        }
    }

    private func radarDimensionBreakdown(score: SoloScore) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let b = score.breakdown
            let dims: [(String, String, Double)] = [
                (NSLocalizedString("solo.seating", comment: ""), "chair", b.seatingFriendly),
                (NSLocalizedString("solo.staff", comment: ""), "person.crop.circle", b.staffPressure),
                (NSLocalizedString("solo.patrons", comment: ""), "person.2", b.soloPatronRatio),
                (NSLocalizedString("solo.ambiance", comment: ""), "sparkles", b.ambianceFit),
                (NSLocalizedString("solo.safety", comment: ""), "shield", b.safety),
                (NSLocalizedString("solo.portioning", comment: ""), "fork.knife", b.soloPortioning),
            ]
            ForEach(dims, id: \.0) { label, symbol, value in
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.caption)
                        .foregroundStyle(score.scoreColor)
                        .frame(width: 18)
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.0f", value))
                        .font(.caption.monospacedDigit().bold())
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }

    // MARK: - US-015: Multi-source indicator

    /// Multi-source indicator shown when the experience was assembled from ≥2 distinct sources.
    @ViewBuilder
    private var multiSourceIndicator: some View {
        if viewModel.experience.sources.count >= 2 {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text(NSLocalizedString("detail.multiSource.indicator", comment: "Verified by multiple sources indicator"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.green.opacity(0.08)))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(NSLocalizedString("detail.multiSource.indicator.a11y", comment: "Verified by multiple sources accessibility label")))
        }
    }

    // MARK: - US-015: Rating and price level rows

    @ViewBuilder
    private var ratingRow: some View {
        if let rating = viewModel.experience.location.rating {
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)
                Text(NSLocalizedString("detail.rating", comment: "Rating row label"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f / 10", rating))
                    .font(.subheadline.monospacedDigit())
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(String(
                format: NSLocalizedString("detail.rating.a11y", comment: "Rating accessibility label"),
                String(format: "%.1f", rating)
            )))
        }
    }

    @ViewBuilder
    private var priceLevelRow: some View {
        if let price = viewModel.experience.location.priceLevel {
            let dots = Int(price.rounded())
            let filled = String(repeating: "●", count: min(dots, 4))
            let empty = String(repeating: "○", count: max(0, 4 - min(dots, 4)))
            HStack(spacing: 8) {
                Image(systemName: "banknote")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(NSLocalizedString("detail.priceLevel", comment: "Price level row label"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(filled)\(empty)")
                    .font(.subheadline.monospacedDigit())
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(String(
                format: NSLocalizedString("detail.priceLevel.a11y", comment: "Price level accessibility label"),
                dots
            )))
        }
    }

    private var sourcesSection: some View {
        sectionContainer(title: NSLocalizedString("section.sources", comment: "")) {
            VStack(alignment: .leading, spacing: 6) {
                multiSourceIndicator
                ratingRow
                priceLevelRow
                ForEach(viewModel.experience.sources) { source in
                    sourceRow(source)
                }
            }
        }
    }

    @ViewBuilder
    private func sourceRow(_ source: InformationSource) -> some View {
        let label = source.attribution ?? source.type.rawValue
        let iconName = symbol(for: source.type)
        if let url = source.url {
            Link(destination: url) {
                HStack {
                    Image(systemName: iconName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(label)
                        .font(.caption)
                    Spacer()
                    Text(source.verifiedAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .simultaneousGesture(TapGesture().onEnded {
                Haptics.impact(.light)
            })
            .accessibilityAddTraits(.isLink)
            .accessibilityHint(Text(NSLocalizedString("detail.source.openHint", comment: "Opens the original source")))
        } else {
            HStack {
                Image(systemName: iconName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.caption)
                Spacer()
                Text(source.verifiedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func symbol(for type: InformationSource.SourceType) -> String {
        switch type {
        case .wikivoyage, .wikipedia: return "book"
        case .reddit:                 return "bubble.left.and.bubble.right"
        case .blog:                   return "doc.text"
        case .youtube:                return "play.rectangle"
        case .user:                   return "person.crop.circle"
        case .fieldVisit:             return "figure.walk"
        }
    }

    private var nearbySection: some View {
        sectionContainer(title: NSLocalizedString("section.nearby", comment: "")) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.nearbyExperiences) { exp in
                        NearbyCard(
                            exp: exp,
                            onSelectExperience: onSelectExperience,
                            reduceMotion: reduceMotion
                        )
                    }
                }
            }
        }
    }

    // MARK: - Nearby card

    private struct NearbyCard: View {
        let exp: Experience
        let onSelectExperience: ((Experience) -> Void)?
        let reduceMotion: Bool

        private var baseCard: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: exp.category.symbol)
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Circle().fill(exp.category.color))
                    Spacer()
                    SoloScoreBadge(score: exp.soloScore, style: .compact)
                }
                Text(exp.title)
                    .font(.caption.bold())
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .frame(width: 180, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.08))
            )
        }

        var body: some View {
            if let onSelect = onSelectExperience {
                let scoreStr = String(format: "%.1f", exp.soloScore.overall)
                let a11yLabel = String(
                    format: NSLocalizedString("detail.nearby.open.a11y", comment: "Nearby card accessibility label: title and Solo Score"),
                    exp.title, scoreStr
                )
                let a11yHint = NSLocalizedString("detail.nearby.open.hint", comment: "Opens experience detail")
                Button {
                    Haptics.impact(.light)
                    onSelect(exp)
                } label: {
                    baseCard
                }
                .buttonStyle(NearbyCardButtonStyle(reduceMotion: reduceMotion))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(Text(a11yLabel))
                .accessibilityHint(Text(a11yHint))
            } else {
                baseCard
            }
        }
    }

    private struct NearbyCardButtonStyle: ButtonStyle {
        let reduceMotion: Bool
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect((!reduceMotion && configuration.isPressed) ? 0.96 : 1.0)
                .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }

    // MARK: - Itinerary toast

    @MainActor
    private func showItineraryToast(_ itinerary: Itinerary) {
        toastDismissTask?.cancel()
        withAnimation { addedItineraryToast = itinerary }
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { addedItineraryToast = nil }
        }
    }

    private func itineraryAddedToast(_ itin: Itinerary) -> some View {
        HStack(spacing: 10) {
            Text(String(
                format: NSLocalizedString("itinerary.toast.added", comment: "Success toast after adding to itinerary"),
                itin.title
            ))
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .lineLimit(1)

            Button {
                toastDismissTask?.cancel()
                withAnimation { addedItineraryToast = nil }
                itineraryToNavigate = itin
            } label: {
                Text(NSLocalizedString("itinerary.toast.viewAction", comment: "View itinerary button in success toast"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color(.systemBackground)).shadow(radius: 6))
    }

    // MARK: - Action bar

    private var actionBar: some View {
        ZStack(alignment: .center) {
        HStack(spacing: 12) {
            Button {
                let willFavorite = !viewModel.isFavorited
                withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) {
                    viewModel.toggleFavorite()
                }
                if willFavorite {
                    heartBurstTrigger += 1
                    Haptics.notify(.success)
                } else {
                    Haptics.impact(.light)
                }
            } label: {
                Image(systemName: viewModel.isFavorited ? "heart.fill" : "heart")
                    .font(.title3)
                    .foregroundStyle(viewModel.isFavorited ? .red : .primary)
                    .symbolEffect(.bounce, value: viewModel.isFavorited)
                    .scaleEffect(viewModel.isFavorited ? 1.12 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.45), value: viewModel.isFavorited)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(.regularMaterial))
                    .overlay {
                        HeartBurstView(trigger: heartBurstTrigger)
                    }
            }
            .accessibilityLabel(Text(viewModel.isFavorited
                ? NSLocalizedString("action.unfavorite", comment: "Remove favorite")
                : NSLocalizedString("action.favorite", comment: "Add favorite")))

            if viewModel.experience.location.clCoordinate != nil {
                Button {
                    Haptics.impact(.light)
                    isShowingNavPicker = true
                } label: {
                    // `arrow.triangle.turn.up.right.diagonal` is NOT a real SF
                    // Symbol — it rendered blank (empty circle). Use the same
                    // turn-arrow as LocationCard's Navigate button for both
                    // correctness and visual consistency.
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .frame(width: 50, height: 50)
                        .background(Circle().fill(.regularMaterial))
                }
                .accessibilityLabel(Text(NSLocalizedString("action.directions", comment: "Open directions picker")))
            }

            Button {
                Haptics.impact(.light)
                isShowingAddToItinerary = true
            } label: {
                Image(systemName: "calendar.badge.plus")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(.regularMaterial))
            }
            .accessibilityLabel(Text(NSLocalizedString("action.addToItinerary", comment: "Add to itinerary")))

            Button {
                let wasCompleted = viewModel.isCompleted
                viewModel.toggleComplete()
                if !wasCompleted {
                    let count = viewModel.completedCount
                    celebrationMilestone = (count == 1 || count % 5 == 0) ? count : nil
                    celebrationTrigger += 1
                    onMarkDone?(viewModel.experience)
                } else {
                    Haptics.impact(.light)
                }
            } label: {
                HStack {
                    Image(systemName: viewModel.isCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                        .symbolEffect(.bounce, value: viewModel.isCompleted)
                    Text(viewModel.isCompleted
                        ? NSLocalizedString("action.completed", comment: "")
                        : NSLocalizedString("action.markDone", comment: ""))
                        .font(.subheadline.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 25)
                        .fill(viewModel.isCompleted ? Color.green : Color.primary)
                )
                .foregroundStyle(.white)
            }
            .accessibilityLabel(Text(viewModel.isCompleted
                ? NSLocalizedString("action.completed", comment: "Marked as completed")
                : NSLocalizedString("action.markDone", comment: "Mark as done")))
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(
            // Opaque bar via safeAreaInset: the bar reserves its own space in the
            // ScrollView (no manual bottom padding), so content never scrolls
            // behind it. A solid material + hairline top divider keeps it legible
            // over any content; it extends into the home-indicator safe area.
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(.regularMaterial)
                    .ignoresSafeArea(edges: .bottom)
                Divider().opacity(0.5)
            }
        )
        .confirmationDialog(
            NSLocalizedString("location.navigate", comment: ""),
            isPresented: $isShowingNavPicker,
            titleVisibility: .visible
        ) {
            if let coord = viewModel.experience.location.clCoordinate {
                let name = viewModel.experience.location.placeNameLocal
                    ?? viewModel.experience.location.placeNameRomanized
                    ?? viewModel.experience.title
                ForEach(NavigationLauncher.availableApps()) { app in
                    Button(app.displayName) {
                        NavigationLauncher.open(app: app, coordinate: coord, name: name)
                    }
                }
            }
            Button(NSLocalizedString("action.cancel", comment: "Cancel picker"), role: .cancel) { }
        }

        CompletionCelebrationView(trigger: celebrationTrigger, milestone: celebrationMilestone)
            .frame(maxWidth: .infinity)
            .offset(y: -28)
        }
    }

    // MARK: - Helpers

    private func sectionContainer<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .minimumScaleFactor(0.85)
                .lineLimit(nil)
            content()
        }
    }

    private func format(window: TimeWindow) -> String {
        String(format: "%02d:00 – %02d:00", window.startHour, window.endHour)
    }
}

// MARK: - Compass Direction View

private struct CompassDirectionView: View {
    let relBearing: Double
    let distanceString: String
    let cardinalDirection: String
    let reduceMotion: Bool

    private let ringSize: CGFloat = 120

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // Cardinal tick marks and labels
                ForEach(["N", "E", "S", "W"], id: \.self) { label in
                    let angle: Double = label == "N" ? 0 : label == "E" ? 90 : label == "S" ? 180 : 270
                    VStack(spacing: 2) {
                        Text(label)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .frame(width: ringSize, height: ringSize)
                    .rotationEffect(.degrees(angle))
                }

                // Outer ring
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1.5)
                    .frame(width: ringSize, height: ringSize)

                // Arrow pointing toward the experience
                Image(systemName: "location.north.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .rotationEffect(.degrees(relBearing))
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.25),
                        value: relBearing
                    )
                    .accessibilityHidden(true)

                // Distance label inside the ring
                VStack(spacing: 2) {
                    Spacer()
                    Text(distanceString)
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(width: ringSize * 0.6, height: ringSize * 0.6)
            }

            // "Pointing toward" + cardinal direction label below the ring
            HStack(spacing: 4) {
                Text(NSLocalizedString("compass.pointing.title", comment: "Compass pointing toward label"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(cardinalDirection)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview("CompassDirectionView") {
    CompassDirectionView(
        relBearing: 45,
        distanceString: "1.2 km",
        cardinalDirection: "northeast",
        reduceMotion: false
    )
    .padding()
}

// MARK: - Best Time Window Row

private struct BestTimeWindowRow: View {
    let window: TimeWindow
    let isActiveNow: Bool
    let categoryColor: Color
    let formatWindow: (TimeWindow) -> String
    let reduceMotion: Bool

    @State private var nowDotPulse = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .foregroundStyle(isActiveNow ? categoryColor : .secondary)
            Text(formatWindow(window))
                .font(isActiveNow ? .subheadline.weight(.semibold) : .subheadline)
            if let note = window.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if isActiveNow {
                Spacer()
                Circle()
                    .fill(categoryColor)
                    .frame(width: 6, height: 6)
                    .scaleEffect(nowDotPulse ? 1.6 : 1.0)
                    .opacity(nowDotPulse ? 0.4 : 1.0)
            }
        }
        .padding(.horizontal, isActiveNow ? 10 : 0)
        .padding(.vertical, isActiveNow ? 6 : 0)
        .background(
            isActiveNow
                ? AnyView(RoundedRectangle(cornerRadius: 8).fill(categoryColor.opacity(0.12)))
                : AnyView(Color.clear)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(isActiveNow
            ? "\(formatWindow(window)), \(NSLocalizedString("bestTimes.window.active.a11y", comment: "Happening now accessibility suffix"))"
            : formatWindow(window)
        ))
        .onAppear { startPulseIfNeeded() }
        .onChange(of: isActiveNow) { _, active in
            if active {
                startPulseIfNeeded()
            } else {
                withAnimation(nil) { nowDotPulse = false }
            }
        }
    }

    private func startPulseIfNeeded() {
        guard isActiveNow && !reduceMotion else { return }
        nowDotPulse = false
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            nowDotPulse = true
        }
    }
}

// MARK: - Best Times Timeline

private struct BestTimesTimeline: View {
    let experience: Experience

    @State private var animateFill = false
    @State private var nowPulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let trackHeight: CGFloat = 10
    private let nowMarkerWidth: CGFloat = 2
    private let tickHours = [0, 6, 12, 18]

    private func nowFraction(for date: Date) -> CGFloat {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (CGFloat(comps.hour ?? 0) + CGFloat(comps.minute ?? 0) / 60) / 24
    }

    private static let nowTickFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private func a11yLabel(for date: Date) -> String {
        let windowLabels = experience.bestTimes.map { w in
            String(format: "%02d:00 – %02d:00", w.startHour, w.endHour)
        }.joined(separator: ", ")
        let nowStatus = experience.isBestNow(at: date)
            ? NSLocalizedString("timeline.now.good", comment: "")
            : NSLocalizedString("timeline.now.off", comment: "")
        let timeStr = Self.nowTickFormatter.string(from: date)
        return String(
            format: NSLocalizedString("timeline.a11y", comment: ""),
            windowLabels,
            "\(nowStatus) \(timeStr)"
        )
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let liveDate = context.date
            GeometryReader { geo in
                let trackWidth = geo.size.width
                let fraction = nowFraction(for: liveDate)
                let nowX = fraction * trackWidth
                let isBest = experience.isBestNow(at: liveDate)
                ZStack(alignment: .topLeading) {
                    // Base track
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: trackHeight)

                    // Window segments
                    ForEach(segments(trackWidth: trackWidth), id: \.id) { seg in
                        Capsule()
                            .fill(experience.category.color.opacity(0.85))
                            .frame(width: seg.width, height: trackHeight)
                            .offset(x: seg.x)
                            .scaleEffect(x: animateFill ? 1 : 0, anchor: .leading)
                    }

                    // 'Now' marker
                    ZStack {
                        if isBest && !reduceMotion {
                            Circle()
                                .stroke(Color.yellow, lineWidth: 1.5)
                                .frame(width: 6, height: 6)
                                .scaleEffect(nowPulse ? 2.4 : 1)
                                .opacity(nowPulse ? 0 : 0.7)
                        }
                        VStack(spacing: 0) {
                            Circle()
                                .fill(isBest ? Color.yellow : Color.accentColor)
                                .frame(width: 6, height: 6)
                            Rectangle()
                                .fill(isBest ? Color.yellow : Color.accentColor)
                                .frame(width: nowMarkerWidth, height: trackHeight - 2)
                        }
                    }
                    .offset(x: nowX - 3, y: 0)
                }
                .frame(height: trackHeight)
                // 'Now' tick label + fixed hour labels below the track
                .overlay(alignment: .bottom) {
                    ZStack(alignment: .topLeading) {
                        // Fixed 0 / 6 / 12 / 18 labels
                        ForEach(tickHours, id: \.self) { hour in
                            let x = CGFloat(hour) / 24.0 * trackWidth
                            Text("\(hour)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .offset(x: hour == 0 ? x : x - 8)
                        }
                        // 'now HH:mm' label — clamped to track bounds, hidden
                        // when it would land within 16pt of a fixed tick label.
                        let tickPositions: [CGFloat] = tickHours.map { CGFloat($0) / 24.0 * trackWidth }
                        let rawLabelX = nowX - 14
                        let clampedX = min(max(rawLabelX, 0), trackWidth - 28)
                        let tooClose = tickPositions.contains { abs($0 - nowX) < 20 }
                        if !tooClose {
                            let nowLabel = NSLocalizedString("timeline.now.tick", comment: "Now tick label under the timeline marker")
                            let timeStr = Self.nowTickFormatter.string(from: liveDate)
                            Text("\(nowLabel) \(timeStr)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(isBest ? Color.yellow : Color.accentColor)
                                .offset(x: clampedX)
                        }
                    }
                    .frame(height: 14)
                    .offset(y: 18)
                }
            }
            .frame(height: trackHeight + 18 + 14)
            .onChange(of: experience.isBestNow(at: liveDate)) { _, isBest in
                guard !reduceMotion else { return }
                if isBest {
                    nowPulse = false
                    withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                        nowPulse = true
                    }
                } else {
                    withAnimation(nil) {
                        nowPulse = false
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(a11yLabel(for: liveDate)))
        }
        .onAppear {
            if reduceMotion {
                animateFill = true
            } else {
                withAnimation(.easeOut(duration: 0.5)) {
                    animateFill = true
                }
                if experience.isBestNow() {
                    withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                        nowPulse = true
                    }
                }
            }
        }
    }

    private struct Segment: Identifiable {
        let id: String
        let x: CGFloat
        let width: CGFloat
    }

    private func segments(trackWidth: CGFloat) -> [Segment] {
        var result: [Segment] = []
        for (i, window) in experience.bestTimes.enumerated() {
            let start = window.startHour
            let end = window.endHour
            if start < end {
                // Normal window (no midnight wrap)
                let x = CGFloat(start) / 24.0 * trackWidth
                let w = CGFloat(end - start) / 24.0 * trackWidth
                result.append(Segment(id: "\(i)-a", x: x, width: max(w, 4)))
            } else {
                // Wrap-around: split into [start→24] + [0→end]
                let xA = CGFloat(start) / 24.0 * trackWidth
                let wA = CGFloat(24 - start) / 24.0 * trackWidth
                result.append(Segment(id: "\(i)-a", x: xA, width: max(wA, 4)))
                if end > 0 {
                    let wB = CGFloat(end) / 24.0 * trackWidth
                    result.append(Segment(id: "\(i)-b", x: 0, width: max(wB, 4)))
                }
            }
        }
        return result
    }
}

#Preview {
    if let exp = ExperienceService.hardcodedSeed.first {
        let vm = ExperienceDetailViewModel(
            experience: exp,
            experienceService: ExperienceService(),
            aiService: AIService(),
            preferences: UserPreferences()
        )
        NavigationStack {
            ExperienceDetailView(viewModel: vm) {}
        }
        .environment(LocationService())
    } else {
        Text("No seed data")
    }
}

#Preview("Dynamic Type XXL") {
    if let exp = ExperienceService.hardcodedSeed.first {
        let vm = ExperienceDetailViewModel(
            experience: exp,
            experienceService: ExperienceService(),
            aiService: AIService(),
            preferences: UserPreferences()
        )
        NavigationStack {
            ExperienceDetailView(viewModel: vm) {}
        }
        .environment(LocationService())
        .environment(\.dynamicTypeSize, .accessibility3)
    } else {
        Text("No seed data")
    }
}

private extension RealInconvenience.Severity {
    var tintColor: Color {
        switch self {
        case .high:   return Color(.systemRed)
        case .medium: return Color(.systemOrange)
        case .low:    return Color(.systemGray)
        }
    }
}

#Preview("Severity tints") {
    if let base = ExperienceService.hardcodedSeed.first {
        let now = Date()
        let exp = Experience(
            id: "preview_severity",
            title: base.title,
            oneLiner: base.oneLiner,
            whyItMatters: base.whyItMatters,
            category: base.category,
            location: base.location,
            bestTimes: base.bestTimes,
            durationMinutes: base.durationMinutes,
            howTo: base.howTo,
            realInconveniences: [
                RealInconvenience(category: .safety, text: "Pre-dawn route is unlit. Use a torch."),
                RealInconvenience(category: .scam, text: "Tuk-tuks near the gate charge 3× the metered rate."),
                RealInconvenience(category: .logistics, text: "Cash only at the entrance booth."),
            ],
            soloScore: base.soloScore,
            sources: base.sources,
            confidence: base.confidence,
            nearbyExperienceIds: base.nearbyExperienceIds,
            stats: base.stats,
            status: base.status,
            createdAt: now,
            updatedAt: now
        )
        let vm = ExperienceDetailViewModel(
            experience: exp,
            experienceService: ExperienceService(),
            aiService: AIService(),
            preferences: UserPreferences()
        )
        NavigationStack {
            ExperienceDetailView(viewModel: vm) {}
        }
        .environment(LocationService())
    } else {
        Text("No seed data")
    }
}
