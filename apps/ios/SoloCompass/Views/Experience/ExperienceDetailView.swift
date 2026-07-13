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
    @State internal var viewModel: ExperienceDetailViewModel
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
    /// When non-nil (and the place has a coordinate), the ··· menu offers a
    /// deep cross-compile entry — parity with the floating preview card's own
    /// recompile menu. The parent owns the work (MapViewModel.recompileExperience)
    /// and reports progress back via `isRecompiling`. nil → menu omits the item,
    /// so previews/tests with no Map context are unaffected.
    var onRecompile: (() -> Void)?
    /// Drives the menu's progress spinner while the parent's recompile runs.
    var isRecompiling: Bool

    @Environment(\.themeService) private var themeService
    @Environment(LocationService.self) private var locationService
    /// Traveler co-build store. Optional so previews/tests that don't inject it
    /// still render — the notes/corrections sections simply hide when nil.
    @Environment(TravelerNoteStore.self) var travelerNoteStore: TravelerNoteStore?
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

    /// P2.4 #240: presented by a long-press on the hero — lets the user
    /// bury a time capsule anchored to this experience. Consumed by
    /// `CapsuleComposeView` and persisted through `CapsuleStore.shared`.
    @State private var isShowingCapsuleCompose: Bool = false
    /// Toast text after a successful bury.
    @State private var capsuleBuryToast: String? = nil

    // MARK: - Traveler co-build UI state
    /// Loaded notes/corrections for this place (refreshed from the store on
    /// appear + after every mutation).
    @State internal var notes: [TravelerNote] = []
    @State internal var corrections: [PlaceCorrection] = []
    /// Notes the current user has tapped "我也确认" on this session.
    @State internal var confirmedNoteIds: Set<String> = []
    @State internal var notesFilter: NoteFilter = .all
    @State internal var notesExpanded = false
    /// Picked mood chips + free-text in the quick-add row.
    @State internal var pickedMoods: Set<String> = []
    @State internal var noteDraft: String = ""
    /// Whether the current user has contributed anything this session — bumps
    /// the hero "L{n} · {n} 信号" line and shows a one-shot toast.
    @State internal var userContributed = false
    @State internal var levelToast: String? = nil
    @State internal var levelToastTask: Task<Void, Never>? = nil
    @State private var barsAppeared = false

    /// Notes feed filter segments.
    enum NoteFilter: String, CaseIterable { case all, experience, correction }

    public init(
        viewModel: ExperienceDetailViewModel,
        onClose: @escaping () -> Void = {},
        onMarkDone: ((_ experience: Experience) -> Void)? = nil,
        onAskSolo: ((_ experience: Experience) -> Void)? = nil,
        onSelectExperience: ((_ experience: Experience) -> Void)? = nil,
        onRecompile: (() -> Void)? = nil,
        isRecompiling: Bool = false
    ) {
        self.viewModel = viewModel
        self.onClose = onClose
        self.onMarkDone = onMarkDone
        self.onAskSolo = onAskSolo
        self.onSelectExperience = onSelectExperience
        self.onRecompile = onRecompile
        self.isRecompiling = isRecompiling
    }

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(BestNowClock.self) private var bestNowClock

    @State private var scrollProxy: ScrollViewProxy? = nil

    public var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                heroImageBanner
                    // P2.4 #240: long-press hero → open time capsule
                    // compose sheet. Short press keeps standard scroll
                    // behaviour so the primary flow is untouched.
                    .onLongPressGesture(minimumDuration: 0.55) {
                        isShowingCapsuleCompose = true
                    }
                // Hero block — provenance tag, category disc + trust chip, title,
                // place names. Quiet mono meta baseline sits just below it.
                heroSection
                metaBaselineRow
                if !viewModel.experience.highlights.isEmpty {
                    highlightsSection
                }
                compassDirectionView
                // ★ Co-build: pending corrections float above the prose.
                correctionsSection
                whyItMattersSection
                if !viewModel.experience.howTo.isEmpty {
                    howToSection
                }
                if !viewModel.experience.realInconveniences.isEmpty {
                    inconveniencesSection
                }
                // ★ Co-build: traveler notes feed + quick-add, between the honest
                // caveats and the best-time ribbon (matches the design order).
                travelerNotesSection
                let hasOpeningHours = viewModel.experience.location.openingHours
                    .map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
                if !viewModel.experience.bestTimes.isEmpty || hasOpeningHours {
                    bestTimesSection
                }
                // Skip the Solo Score for un-enriched OSM entries. Their score
                // is a flat 7.0 placeholder from skeletonExperience, not a real
                // estimate — showing it as "Solo Score (AI estimate)" misleads.
                if !(viewModel.experience.isFromOpenStreetMap && !viewModel.experience.isAIEnriched) {
                    soloScoreSection
                }
                locationStripSection
                aiInsightSection
                openingHoursLineSection
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
        .scrollContentBackground(.hidden)
        .background(CT.bgWarm.ignoresSafeArea())
        .onAppear { scrollProxy = proxy }
        } // ScrollViewReader
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
                    // Parity with the floating card: deep cross-compile lives at
                    // the top of the ··· menu. Shown only when the parent wired a
                    // recompile handler AND the place has a coordinate to enrich
                    // around — same guard the card uses (ExperienceCardView).
                    if let onRecompile, viewModel.experience.coordinate != nil {
                        Button {
                            Haptics.impact(.light)
                            onRecompile()
                        } label: {
                            Label(
                                NSLocalizedString("recompile.action", comment: "Deep cross-compile menu item"),
                                systemImage: "sparkle.magnifyingglass"
                            )
                        }
                        Divider()
                    }
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
                    // While a recompile runs, swap the ··· glyph for a spinner so
                    // the in-flight cross-compile is visible without a toast.
                    if isRecompiling {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                    } else {
                        Image(systemName: "ellipsis.circle")
                    }
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
        // P2.4 #240 / #241: bury a time capsule anchored to this
        // experience. Persistence via CapsuleStore.shared; on success
        // we surface a subtle toast so the user knows the note was
        // safely stashed.
        .sheet(isPresented: $isShowingCapsuleCompose) {
            CapsuleComposeView(
                experienceId: viewModel.experience.id,
                experienceTitle: viewModel.experience.title,
                onBury: { payload in
                    let ok = CapsuleStore.shared.bury(
                        experienceId: viewModel.experience.id,
                        contentType: payload.contentType,
                        contentBlob: payload.contentBlob,
                        context: nil,
                        monthsFromNow: payload.monthsFromNow
                    ) != nil
                    if ok {
                        AnalyticsService.shared.track(
                            .capsuleBuried,
                            properties: ["months": .int(payload.monthsFromNow)]
                        )
                        capsuleBuryToast = "Buried. It'll surface in \(payload.monthsFromNow) months."
                    }
                    isShowingCapsuleCompose = false
                },
                onCancel: { isShowingCapsuleCompose = false }
            )
        }
        .alert(
            capsuleBuryToast ?? "",
            isPresented: Binding(
                get: { capsuleBuryToast != nil },
                set: { if !$0 { capsuleBuryToast = nil } }
            ),
            actions: {
                Button(NSLocalizedString("common.ok", comment: "OK")) { capsuleBuryToast = nil }
            }
        )
        .overlay(alignment: .bottom) {
            if let itin = addedItineraryToast {
                itineraryAddedToast(itin)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 96)
            }
        }
        // Data-level toast for traveler contributions ("信号 +1 · 数据等级 L2").
        .overlay(alignment: .top) {
            if let toast = levelToast {
                levelToastView(toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .task {
            await viewModel.loadAIExplanation()
            await viewModel.loadRemoteSoloScore()
        }
        .onAppear { reloadCoBuild() }
        .onReceive(NotificationCenter.default.publisher(for: TravelerNoteStore.didChange)) { _ in
            reloadCoBuild()
        }
    }

    /// Small floating toast announcing a data-level bump after a contribution.
    private func levelToastView(_ text: String) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles").font(.system(size: 10))
                Text(text.contains("L2") ? "L1 → L2" : NSLocalizedString("notes.signal.plus", comment: "+1 signal"))
                    .ctMono(11, .semibold)
            }
            .foregroundStyle(CT.accent)
            Text(text)
                .ctBody(12.5, .medium)
                .foregroundStyle(CT.fgPrimary)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Capsule().fill(CT.surfaceWhite).shadow(color: .black.opacity(0.12), radius: 8, y: 3))
        .overlay(Capsule().strokeBorder(CT.accentBorder, lineWidth: 0.5))
    }

    // MARK: - Hero

    /// Full-bleed hero photo at the top of the detail sheet, shown only when a
    /// real place photo resolved (OSM image / Wikimedia). Breaks out of the 20pt
    /// horizontal padding to sit edge-to-edge. Absent → nothing renders and the
    /// sheet starts at the hero text exactly as before.
    @ViewBuilder
    private var heroImageBanner: some View {
        if let urlString = viewModel.experience.location.photoUrls?.first,
           let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty:
                    ZStack {
                        Rectangle().fill(viewModel.experience.category.color.opacity(0.12))
                        ProgressView()
                    }
                case .failure:
                    EmptyView()
                @unknown default:
                    EmptyView()
                }
            }
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            .clipped()
            // Break out of the VStack's 20pt horizontal padding for a full-bleed
            // banner; the negative top padding closes the gap above it.
            .padding(.horizontal, -20)
            .padding(.top, -16)
            .accessibilityHidden(true)
        }
    }

    /// Category-specific scannable facts (Wi-Fi, signature, best light…) shown
    /// as a pill row near the top, so the detail that matters for *this* kind of
    /// place reads right after the hero. Only renders when highlights exist
    /// (guarded at the call site).
    private var highlightsSection: some View {
        FlowLayout(spacing: 8) {
            ForEach(viewModel.experience.highlights) { highlight in
                HStack(spacing: 5) {
                    Image(systemName: highlight.kind.symbol)
                        .font(.caption)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(highlight.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(highlight.value)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color(.tertiarySystemFill)))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(highlight.label): \(highlight.value)")
            }
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            // Provenance chip — TrustBadge unifies the five source buckets
            // (verified / amap / osm / user / curated). Replaced the
            // isFromOpenStreetMap+isAIEnriched string-match dual-badge with a
            // structured chip so AutoNavi is visibly distinct from OSM at a
            // glance (slice A of the Explore-Mode redesign).
            TrustBadge(level: viewModel.experience.trustBadgeLevel, size: .full)

            // Category row — colored disc + uppercase label + level/signals +
            // trust chip (verified / observing / questioned).
            HStack(spacing: 7) {
                Image(systemName: viewModel.experience.category.symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(viewModel.experience.category.color))
                Text(viewModel.experience.category.localizedTitle.uppercased())
                    .ctDisplay(11.5, .bold)
                    .tracking(1.4)
                    .foregroundStyle(CT.fgMuted)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                Text(levelSignalText)
                    .ctMono(10.5, userContributed ? .semibold : .regular)
                    .tracking(0.5)
                    .foregroundStyle(userContributed ? CT.accent : CT.fgMuted)
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                trustChip
            }
            .fixedSize(horizontal: false, vertical: true)

            Text(viewModel.experience.title)
                .ctDisplay(27, .bold)
                .foregroundStyle(CT.fgPrimary)
                .lineLimit(nil)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 1)
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
                .ctBody(15)
                .foregroundStyle(CT.fgMuted)
                .fixedSize(horizontal: false, vertical: true)

            // Place names — local + romanized, romanized in mono.
            if let local = viewModel.experience.location.placeNameLocal, !local.isEmpty {
                let romanized = viewModel.experience.location.placeNameRomanized
                if let romanized, !romanized.isEmpty {
                    Text(romanized)
                        .ctMono(12.5)
                        .foregroundStyle(CT.fgMuted)
                    Text(local)
                        .ctBody(13)
                        .foregroundStyle(CT.fgMuted)
                } else {
                    Text(local)
                        .ctBody(13)
                        .foregroundStyle(CT.fgMuted)
                }
            }
        }
    }

    /// Hero "L{n} · {n} 信号" mono line. Base level 1, +1 once the user
    /// contributes a note/confirmation this session (matches the design's data-
    /// level progression).
    private var levelSignalText: String {
        let level = 1 + (userContributed ? 1 : 0)
        let signals = notes.count + (userContributed ? 1 : 0)
        if signals == 0 {
            return NSLocalizedString("notes.signals.aiEstimate", comment: "AI estimate label for cold-start")
        }
        return "L\(level) · \(signals) " + NSLocalizedString("notes.signals", comment: "signals unit")
    }

    /// Trust chip mapped from `confidence.health` to the design's three states:
    /// verified (green) / observing (grey) / questioned (amber).
    @ViewBuilder
    private var trustChip: some View {
        let health = viewModel.experience.confidence.health
        let signals = viewModel.experience.confidence.signals.totalCount
        let (labelKey, symbol, fg, bg): (String, String, Color, Color) = {
            switch health {
            case .healthy:
                return ("trust.verified", "checkmark.seal.fill", CT.successText, CT.successSoft)
            case .questioned, .mayBeGone:
                return ("trust.questioned", "exclamationmark.circle.fill", CT.warningTextStrong, CT.warningSoft)
            case .fading:
                return ("trust.observing", "eye", CT.fgMuted, CT.surfaceSunken)
            }
        }()
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9))
            Text(NSLocalizedString(labelKey, comment: "Trust state label"))
                .ctMono(10)
            if signals > 0 {
                Text("· \(signals)")
                    .ctMono(10)
            }
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 8)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(bg))
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(NSLocalizedString(labelKey, comment: "Trust state label")))
    }

    // MARK: - Quiet meta baseline

    /// A single mono baseline row under the hero: walk time · distance ↗ · Solo
    /// X.X · 此刻最佳. Replaces the scattered distance pill + confidence badge
    /// (styles.css .sc-meta-row). Distance items appear only with a GPS fix.
    private var metaBaselineRow: some View {
        let now = bestNowClock.tick
        let isNow = viewModel.experience.isBestNow(at: now)
        return HStack(spacing: 0) {
            if locationService.currentLocation != nil,
               let coord = viewModel.experience.location.clCoordinate {
                let meters = locationService.distance(to: coord)
                if meters < .greatestFiniteMagnitude {
                    metaItem {
                        Image(systemName: "figure.walk").font(.system(size: 11, weight: .semibold))
                        Text(Self.formatWalkTime(meters))
                    }
                    metaSeparator
                    metaItem {
                        if let bearing = relativeBearing(to: coord) {
                            Image(systemName: "location.north.fill")
                                .font(.system(size: 10))
                                .rotationEffect(.degrees(bearing))
                        }
                        Text(Self.formatDistance(meters))
                    }
                    metaSeparator
                }
            }
            HStack(spacing: 5) {
                Text("Solo \(String(format: "%.1f", viewModel.displaySoloScore.overall))")
            }
            .foregroundStyle(CT.successText)
            .fontWeight(.semibold)
            if isNow {
                metaSeparator
                HStack(spacing: 4) {
                    Image(systemName: "sparkles").font(.system(size: 10))
                    Text(NSLocalizedString("meta.bestNow", comment: "Good now meta item"))
                }
                .foregroundStyle(CT.sunGoldDeep)
                .fontWeight(.semibold)
            }
            Spacer(minLength: 0)
        }
        .ctMono(12)
        .foregroundStyle(CT.fgMuted)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) {
            Rectangle().fill(CT.borderSubtle).frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    private func metaItem<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 5) { content() }
    }

    private var metaSeparator: some View {
        Rectangle()
            .fill(CT.borderDefault)
            .frame(width: 1, height: 11)
            .padding(.horizontal, 11)
    }

    /// Walk time estimate from distance (≈80 m/min), e.g. "步行 7'".
    private static func formatWalkTime(_ meters: Double) -> String {
        let minutes = max(1, Int((meters / 80).rounded()))
        return String(format: NSLocalizedString("meta.walkMinutes", comment: "Walk N minutes"), minutes)
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

    // The "Ask Solo" CTA now lives in the bottom dock (see `actionBar`), not as
    // an inline section — matching the design's last iteration. The routing
    // helper `askSoloAction(canAskSolo:)` above stays (used by the dock + tests).

    // MARK: - Sections

    @ViewBuilder
    private var whyItMattersSection: some View {
        let content = viewModel.experience.whyItMatters.trimmingCharacters(in: .whitespacesAndNewlines)
        let isLoading = viewModel.isLoadingWhyItMatters
        let tags = viewModel.experience.userTags ?? []
        if isLoading || !content.isEmpty {
            sectionContainer(title: NSLocalizedString("section.whyItMatters", comment: "")) {
                if isLoading {
                    SkeletonView(lineCount: 3)
                        .id("whyItMatters-skeleton")
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                } else {
                    Text(content)
                        .ctBody(14.5)
                        .foregroundStyle(CT.fgPrimary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .id("whyItMatters-content")
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                    if !tags.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                Text(tag)
                                    .ctBody(12)
                                    .foregroundStyle(CT.accent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(CT.accentSoft))
                                    .overlay(Capsule().strokeBorder(CT.accentBorder, lineWidth: 1))
                            }
                        }
                        .padding(.top, 2)
                    }
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
                        ProgressView().tint(CT.accent)
                        Text(NSLocalizedString("ai.explanation.loading", comment: "AI insight loading indicator"))
                            .ctBody(14)
                            .foregroundStyle(CT.fgMuted)
                    }
                    .id("aiInsight-skeleton")
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                } else if let explanation = viewModel.aiExplanation {
                    Text(explanation)
                        .ctBody(14.5)
                        .foregroundStyle(CT.fgPrimary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .id("aiInsight-content")
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: isLoading)
        }
    }

    // MARK: - Location strip + opening hours line (design-aligned)

    /// Compact location strip: rounded amber pin + name/coord + amber Navigate
    /// pill (styles.css .sc-loc-strip). Replaces the full LocationCard map card.
    @ViewBuilder
    private var locationStripSection: some View {
        if let coord = viewModel.experience.location.clCoordinate {
            let name = viewModel.experience.location.placeNameLocal
                ?? viewModel.experience.location.placeNameRomanized
                ?? viewModel.experience.title
            sectionContainer(title: NSLocalizedString("section.location", comment: "Location section title")) {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 16))
                        .foregroundStyle(CT.accent)
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(CT.accentSoft))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .ctBody(13, .medium)
                            .foregroundStyle(CT.fgPrimary)
                            .lineLimit(1)
                        Text(String(format: "%.4f, %.4f", coord.latitude, coord.longitude))
                            .ctMono(10.5)
                            .foregroundStyle(CT.fgMuted)
                    }
                    Spacer(minLength: 0)
                    Button {
                        Haptics.impact(.light)
                        if let only = NavigationLauncher.soleApp() {
                            NavigationLauncher.open(app: only, coordinate: coord, name: name)
                        } else {
                            isShowingNavPicker = true
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text(NSLocalizedString("location.navigate", comment: "Navigate"))
                                .ctBody(12.5, .semibold)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(CT.accent))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(NSLocalizedString("action.directions", comment: "")))
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(CT.surfaceWhite))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(CT.borderSubtle, lineWidth: 0.5))
            }
        }
    }

    /// Single mono opening-hours line: clock · hours · green "open now" dot
    /// (styles.css .sc-hours-line).
    @ViewBuilder
    private var openingHoursLineSection: some View {
        if let raw = viewModel.experience.location.openingHours {
            let hours = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !hours.isEmpty {
                sectionContainer(title: NSLocalizedString("location.openingHours", comment: "Posted hours label")) {
                    HStack(spacing: 9) {
                        Image(systemName: "clock")
                            .font(.system(size: 13))
                            .foregroundStyle(CT.fgMuted)
                        Text(hours)
                            .ctMono(12.5)
                            .foregroundStyle(CT.fgMuted)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text(String(
                        format: NSLocalizedString("location.openingHours.a11y", comment: "Posted hours accessibility label"),
                        hours
                    )))
                }
            }
        }
    }

    private var bestTimeStatusPill: some View {
        let now = bestNowClock.tick
        let isNow = viewModel.experience.isBestNow(at: now)
        let hint = viewModel.experience.bestTimeHint(at: now)
        let minutesLeft = viewModel.experience.minutesLeftInBestWindow(at: now)
        let closingSoon = isNow && (minutesLeft ?? .max) <= 45
        let label: String
        let symbol: String
        let background: Color
        let tint: Color
        if isNow {
            if closingSoon, let mins = minutesLeft {
                label = String(
                    format: NSLocalizedString("bestTimes.now.pill.closing", comment: "Closing soon pill in best times detail"),
                    mins
                )
                symbol = "clock.badge.exclamationmark"
                background = CT.warningSoft
                tint = CT.warningTextStrong
            } else if let minutesLeft {
                label = String(
                    format: NSLocalizedString("bestTimes.now.pill.left", comment: "Good now with minutes left pill"),
                    minutesLeft
                )
                symbol = "clock.badge.checkmark"
                background = CT.successSoft
                tint = CT.successText
            } else {
                label = NSLocalizedString("bestTimes.now.pill", comment: "Good time now pill")
                symbol = "clock.badge.checkmark"
                background = CT.successSoft
                tint = CT.successText
            }
        } else if let hint {
            label = String(format: NSLocalizedString("bestTimes.next.pill", comment: "Better at time pill"), hint)
            symbol = "clock"
            background = Color(.tertiarySystemFill)
            tint = Color.secondary
        } else {
            return AnyView(EmptyView())
        }
        let a11yLabel: String
        if isNow {
            if closingSoon, let mins = minutesLeft {
                a11yLabel = String(
                    format: NSLocalizedString("bestTimes.now.pill.closing.a11y", comment: "Closing soon accessibility label in best times detail"),
                    mins
                )
            } else if let minutesLeft {
                a11yLabel = String(
                    format: NSLocalizedString("bestTimes.now.pill.left.a11y", comment: "Good now accessibility with minutes left"),
                    minutesLeft
                )
            } else {
                a11yLabel = NSLocalizedString("timeline.now.good", comment: "")
            }
        } else {
            a11yLabel = NSLocalizedString("timeline.now.off", comment: "")
        }
        let scrollHint = NSLocalizedString("bestTimes.pill.scrollHint", comment: "Scrolls to the time-of-day timeline")
        return AnyView(
            Button {
                Haptics.selection()
                if let proxy = scrollProxy {
                    withAnimation(reduceMotion ? nil : .easeInOut) {
                        proxy.scrollTo("bestTimesTimeline", anchor: .center)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: symbol)
                        .font(.caption2.weight(.semibold))
                        .symbolEffect(.pulse, isActive: isNow && !reduceMotion)
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .easeInOut, value: minutesLeft)
                }
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(background))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(a11yLabel))
            .accessibilityHint(Text(scrollHint))
        )
    }

    // `openingHoursRow` was replaced by `openingHoursLineSection` (a mono line
    // with a green open-now dot), so the old system-styled row is gone.

    private var bestTimesSection: some View {
        sectionContainer(title: NSLocalizedString("section.bestTimes", comment: "")) {
            VStack(alignment: .leading, spacing: 6) {
                if !viewModel.experience.bestTimes.isEmpty {
                    // Warm amber ribbon: golden window band + crowd-density curve +
                    // a "此刻" now marker (styles.css .sc-best-window-v2).
                    BestTimeRibbon(
                        windows: viewModel.experience.bestTimes,
                        reduceMotion: reduceMotion
                    )
                    .id("bestTimesTimeline")
                    HStack {
                        let range = viewModel.experience.durationMinutes
                        Text(String(format: NSLocalizedString("section.duration", comment: ""), range.min, range.max))
                            .ctMono(11)
                            .foregroundStyle(CT.fgMuted)
                        Spacer()
                        bestTimeStatusPill
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private var howToSection: some View {
        sectionContainer(title: NSLocalizedString("section.howTo", comment: "")) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(viewModel.experience.howTo.enumerated()), id: \.element.id) { index, step in
                    if index > 0 {
                        Rectangle().fill(CT.borderSubtle).frame(height: 0.5)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(step.order)")
                            .ctMono(11.5, .semibold)
                            .foregroundStyle(CT.accent)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(CT.accentSoft))
                        Text(step.text)
                            .ctBody(14)
                            .foregroundStyle(CT.fgPrimary)
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private func inconvenienceCategoryName(_ category: RealInconvenience.Category) -> String {
        let key = "inconvenience.category.\(category.rawValue)"
        return NSLocalizedString(key, comment: "Inconvenience category display name")
    }

    /// Honest caveats — one warm amber card per item with an uppercase mono
    /// category tag. Unlike before, all severities share the same warm tint
    /// (styles.css .sc-caveat): the product's voice is honest, not alarmist.
    private var inconveniencesSection: some View {
        sectionContainer(title: NSLocalizedString("section.inconveniences", comment: "")) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.experience.realInconveniences) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Image(systemName: item.category.symbol)
                                .font(.system(size: 12))
                                .accessibilityHidden(true)
                            Text(inconvenienceCategoryName(item.category).uppercased())
                                .ctDisplay(10, .bold)
                                .tracking(1.2)
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(CT.warningTextStrong)
                        Text(item.text)
                            .ctBody(13.5)
                            .foregroundStyle(CT.fgPrimary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(CT.warningSoft)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(CT.warningText.opacity(0.18), lineWidth: 0.5)
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

        // Title row: section label on the left, the big amber score on the right
        // (styles.css .sc-solo-head). Card below carries the one-liner, the
        // "based on N" line, the amber heatmap bars, and the best-call.
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(NSLocalizedString(titleKey, comment: "").uppercased())
                    .ctDisplay(11, .bold)
                    .tracking(1.6)
                    .foregroundStyle(CT.fgMuted)
                Spacer()
                Text(String(format: "%.1f", score.overall))
                    .ctDisplay(34, .bold)
                    .foregroundStyle(isEstimate ? CT.accent.opacity(0.55) : CT.accent)
                    .monospacedDigit()
                    .accessibilityLabel(Text(String(
                        format: NSLocalizedString("solo.a11y", comment: "Solo Score %@ of 10"),
                        String(format: "%.1f", score.overall)
                    )))
            }
            soloScoreCard(score: score, subtitle: subtitle, isEstimate: isEstimate)
        }
    }

    /// The amber Solo-Score card: hint line, based-on line, heatmap dimension
    /// bars (3 shown, expandable to 6), and a "strongest dimension" callout.
    private func soloScoreCard(score: SoloScore, subtitle: String?, isEstimate: Bool) -> some View {
        let dims = soloDimensions(score.breakdown)
        let strongest = dims.max(by: { $0.value < $1.value })
        let shown = showingRadarTooltip ? dims : Array(dims.prefix(3))
        return VStack(alignment: .leading, spacing: 0) {
            if let hint = score.hint, !hint.isEmpty {
                Text(hint)
                    .ctBody(14.5)
                    .foregroundStyle(CT.fgPrimary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
            }
            if let subtitle {
                Text(isEstimate ? NSLocalizedString("solo.estimate.pill", comment: "AI estimate pill") : subtitle)
                    .ctMono(10.5)
                    .foregroundStyle(CT.fgMuted)
                    .padding(.bottom, 14)
            }
            VStack(spacing: 9) {
                ForEach(shown, id: \.label) { dim in
                    soloDimRow(dim)
                }
            }
            Button {
                Haptics.selection()
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                    showingRadarTooltip.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(showingRadarTooltip
                        ? NSLocalizedString("solo.collapse", comment: "Collapse dimensions")
                        : String(format: NSLocalizedString("solo.showAll", comment: "Show all N dimensions"), dims.count))
                    Image(systemName: showingRadarTooltip ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .ctBody(12)
                .foregroundStyle(CT.fgMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(NSLocalizedString("solo.breakdown.expand.hint", comment: "Accessibility hint for breakdown toggle")))
            if let strongest, strongest.value >= 8 {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 11))
                    Text(String(format: NSLocalizedString("solo.bestCall", comment: "Best solo dimension callout"), strongest.label))
                }
                .ctBody(12.5)
                .foregroundStyle(CT.accent)
                .padding(.top, 8)
                .overlay(alignment: .top) {
                    Rectangle().fill(CT.borderSubtle).frame(height: 0.5)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(CT.surfaceWhite))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(CT.borderSubtle, lineWidth: 0.5))
        .opacity(isEstimate ? 0.85 : 1.0)
        .onAppear {
            guard !barsAppeared else { return }
            if reduceMotion {
                barsAppeared = true
            } else {
                withAnimation(.easeOut(duration: 0.7).delay(0.1)) { barsAppeared = true }
            }
        }
    }

    private struct SoloDim { let label: String; let value: Double }

    private func soloDimensions(_ b: SoloScore.Breakdown) -> [SoloDim] {
        [
            SoloDim(label: NSLocalizedString("solo.seating", comment: ""), value: b.seatingFriendly),
            SoloDim(label: NSLocalizedString("solo.staff", comment: ""), value: b.staffPressure),
            SoloDim(label: NSLocalizedString("solo.patrons", comment: ""), value: b.soloPatronRatio),
            SoloDim(label: NSLocalizedString("solo.ambiance", comment: ""), value: b.ambianceFit),
            SoloDim(label: NSLocalizedString("solo.safety", comment: ""), value: b.safety),
            SoloDim(label: NSLocalizedString("solo.portioning", comment: ""), value: b.soloPortioning),
        ]
    }

    /// One heatmap dimension row: label · amber bar (hi/mid/lo) · mono value.
    private func soloDimRow(_ dim: SoloDim) -> some View {
        let clamped = max(0, min(10, dim.value))
        let fill: Color = clamped >= 9 ? CT.heatmapHi : clamped >= 7 ? CT.heatmapMid : CT.heatmapLow
        let isTop = clamped >= 10
        return HStack(spacing: 10) {
            Text(dim.label)
                .ctBody(12)
                .foregroundStyle(CT.fgMuted)
                .frame(width: 52, alignment: .leading)
            GeometryReader { geo in
                Capsule().fill(CT.heatmapEmpty)
                    .overlay(alignment: .leading) {
                        Capsule().fill(fill)
                            .frame(width: barsAppeared ? geo.size.width * clamped / 10 : 0)
                    }
            }
            .frame(height: 6)
            Text(String(format: "%.0f", clamped))
                .ctMono(11.5, isTop ? .semibold : .regular)
                .foregroundStyle(isTop ? CT.accent : CT.fgMuted)
                .frame(width: 20, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(dim.label) \(String(format: "%.0f", clamped))"))
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
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    // MARK: - US-015: Multi-source indicator

    /// Multi-source indicator shown when the experience was assembled from ≥2 distinct sources.
    @ViewBuilder
    private var multiSourceIndicator: some View {
        if viewModel.experience.sources.count >= 2 {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundStyle(CT.verifiedGreen)
                Text(NSLocalizedString("detail.multiSource.indicator", comment: "Verified by multiple sources indicator"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(CT.successSoft))
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
                sourceRowContent(label: label, iconName: iconName, date: source.verifiedAt, isLink: true)
            }
            .simultaneousGesture(TapGesture().onEnded {
                Haptics.impact(.light)
            })
            .accessibilityAddTraits(.isLink)
            .accessibilityHint(Text(NSLocalizedString("detail.source.openHint", comment: "Opens the original source")))
        } else {
            sourceRowContent(label: label, iconName: iconName, date: source.verifiedAt, isLink: false)
        }
    }

    /// One mono source row: list glyph · name · date · optional open chevron
    /// (styles.css .sc-source).
    private func sourceRowContent(label: String, iconName: String, date: Date, isLink: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 12))
                .foregroundStyle(CT.fgMuted)
            Text(label)
                .ctBody(12.5)
                .foregroundStyle(CT.fgMuted)
            Spacer(minLength: 8)
            Text(date, style: .date)
                .ctMono(10.5)
                .foregroundStyle(CT.fgMuted)
            if isLink {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9))
                    .foregroundStyle(CT.fgMuted)
            }
        }
        .padding(.vertical, 5)
    }

    private func symbol(for type: InformationSource.SourceType) -> String {
        switch type {
        case .wikivoyage, .wikipedia: return "book"
        case .reddit:                 return "bubble.left.and.bubble.right"
        case .blog:                   return "doc.text"
        case .youtube:                return "play.rectangle"
        case .user:                   return "person.crop.circle"
        case .fieldVisit:             return "figure.walk"
        case .amap:                   return "map.fill"
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
                    .foregroundStyle(CT.fgPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .frame(width: 180, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(CT.surfaceSunken)
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
                    .foregroundStyle(CT.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color(.systemBackground)).shadow(radius: 6))
    }

    // MARK: - Action bar

    /// A circular secondary dock action — warm-white disc, hairline border, amber
    /// when toggled on (styles.css .sc-detail-dock .dock-act).
    private func dockIconButton(
        systemName: String,
        isOn: Bool = false,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(isOn ? CT.accent : CT.fgMuted)
                .frame(width: 46, height: 46)
                .background(Circle().fill(isOn ? CT.accentSoft : CT.surfaceWhite))
                .overlay(Circle().strokeBorder(isOn ? CT.accentBorder : CT.borderSubtle, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var actionBar: some View {
        ZStack(alignment: .center) {
        HStack(spacing: 9) {
            // Favorite
            dockIconButton(
                systemName: viewModel.isFavorited ? "heart.fill" : "heart",
                isOn: viewModel.isFavorited,
                accessibilityLabel: viewModel.isFavorited
                    ? NSLocalizedString("action.unfavorite", comment: "Remove favorite")
                    : NSLocalizedString("action.favorite", comment: "Add favorite")
            ) {
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
            }
            .overlay { HeartBurstView(trigger: heartBurstTrigger) }

            // Add to itinerary
            dockIconButton(
                systemName: "calendar.badge.plus",
                accessibilityLabel: NSLocalizedString("action.addToItinerary", comment: "Add to itinerary")
            ) {
                Haptics.impact(.light)
                isShowingAddToItinerary = true
            }

            // Ask Solo — opens the chat scoped to this place (or paywall for free
            // tier). Wired only when the parent supplied `onAskSolo`.
            if onAskSolo != nil {
                dockIconButton(
                    systemName: "bubble.left.and.text.bubble.right",
                    accessibilityLabel: NSLocalizedString("experience.askSolo.cta", comment: "Ask Solo")
                ) {
                    Haptics.impact(.light)
                    switch Self.askSoloAction(canAskSolo: viewModel.canAskSolo) {
                    case .openChat:        onAskSolo?(viewModel.experience)
                    case .presentPaywall:  isShowingPaywall = true
                    }
                }
                .accessibilityIdentifier("experience.askSolo.cta")
            }

            // Mark done — primary amber pill, turns green when completed.
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
                HStack(spacing: 7) {
                    Image(systemName: viewModel.isCompleted ? "checkmark.circle.fill" : "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .symbolEffect(.bounce, value: viewModel.isCompleted)
                    Text(viewModel.isCompleted
                        ? NSLocalizedString("action.completed", comment: "")
                        : NSLocalizedString("action.markDone", comment: ""))
                        .ctBody(14.5, .semibold)
                }
                .foregroundStyle(viewModel.isCompleted ? CT.successText : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    Capsule().fill(viewModel.isCompleted ? CT.successSoft : CT.accent)
                )
            }
            .buttonStyle(.plain)
            .padding(.leading, 3)
            .accessibilityLabel(Text(viewModel.isCompleted
                ? NSLocalizedString("action.completed", comment: "Marked as completed")
                : NSLocalizedString("action.markDone", comment: "Mark as done")))
        }
        .padding(.horizontal, 16)
        .padding(.top, 11)
        // Bottom padding raised 12 → 26 pt so the Mark-done pill no longer
        // visually crashes into the home-indicator area on iPhone 17. The
        // background ZStack below already ignoresSafeArea(.bottom), so the
        // bar's blur extends to the screen edge; this extra inner padding is
        // what gives the row breathing room above the indicator strip.
        .padding(.bottom, 26)
        .background(
            // Opaque warm bar: reserves its own space via safeAreaInset (no manual
            // bottom padding), so content never scrolls behind it. Warm-white blur
            // + hairline top keeps it in the amber system and legible over content.
            ZStack(alignment: .top) {
                CT.bgWarm.opacity(0.94)
                    .background(.regularMaterial)
                    .ignoresSafeArea(edges: .bottom)
                Rectangle().fill(CT.borderSubtle).frame(height: 0.5)
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

    /// Section wrapper with the design's quiet uppercase-mono heading
    /// (styles.css .sc-detail-block h3: 11px / tracking / uppercase / fg-muted).
    private func sectionContainer<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .ctDisplay(11, .bold)
                .tracking(1.6)
                .foregroundStyle(CT.fgMuted)
                .minimumScaleFactor(0.85)
                .lineLimit(2)
            content()
        }
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
                    .foregroundStyle(CT.accent)
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
                    .foregroundStyle(.secondary)
                Text(cardinalDirection)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
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
