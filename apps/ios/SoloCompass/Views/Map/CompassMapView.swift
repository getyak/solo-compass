import SwiftUI
import MapKit
import SwiftData
import os

enum MapStyleChoice: String, CaseIterable {
    case standard
    case imagery
    case hybrid

    var label: String {
        switch self {
        case .standard: return NSLocalizedString("map.style.standard", comment: "Standard map")
        case .imagery:  return NSLocalizedString("map.style.satellite", comment: "Satellite map")
        case .hybrid:   return NSLocalizedString("map.style.hybrid", comment: "Hybrid map")
        }
    }

    var icon: String {
        switch self {
        case .standard: return "map"
        case .imagery:  return "globe.americas"
        case .hybrid:   return "square.on.square"
        }
    }

    var mapStyle: MapStyle {
        switch self {
        case .standard: return .standard(elevation: .flat, pointsOfInterest: .excludingAll)
        case .imagery:  return .imagery(elevation: .flat)
        case .hybrid:   return .hybrid(elevation: .flat, pointsOfInterest: .excludingAll)
        }
    }

    mutating func cycle() {
        let all = Self.allCases
        guard let idx = all.firstIndex(of: self) else { return }
        self = all[(idx + 1) % all.count]
    }
}

/// Which route-related sheet is currently presented over the map. A single
/// `.sheet(item:)` keyed on this enum replaces the two stacked
/// `.sheet(isPresented:)` modifiers that SwiftUI silently collapsed (only the
/// last won), which left route cards un-tappable.
enum RouteSheet: Identifiable {
    /// Open a route's detail view.
    case detail(Route)
    /// Open the create-your-own-route flow.
    case create

    var id: String {
        switch self {
        case .detail(let route): return "detail-\(route.id.rawValue)"
        case .create:            return "create"
        }
    }
}

/// THE root view. Map-first means: this is what the app *is*. No tabs. No
/// drawer. Filters and the bottom info bar overlay it; an experience card
/// floats up when a marker is tapped.
///
/// US-021: this is a thin wrapper that reads the `@Environment` services and
/// hands them to `CompassMapContentView`, whose `MapViewModel` is built
/// *eagerly* in `init` (a `@State` default initializer can't see the
/// environment). Eager construction closes the launch→onAppear window where
/// the old optional view model silently dropped writes, and removes the
/// `ProgressView` placeholder that used to flash before the map appeared.
public struct CompassMapView: View {
    @Environment(LocationService.self) private var locationService
    @Environment(ExperienceService.self) private var experienceService
    @Environment(AIService.self) private var aiService
    @Environment(UserPreferences.self) private var preferences
    @Environment(NotificationService.self) private var notificationService
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(\.themeService) private var themeService
    @Environment(CompanionService.self) private var companionService
    @Environment(PresenceService.self) private var presenceService

    public init() {}

    /// Returns how full the imminence ring should be: 0.0 at `windowMinutes` out, 1.0 at 0m.
    /// Clamped to [0, 1].
    static func imminenceProgress(minutesUntil: Int, windowMinutes: Int = 120) -> Double {
        max(0, min(1, 1 - Double(minutesUntil) / Double(windowMinutes)))
    }

    public var body: some View {
        CompassMapContentView(
            locationService: locationService,
            experienceService: experienceService,
            aiService: aiService,
            preferences: preferences,
            notificationService: notificationService,
            subscriptionService: subscriptionService,
            themeService: themeService,
            companionService: companionService,
            presenceService: presenceService
        )
    }

    #if DEBUG
    /// US-005 test hook: the dynamic type name of `body` once the view is
    /// installed in a SwiftUI graph with its environment injected. Asserting
    /// on this string proves the root returns a concrete opaque view (no
    /// `AnyView` erasure), which is what lets SwiftUI diff this heavy view
    /// incrementally. DEBUG-only and read-only — never affects production
    /// rendering. Captured lazily inside `CompassMapContentView.mapContent.onAppear`.
    @MainActor static var debugBodyTypeName: String = ""

    /// US-009 test hook: set to `true` the moment the Companion-layer toggle
    /// branch is evaluated into the overlay (i.e. when
    /// `FeatureFlags.companionLayerEnabled` is on). Stays `false` when the flag
    /// gates the toggle out, which lets `CompassMapViewLayerToggleTests` assert
    /// the control is / is not in the view hierarchy. DEBUG-only and read-only.
    @MainActor static var debugCompanionLayerToggleRendered: Bool = false

    /// Regression hook for the bottom-left settings FAB. Set to `true` the
    /// moment `settingsSheetContent` is evaluated — which only happens when the
    /// `.sheet(isPresented: settingsSheetBinding)` modifier is actually wired
    /// into the view tree AND `isShowingSettings` is true. Commit 6655422 once
    /// dropped that modifier, leaving the FAB inert; this hook lets
    /// `SettingsSheetPresentationTests` prove the wiring is back. DEBUG-only.
    @MainActor static var debugSettingsSheetRendered: Bool = false

    /// Test-only switch: when `true`, `CompassMapContentView`'s first `onAppear`
    /// flips `isShowingSettings` so the settings sheet presents without a tap.
    /// Paired with `debugSettingsSheetRendered` to regression-test the FAB wiring.
    @MainActor static var debugForceShowSettings: Bool = false
    #endif
}

/// Owns the eagerly-initialized `MapViewModel`. Receives every dependency as a
/// plain init parameter (not `@Environment`) so the view model can be built in
/// `init` — there is never a window where `viewModel` is `nil`.
///
/// `@MainActor` so the `init` can synchronously construct and configure the
/// `@MainActor`-isolated `MapViewModel` under `SWIFT_STRICT_CONCURRENCY:
/// complete`.
@MainActor
struct CompassMapContentView: View {
    private let locationService: LocationService
    private let experienceService: ExperienceService
    private let aiService: AIService
    private let preferences: UserPreferences
    private let notificationService: NotificationService
    private let subscriptionService: SubscriptionService
    private let themeService: ThemeService
    private let companionService: CompanionService
    private let presenceService: PresenceService

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Honored by the preview-card pop animation on long-press: motion-sensitive
    /// users get an instant, spring-free selection instead of the scale+rise.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// US-049: the shared 60s clock. Reading `tick` inside `mapLayer` re-evaluates
    /// the marker layer every minute, so a best-now pin flips to its amber
    /// "closing soon" treatment live as its window crosses the 45-min threshold —
    /// matching the cards, which already observe this same clock.
    @Environment(BestNowClock.self) private var bestNowClock

    @State private var viewModel: MapViewModel
    @State private var voiceService = VoiceService()
    @State private var dismissedAIError: String? = nil
    @State private var dismissedExploreError: String? = nil
    @State private var dismissedQuotaInfo: String? = nil
    // US-026: true once the user dismisses the GPS-error banner; reset when the
    // underlying LocationService.lastError clears so a new failure re-shows it.
    @State private var dismissedLocationError: Bool = false

    @State private var isShowingCityPicker: Bool = false
    @State private var surveyExperience: Experience? = nil
    @State private var isShowingFavorites: Bool = false

    // MARK: - City OS v2 (PRD solo-city-os-v2 §4–5), all gated by FeatureFlags.cityOS
    /// Per-city mode (Live/Plan/Recall) + kit auto-surface bookkeeping.
    @State private var cityOSStore: CityOSStore
    /// Landing-kit + local-events content plane (cache-first, seed fallback).
    @State private var cityBriefService: CityBriefService
    /// Visa / 183-day self-computation (pure-local).
    @State private var complianceService: ComplianceService
    @State private var isShowingKitSheet: Bool = false
    /// When set, the kit sheet opens focused on this row (e.g. the visa row from
    /// the compliance banner). Cleared on dismiss.
    @State private var kitSheetFocus: CityKitItem.Kind? = nil
    @State private var isShowingLiveSheet: Bool = false
    /// City OS v3 · Recall 印证 target — non-nil presents the VerifySheet.
    @State private var verifyTarget: Experience?
    /// Transient City-OS toast ("已印证 · 信心 +1") floating above the dock slot.
    @State private var cityOSToast: String?
    /// Session-scoped dismissal of the compliance banner — it reappears next day
    /// (a fresh interruption-budget day), never again this session.
    @State private var complianceBannerDismissed: Bool = false
    /// Mirror of the BottomInfoSheet's current detent, so the drawer tabs only
    /// show at `.peek`. Threaded via `onDetentChange`.
    @State private var sheetDetent: BottomSheetDetent = .peek
    @State private var voiceOrchestrator: VoiceAgentOrchestrator? = nil
    /// Selected detent for the chat sheet. Bound into `presentationDetents` so
    /// the sheet can auto-expand to `.large` while the agent is working (see
    /// `ChatSheet`), giving the reply room to breathe instead of being read in a
    /// cramped half-sheet.
    @State private var chatDetent: PresentationDetent = .medium
    @State private var mapStyleChoice: MapStyleChoice = .standard

    // US-017: Companion map layer (default off)
    @State private var isCompanionLayerOn: Bool = false
    @State private var nearbyCells: [NearbyCell] = []

    // P1.1 #112: passive visit halo. The model container is supplied at the
    // WindowGroup level (SoloCompassApp.swift), so @Query just works here.
    // Sort doesn't matter — we only need the experienceId set.
    @Query private var visitRecords: [VisitRecord]

    // US-025: Routes section in BottomInfoSheet
    @State private var routeStore = RouteStore()
    /// Persists chat conversations so history survives the sheet closing / app
    /// restart and the user can reopen them from the chat header.
    @State private var chatHistoryStore = ChatHistoryStore()
    @State private var nearbyRoutes: [Route] = []
    // Single source of truth for the route detail / create-route sheets. Two
    // separate `.sheet(isPresented:)` modifiers on the same view silently
    // collapse to only the last one in SwiftUI — which is why tapping a route
    // card used to do nothing (the create-route sheet shadowed the detail one).
    // A single `.sheet(item:)` driven by this enum presents whichever is active.
    @State private var routeSheet: RouteSheet? = nil
    // The route currently drawn on the map (polyline + numbered stops), set when
    // the traveler taps "开始路线" in RouteDetailView. nil = no active route.
    @State private var activeRoute: ActiveRoute? = nil

    // Single chat sheet (replaces former plus-menu + voice-overlay split).
    // Presentation is driven by `voiceOrchestrator` via `.sheet(item:)`.
    @State private var chatStartMode: ChatStartMode = .text
    @State private var isMapPanning: Bool = false
    // US-007: personal hub (MeSheet) presentation, driven by the top-right
    // avatar bubble in the map overlay. Friend state is read live so the
    // bubble can show a pending-request dot.
    @State private var isShowingMe: Bool = false
    // US-024: when a `message` push is tapped, the personal hub opens with this
    // conversation id so its Messages list auto-pushes the matching ChatView.
    // `nil` when the hub was opened any other way (avatar bubble, inbox).
    @State private var deepLinkConversationId: String?
    @State private var friendService = FriendService.shared
    @State private var lastPanAt: Date = .distantPast
    @State private var panDebounceTask: Task<Void, Never>? = nil

    // Direction 2: on the first frame after the map loads, only the 3 AI
    // smart-pick pins "shine"; every other pin is dimmed (~35% opacity, ~85%
    // scale) so the map reads as a curated short-list, not a wall of dots.
    // Flips off on the user's first map drag/tap or when Explore mode kicks in,
    // and never re-activates within this view's lifetime — the curation cue is
    // a cold-start affordance, not a permanent treatment.
    @State private var smartPickHighlightActive: Bool = true

    // Tracks whether we've seen a disconnect so the success haptic only fires
    // after a real offline→online transition, never on cold launch.
    @State private var hasDisconnected: Bool = false

    // US-021: the city-picker first-launch prompt used to be gated by the
    // `viewModel == nil` check (true only on the first onAppear). With the
    // eager view model that guard is gone, so this one-shot flag preserves the
    // "prompt only once" behaviour across repeat onAppear fires.
    @State private var hasRunFirstAppear: Bool = false

    /// Startup self-diagnostics — runs once per calendar day 1.5s after first
    /// paint. Findings drive a `SoloAgentBubble` shown just above the Solo
    /// mascot FAB; tapping the CTA seeds the findings into ChatSheet as the
    /// first user turn so the AI opens by explaining each detected issue.
    @State private var diagnostics: StartupDiagnosticsService? = nil
    @State private var agentBubbleQueue = SoloAgentBubbleQueue()
    /// Seed prompt cached at bubble-tap time so `chatSheetContent` can hand
    /// it to `ChatSheet.initialUserPrompt`.
    @State private var pendingDiagnosticsPrompt: String? = nil

    private let networkMonitor = NetworkMonitor.shared

    private var isFilterActive: Bool {
        (viewModel.selectedCategory != nil) || (viewModel.selectedCustomTag != nil) || viewModel.isNowFilter || viewModel.isFavoriteFilter
    }

    private var activeFilterName: String {
        if let category = viewModel.selectedCategory {
            return category.localizedTitle
        } else if let tag = viewModel.selectedCustomTag {
            return tag
        } else if viewModel.isNowFilter {
            return NSLocalizedString("filter.now", comment: "Now filter label")
        } else if viewModel.isFavoriteFilter {
            return NSLocalizedString("filter.saved", comment: "Saved filter label")
        }
        return ""
    }

    /// Idle window after the last pan before POIs refresh. Lowered from 1.5s
    /// to cut the "dragged the map, nothing happened" lag (#133).
    private static let panRefreshDebounce: TimeInterval = 0.8

    enum ChatStartMode { case text, voice }

    init(
        locationService: LocationService,
        experienceService: ExperienceService,
        aiService: AIService,
        preferences: UserPreferences,
        notificationService: NotificationService,
        subscriptionService: SubscriptionService,
        themeService: ThemeService,
        companionService: CompanionService,
        presenceService: PresenceService
    ) {
        self.locationService = locationService
        self.experienceService = experienceService
        self.aiService = aiService
        self.preferences = preferences
        self.notificationService = notificationService
        self.subscriptionService = subscriptionService
        self.themeService = themeService
        self.companionService = companionService
        self.presenceService = presenceService

        // Eager (US-021): build the view model up-front so writes between
        // launch and `onAppear` land on a live instance instead of dropping
        // against `nil`. Production opts into the SwiftData-backed Overpass
        // cache so warm starts skip the network; tests construct `MapViewModel`
        // directly and stay cache-isolated via the default `OverpassService()`.
        let vm = MapViewModel(
            locationService: locationService,
            experienceService: experienceService,
            aiService: aiService,
            preferences: preferences,
            overpassService: OverpassService(maxResults: DataSourceSettings.poiFetchLimit, useSharedCache: true)
        )
        vm.attachSubscriptionService(subscriptionService)
        _viewModel = State(initialValue: vm)

        // City OS v2: these three own the (city, mode) + brief content + visa
        // math. Built here (not lazily) because they need `preferences` and,
        // like `vm`, must be live for any write between launch and `onAppear`.
        _cityOSStore = State(initialValue: CityOSStore(preferences: preferences))
        _cityBriefService = State(initialValue: CityBriefService())
        _complianceService = State(initialValue: ComplianceService(preferences: preferences))
    }

    /// Bottom inset for the floating selected-experience card so it rests
    /// clear of the `BottomInfoSheet` at its `peek` height — at any Dynamic
    /// Type size, since the peek height itself scales with `UIFontMetrics`.
    /// The old hard-coded `80pt` clipped the card's Solo-Score row behind the
    /// sheet (the peek height is ≥170pt). `cardSheetGap` is the breathing room
    /// between the card's lower edge and the sheet's top, so the layering reads
    /// as "card floating above sheet" rather than "card jammed against it".
    private var cardBottomInset: CGFloat {
        let cardSheetGap: CGFloat = 12
        return sheetPeekClearance + cardSheetGap
    }

    /// Bottom inset for the map's floating control bar (filter, explore, and the
    /// `+` FAB) so they rest clear of the `BottomInfoSheet` peek instead of being
    /// half-occluded by it. Same root cause as the card: a fixed `80pt` inset sat
    /// below the ≥170pt peek height. Slightly smaller gap than the card so the
    /// controls hug the sheet without crowding it.
    private var controlBarBottomInset: CGFloat {
        let controlSheetGap: CGFloat = 8
        let base = sheetPeekClearance + controlSheetGap
        return cityOSBottomSlotOccupied ? base + 60 : base
    }

    // MARK: - City OS v2 helpers

    /// Bottom inset for the City-OS drawer tabs so they float just above the
    /// peek sheet. Slightly more gap than the control bar so the two glass
    /// pills read as their own row, not stacked on the FAB.
    private var drawerTabsBottomInset: CGFloat {
        sheetPeekClearance + 8
    }

    /// The current city's mode (Live/Plan/Recall). Live is the default.
    private var currentCityMode: CityMode {
        cityOSStore.mode(for: viewModel.selectedCity)
    }

    /// City OS v3 · lifecycle stage for the city pill's rail dots. Days stayed
    /// come from the visa entry date the traveler already gave the kit.
    private var currentCityStage: CityStage? {
        cityOSStore.stage(
            for: viewModel.selectedCity,
            daysStayed: complianceService.state()?.daysStayed
        )
    }

    /// City OS v3 · the city pill's second line ("第 3 天 · 生活" / "未到 · 计划"
    /// / "已离 · 回顾"). Nil keeps the pill single-line: Live with no entry date
    /// has nothing honest to say, so it says nothing.
    private var cityPillModeLine: String? {
        guard FeatureFlags.cityOS, viewModel.selectedCity != nil else { return nil }
        switch currentCityMode {
        case .plan:
            return NSLocalizedString("cityos.pill.plan", comment: "未到 · 计划")
        case .recall:
            return NSLocalizedString("cityos.pill.recall", comment: "已离 · 回顾")
        case .live:
            guard let days = complianceService.state()?.daysStayed, days >= 1,
                  let stage = currentCityStage else { return nil }
            return String(
                format: NSLocalizedString("cityos.pill.live", comment: "第 %1$d 天 · %2$@"),
                days, stage.localizedLabel
            )
        }
    }

    /// Stage-dot rail index for the pill (Live mode only; nil hides the rail).
    private var cityPillStageIndex: Int? {
        guard FeatureFlags.cityOS, currentCityMode == .live,
              complianceService.state() != nil else { return nil }
        return currentCityStage?.index
    }

    /// Recall mode · experiences in the current city the traveler completed
    /// (去过). Source of truth is `preferences.completedExperiences`.
    private var recallVisited: [Experience] {
        guard let city = viewModel.selectedCity else { return [] }
        let key = CityOSStore.normalizedCityKey(city)
        return experienceService.allExperiences.filter {
            CityOSStore.normalizedCityKey($0.location.cityCode) == key
                && preferences.completedExperiences.contains($0.id)
        }
    }

    /// Visited experiences the traveler hasn't personally verified yet — the
    /// Recall card's contribution queue.
    private var recallPending: [Experience] {
        recallVisited.filter { !cityOSStore.isVerified($0.id) }
    }

    /// VerifySheet submit: record the verification (idempotent), feed the
    /// answers into the co-build layer as a note authored by "你", and confirm
    /// with a toast — the 消费者→贡献者 loop closing in one tap.
    private func submitVerification(_ answers: VerifySheet.Answers, for experience: Experience) {
        cityOSStore.markVerified(experience.id)
        let parts = [
            answers.stillThere == 0
                ? NSLocalizedString("cityos.verify.note.exists", comment: "还在营业")
                : NSLocalizedString("cityos.verify.note.changed", comment: "已变动/关闭"),
            answers.soloComfort == 0
                ? NSLocalizedString("cityos.verify.note.solo", comment: "一个人很自在")
                : NSLocalizedString("cityos.verify.note.awkward", comment: "一个人有点尴尬"),
            answers.crowd == 0
                ? NSLocalizedString("cityos.verify.note.few", comment: "人少")
                : NSLocalizedString("cityos.verify.note.crowded", comment: "挺挤"),
        ]
        let prefix = NSLocalizedString("cityos.verify.note.prefix", comment: "印证：")
        TravelerNoteStore().addNote(
            experienceId: experience.id,
            text: prefix + parts.joined(separator: " · ")
        )
        showCityOSToast(NSLocalizedString(
            "cityos.verify.toast",
            comment: "已印证 · 这个点的信心 +1，谢谢你"
        ))
    }

    /// Show the transient City-OS toast for ~2.4s.
    private func showCityOSToast(_ text: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { cityOSToast = text }
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(.easeInOut(duration: 0.3)) { cityOSToast = nil }
        }
    }

    /// Display name for the current city (for the mode placeholder cards),
    /// falling back to the raw code, then a generic label.
    private var currentCityDisplayName: String {
        guard let code = viewModel.selectedCity else {
            return NSLocalizedString("cityos.mode.thisCity", comment: "This city (unknown)")
        }
        return viewModel.availableCities.first { $0.code == code }?.name ?? code
    }

    /// Pure banner-arbitration ladder: offline > POI loading > compliance. The
    /// compliance banner shows only when City OS is on, the visa is critical,
    /// the banner hasn't been dismissed this session, and the city is in Live
    /// mode. Extracted so `ComplianceBannerArbitrationTests` can pin every rung.
    /// `nonisolated` (pure) so tests can call it off the main actor.
    nonisolated static func showsComplianceBanner(
        offline: Bool,
        fetching: Bool,
        cityOSEnabled: Bool,
        critical: Bool,
        dismissed: Bool,
        isLive: Bool
    ) -> Bool {
        guard cityOSEnabled, !offline, !fetching else { return false }
        return critical && !dismissed && isLive
    }

    /// Whether the compliance banner should render right now, consulting live
    /// state. `showsComplianceBanner` holds the pure logic.
    private var shouldShowComplianceBanner: Bool {
        Self.showsComplianceBanner(
            offline: !networkMonitor.isConnected,
            fetching: viewModel.isFetchingPOIs,
            cityOSEnabled: FeatureFlags.cityOS,
            critical: complianceService.state()?.isCritical == true,
            dismissed: complianceBannerDismissed,
            isLive: currentCityMode == .live
        )
    }

    /// Whether the City-OS drawer tabs should show: flag on, resting at peek,
    /// Live mode, no experience selected, and kit content exists.
    private var shouldShowDrawerTabs: Bool {
        FeatureFlags.cityOS
            && sheetDetent == .peek
            && viewModel.selectedExperience == nil
            && currentCityMode == .live
            && !cityBriefService.kit.isEmpty
    }

    /// Whether the City-OS floating bottom slot (drawer tabs in Live mode, the
    /// Plan/Recall placeholder otherwise) is occupied. Centered empty-state
    /// cards consult this to shift up clear of the slot — without it the
    /// quiet-hours card's CTA renders underneath the drawer tabs.
    private var cityOSBottomSlotOccupied: Bool {
        FeatureFlags.cityOS
            && sheetDetent == .peek
            && viewModel.selectedExperience == nil
            && (currentCityMode != .live || !cityBriefService.kit.isEmpty)
    }

    /// Load the landing kit + local events for a city and, when `autoSurface`
    /// is true and the city is unseen + in Live mode + has kit content + the
    /// interruption budget allows + no other sheet is up, push the kit sheet
    /// once. Also fires the 今日城市签 daily omen (its own 1/day budget). Always
    /// reloads content regardless of the auto-surface decision.
    private func loadCityBrief(for cityCode: String?, autoSurface: Bool) {
        guard FeatureFlags.cityOS, let cityCode, !cityCode.isEmpty else { return }
        Task {
            await cityBriefService.load(cityCode: cityCode)
            guard currentCityMode == .live else { return }
            startDailyOmenIfAvailable()
            guard autoSurface,
                  !cityOSStore.hasSeenKit(cityCode),
                  cityBriefService.hasKit(for: cityCode),
                  !anyCityOSSheetIsUp,
                  CityOSInterruptionBudget.consumeProactive()
            else { return }
            cityOSStore.markKitSeen(cityCode)
            kitSheetFocus = nil
            isShowingKitSheet = true
        }
    }

    /// True when any sheet that would collide with an auto-surfacing kit is
    /// already presented — the kit must never shove itself in front of one.
    private var anyCityOSSheetIsUp: Bool {
        isShowingCityPicker || isShowingKitSheet || isShowingLiveSheet
            || isShowingFavorites || isShowingMe || viewModel.isShowingDetail
            || voiceOrchestrator != nil
    }

    /// Present today's 今日城市签 Live Activity for the loaded city's daily pick.
    /// `startDailyOmen` owns the 1/day budget, so repeat calls are no-ops.
    private func startDailyOmenIfAvailable() {
        guard let pick = cityBriefService.dailyPick() else { return }
        let line = String(
            format: NSLocalizedString("cityos.omen.line", comment: "今日城市签 · %@"),
            pick.name
        )
        LiveActivityService.shared.startDailyOmen(
            line: line,
            microTask: pick.soloNote ?? pick.whenLabel
        )
    }

    /// Consume one interruption-budget unit the FIRST time the compliance banner
    /// renders on a given local day — a per-day UserDefaults stamp ensures a
    /// re-render within the same day doesn't double-charge. When the budget is
    /// already spent, dismiss the banner for this session so it stays silent.
    private func consumeComplianceBudgetOncePerDay() {
        let key = Self.complianceBudgetStampKey(for: Date())
        guard UserDefaults.standard.string(forKey: "cityos.compliance.banner.day") != key else { return }
        UserDefaults.standard.set(key, forKey: "cityos.compliance.banner.day")
        if !CityOSInterruptionBudget.consumeProactive() {
            complianceBannerDismissed = true
        }
    }

    /// Per-day stamp key (yyyy-MM-dd) for the compliance-banner budget guard.
    private static func complianceBudgetStampKey(for date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    /// The `BottomInfoSheet` peek height at the current Dynamic Type size — the
    /// vertical space any bottom-anchored floating overlay must clear.
    private var sheetPeekClearance: CGFloat {
        let traits = UITraitCollection(
            preferredContentSizeCategory: dynamicTypeSize.uiContentSizeCategory
        )
        return BottomSheetDetent.peekHeight(for: traits)
    }

    /// The single experience featured in the BottomInfoSheet's peek summary card
    /// ("此刻最值得去"). Prefers the first visible AI smart pick, else the nearest
    /// visible experience to the user (or the selected city's centre when GPS is
    /// unavailable). Resolved by the pure `PeekPickResolver` so the rule is unit-
    /// tested independently of the view graph.
    private var peekExperience: Experience? {
        PeekPickResolver.resolve(
            experiences: viewModel.visibleExperiences,
            smartPickIds: viewModel.aiSmartPickIds,
            referenceCoordinate: locationService.currentLocation?.coordinate
                ?? viewModel.defaultCenterForSelectedCity,
            excluding: Set(peekShuffledIds)
        )
    }

    /// Ids the traveler shuffled away via the peek card's "换一个" pill, in
    /// order. The resolver skips them so each shuffle deals the next-best
    /// pick; when the rotation has cycled through everything visible the
    /// handler clears the list and the deck starts again from the top pick.
    /// Stale ids from a previous city/filter are harmless — they simply no
    /// longer match anything visible.
    @State private var peekShuffledIds: [String] = []

    /// Whether `peekExperience` is the AI smart pick — drives the peek card's
    /// gold gradient and "AI Pick" tag.
    private var peekExperienceIsSmartPick: Bool {
        PeekPickResolver.isSmartPick(
            resolved: peekExperience,
            smartPickIds: viewModel.aiSmartPickIds
        )
    }

    @ViewBuilder
    var body: some View {
        mapContent
    }

    #if DEBUG
    /// US-021 test hook: the eagerly-initialized view model. Reachable the
    /// instant the view is constructed (the app-launch path), before any
    /// `onAppear` fires — which is exactly what `MapViewModelEagerInitTest`
    /// asserts. DEBUG-only and read-only.
    @MainActor var debugViewModel: MapViewModel { viewModel }
    #endif

    // US-005 / US-009 test hooks live on `CompassMapView` (the public type the
    // tests reference as `CompassMapView.debug…`). See that type below.

    @ViewBuilder
    private var mapContent: some View {
        mapZStack
            .background(themeService.currentTheme.background)
            .onAppear {
                #if DEBUG
                CompassMapView.debugBodyTypeName = String(describing: type(of: body))
                // Regression test entry point: lets SettingsSheetPresentationTests
                // drive the private `isShowingSettings` state without a tap, so it
                // can assert the settings `.sheet` modifier is wired into the tree.
                if CompassMapView.debugForceShowSettings {
                    viewModel.isShowingSettings = true
                }
                // Visual-verification entry point: `-openMe` opens the personal hub
                // (MeSheet) on launch so its layout can be screenshotted without an
                // avatar-bubble tap (idb/simctl tapping is unreliable on Xcode 26).
                if ProcessInfo.processInfo.arguments.contains("-openMe") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        isShowingMe = true
                    }
                }
                // Visual-verification entry point: `-openExperience` opens the
                // richest available experience's detail sheet directly, so the
                // warm-amber detail redesign can be screenshotted without a pin tap.
                // Prefers an experience that has howTo + inconveniences (so every
                // section renders); falls back to the first available one.
                if ProcessInfo.processInfo.arguments.contains("-openExperience") {
                    // Source from `allExperiences` (seed-loaded synchronously) so
                    // this works at cold start before the map has framed a region
                    // and populated `visibleExperiences`.
                    let pool = experienceService.allExperiences
                    let rich = pool.first { !$0.howTo.isEmpty && !$0.realInconveniences.isEmpty }
                    if let target = rich ?? pool.first {
                        viewModel.openExperienceDetail(target)
                    }
                }
                // Visual/behavioral-verification entry point: `-startIsland <kind>`
                // starts a real Live Activity at launch (kind ∈ route | countdown
                // | recording | compile), so the Dynamic Island can be exercised
                // without driving the deep UI flow that triggers it (idb/simctl
                // tapping is unreliable on Xcode 26). Sample data only.
                if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-startIsland"),
                   i + 1 < ProcessInfo.processInfo.arguments.count {
                    Self.startIslandDemo(kind: ProcessInfo.processInfo.arguments[i + 1])
                }
                // Visual-verification entry point: `-openChatMedium` opens the
                // global "+" ChatSheet at half detent on launch so the
                // editorial half-sheet redesign can be screenshotted without
                // an on-screen tap (idb/simctl tapping is unreliable on
                // Xcode 26). No experience scope — this is the generic
                // "Ask me where to go" doorway.
                if ProcessInfo.processInfo.arguments.contains("-openChatMedium") {
                    chatStartMode = .text
                    chatDetent = .medium
                    ensureOrchestrator(viewModel: viewModel)
                }
                if ProcessInfo.processInfo.arguments.contains("-openCityPicker") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        isShowingCityPicker = true
                    }
                }
                if ProcessInfo.processInfo.arguments.contains("-openSettings") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        viewModel.isShowingSettings = true
                    }
                }
                // Visual-verification entry point: `-forceDiagnosticsChat`
                // seeds a synthetic diagnostics finding and immediately
                // opens ChatSheet with the seed prompt. Screenshots verify
                // the seed prompt actually gets delivered to the AI without
                // depending on the bubble being tapped by an unreliable
                // simctl automation.
                if ProcessInfo.processInfo.arguments.contains("-forceDiagnosticsChatMulti") {
                    let error = StartupDiagnosticsService.Finding(
                        check: .locationAuth, severity: .error,
                        title: NSLocalizedString("diagnostics.location.denied.title", value: "定位被拒了", comment: ""),
                        detail: NSLocalizedString("diagnostics.location.denied.detail", value: "地图不知道你在哪。", comment: ""),
                        suggestedFix: NSLocalizedString("diagnostics.location.denied.fix", value: "去设置 → Solo Compass → 位置。", comment: "")
                    )
                    let warn = StartupDiagnosticsService.Finding(
                        check: .anthropicKey, severity: .warn,
                        title: NSLocalizedString("diagnostics.anthropic.missing.title", value: "AI 大脑没接上", comment: ""),
                        detail: NSLocalizedString("diagnostics.anthropic.missing.detail", value: "没检测到 AI API key。", comment: ""),
                        suggestedFix: NSLocalizedString("diagnostics.anthropic.missing.fix", value: "去设置 → AI Provider 填一个 key。", comment: "")
                    )
                    let info = StartupDiagnosticsService.Finding(
                        check: .userPrefs, severity: .info,
                        title: NSLocalizedString("diagnostics.onboarding.incomplete.title", value: "onboarding 还没走完", comment: ""),
                        detail: NSLocalizedString("diagnostics.onboarding.incomplete.detail", value: "推荐会退化。", comment: ""),
                        suggestedFix: NSLocalizedString("diagnostics.onboarding.incomplete.fix", value: "回到 onboarding 把三步选完。", comment: "")
                    )
                    let all = [error, warn, info]
                    let svc = diagnostics ?? StartupDiagnosticsService(
                        preferences: preferences,
                        locationService: locationService,
                        experienceService: experienceService
                    )
                    diagnostics = svc
                    svc.injectFindingsForTesting(all)
                    pendingDiagnosticsPrompt = svc.chatSeedPrompt(for: all)
                    chatStartMode = .text
                    chatDetent = .large
                    ensureOrchestrator(viewModel: viewModel)
                }
                if ProcessInfo.processInfo.arguments.contains("-forceDiagnosticsChat") {
                    let stub = StartupDiagnosticsService.Finding(
                        check: .anthropicKey, severity: .warn,
                        title: NSLocalizedString(
                            "diagnostics.anthropic.missing.title",
                            value: "AI 大脑没接上",
                            comment: ""
                        ),
                        detail: NSLocalizedString(
                            "diagnostics.anthropic.missing.detail",
                            value: "没检测到 AI API key。",
                            comment: ""
                        ),
                        suggestedFix: NSLocalizedString(
                            "diagnostics.anthropic.missing.fix",
                            value: "去设置 → AI Provider 填一个 key。",
                            comment: ""
                        )
                    )
                    let svc = diagnostics ?? StartupDiagnosticsService(
                        preferences: preferences,
                        locationService: locationService,
                        experienceService: experienceService
                    )
                    diagnostics = svc
                    svc.injectFindingsForTesting([stub])
                    pendingDiagnosticsPrompt = svc.chatSeedPrompt(for: [stub])
                    chatStartMode = .text
                    chatDetent = .large
                    ensureOrchestrator(viewModel: viewModel)
                }
                #endif
                locationService.requestPermission()
                // US-021: `viewModel` is built eagerly in `init`, so there is no
                // lazy-creation block here anymore. We only run the one-shot
                // first-launch side effects that used to live behind the
                // `viewModel == nil` guard.
                if !hasRunFirstAppear {
                    hasRunFirstAppear = true
                    kickoffStartupDiagnostics()
                    // On first launch with no resolved city and no GPS, prompt city
                    // picker. We consult `viewModel.selectedCity` (not just persisted
                    // `lastSelectedCity`) so the DEBUG `-startCity` launch arg — which
                    // never writes back to preferences — actually suppresses the
                    // picker. Without this guard a cold launch with `-startCity` still
                    // unexpectedly opens the picker over the consent gate.
                    // DEBUG: screenshot harness can pass -skipLocationPicker to keep
                    // the home view clean (no modal sheet covering peek/pins/FAB).
                    let skipPicker = ProcessInfo.processInfo.arguments.contains("-skipLocationPicker")
                    if !skipPicker
                        && viewModel.selectedCity == nil
                        && preferences.lastSelectedCity == nil
                        && locationService.currentLocation == nil {
                        isShowingCityPicker = true
                    }
                    // DEBUG: screenshot harness can pass -startNow to switch the
                    // filter to Now mode on cold start, so the RoutesSection's
                    // empty-state placeholder can be captured deterministically.
                    if ProcessInfo.processInfo.arguments.contains("-startNow") {
                        viewModel.isNowFilter = true
                    }
                    // Populate the Routes section for the initial city. `selectedCity`
                    // is resolved in the view model's init (from a persisted city or
                    // the -startCity override), so `onChange(of:selectedCity)` never
                    // fires for that initial value — without this, a cold start that
                    // lands directly on a city with seeded routes shows an empty
                    // Routes section, and 开始路线 is unreachable from the map.
                    refreshNearbyRoutes(cityCode: viewModel.selectedCity)
                    // City OS v2: load the landing kit + local events for the
                    // initial city and, on first cold start in a Live city, let
                    // the kit auto-surface once (budget-gated).
                    loadCityBrief(for: viewModel.selectedCity, autoSurface: true)
                    // #80: Cold-start resume. If RouteStore has an active route
                    // persisted from a previous session, rebuild the in-memory
                    // ActiveRoute @State so the polyline, numbered pins, and
                    // banner reappear automatically. Without this, persistence
                    // is invisible — user opens the app expecting to keep
                    // walking, but the map is back to "no route".
                    if let (route, _, _) = routeStore.loadActiveRoute() {
                        let resolved = route.experienceIds
                            .compactMap { experienceService.getExperience(id: $0)?.coordinate }
                        if !resolved.isEmpty {
                            activeRoute = ActiveRoute(route: route, coordinates: resolved)
                        }
                    }
                    // DEBUG visual-verification: `-triggerExplore` fires one
                    // explore at the resolved city center on cold start so a
                    // screenshot harness can see real POIs (Amap in mainland
                    // China, Overpass overseas) instead of the "Quiet patch"
                    // empty state. Mirrors the -openMe/-openExperience
                    // convention: only DEBUG builds honour it. Pairs with
                    // `-devConsentAccepted` which flips the Explore-Here
                    // consent so the sheet never blocks the automated pass.
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-devConsentAccepted") {
                        preferences.acceptExploreConsent()
                    }
                    if ProcessInfo.processInfo.arguments.contains("-triggerExplore") {
                        let center = viewModel.defaultCenterForSelectedCity
                        Task { await viewModel.exploreNearby(at: center) }
                    }
                    // City OS v2 screenshot-harness hooks: force-open the landing
                    // kit or live sheet unconditionally, bypassing the "seen kit"
                    // budget so an automated verification run always sees the same
                    // surface. Small delay lets the picker resolve and the sheet
                    // detent settle first.
                    if ProcessInfo.processInfo.arguments.contains("-openKitSheet") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            kitSheetFocus = nil
                            isShowingKitSheet = true
                        }
                    }
                    if ProcessInfo.processInfo.arguments.contains("-openLiveSheet") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            isShowingLiveSheet = true
                        }
                    }
                    // ④ Self-eval Rubric e2e hook: on cold start simulate one
                    // completed turn matching the "happy path" fixture and
                    // NSLog the resulting overall score. The e2e watcher greps
                    // the sim log for the marker to prove the scorer wired
                    // through to the store end-to-end.
                    if ProcessInfo.processInfo.arguments.contains("-simulateRubricTurn") {
                        ensureOrchestrator(viewModel: viewModel)
                        if let orch = voiceOrchestrator {
                            // Push a fixture that saturates every dimension:
                            // 3+ shared content tokens (咖啡馆/附近/安静/推荐),
                            // real synthesis, at least one card, and a card-
                            // eligible ask so cardCoverage = 10 too.
                            orch.debug_simulateCompletedTurn(
                                user: "附近推荐一家安静的咖啡馆",
                                assistant: "附近有家咖啡馆很安静，适合独自阅读，推荐。",
                                toolCalls: ["searchPlaces"],
                                cards: 1,
                                quality: .real
                            )
                            if let latest = orch.rubricStore.latest {
                                NSLog("[RUBRIC-E2E] overall=\(latest.overall) verdict=\(latest.verdict.rawValue) weakest=\(latest.weakestDimension) notes=\(latest.notes)")
                            } else {
                                NSLog("[RUBRIC-E2E] no report in store")
                            }
                        }
                    }
                    #endif
                }
                viewModel.checkForPendingCheckIns()
                // P1.1 #112: seed the visited-id set so .footprinted halos
                // light up on first render — without waiting for the next
                // VisitRecord write to trigger the onChange below.
                viewModel.attachVisitedExperienceIds(Set(visitRecords.map(\.experienceId)))
            }
            .onChange(of: locationService.currentLocation) { _, _ in
                viewModel.bindToLocation()
            }
            // P1.1 #112: keep the halo set in sync as new VisitRecords land
            // (the SwiftData @Query auto-refreshes; we re-publish to the vm).
            .onChange(of: visitRecords.count) { _, _ in
                viewModel.attachVisitedExperienceIds(Set(visitRecords.map(\.experienceId)))
            }
            // Beta-P1-H follow-up: LocationService.routeStopEntered fires when
            // the user crosses a 200m route-stop geofence, but until now nothing
            // was listening — Live Activity froze on stop 1, no notification
            // fired, and the user got zero feedback for "I arrived". Wire it
            // through here: advance the persisted route + refresh Dynamic Island.
            .onReceive(NotificationCenter.default.publisher(for: LocationService.routeStopEntered)) { note in
                guard let expId = note.userInfo?["experienceId"] as? String else { return }
                Task { @MainActor in
                    await handleRouteStopEntered(experienceId: expId)
                }
            }
            .onChange(of: preferences.pendingCheckIns) { _, _ in
                viewModel.checkForPendingCheckIns()
            }
            .onChange(of: viewModel.visibleExperiences.count) { _, count in
                guard isFilterActive, UIAccessibility.isVoiceOverRunning else { return }
                let filterName = activeFilterName
                let argument: NSAttributedString
                if count == 0 {
                    argument = NSAttributedString(
                        string: String(
                            format: NSLocalizedString("filter.a11y.noResultsAnnounce", comment: "VoiceOver: filter active, no results"),
                            filterName
                        ),
                        attributes: [.accessibilitySpeechQueueAnnouncement: true]
                    )
                } else {
                    argument = NSAttributedString(
                        string: String(
                            format: NSLocalizedString("filter.a11y.resultsAnnounce", comment: "VoiceOver: filter active, results count"),
                            filterName, count
                        ),
                        attributes: [.accessibilitySpeechQueueAnnouncement: true]
                    )
                }
                UIAccessibility.post(notification: .announcement, argument: argument)
            }
            .onChange(of: networkMonitor.isConnected) { _, connected in
                if !connected {
                    hasDisconnected = true
                    Haptics.notify(.warning)
                } else if hasDisconnected {
                    Haptics.notify(.success)
                }
            }
            .onChange(of: viewModel.isShowingDetail) { _, showing in
                if showing {
                    HapticService.shared.impact(style: .medium)
                }
            }
            // US-023: a tapped friend-request push deep-links to the inbox. The
            // friend-request inbox lives inside the personal hub (MeSheet), so
            // surface it and consume the link so a re-render won't re-open it.
            .onChange(of: notificationService.pendingDeepLink) { _, link in
                switch link {
                case .friendRequestInbox:
                    deepLinkConversationId = nil
                    isShowingMe = true
                    notificationService.pendingDeepLink = nil
                case .chatConversation(let conversationId):
                    // US-024: a tapped message push opens the personal hub's
                    // Messages list, which auto-pushes the matching ChatView.
                    deepLinkConversationId = conversationId
                    isShowingMe = true
                    notificationService.pendingDeepLink = nil
                case .experienceDetail(let experienceId):
                    if let exp = experienceService.getExperience(id: experienceId) {
                        viewModel.openExperienceDetail(exp)
                    }
                    notificationService.pendingDeepLink = nil
                case .routePreview(let routeId):
                    if let route = routeStore.get(RouteId(rawValue: routeId)) {
                        routeSheet = .detail(route)
                    }
                    notificationService.pendingDeepLink = nil
                case .none:
                    break
                }
            }
            .onChange(of: viewModel.selectedCity) { _, cityCode in
                refreshNearbyRoutes(cityCode: cityCode)
                // Clear an active route that belongs to the city we just left —
                // otherwise its polyline + numbered pins stay drawn at the old
                // city's coordinates while the camera and experiences have moved
                // to the new city (an orphan walk floating over the wrong map).
                if let active = activeRoute, active.route.cityCode != cityCode {
                    activeRoute = nil
                }
                // City OS v2: switching city always reloads the brief (content
                // refresh); the kit may auto-surface once for a Live city not
                // yet seen. Reset the highlight + banner dismissal for the new
                // city so a stale marker glow / dismissed banner don't carry over.
                viewModel.highlightedEventId = nil
                complianceBannerDismissed = false
                // City OS v3: 切城 = 切换整个聚合上下文 — active filters belong
                // to the city they were set in, so they never carry over.
                viewModel.clearFilters()
                loadCityBrief(for: cityCode, autoSurface: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: RouteStore.didChange)) { _ in
                refreshNearbyRoutes(cityCode: viewModel.selectedCity)
            }
            .sheet(item: $surveyExperience) { exp in surveySheetContent(exp: exp) }
            .alert(
                NSLocalizedString("addExperience.confirm.title", comment: "Add an experience here?"),
                isPresented: addExperienceAlertBinding
            ) {
                Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) {
                    viewModel.cancelAddExperience()
                }
                Button(NSLocalizedString("addExperience.confirm.add", comment: "Add")) {
                    viewModel.confirmAddExperienceWithForm()
                }
            } message: {
                Text(NSLocalizedString("addExperience.confirm.message", comment: "Describe it with your voice"))
            }
            .sheet(isPresented: createFormSheetBinding) { createFormSheetContent }
            .sheet(isPresented: recordExperienceSheetBinding) { recordExperienceSheetContent }
            .sheet(isPresented: detailSheetBinding) { detailSheetContent }
            .sheet(isPresented: $isShowingCityPicker) { cityPickerSheetContent }
            // City OS v2: KitSheet / LiveSheet presenters live on the OUTER
            // mapContent chain (never the inner ZStack) — SwiftUI silently drops
            // deeply-nested presenters when the outer chain already carries many
            // sheets (see the L1180-ish stacked-sheets note).
            .sheet(isPresented: $isShowingKitSheet, onDismiss: { kitSheetFocus = nil }) { kitSheetContent }
            .sheet(isPresented: $isShowingLiveSheet) { liveSheetContent }
            .sheet(item: $verifyTarget) { experience in
                VerifySheet(
                    placeName: experience.shortName,
                    onSubmit: { answers in submitVerification(answers, for: experience) },
                    onDismiss: { verifyTarget = nil }
                )
            }
            .sheet(isPresented: $isShowingFavorites) { favoritesSheetContent }
            // Bind the chat sheet to the orchestrator itself instead of a
            // separate Bool. With `.sheet(isPresented:)` the content closure
            // could be evaluated in the same render pass that flips the flag —
            // before the `@State` orchestrator write was observed — so `if let`
            // saw `nil` and presented a blank sheet (the intermittent white
            // page). `.sheet(item:)` only presents once the orchestrator is set
            // and hands a non-nil value to the content closure, killing the
            // race. The custom binding tears the orchestrator down on dismiss
            // (swipe or "X") so a future global "+" chat never inherits a
            // per-card <experience_context> block (US-004).
            .sheet(item: chatOrchestratorBinding) { orch in
                chatSheetContent(orch)
            }
            .sheet(isPresented: paywallSheetBinding, onDismiss: { viewModel.onPaywallUnlocked = nil }) { paywallSheetContent }
            // US-025 regression: the Routes-section commit (6655422) accidentally
            // dropped this line, leaving the bottom-left settings FAB inert — its
            // `isShowingSettings = true` had no presenter to observe it.
            .sheet(isPresented: settingsSheetBinding) { settingsSheetContent }
            // One sheet for both route flows (detail + create), driven by the
            // `routeSheet` enum. Hosted here on the outer `mapContent` chain — not
            // on the inner BottomInfoSheet ZStack — so SwiftUI arbitrates it
            // alongside the other top-level sheets instead of silently dropping a
            // deeply-nested presenter (which left RouteCards un-openable).
            .sheet(item: $routeSheet) { sheet in routeSheetContent(sheet) }
            // US-007: personal hub presented from the top-right map avatar bubble.
            .sheet(isPresented: $isShowingMe) {
                MeSheet(
                    pendingRequestCount: friendService.incomingRequests.count,
                    deepLinkConversationId: deepLinkConversationId
                )
            }
            .modifier(ExploreConsentSheetModifier(viewModel: viewModel, preferences: preferences))
    }

    /// Content for the route detail / create sheet, driven by `routeSheet`.
    /// Extracted so the presenter can live on the outer `mapContent` modifier
    /// chain (next to the other sheets) rather than buried on the inner
    /// BottomInfoSheet ZStack where SwiftUI's arbitration dropped it.
    @ViewBuilder
    private func routeSheetContent(_ sheet: RouteSheet) -> some View {
        switch sheet {
        case .detail(let route):
            NavigationStack {
                RouteDetailView(
                    route: route,
                    onTapStop: { exp in
                        routeSheet = nil
                        viewModel.selectExperience(exp)
                        viewModel.isShowingDetail = true
                    },
                    onStartRoute: { route in
                        routeSheet = nil
                        startRouteOnMap(route)
                    }
                )
                .environment(experienceService)
            }
        case .create:
            CreateRouteView(
                candidates: viewModel.visibleExperiences,
                cityCode: viewModel.selectedCity ?? "",
                userCoordinate: locationService.currentLocation?.coordinate
                    ?? viewModel.defaultCenterForSelectedCity
            ) { route in
                // Persist + open the new route's detail; RouteStore.didChange
                // refreshes the sheet's routes section automatically. Swapping
                // `routeSheet` from .create → .detail replaces content in place.
                routeStore.save(route)
                routeSheet = .detail(route)
            }
            .environment(aiService)
            .environment(experienceService)
        }
    }

    @ViewBuilder
    private var mapZStack: some View {
        ZStack {
            // US-021: `viewModel` is eager and non-optional, so the map renders
            // immediately — there is no `if let` / `ProgressView` placeholder
            // that could flicker before the map appears on cold launch.
            // Backing tile bleeds under every edge so the map looks
            // edge-to-edge; the `Map` view itself also extends to every edge
            // (V-006) so tiles — not the flat theme background — render in the
            // top status-bar region.
            themeService.currentTheme.background
                .ignoresSafeArea()
            // V-006 fix: the map must fill ALL edges — including the top safe
            // area — so real street tiles render under the status bar. The map
            // previously kept its top inset (only `.bottom, .horizontal`), which
            // left the status-bar-height strip showing the flat theme background
            // (a dark band in dark mode, the "NORTH BEACH band"). `.mapControls`
            // still avoid the status bar because they are laid out against the
            // map's layout margins, which honour the safe area regardless of
            // `.ignoresSafeArea`. The overlay content (city pill / filter bar)
            // is a sibling layer that keeps its own safe-area inset, so nothing
            // collides with the status bar.
            mapLayer(viewModel: viewModel)
                .ignoresSafeArea()

                // City OS v2: in Plan mode the whole map cools to a considered,
                // "you're not here yet" register — a soft blue-white wash that
                // crossfades in over 350ms and never blocks touches.
                if FeatureFlags.cityOS && currentCityMode == .plan {
                    CT.modePlanBlue.opacity(0.06)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                MapOverlayView(
                    viewModel: viewModel,
                    isAIProcessing: aiService.isProcessing,
                    cityModeLine: cityPillModeLine,
                    cityStageIndex: cityPillStageIndex,
                    isShowingCityPicker: $isShowingCityPicker,
                    dismissedAIError: $dismissedAIError,
                    dismissedExploreError: $dismissedExploreError,
                    dismissedQuotaInfo: $dismissedQuotaInfo,
                    dismissedLocationError: $dismissedLocationError,
                    isMapPanning: $isMapPanning,
                    mapStyleChoice: $mapStyleChoice,
                    pendingRequestCount: friendService.incomingRequests.count,
                    onTapAvatar: { isShowingMe = true }
                )

                VStack {
                    Spacer()
                    // US-017 / US-009: Companion layer toggle — only rendered when
                    // the companion-layer flag is on. Hidden by default (decision A)
                    // because the underlying discovery still returns nil, so the
                    // control would be a dead button.
                    if FeatureFlags.companionLayerEnabled {
                        HStack {
                            Spacer()
                            CompanionLayerToggle(
                                isLayerOn: $isCompanionLayerOn,
                                presenceActive: presenceService.isActive,
                                companionEnabled: FeatureFlags.companion
                            )
                            .padding(.trailing, 16)
                        }
                        .padding(.bottom, 4)
                        .onAppear {
                            #if DEBUG
                            CompassMapView.debugCompanionLayerToggleRendered = true
                            #endif
                        }
                    }
                    MapControlBar(
                        viewModel: viewModel,
                        aiService: aiService,
                        voiceService: voiceService,
                        preferences: preferences,
                        voiceOrchestrator: $voiceOrchestrator,
                        onOpenChat: { mode in
                            // Set the mode *before* creating the orchestrator:
                            // assigning `voiceOrchestrator` is what presents the
                            // `.sheet(item:)`, so `chatStartMode` must already be
                            // correct when the sheet content is first evaluated.
                            chatStartMode = mode
                            ensureOrchestrator(viewModel: viewModel)
                        },
                        bottomInset: controlBarBottomInset
                    )
                }
                .onChange(of: isCompanionLayerOn) { _, on in
                    if on {
                        Task { await fetchNearbyCells(viewModel: viewModel) }
                    } else {
                        nearbyCells = []
                    }
                }

                // Slice C fix: an Explore session in flight already promises
                // "we're scanning" via the top pill (`ExploreModeOverlay`) and
                // a live radius ring — the "Quiet patch of map · try wider"
                // empty state directly contradicts that promise if it renders
                // in the same frame. Rubric evidence caught this at t=5 s
                // and t=13 s (Scanning · 1 km / 5 km pill on top, "Showing
                // within 8 km — Expand to 25 km" empty state on bottom).
                // Suppress the empty state while the session is active; the
                // pill already covers "we're working" and the ring shows
                // reach. When the session ends and STILL yields zero, the
                // real empty state re-appears — that's the honest fallback.
                if viewModel.visibleExperiences.isEmpty
                    && !isFilterActive
                    && !viewModel.exploreSession.isActive {
                    VStack {
                        Spacer()
                        EmptyStateOverlay(
                            viewModel: viewModel,
                            preferences: preferences,
                            locationService: locationService
                        )
                        .padding(.bottom, sheetPeekClearance + 16)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeOut(duration: 0.35), value: viewModel.visibleExperiences.isEmpty)
                } else if viewModel.visibleExperiences.isEmpty && isFilterActive && viewModel.selectedExperience == nil
                    && viewModel.highlightedEventId == nil {
                    if viewModel.isNowFilter {
                        VStack {
                            Spacer()
                            NowEmptyOverlay(viewModel: viewModel)
                                .padding(.bottom, sheetPeekClearance + 16 + (cityOSBottomSlotOccupied ? 52 : 0))
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.easeOut(duration: 0.35), value: viewModel.visibleExperiences.isEmpty)
                    } else {
                        VStack {
                            Spacer()
                            FilteredEmptyOverlay(viewModel: viewModel)
                                .padding(.bottom, sheetPeekClearance + 16 + (cityOSBottomSlotOccupied ? 52 : 0))
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.easeOut(duration: 0.35), value: viewModel.visibleExperiences.isEmpty)
                    }
                }

                // Offline banner (US-041): amber pill when network is unavailable
                if !networkMonitor.isConnected {
                    VStack {
                        OfflineBanner(onRetry: {
                            viewModel.loadNearbyExperiences()
                        })
                        .padding(.top, 8)
                        Spacer()
                    }
                    .animation(.easeInOut, value: networkMonitor.isConnected)
                } else if viewModel.isFetchingPOIs {
                    // POI loading banner (#134): only while online — offline
                    // never fetches, and the offline pill already owns the slot.
                    VStack {
                        POILoadingBanner()
                            .padding(.top, 8)
                        Spacer()
                    }
                    .animation(.easeInOut, value: viewModel.isFetchingPOIs)
                } else if shouldShowComplianceBanner {
                    // City OS v2 compliance banner (§4.3): the lowest rung of the
                    // top-banner ladder (offline > POI loading > compliance) so it
                    // never stacks with either. Its first appearance of the day
                    // consumes the interruption budget in `.onAppear` below.
                    VStack {
                        ComplianceBanner(
                            daysRemaining: complianceService.state()?.visaDaysRemaining ?? 0,
                            onHandle: {
                                kitSheetFocus = .visa
                                isShowingKitSheet = true
                            },
                            onDismiss: {
                                withAnimation(.easeInOut) { complianceBannerDismissed = true }
                            }
                        )
                        .padding(.top, 8)
                        .onAppear { consumeComplianceBudgetOncePerDay() }
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                ZStack(alignment: .bottom) {
                    BottomInfoSheet(
                        aiHint: viewModel.isNowFilter
                            ? NSLocalizedString("sheet.now.headline", comment: "Bottom sheet now-mode headline")
                            : NSLocalizedString("ai.now.hint", comment: "AI now hint"),
                        count: viewModel.isNowFilter
                            ? viewModel.nowCount
                            : viewModel.visibleExperiences.count,
                        isNowMode: viewModel.isNowFilter,
                        peekExperience: peekExperience,
                        isSmartPick: peekExperienceIsSmartPick,
                        referenceCoordinate: locationService.currentLocation?.coordinate
                            ?? viewModel.defaultCenterForSelectedCity,
                        referenceIsUserLocation: locationService.currentLocation != nil,
                        // D 双卡片冲突: while the floating preview card is up for
                        // a user-selected experience, the peek summary card
                        // yields so only one "best pick" card is on screen.
                        isPreviewActive: viewModel.selectedExperience != nil
                            && !viewModel.isShowingDetail,
                        onShuffle: {
                            guard let current = peekExperience else { return }
                            let shuffled = peekShuffledIds + [current.id]
                            let visibleIds = Set(viewModel.visibleExperiences.map(\.id))
                            // Cycled through everything visible → restart the
                            // rotation so "换一个" never comes back empty-handed.
                            peekShuffledIds = visibleIds.subtracting(shuffled).isEmpty
                                ? []
                                : shuffled
                        },
                        onRefresh: {
                            viewModel.loadNearbyExperiences()
                        },
                        onDetentChange: { detent in
                            if sheetDetent != detent { sheetDetent = detent }
                        }
                    ) { detent, sortMode in
                        if detent != .peek {
                            VStack(spacing: 0) {
                                // 路线图仅在 Now / 当下栏目出现 — routes are a
                                // time-sensitive "what should I walk right now"
                                // artifact, meaningless outside the Now context.
                                // In every other sort mode the Routes section and
                                // the create-route entry are hidden entirely, so the
                                // sheet shows only 附近 there. Inside this branch
                                // `isNowFilter` is always true. Gating goes through
                                // the testable `shouldShowRoutesSection` helper.
                                if Self.shouldShowRoutesSection(isNowFilter: viewModel.isNowFilter) {
                                    // US-025: Routes section above Nearby (non-scrollable header rows)
                                    RoutesSection(
                                        routes: nearbyRoutes,
                                        isNowFilter: true,
                                        onSelectRoute: { route in
                                            routeSheet = .detail(route)
                                        },
                                        // Direction 3 — cold start in Now mode: when
                                        // RoutesSection finds zero displayed items it
                                        // renders NowEmptyRoutePlaceholder; its CTA must
                                        // hit the same flow as CreateRouteEntryCard
                                        // below so we keep a single create-route code
                                        // path (no new orchestration).
                                        onProposeRoute: {
                                            routeSheet = .create
                                        }
                                    )

                                    // Create-your-own-route entry, between Routes and Nearby.
                                    CreateRouteEntryCard {
                                        routeSheet = .create
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.top, 8)
                                }

                                NearbySection(
                                    experiences: viewModel.visibleExperiences,
                                    smartPickIds: viewModel.aiSmartPickIds,
                                    referenceCoordinate: locationService.currentLocation?.coordinate
                                        ?? viewModel.defaultCenterForSelectedCity,
                                    sortMode: sortMode.wrappedValue,
                                    // US-036: divider above the Nearby header separates it from
                                    // Routes — but only when Routes is actually shown (Now mode).
                                    // Outside Now the Routes section is hidden, so the divider would
                                    // dangle above the very first section; suppress it there.
                                    showsSectionDivider: viewModel.isNowFilter,
                                    isLoading: viewModel.isFetchingPOIs,
                                    isNowFilter: viewModel.isNowFilter,
                                    onExploreElsewhere: {
                                        // Zoom the map out one step by doubling the visible span,
                                        // capped at ±90° lat / ±180° lon, so out-of-range
                                        // experiences scroll into view.
                                        if let region = viewModel.cameraPosition.region {
                                            let newSpan = MKCoordinateSpan(
                                                latitudeDelta: min(region.span.latitudeDelta * 2, 90),
                                                longitudeDelta: min(region.span.longitudeDelta * 2, 180)
                                            )
                                            viewModel.cameraPosition = .region(
                                                MKCoordinateRegion(center: region.center, span: newSpan)
                                            )
                                        }
                                    },
                                    suggestedCityName: viewModel.suggestedCityName,
                                    onSwitchToSuggestedCity: viewModel.suggestedCityCode.map { code in
                                        { viewModel.selectCity(code) }
                                    },
                                    onSelectExperience: { exp in
                                        // Tap → jump straight to the detail sheet.
                                        // (Long-press floats the preview card via
                                        // onLongPressExperience below.) The list
                                        // row and a map-pin tap stay consistent:
                                        // both open detail on tap, both peek on
                                        // long-press. withAnimation drives the
                                        // detail content transition.
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                            viewModel.openExperienceDetail(exp)
                                        }
                                    },
                                    onLongPressExperience: { exp in
                                        // Context-menu "show on map" → float the
                                        // quick preview card (the former tap
                                        // behavior). Backing out of detail still
                                        // lands on this card.
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                            viewModel.selectExperience(exp)
                                        }
                                    },
                                    onAskSoloExperience: { exp in
                                        // Context-menu "问 Solo" → open a chat
                                        // scoped to this place (same path as the
                                        // detail sheet's Ask-Solo button): ensure
                                        // the orchestrator, then inject the
                                        // <experience_context> block before the
                                        // sheet content evaluates.
                                        chatStartMode = .text
                                        ensureOrchestrator(viewModel: viewModel)
                                        voiceOrchestrator?.rebindContext(exp)
                                    }
                                )
                            }
                        }
                    }
                }
                .ignoresSafeArea(edges: .bottom)
                // NOTE: the `routeSheet` presenter is intentionally NOT attached
                // here. When `.sheet(item: $routeSheet)` was hosted on this inner
                // nested ZStack while the outer `mapContent` chain already carried
                // ~8 `.sheet`/`.fullScreenCover` modifiers, SwiftUI's presentation
                // arbitration silently dropped this deeply-nested presenter — so
                // tapping a RouteCard flipped `routeSheet = .detail(route)` but no
                // sheet ever appeared (the route cards "點不進去"). It now lives on
                // the outer chain next to the other sheets — see `routeSheetContent`.
                // Kin to [[project_stacked_sheets_only_last_wins]].

                // Selected-experience card floats ABOVE the BottomInfoSheet
                // (declared after it → higher z-order) and rests on a Dynamic-
                // Type-aware inset so its Solo-Score row is never clipped by the
                // sheet's peek height. Previously declared before the sheet with
                // a fixed 80pt inset, which let the sheet occlude its lower edge.
                if let selected = viewModel.selectedExperience, !viewModel.isShowingDetail {
                    VStack {
                        Spacer()
                        ExperienceCardView(
                            experience: selected,
                            onExpand: { viewModel.isShowingDetail = true },
                            onDismiss: {
                                // The card's own dismiss is the only place the
                                // selection is fully cleared — detail dismiss
                                // falls back to this card, not to the bare map.
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    viewModel.clearSelection()
                                }
                            },
                            onRecompile: {
                                Task { await viewModel.recompileExperience(selected) }
                            },
                            isRecompiling: viewModel.recompilingExperienceId == selected.id,
                            onRecenter: { _ in
                                viewModel.focusOnExperience(selected)
                            }
                        )
                        .padding(.bottom, cardBottomInset)
                    }
                    // Pop-out entrance: the card scales up from a slightly
                    // smaller, bottom-anchored state while rising — paired with
                    // the spring driving `selectExperience` on long-press, it
                    // reads as the card springing out of the pressed pin rather
                    // than sliding flatly up from the screen edge. reduceMotion
                    // collapses this to a plain fade.
                    .transition(reduceMotion
                        ? .opacity
                        : .scale(scale: 0.92, anchor: .bottom)
                            .combined(with: .move(edge: .bottom))
                            .combined(with: .opacity))
                    // Approach C (peek parity): the floating card is reachable
                    // without ever opening the full detail sheet (long-press
                    // peek, nearby-list tap). Mirror the detail sheet's
                    // auto-upgrade so a shallow OSM skeleton silently deep
                    // cross-compiles in the background here too — otherwise a
                    // user who only peeks the card is stuck on the "real place
                    // from OpenStreetMap" template forever. No-op for Pro-less
                    // users, already-rich cards, or cards upgraded earlier this
                    // session — autoUpgradeExperience enforces all three.
                    .task(id: selected.id) {
                        await viewModel.autoUpgradeExperience(selected)
                    }
                }

                // City OS v2: the floating slot above the peek sheet holds either
                // the two drawer tabs (Live mode) or a Plan/Recall placeholder
                // card (other modes). Both sit clear of the peek sheet via the
                // Dynamic-Type-aware inset and never coexist with a selection card
                // (their guards are mutually exclusive with `selectedExperience`).
                if FeatureFlags.cityOS {
                    if shouldShowDrawerTabs {
                        VStack {
                            Spacer()
                            CityDrawerTabs(
                                kitCount: cityBriefService.kit.count,
                                eventCount: cityBriefService.activeEvents().count,
                                onOpenKit: {
                                    kitSheetFocus = nil
                                    isShowingKitSheet = true
                                },
                                onOpenLive: { isShowingLiveSheet = true }
                            )
                            .padding(.bottom, drawerTabsBottomInset)
                        }
                        .transition(.opacity)
                    } else if currentCityMode != .live
                        && sheetDetent == .peek
                        && viewModel.selectedExperience == nil {
                        VStack {
                            Spacer()
                            Group {
                                if currentCityMode == .plan {
                                    PlanCard(
                                        cityName: currentCityDisplayName,
                                        doneCount: viewModel.selectedCity.map {
                                            cityOSStore.kitTodoDoneCount(cityCode: $0, kit: cityBriefService.kit)
                                        } ?? 0,
                                        totalCount: cityBriefService.kit.count,
                                        onOpenKit: { isShowingKitSheet = true }
                                    )
                                } else {
                                    RecallCard(
                                        cityName: currentCityDisplayName,
                                        visitedCount: recallVisited.count,
                                        pendingCount: recallPending.count,
                                        nextPendingName: recallPending.first?.shortName,
                                        onVerifyNext: { verifyTarget = recallPending.first },
                                        onOpenKit: { isShowingKitSheet = true }
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, drawerTabsBottomInset)
                        }
                        .transition(.opacity)
                    }
                }

                // City OS v3 toast (印证 confirmation). Floats above the dock
                // slot; purely informational, never intercepts touches.
                if let cityOSToast {
                    VStack {
                        Spacer()
                        Text(cityOSToast)
                            .font(CT.body(13, .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(CT.accent))
                            .padding(.bottom, drawerTabsBottomInset + 62)
                    }
                    .allowsHitTesting(false)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
                }

                // Active-route banner: a pill naming the walk with an end button.
                // Floats above the map; tapping ⨯ clears the polyline. It sits
                // BELOW the city pill + filter bar (offset by the filter bar's
                // bottom edge) so it never overlaps the top controls — including
                // at large Dynamic Type, where a top-pinned banner would collide.
                // `.zIndex` keeps it above every other overlay layer.
                if let active = activeRoute {
                    VStack {
                        ActiveRouteBanner(
                            title: active.route.title,
                            stopCount: active.coordinates.count,
                            onSkip: {
                                // Drop the current stop without crediting it
                                // as completed — see RouteStore.skipStop docs.
                                routeStore.skipStop(active.route.id)
                            },
                            onPause: {
                                // Pause: keep progress, clear activeStartedAt
                                // so loadActiveRoute stops returning it. The
                                // banner stays mounted; user can resume from
                                // the route list. Live Activity ends so the
                                // island doesn't lie about being in-progress.
                                routeStore.pauseRoute(active.route.id)
                                Task { await LiveActivityService.shared.end() }
                            },
                            onEnd: {
                                withAnimation(.easeInOut(duration: 0.25)) { activeRoute = nil }
                                // US-026: tear down the route Live Activity too.
                                Task { await LiveActivityService.shared.end() }
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, MapOverlayMetrics.filterBarTopOffset
                            + MapOverlayMetrics.filterBarHeight + 8)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
                }

                // Startup self-diagnostics banner — slides down from beneath
                // the filter bar, system-notification style. `SoloAgentBubbleView`
                // uses `@Bindable` on the queue so its own body observes head
                // changes; we don't gate the outer VStack (that would need
                // a manual observation seam here).
                VStack {
                    SoloAgentBubbleView(queue: agentBubbleQueue, onTapCTA: { bubble in
                        if let svc = diagnostics {
                            pendingDiagnosticsPrompt = svc
                                .chatSeedPrompt(for: svc.lastRunFindings)
                        }
                        agentBubbleQueue.dismiss(id: bubble.id)
                        chatStartMode = .text
                        ensureOrchestrator(viewModel: viewModel)
                    })
                    .padding(.horizontal, 16)
                    .padding(.top, MapOverlayMetrics.filterBarTopOffset
                        + MapOverlayMetrics.filterBarHeight + 8)
                    Spacer()
                }
                .allowsHitTesting(agentBubbleQueue.items.isEmpty ? false : true)
                .zIndex(12)

            // Slice C: Explore-Mode overlay. Renders top pill + Cancel FAB
            // only while an Explore session is in `.active`. Handoff card &
            // cancelled banner sit on top (higher zIndex) so they can take
            // over the stage when the scan finishes or the user bails.
            if viewModel.exploreSession.isActive,
               case .active = viewModel.exploreSession.state {
                ExploreModeOverlay(
                    session: viewModel.exploreSession,
                    cityDisplayName: viewModel.currentDisplayCityName,
                    onCancel: { viewModel.exploreCancel() }
                )
                .zIndex(20)
                .transition(.opacity)
            }

            // Handoff card — the result-set surface that replaces the
            // 3-second toast. Ranks: Ask Solo (primary) → Save as walk →
            // Expand radius → Clear these. 10-second idle auto-minimize.
            if let handoff = viewModel.exploreSession.handoffResult {
                ExploreHandoffCard(
                    result: handoff,
                    onAskSolo: {
                        viewModel.exploreClearHandoff()
                        chatStartMode = .text
                        ensureOrchestrator(viewModel: viewModel)
                    },
                    onSaveWalk: {
                        // Freeze the batch into a route candidate set.
                        // CreateRouteView pulls its candidates from
                        // `viewModel.visibleExperiences`, which already
                        // contains the added set at this point.
                        viewModel.exploreClearHandoff()
                        routeSheet = .create
                    },
                    onExpand: {
                        viewModel.exploreClearHandoff()
                        Task { _ = await viewModel.expandOneStage() }
                    },
                    onClear: {
                        viewModel.exploreDiscardHandoff()
                    },
                    onDismiss: {
                        viewModel.exploreClearHandoff()
                    }
                )
                .zIndex(25)
            }
        }
        // City OS v2: crossfade the Plan wash + the mode-dependent floating slot
        // (drawer tabs ⇄ placeholder cards) when the traveler flips city mode.
        .animation(.easeInOut(duration: 0.35), value: currentCityMode)
    }

    // MARK: - Sheet Bindings

    private var settingsSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isShowingSettings },
            set: { if !$0 { viewModel.isShowingSettings = false } }
        )
    }

    private var addExperienceAlertBinding: Binding<Bool> {
        Binding(
            get: {
                (viewModel.pendingAddCoordinate != nil)
                    && !viewModel.isRecordingNewExperience
                    && !viewModel.isShowingCreateForm
            },
            set: { if !$0 { viewModel.cancelAddExperience() } }
        )
    }

    /// Drives the structured create-place form. Presents only when the user
    /// confirmed the long-press AND a coordinate is pending. On dismiss we only
    /// tear down the add-flow if the user isn't switching to the voice path —
    /// otherwise cancelling here would clear the pending coordinate before the
    /// voice sheet could open.
    private var createFormSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isShowingCreateForm && viewModel.pendingAddCoordinate != nil },
            set: { presenting in
                guard !presenting else { return }
                viewModel.isShowingCreateForm = false
                if !viewModel.isRecordingNewExperience {
                    viewModel.cancelAddExperience()
                }
            }
        )
    }

    private var recordExperienceSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isRecordingNewExperience },
            set: { if !$0 { viewModel.cancelAddExperience() } }
        )
    }

    private var detailSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isShowingDetail },
            // Route swipe-to-dismiss through dismissDetail() too, matching the
            // chevron close button: both peel off only the detail layer and
            // fall back to the floating preview card (selection retained).
            set: { if !$0 { viewModel.dismissDetail() } }
        )
    }

    private var paywallSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isShowingPaywall },
            set: { if !$0 { viewModel.isShowingPaywall = false } }
        )
    }

    // MARK: - Sheet Contents

    @ViewBuilder
    private var settingsSheetContent: some View {
        SettingsView(
            onClose: { viewModel.isShowingSettings = false },
            onShowFavorites: { isShowingFavorites = true },
            onDistanceCommitted: { viewModel.reloadForDistanceChange() }
        )
        .environment(preferences)
        .environment(notificationService)
        #if DEBUG
        .onAppear { CompassMapView.debugSettingsSheetRendered = true }
        #endif
    }

    @ViewBuilder
    private func surveySheetContent(exp: Experience) -> some View {
        MicroSurveySheet(
            experience: exp,
            onSubmit: { comfort, pressure, recommend in
                // US-020: persist via the repo so the aggregated
                // SoloScore reflects this immediately.
                experienceService.repo.recordSurvey(
                    experienceId: exp.id,
                    comfort: comfort,
                    pressure: pressure,
                    recommend: recommend.rawValue,
                    anonDeviceId: DeviceIdentityService.shared.deviceID
                )
                surveyExperience = nil
            },
            onSkip: { surveyExperience = nil }
        )
    }

    @ViewBuilder
    private var createFormSheetContent: some View {
        if let coordinate = viewModel.pendingAddCoordinate {
            CreateExperienceSheet(
                coordinate: coordinate,
                onSave: { input in viewModel.createUserExperience(from: input) },
                onUseVoice: { viewModel.confirmAddExperience() },
                onCancel: { viewModel.cancelAddExperience() }
            )
        }
    }

    @ViewBuilder
    private var recordExperienceSheetContent: some View {
        VStack(spacing: 24) {
            Text(NSLocalizedString("addExperience.record.title", comment: "Tell us about this place"))
                .font(.headline)
            Text(NSLocalizedString("addExperience.record.hint", comment: "Hold the mic and describe what makes it worth a solo visit"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VoiceButton(voiceService: voiceService) { transcript in
                Task { await viewModel.handleNewExperienceTranscript(transcript) }
            }
        }
        .padding(32)
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private var detailSheetContent: some View {
        if let exp = viewModel.selectedExperience {
            NavigationStack {
                ExperienceDetailView(
                    viewModel: ExperienceDetailViewModel(
                        experience: exp,
                        experienceService: experienceService,
                        aiService: aiService,
                        preferences: preferences,
                        subscriptionService: subscriptionService
                    ),
                    onClose: { viewModel.dismissDetail() },
                    onMarkDone: { experience in surveyExperience = experience },
                    // US-004: open ChatSheet bound to this experience. We
                    // dismiss the detail sheet first so the chat sheet can
                    // come up cleanly (iOS won't stack two .sheet()s on the
                    // same parent reliably). The orchestrator is lazily
                    // created if needed, then `rebindContext` injects the
                    // <experience_context> system block.
                    onAskSolo: { experience in
                        viewModel.dismissDetail()
                        // Per-card chat stays text-first. Set mode before the
                        // orchestrator assignment presents the sheet, then
                        // rebind the experience scope (still synchronous, so it
                        // lands before the sheet content is evaluated).
                        chatStartMode = .text
                        ensureOrchestrator(viewModel: viewModel)
                        voiceOrchestrator?.rebindContext(experience)
                    },
                    onSelectExperience: { experience in
                        // In-detail "nearby" tap swaps the featured experience.
                        // withAnimation drives the .id-keyed content transition
                        // below so the switch is perceptible, not a silent
                        // data swap. (B 详情内切体验加转场)
                        withAnimation(.easeInOut(duration: 0.3)) {
                            viewModel.selectExperience(experience)
                        }
                    },
                    // Detail-sheet parity with the floating card's recompile
                    // menu: same MapViewModel work, same in-flight flag.
                    onRecompile: {
                        Task { await viewModel.recompileExperience(exp) }
                    },
                    isRecompiling: viewModel.recompilingExperienceId == exp.id
                )
                // Bind SwiftUI identity to the experience so selecting a
                // different one rebuilds the detail view AND its @State
                // view model. Without this, ExperienceDetailView's @State
                // viewModel kept the original experience and an in-detail
                // "nearby" tap changed nothing on screen. The transition
                // gives the rebuild a visible cross-fade + slide.
                //
                // `updatedAt` is folded into the identity so an in-place
                // recompile (which keeps the same id via `adoptingContent` and
                // only bumps `updatedAt`) also rebuilds the @State view model —
                // otherwise the menu's deep cross-compile would swap the backing
                // experience but the sheet would keep rendering the stale
                // skeleton copy it snapshotted at init.
                .id("\(exp.id)-\(exp.updatedAt.timeIntervalSince1970)")
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
            // Approach C: when the detail sheet opens for a shallow (not yet
            // AI-enriched) place, silently deep cross-compile it in the
            // background and upgrade the content in place. No-op for Pro-less
            // users, already-rich cards, or cards upgraded earlier this
            // session — autoUpgradeExperience enforces all three.
            .task(id: exp.id) {
                await viewModel.autoUpgradeExperience(exp)
            }
        }
    }

    @ViewBuilder
    private var cityPickerSheetContent: some View {
        LocationPickerSheet(
            viewModel: viewModel,
            cityOSStore: FeatureFlags.cityOS ? cityOSStore : nil
        ) {
            isShowingCityPicker = false
        }
    }

    // MARK: - City OS v2 sheet content

    @ViewBuilder
    private var kitSheetContent: some View {
        KitSheet(
            kit: cityBriefService.kit,
            preferences: preferences,
            complianceService: complianceService,
            focusKind: kitSheetFocus,
            planMode: currentCityMode == .plan,
            isTodoDone: { kind in
                guard let city = viewModel.selectedCity else { return false }
                return cityOSStore.isKitTodoDone(kind, cityCode: city)
            },
            onToggleTodo: { kind in
                guard let city = viewModel.selectedCity else { return }
                cityOSStore.toggleKitTodo(kind, cityCode: city)
            },
            onDismiss: { isShowingKitSheet = false }
        )
    }

    @ViewBuilder
    private var liveSheetContent: some View {
        LiveSheet(
            events: cityBriefService.activeEvents(),
            onShowOnMap: { event in
                isShowingLiveSheet = false
                focusEventOnMap(event)
            },
            onDismiss: { isShowingLiveSheet = false }
        )
    }

    /// Recenter the camera on an event and highlight its marker (shared by the
    /// live sheet and the chat event card).
    private func focusEventOnMap(_ event: CityEvent) {
        guard let lat = event.lat, let lng = event.lng else { return }
        withAnimation(.easeInOut(duration: 0.4)) {
            viewModel.cameraPosition = .region(MKCoordinateRegion(
                // Bias the centre south of the pin so it settles in the upper
                // third of the screen — the lower half is owned by the peek
                // sheet + floating chrome, which would otherwise cover the
                // very marker the user asked to see.
                center: CLLocationCoordinate2D(latitude: lat - 0.002, longitude: lng),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        }
        viewModel.highlightedEventId = event.id
        // The glow (and the empty-card quieting it triggers) is a transient
        // "look here" cue, not a mode — release it after a beat so the Now
        // card comes back without requiring a city switch.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(18))
            if viewModel.highlightedEventId == event.id {
                withAnimation(.easeInOut(duration: 0.35)) {
                    viewModel.highlightedEventId = nil
                }
            }
        }
    }

    @ViewBuilder
    private var favoritesSheetContent: some View {
        FavoritesListView(
            onSelectExperience: { exp in
                isShowingFavorites = false
                // Tap → open the detail sheet directly (long-press peeks instead).
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    viewModel.openExperienceDetail(exp)
                }
            },
            onLongPressExperience: { exp in
                isShowingFavorites = false
                // Long-press → float the quick preview card (former tap behavior).
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    viewModel.selectExperience(exp)
                }
            },
            onExplore: { isShowingFavorites = false }
        )
        .environment(experienceService)
        .environment(preferences)
    }

    // MARK: - Start route on map

    private static let routeLog = OSLog(subsystem: "com.solocompass.app", category: "RouteOnMap")

    /// Resolve a route's stops to coordinates, store them as the active route so
    /// the map draws the polyline + numbered pins, and frame the camera around
    /// the whole walk. Called when the traveler taps "开始路线".
    private func startRouteOnMap(_ route: Route) {
        let resolved = route.experienceIds
            .map { (id: $0, coord: experienceService.getExperience(id: $0)?.coordinate) }
        let coords = resolved.compactMap(\.coord)
        guard !coords.isEmpty else {
            // No geocoded stops at all — nothing to draw. Clear any prior route and
            // surface the failure (a stale/broken route) instead of a silent no-op,
            // which reads to the user as "开始路线 did nothing".
            os_log(
                "startRouteOnMap: route %{public}@ has 0 resolvable stops (ids=%{public}@) — nothing drawn",
                log: Self.routeLog, type: .error,
                route.id.rawValue, route.experienceIds.joined(separator: ",")
            )
            activeRoute = nil
            return
        }
        // Partial resolution: the polyline silently bridges the gap (stop 1 → stop 3
        // if stop 2 is missing), which misrepresents the walk. We still draw what we
        // can but log the dropped stops so the data drift is visible, not silent.
        let missing = resolved.filter { $0.coord == nil }.map(\.id)
        if !missing.isEmpty {
            os_log(
                "startRouteOnMap: route %{public}@ drew %d/%d stops; unresolved=%{public}@",
                log: Self.routeLog, type: .info,
                route.id.rawValue, coords.count, route.experienceIds.count,
                missing.joined(separator: ",")
            )
        }
        // 1 stop → no polyline (handled by the Map's count>=2 guard) but we still
        // mark the stop and fly there, so "start" always gives visible feedback.
        activeRoute = ActiveRoute(route: route, coordinates: coords)
        viewModel.cameraPosition = .region(Self.region(enclosing: coords))
        HapticService.shared.impact(style: .medium)

        // #80: Persist the active-route progress so a cold-start can resume
        // where the user left off. RouteStore.startRoute stamps activeStartedAt
        // + zeros currentStopIndex / completedStopIds; pairs with the
        // .onAppear cold-start hydration (see resumeActiveRouteIfNeeded) and
        // the skipStop / pauseRoute / advanceStop calls from the banner +
        // geofence. Without this call the entire Beta-P0-A persistence
        // contract was dead-on-arrival — only tests exercised it.
        routeStore.startRoute(route.id)

        // US-026: start the "路线进行中" Live Activity so the next stop, walking
        // ETA, and overall progress live in the Dynamic Island. The first stop's
        // short place name (never its long title sentence) heads the card.
        let firstStop = route.experienceIds.first.flatMap { experienceService.getExperience(id: $0) }
        let firstStopName = firstStop.map { $0.location.placeNameRomanized ?? $0.location.placeNameLocal ?? $0.title }
            ?? route.title
        // Rough first-leg ETA: ~1/N of the route's estimated duration from now.
        let legMinutes = max(1, route.estimatedDuration / max(coords.count, 1))
        let eta = Date().addingTimeInterval(Double(legMinutes) * 60)
        let etaText = Self.islandTimeFormatter.string(from: eta)
        LiveActivityService.shared.startRoute(
            routeTitle: route.title,
            nextStopName: firstStopName,
            nextStopMeta: "步行约 \(legMinutes) 分 · 共 \(coords.count) 站",
            etaText: etaText,
            currentStopIndex: 1,
            totalStops: coords.count
        )
    }

    /// Triggered by `LocationService.routeStopEntered` (200m geofence around
    /// any active-route experience). Advances persisted progress and refreshes
    /// the Dynamic Island so the user gets immediate "你已到达" feedback. If
    /// the entered experience is the last stop, ends the Live Activity.
    @MainActor
    private func handleRouteStopEntered(experienceId: String) async {
        guard let (route, _, _) = routeStore.loadActiveRoute() else { return }
        guard let arrivedIndex = route.experienceIds.firstIndex(of: experienceId) else { return }

        routeStore.advanceStop(route.id, completedExperienceId: experienceId)

        let totalStops = route.experienceIds.count
        let nextIndex = arrivedIndex + 1
        if nextIndex >= totalStops {
            // Last stop — close out the activity; CompletionMoment / UI flow
            // takes over for the回顾.
            await LiveActivityService.shared.end()
            return
        }

        // Otherwise refresh the island with the *next* stop's data.
        let nextExpId = route.experienceIds[nextIndex]
        guard let nextExp = experienceService.getExperience(id: nextExpId) else { return }
        let nextName = nextExp.location.placeNameRomanized
            ?? nextExp.location.placeNameLocal
            ?? nextExp.title
        let legMinutes = max(1, route.estimatedDuration / max(totalStops, 1))
        let etaText = Self.islandTimeFormatter.string(from: Date().addingTimeInterval(Double(legMinutes) * 60))
        await LiveActivityService.shared.updateRoute(
            nextStopName: nextName,
            nextStopMeta: "步行约 \(legMinutes) 分 · 还剩 \(totalStops - nextIndex) 站",
            etaText: etaText,
            currentStopIndex: nextIndex + 1, // 1-indexed for human display
            totalStops: totalStops
        )
    }

    /// HH:mm formatter for Live Activity ETAs — fixed 24h so the island reads
    /// the same regardless of the device's 12/24-hour setting.
    private static let islandTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    #if DEBUG
    /// Start a sample Live Activity for the `-startIsland <kind>` launch arg, so
    /// the Dynamic Island can be verified on a simulator/device without driving
    /// the real trigger flow. Sample copy mirrors the design handoff.
    @MainActor
    static func startIslandDemo(kind: String) {
        switch kind {
        case "route":
            LiveActivityService.shared.startRoute(
                routeTitle: "湄公河日落散步", nextStopName: "昭阿努翁雕像",
                nextStopMeta: "步行 7 分 · 540 m", etaText: "17:49",
                currentStopIndex: 2, totalStops: 3
            )
        case "countdown":
            LiveActivityService.shared.startCountdown(
                groupTitle: "同伴团 · 30 分钟后集合", meetPointName: "昭阿努翁雕像",
                departureDate: Date().addingTimeInterval(29 * 60 + 14),
                memberInitials: ["M", "你", "T"], memberSummary: "Maya(主理) · 你 · Tomas"
            )
        case "recording":
            LiveActivityService.shared.beginRecordingSession(locality: "万象 河堤") { 0.6 }
        case "compile":
            LiveActivityService.shared.startCompile(
                title: "正在编排今日页面", subtitle: "12 条 signal · 3 个地点"
            )
        default:
            break
        }
    }
    #endif

    /// Radius (meters) of the translucent circle drawn around the traveler's
    /// own location marker. ~120m reads as a comfortable "right here" bubble at
    /// typical street-level zoom without swallowing nearby POI markers. The
    /// marker dot itself is a fixed on-screen size (`UserLocationMarker`); this
    /// circle is the one that scales with the map to convey real distance.
    private static let userRadiusMeters: CLLocationDistance = 120

    /// Minimum half-comfortable region span (~1.1 km at the equator). Used as the
    /// floor for a route's bounding box so a single-stop route — or stops that sit
    /// almost on top of each other — frames at a sensible street-level zoom rather
    /// than slamming all the way in.
    private static let minRegionSpan: CLLocationDegrees = 0.01

    /// A region that comfortably encloses all `coords`, with ~30% padding so the
    /// end pins aren't flush against the screen edge. A single point (1-stop route)
    /// frames at `minRegionSpan` so the lone pin reads at street level.
    private static func region(enclosing coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            return MKCoordinateRegion(
                center: coords.first ?? CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: minRegionSpan, longitudeDelta: minRegionSpan)
            )
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.3, minRegionSpan),
            longitudeDelta: max((maxLon - minLon) * 1.3, minRegionSpan)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    @ViewBuilder
    private var paywallSheetContent: some View {
        PaywallView(onUnlocked: {
            let resume = viewModel.onPaywallUnlocked
            viewModel.onPaywallUnlocked = nil
            resume?()
        })
        .environment(subscriptionService)
    }

    /// Load up to 8 routes for the current city from RouteStore (US-025).
    private func refreshNearbyRoutes(cityCode: String?) {
        guard let code = cityCode, !code.isEmpty else {
            nearbyRoutes = []
            return
        }
        nearbyRoutes = routeStore.nearby(cityCode: code, limit: 8)
    }

    /// Fetch nearby companion posts and convert geohash6 fields to cell centres
    /// for the companion map layer (US-017).
    private func fetchNearbyCells(viewModel: MapViewModel) async {
        let cityCode = viewModel.selectedCity ?? ""
        await companionService.fetchDiscovery(
            params: CompanionDiscoverParams(cityCode: cityCode, mode: .nearby)
        )
        // Map each nearby-mode discovery hit to its blurred geohash-6 cell centre.
        // `DiscoverPost.geohash6` exists, so resolve it directly; posts without a
        // geohash6 (itinerary mode, or a backend that doesn't yet return the
        // field) are dropped rather than rendered at a bogus location.
        nearbyCells = companionService.discoverPosts.compactMap { post in
            guard let gh = post.geohash6 else { return nil }
            return NearbyCell(geohash: gh)
        }
    }

    /// Fires the once-per-day startup self-check ~1.5s after first paint. Any
    /// finding (missing API key, denied permission, incomplete onboarding, …)
    /// pushes a `SoloAgentBubble` from the mascot FAB inviting the traveler to
    /// tap through to ChatSheet where the AI opens by explaining each issue.
    /// A clean bill of health leaves the map untouched.
    ///
    /// DEBUG `-forceDiagnosticsBubble` launch arg: injects a synthetic finding
    /// so screenshot / e2e harnesses can always exercise the bubble without
    /// depending on the current sim's authorization / key state.
    private func kickoffStartupDiagnostics() {
        let svc = diagnostics ?? StartupDiagnosticsService(
            preferences: preferences,
            locationService: locationService,
            experienceService: experienceService
        )
        diagnostics = svc
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-forceDiagnosticsBubble") {
                let stub = StartupDiagnosticsService.Finding(
                    check: .anthropicKey, severity: .warn,
                    title: NSLocalizedString(
                        "diagnostics.anthropic.missing.title",
                        value: "AI 大脑没接上",
                        comment: ""
                    ),
                    detail: NSLocalizedString(
                        "diagnostics.anthropic.missing.detail",
                        value: "没检测到 AI API key。",
                        comment: ""
                    ),
                    suggestedFix: NSLocalizedString(
                        "diagnostics.anthropic.missing.fix",
                        value: "去设置 → AI Provider 填一个 key。",
                        comment: ""
                    )
                )
                svc.injectFindingsForTesting([stub])
                agentBubbleQueue.enqueue(diagnosticsBubble(for: [stub]))
                return
            }
            // Screenshot harness: `-forceDiagnosticsMulti` injects three
            // findings of mixed severity so the "N more issues" bubble copy
            // and the multi-row DiagnosticsRequestCard can be verified.
            if ProcessInfo.processInfo.arguments.contains("-forceDiagnosticsMulti") {
                let error = StartupDiagnosticsService.Finding(
                    check: .locationAuth, severity: .error,
                    title: NSLocalizedString("diagnostics.location.denied.title", value: "定位被拒了", comment: ""),
                    detail: NSLocalizedString("diagnostics.location.denied.detail", value: "地图不知道你在哪。", comment: ""),
                    suggestedFix: NSLocalizedString("diagnostics.location.denied.fix", value: "去设置 → Solo Compass → 位置。", comment: "")
                )
                let warn = StartupDiagnosticsService.Finding(
                    check: .anthropicKey, severity: .warn,
                    title: NSLocalizedString("diagnostics.anthropic.missing.title", value: "AI 大脑没接上", comment: ""),
                    detail: NSLocalizedString("diagnostics.anthropic.missing.detail", value: "没检测到 AI API key。", comment: ""),
                    suggestedFix: NSLocalizedString("diagnostics.anthropic.missing.fix", value: "去设置 → AI Provider 填一个 key。", comment: "")
                )
                let info = StartupDiagnosticsService.Finding(
                    check: .userPrefs, severity: .info,
                    title: NSLocalizedString("diagnostics.onboarding.incomplete.title", value: "onboarding 还没走完", comment: ""),
                    detail: NSLocalizedString("diagnostics.onboarding.incomplete.detail", value: "推荐会退化。", comment: ""),
                    suggestedFix: NSLocalizedString("diagnostics.onboarding.incomplete.fix", value: "回到 onboarding 把三步选完。", comment: "")
                )
                let all = [error, warn, info]
                svc.injectFindingsForTesting(all)
                agentBubbleQueue.enqueue(diagnosticsBubble(for: all))
                return
            }
            #endif
            let findings = await svc.runIfNeeded()
            guard !findings.isEmpty else { return }
            agentBubbleQueue.enqueue(diagnosticsBubble(for: findings))
        }
    }

    /// Highest-severity finding drives the visible bubble copy — one bubble at
    /// a time so the mascot doesn't scream. Tapping the CTA pulls *all*
    /// findings into the seeded chat prompt so the user still sees the full
    /// list once inside ChatSheet.
    private func diagnosticsBubble(for findings: [StartupDiagnosticsService.Finding]) -> SoloAgentBubble {
        let priority: (StartupDiagnosticsService.Severity) -> Int = {
            switch $0 { case .error: return 0; case .warn: return 1; case .info: return 2 }
        }
        let sorted = findings.sorted { priority($0.severity) < priority($1.severity) }
        let head = sorted[0]
        let tone: SoloAgentBubble.Tone
        switch head.severity {
        case .error: tone = .error
        case .warn:  tone = .warn
        case .info:  tone = .info
        }
        let subtitle: String
        if findings.count > 1 {
            subtitle = String(
                format: NSLocalizedString(
                    "solo.agent.bubble.diagnostics.subtitle.multi",
                    value: "还有 %d 个问题,点开我一起说。",
                    comment: "Bubble subtitle when multiple diagnostics findings"
                ),
                findings.count - 1
            )
        } else {
            // Single finding: show the suggested fix (short, action-oriented)
            // instead of `detail` (a full paragraph that gets truncated to
            // "…" in the bubble's 3-line limit). Full explanation still lands
            // inside ChatSheet when the traveler taps through.
            subtitle = head.suggestedFix
        }
        return SoloAgentBubble(
            tone: tone,
            title: head.title,
            subtitle: subtitle,
            ctaLabel: NSLocalizedString(
                "solo.agent.bubble.diagnostics.cta",
                value: "问 Solo 怎么修 →",
                comment: "Bubble CTA to open ChatSheet with the findings seeded"
            )
        )
    }

    /// Lazily instantiates `voiceOrchestrator` on first chat-sheet open.
    /// Keeping the orchestrator around between dismissals would mean the
    /// next session sees stale messages — we discard it when the sheet
    /// closes (see `chatSheetContent.onDismiss`).
    private func ensureOrchestrator(viewModel vm: MapViewModel) {
        guard voiceOrchestrator == nil else { return }
        let orch = VoiceAgentOrchestrator(
            aiService: aiService,
            voiceService: voiceService,
            mapViewModel: vm,
            preferences: preferences,
            historyStore: chatHistoryStore,
            // P2.0 #201/#202: hand the shared MemoryDigestService so the
            // agent injects the AgentMemorySnapshot into its system prompt
            // and refreshes the digest after each completed turn.
            memoryDigest: MemoryDigestService.shared,
            // City OS v2: wire the content plane + visa math so the get_city_kit
            // / find_local_events tools resolve real facts (gated by the flag).
            cityBriefService: FeatureFlags.cityOS ? cityBriefService : nil,
            complianceService: FeatureFlags.cityOS ? complianceService : nil
        )
        orch.start()
        voiceOrchestrator = orch
    }

    /// Drives the chat `.sheet(item:)`. Reading returns the live orchestrator;
    /// setting it to `nil` (swipe-to-dismiss or the in-view "X") first unscopes
    /// + stops the instance so it never leaks an `<experience_context>` block
    /// into a later global chat (US-004).
    private var chatOrchestratorBinding: Binding<VoiceAgentOrchestrator?> {
        Binding(
            get: { voiceOrchestrator },
            set: { newValue in
                if newValue == nil, let current = voiceOrchestrator {
                    current.rebindContext(nil)
                    current.stop()
                }
                voiceOrchestrator = newValue
            }
        )
    }

    private func chatSheetContent(_ orch: VoiceAgentOrchestrator) -> some View {
        ChatSheet(
            orchestrator: orch,
            voiceService: voiceService,
            startInVoiceMode: chatStartMode == .voice,
            // The in-view "X" routes through the same binding setter so its
            // teardown matches swipe-to-dismiss exactly.
            onDismiss: {
                // Persist the conversation before tearing the orchestrator down
                // so it lands in history even if the user only closed the sheet.
                orch.persistConversation()
                chatOrchestratorBinding.wrappedValue = nil
            },
            // Tapping a chat place card reveals it on the map (the agent never
            // jumps there on its own — this is the user's explicit action).
            onSelectExperience: { exp in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    viewModel.selectExperience(exp)
                }
            },
            // Adopting a proposed route saves it and opens its detail sheet.
            onAdoptRoute: { proposal in
                routeStore.save(proposal.route)
                refreshNearbyRoutes(cityCode: viewModel.selectedCity)
                routeSheet = .detail(proposal.route)
            },
            // City OS v2: tapping "在地图上看" on a chat event card recenters the
            // map on the event and highlights its marker (chat already dismissed).
            onShowEventOnMap: { event in
                focusEventOnMap(event)
            },
            // Bound detent lets the sheet auto-expand to full height while the
            // agent is thinking, then the user can still drag it back down.
            detent: $chatDetent,
            historyStore: chatHistoryStore,
            // Startup-diagnostics seed. Non-nil only when the traveler tapped
            // the self-diagnostics bubble's CTA. Cleared inside .onAppear so
            // a subsequent "+ button" chat opens clean.
            initialUserPrompt: pendingDiagnosticsPrompt
        )
        .onAppear { pendingDiagnosticsPrompt = nil }
        .presentationDetents([.medium, .large], selection: $chatDetent)
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    @ViewBuilder
    private func mapLayer(viewModel: MapViewModel) -> some View {
        let bindingCamera = Binding<MapCameraPosition>(
            get: { viewModel.cameraPosition },
            set: { viewModel.cameraPosition = $0 }
        )

        MapReader { proxy in
            Map(position: bindingCamera) {
                // The traveler's own location. The built-in `UserAnnotation()`
                // blue dot is too small to find among the POI markers, so we
                // draw two composed layers instead (decision: "两者结合"):
                //   1. A translucent geographic radius circle (~120m) that
                //      scales with the map, giving a real sense of "near me".
                //   2. A fixed-size, high-contrast `UserLocationMarker` at the
                //      exact coordinate so the center is always easy to spot.
                // Only drawn once GPS has a fix; otherwise nothing renders
                // (no marker stranded at 0,0).
                if let here = locationService.currentLocation {
                    MapCircle(center: here.coordinate, radius: Self.userRadiusMeters)
                        .foregroundStyle(Color.accentColor.opacity(0.12))
                        .stroke(Color.accentColor.opacity(0.4), lineWidth: 1.5)
                    Annotation("", coordinate: here.coordinate) {
                        UserLocationMarker()
                    }
                }
                // Zoom-adaptive density with clustering: at city/district zoom,
                // overlapping pins collapse into cluster bubbles showing a count.
                // At street zoom, every pin renders individually.
                ForEach(viewModel.clusteredMapItems) { item in
                    switch item {
                    case .single(let exp):
                        if let coord = exp.coordinate {
                            let state = viewModel.markerState(for: exp)
                            let isClosingSoon = BestNowChipState
                                .resolve(for: exp, at: bestNowClock.tick)
                                .isClosingSoon
                            let smartPickRank = viewModel.effectiveSmartPickIds.firstIndex(of: exp.id)
                            let isSmartPick = smartPickRank != nil
                            let highlightActive = smartPickHighlightActive
                                && !viewModel.effectiveSmartPickIds.isEmpty
                                && viewModel.exploreRadiusOverlay == nil
                            Annotation("", coordinate: coord) {
                                Button {
                                    viewModel.openExperienceDetail(exp)
                                    HapticService.shared.impact(style: .light)
                                } label: {
                                    VStack(spacing: 2) {
                                        MarkerIconView(
                                            category: exp.category,
                                            state: state,
                                            confidenceLevel: exp.confidence.level,
                                            isSelected: viewModel.selectedExperience?.id == exp.id,
                                            nowFilterActive: viewModel.isNowFilter,
                                            closingSoon: isClosingSoon
                                        )
                                        if case .footprinted = state {
                                            Text("\(viewModel.footprintCount(for: exp))")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Capsule().fill(CT.fgMuted))
                                        }
                                    }
                                    .modifier(SmartPickHighlightModifier(
                                        isSmartPick: isSmartPick,
                                        highlightActive: highlightActive,
                                        reduceMotion: reduceMotion,
                                        smartPickRank: smartPickRank
                                    ))
                                    // Slice C: dim non-session pins so the
                                    // Explore-Mode overlay's live-feed reads
                                    // against a hushed background of the pre-
                                    // existing map. The `.active` check gates
                                    // this so idle map is untouched.
                                    .modifier(ExploreSessionDimModifier(
                                        isNewInSession: viewModel.exploreSessionAddedIds.contains(exp.id),
                                        sessionActive: viewModel.exploreSession.isActive,
                                        reduceMotion: reduceMotion
                                    ))
                                    .transition(.scale.combined(with: .opacity))
                                }
                                .buttonStyle(.plain)
                                .modifier(LongPressCardModifier(onLongPress: {
                                    withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.72)) {
                                        viewModel.selectExperience(exp)
                                    }
                                }))
                                .transition(.scale.combined(with: .opacity))
                                .accessibilityLabel(Text(exp.title))
                                .accessibilityAction(named: Text(NSLocalizedString("experience.card.preview.a11y", comment: "Preview action: float the quick preview card"))) {
                                    viewModel.selectExperience(exp)
                                }
                            }
                        }
                    case .cluster(let cluster):
                        // A cluster bubble is, by definition, a bag of "not the
                        // top 3" pins — so during the cold-start curation pass
                        // it follows the same dim-and-shrink treatment as any
                        // non-smart-pick. If a smart pick happens to fall into
                        // the cluster it's still surfaced, just not visually
                        // forced; the home-screen narrative ("look at these
                        // three") stays clean.
                        let clusterRanks = cluster.experiences.compactMap { viewModel.effectiveSmartPickIds.firstIndex(of: $0.id) }
                        let clusterHasSmartPick = !clusterRanks.isEmpty
                        let clusterTopRank = clusterRanks.min()
                        let clusterHighlightActive = smartPickHighlightActive
                            && !viewModel.effectiveSmartPickIds.isEmpty
                            && viewModel.exploreRadiusOverlay == nil
                        Annotation("", coordinate: cluster.coordinate) {
                            ClusterAnnotationView(cluster: cluster) {
                                HapticService.shared.impact(style: .medium)
                                if let first = cluster.experiences.first {
                                    viewModel.openExperienceDetail(first)
                                }
                            }
                            .modifier(SmartPickHighlightModifier(
                                isSmartPick: clusterHasSmartPick,
                                highlightActive: clusterHighlightActive,
                                reduceMotion: reduceMotion,
                                smartPickRank: clusterTopRank
                            ))
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                ForEach(viewModel.candidateExperiences) { cand in
                    if let coord = cand.coordinate {
                        let candHighlightActive = smartPickHighlightActive
                            && !viewModel.effectiveSmartPickIds.isEmpty
                            && viewModel.exploreRadiusOverlay == nil
                        Annotation("", coordinate: coord) {
                            MarkerIconView(
                                category: cand.category,
                                state: .default,
                                confidenceLevel: cand.confidence.level,
                                isSelected: viewModel.selectedExperience?.id == cand.id
                            )
                            .modifier(SmartPickHighlightModifier(
                                isSmartPick: false,
                                highlightActive: candHighlightActive,
                                reduceMotion: reduceMotion
                            ))
                            .accessibilityLabel(Text(String(
                                format: NSLocalizedString("map.candidate.label", comment: "Candidate experience: %@"),
                                cand.title
                            )))
                        }
                    }
                }
                // City OS v2: 在地 event回流 markers on their OWN Annotation
                // layer — deliberately outside the clustered POI pipeline so the
                // marker-count perf tests stay honest. Live mode only; each event
                // with a coordinate gets a breathing (reduce-motion static) ring.
                if FeatureFlags.cityOS && currentCityMode == .live {
                    ForEach(cityBriefService.activeEvents()) { event in
                        if let lat = event.lat, let lng = event.lng {
                            Annotation("", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)) {
                                EventMarkerView(
                                    event: event,
                                    isHighlighted: viewModel.highlightedEventId == event.id,
                                    onTap: {
                                        viewModel.highlightedEventId = event.id
                                        isShowingLiveSheet = true
                                    }
                                )
                            }
                        }
                    }
                }
                // US-017: Companion nearby layer — blurred ~600m cell centres.
                // No exact pins; no user identifiers. Layer must be explicitly on.
                if isCompanionLayerOn {
                    ForEach(nearbyCells) { cell in
                        Annotation("", coordinate: cell.coordinate) {
                            NearbyBlurAnnotation()
                        }
                    }
                }
                // US-011: fading radius ring during progressive explore.
                // Drawn below annotations so it never occludes marker tap targets.
                if let ring = viewModel.exploreRadiusOverlay {
                    MapCircle(center: ring.center, radius: ring.radiusMeters)
                        .foregroundStyle(Color.accentColor.opacity(0.08))
                        .stroke(Color.accentColor.opacity(0.35), lineWidth: 1.5)
                }

                // Active route: a connecting polyline plus numbered stop pins so
                // the walk reads as an ordered sequence on the map. Drawn last so
                // the line and numbers sit above the radius ring.
                if let active = activeRoute, active.coordinates.count >= 2 {
                    MapPolyline(coordinates: active.coordinates, contourStyle: .straight)
                        .stroke(
                            Color.accentColor,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                        )
                    ForEach(Array(active.coordinates.enumerated()), id: \.offset) { index, coord in
                        Annotation("", coordinate: coord) {
                            RouteStopBadge(number: index + 1)
                        }
                    }
                }
            }
            .mapStyle(mapStyleChoice.mapStyle)
            // Only keep the compass (which auto-hides unless the map is
            // rotated). The built-in MapUserLocationButton is intentionally
            // dropped: because the map sets `.ignoresSafeArea()` to bleed tiles
            // under the status bar, MapKit lays the control out against the
            // ignored margins and pins it into the status-bar strip, where it
            // collided with the system battery glyph. A custom recenter button
            // (see `recenterButton` in the overlay) gives us a safe-area-aware,
            // fully controllable placement instead.
            .mapControls {
                MapCompass()
            }
            .onMapCameraChange(frequency: .continuous) { _ in
                isMapPanning = true
                lastPanAt = Date()
                if panDebounceTask == nil {
                    panDebounceTask = Task {
                        repeat {
                            try? await Task.sleep(for: .milliseconds(100))
                            if Task.isCancelled { return }
                        } while Date().timeIntervalSince(lastPanAt) < Self.panRefreshDebounce
                        if !Task.isCancelled {
                            isMapPanning = false
                        }
                        panDebounceTask = nil
                    }
                }
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                // Feed the zoom level into the view model so the map's
                // Level-of-Detail (few prominent pins zoomed out → more zoomed
                // in) recomputes. Animate so pins fade in/out rather than snap.
                withAnimation(MapViewModel.markerSetAnimation) {
                    viewModel.currentSpanLatitudeDelta = context.region.span.latitudeDelta
                }
                viewModel.refreshForLocation(context.region.center)
                // Direction 2: the curation dim-out is a cold-start cue. Once
                // the camera settles for the first time after the user has
                // panned or zoomed (isMapPanning flipped during the move),
                // restore every pin to full opacity so Explore feels like the
                // whole map again — not a guided tour.
                if smartPickHighlightActive && isMapPanning {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                        smartPickHighlightActive = false
                    }
                }
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.6)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onEnded { value in
                        if case .second(true, let drag?) = value,
                           let coord = proxy.convert(drag.location, from: .local) {
                            viewModel.handleMapLongPress(at: coord)
                            Haptics.impact(.medium)
                        }
                    }
            )
            // Tap empty map → dismiss the floating preview card, matching the
            // tap-to-deselect convention of Apple/Google Maps. Pin `Button`s and
            // the card itself sit in their own layers and consume their own taps
            // first, so only a tap on bare map reaches here. Guarded to the
            // preview state (selection without the detail sheet) so it never
            // interferes with pin selection or the open detail view.
            .simultaneousGesture(
                TapGesture().onEnded {
                    guard viewModel.selectedExperience != nil, !viewModel.isShowingDetail else { return }
                    Haptics.selection()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.clearSelection()
                    }
                }
            )
        }
    }

    /// Render the multi-ring Explore progress capsule text. Returns nil
    /// when `.idle` so the capsule disappears completely. US-MR-04.
    static func progressText(for progress: MapViewModel.ExploreProgress) -> String? {
        switch progress {
        case .idle:
            return nil
        case .multiRingScanning(let done, let total):
            return String(
                format: NSLocalizedString("explore.progress.scanning", comment: "ring m of n"),
                done, total
            )
        case .synthesizing(let count):
            return String(
                format: NSLocalizedString("explore.progress.synthesizing", comment: "n places"),
                count
            )
        case .scanning(let radiusKm):
            return String(
                format: NSLocalizedString("explore.progress.progressiveScanning", comment: "scanning radius km"),
                radiusKm
            )
        case .expanding(let toRadiusKm):
            return String(
                format: NSLocalizedString("explore.progress.expanding", comment: "expanding to radius km"),
                toRadiusKm
            )
        }
    }

    /// Whether the bottom sheet should surface the Routes section + create-route
    /// entry. Routes are a "what should I walk right now" artifact, so they only
    /// appear in the Now / 当下 context — every other sort mode hides them
    /// entirely. Exposed as a pure static so the rule is unit-testable rather
    /// than buried in the view body. See [[project_routes_now_only]].
    static func shouldShowRoutesSection(isNowFilter: Bool) -> Bool {
        isNowFilter
    }
}

#Preview {
    CompassMapView()
        .environment(LocationService.shared)
        .environment(ExperienceService())
        .environment(AIService())
        .environment(UserPreferences())
        .environment(CompanionService.shared)
        .environment(PresenceService.shared)
        .environment(BestNowClock.shared)
}

// Internal (not `private`) so module siblings such as `VoiceProcessingToast`
// can reuse the same single-line truncation helper.
extension String {
    func truncated(limit: Int) -> String {
        guard count > limit else { return self }
        return String(prefix(limit)) + "…"
    }
}

/// Layout metrics shared between `MapOverlayView` and its tests.
enum MapOverlayMetrics {
    /// Minimum hit target size per Apple HIG (44×44 pt).
    /// The visual city pill is smaller than this, so `.contentShape` + `.frame`
    /// expand the tappable region without changing the visual appearance.
    static let cityPillHitTarget: CGFloat = 44

    // US-022: explicit vertical band layout so the city-pill row and the filter
    // bar can never overlap or hit-test interfere. The two rects are computed
    // from these constants in `TopOverlayLayoutTest` and applied verbatim in
    // `MapOverlayView.body`.

    /// Top inset (below the safe area) where the city-pill row begins.
    static let cityPillTopPadding: CGFloat = 8

    /// Fixed height reserved for the city-pill row. Equals the 44pt hit box so
    /// the row never grows into the gap, regardless of the pill's visual size.
    static let cityPillRowHeight: CGFloat = cityPillHitTarget

    /// Mandatory empty gap between the city-pill row and the filter bar. This
    /// is what guarantees the two capsules read as separate bands and that
    /// their hit regions don't touch.
    static let cityPillToFilterBarGap: CGFloat = 12

    /// Approximate rendered height of `FilterBarView` (glass capsule with one
    /// row of pills). Used only by the layout test to model the filter bar's
    /// rect; the live view sizes itself intrinsically.
    static let filterBarHeight: CGFloat = 56

    /// Y offset at which the filter bar's rect starts, measured from the top of
    /// the overlay band. Sum of the city-pill row + the mandated gap.
    static var filterBarTopOffset: CGFloat {
        cityPillTopPadding + cityPillRowHeight + cityPillToFilterBarGap
    }

    /// The city-pill row rect within the overlay coordinate space.
    static func cityPillRowRect(width: CGFloat) -> CGRect {
        CGRect(x: 0, y: cityPillTopPadding, width: width, height: cityPillRowHeight)
    }

    /// The filter bar rect within the overlay coordinate space.
    static func filterBarRect(width: CGFloat) -> CGRect {
        CGRect(x: 0, y: filterBarTopOffset, width: width, height: filterBarHeight)
    }
}

private struct MapOverlayView: View {
    var viewModel: MapViewModel
    var isAIProcessing: Bool
    /// City OS v3 · optional second pill line ("第 3 天 · 生活"). Nil = one line.
    var cityModeLine: String?
    /// City OS v3 · lifecycle rail position (0–3) for the stage dots; nil hides.
    var cityStageIndex: Int?
    @Binding var isShowingCityPicker: Bool
    @Binding var dismissedAIError: String?
    @Binding var dismissedExploreError: String?
    @Binding var dismissedQuotaInfo: String?
    @Binding var dismissedLocationError: Bool
    @Binding var isMapPanning: Bool
    @Binding var mapStyleChoice: MapStyleChoice
    // US-007: pending friend-request count drives the avatar's red dot;
    // the tap opens the personal hub (MeSheet).
    var pendingRequestCount: Int = 0
    var onTapAvatar: () -> Void = {}

    @State private var checkInCelebrationTrigger = 0
    @State private var noMatchPop = false
    /// P2.5 #252: "我的菜" toggle on the filter bar. Local UI state.
    @State private var isTasteRankOn: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isFilterActive: Bool {
        viewModel.selectedCategory != nil || viewModel.selectedCustomTag != nil || viewModel.isNowFilter
    }

    private var activeFilterName: String {
        if let category = viewModel.selectedCategory {
            return category.localizedTitle
        } else if let tag = viewModel.selectedCustomTag {
            return tag
        } else if viewModel.isNowFilter {
            return NSLocalizedString("filter.now", comment: "Now filter label")
        }
        return ""
    }

    var body: some View {
        VStack(spacing: 0) {
            // US-022: the city pill lives in its own fixed-height band at the
            // very top, vertically separated from the filter bar by an explicit
            // gap, so the two capsules no longer overlap or hit-test interfere.
            // The row is pinned to a 44pt height (the pill's hit box) so it
            // never bleeds into the gap regardless of the pill's visual size.
            HStack {
                cityPill
                    .padding(.leading, 12)
                Spacer()
                // Custom "locate me" button — replaces the built-in
                // MapUserLocationButton, which MapKit pinned into the status bar
                // (it collided with the battery glyph) because the map ignores
                // the top safe area. Living in this safe-area-respecting overlay
                // row keeps it clear of the status bar, on the city-pill line.
                // US-007: emoji avatar bubble — the entry point into the
                // personal hub (MeSheet). Placed before the recenter button so
                // it stays fully on-screen in this safe-area-respecting overlay
                // row (top-right), clear of the status bar.
                mapStyleButton
                    .padding(.trailing, 4)
                MapAvatarBubble(
                    hasPendingRequests: pendingRequestCount > 0,
                    action: onTapAvatar
                )
                .padding(.trailing, 8)
                recenterButton
                    .padding(.trailing, 12)
            }
            .frame(height: MapOverlayMetrics.cityPillRowHeight)
            .padding(.top, MapOverlayMetrics.cityPillTopPadding)

            // Mandatory empty gap separating the city-pill band from the
            // filter bar — this is the dead zone that guarantees no overlap.
            Spacer()
                .frame(height: MapOverlayMetrics.cityPillToFilterBarGap)

            FilterBarView(
                selectedCategory: viewModel.selectedCategory,
                isNowSelected: viewModel.isNowFilter,
                selectedCustomTag: viewModel.selectedCustomTag,
                isFavoriteSelected: viewModel.isFavoriteFilter,
                nowCount: viewModel.nowCount,
                onSelectNow: { viewModel.selectNowFilter() },
                onSelectAll: { viewModel.clearFilters() },
                onSelectFavorite: { viewModel.selectFavoriteFilter() },
                onClear: { viewModel.clearFilters() },
                onSelectCategory: { viewModel.selectCategory($0) },
                onSelectCustomTag: { viewModel.selectCustomTag($0) },
                isMapPanning: $isMapPanning,
                resultCount: viewModel.visibleExperiences.count,
                // P2.5 hooks: Solo Agent pill fires the map's ambient
                // "Ask Solo" affordance; taste rank pill toggles the
                // TasteProfile-weighted ordering.
                onSoloAgentTap: { viewModel.selectNowFilter() },
                isTasteRankOn: isTasteRankOn,
                onTasteRankToggle: { isTasteRankOn = $0 }
            )
            // US-026: reset the GPS-error dismissal once the error clears so a
            // later failure re-surfaces the banner. Anchored on the always-present
            // filter bar (the banner itself is conditional, so its own onChange
            // wouldn't fire on the nil transition that removes it).
            .onChange(of: viewModel.locationErrorBannerText) { _, newValue in
                if newValue == nil { dismissedLocationError = false }
            }

            let showEmptyFilterBanner = isFilterActive && viewModel.visibleExperiences.isEmpty
                && !viewModel.isNowFilter
            if showEmptyFilterBanner {
                EmptyFilterBanner(
                    filterName: activeFilterName,
                    category: viewModel.selectedCategory,
                    onShowAll: {
                        viewModel.clearFilters()
                    }
                )
                .padding(.top, 2)
                .transition(reduceMotion
                    ? .opacity
                    : .move(edge: .top).combined(with: .opacity)
                )
            }

            // Show the floating chip ONLY when it's adding information the
            // FilterBar can't: zero matches (with optional "next best" jump)
            // or zero-after-search empty state. When count > 0 the active
            // filter chip in the FilterBar already shows the match count as a
            // badge ("此刻 1"), so the mid-map "1 个匹配" is pure duplication.
            if isFilterActive && viewModel.visibleExperiences.isEmpty {
                filterResultBadge
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .opacity(isMapPanning ? 0.4 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isMapPanning)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.visibleExperiences.count)
            }

            if let errorText = viewModel.lastAIError, errorText != dismissedAIError {
                DismissibleBanner(
                    systemImage: "exclamationmark.triangle.fill",
                    text: errorText,
                    color: CT.warningText,
                    onDismiss: { dismissedAIError = errorText }
                )
            }

            if let exploreError = viewModel.lastExploreError, exploreError != dismissedExploreError {
                DismissibleBanner(
                    // `airplane.slash` is not a real SF Symbol (rendered blank);
                    // match the sibling error banners' warning glyph.
                    systemImage: "exclamationmark.triangle.fill",
                    text: exploreError,
                    color: CT.warningText,
                    onDismiss: { dismissedExploreError = exploreError }
                )
                .accessibilityIdentifier("exploreErrorBanner")
            }

            if let quotaInfo = viewModel.lastQuotaInfo, quotaInfo != dismissedQuotaInfo {
                DismissibleBanner(
                    systemImage: "clock.badge.exclamationmark",
                    text: quotaInfo,
                    color: CT.warningText,
                    onDismiss: { dismissedQuotaInfo = quotaInfo }
                )
                .accessibilityIdentifier("quotaBanner")
            }

            // US-026: GPS failure → explain why the map fell back to a region.
            if let locationError = viewModel.locationErrorBannerText, !dismissedLocationError {
                DismissibleBanner(
                    systemImage: "location.slash.fill",
                    text: locationError,
                    color: CT.warningText,
                    actionLabel: NSLocalizedString("location.banner.openSettings", comment: "Open Settings"),
                    onAction: {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    },
                    onDismiss: { dismissedLocationError = true }
                )
                .accessibilityIdentifier("locationErrorBanner")
            }

            Spacer()

            if isAIProcessing {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(NSLocalizedString("ai.processing", comment: "AI is processing"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
                .transition(.opacity)
            }

            if let progressText = CompassMapContentView.progressText(for: viewModel.exploreProgress) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(progressText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.thinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                .transition(.opacity)
                .accessibilityIdentifier("exploreProgress")
                .accessibilityLabel(Text(progressText))
            }

            if viewModel.isProcessingVoiceIntent {
                VoiceProcessingToast(
                    text: VoiceProcessingToast.localizedText(
                        for: viewModel.currentVoiceTranscript
                    )
                )
            }

            if let toast = viewModel.voiceResultToast {
                HStack(spacing: 8) {
                    Image(systemName: toast == NSLocalizedString("voice.result.none", comment: "No matching places found nearby")
                        ? "magnifyingglass" : "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(toast == NSLocalizedString("voice.result.none", comment: "No matching places found nearby")
                            ? Color.secondary : CT.verifiedGreen)
                    Text(toast)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.thinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .accessibilityIdentifier("voiceResultToast")
            }

            if let toast = viewModel.lastExploreToast {
                Text(toast)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.thinMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .accessibilityIdentifier("exploreToast")
                    .onAppear {
                        Task {
                            try? await Task.sleep(for: .seconds(3))
                            withAnimation(.easeOut(duration: 0.3)) {
                                viewModel.lastExploreToast = nil
                            }
                        }
                    }
            }

            if let pending = viewModel.pendingCheckIn {
                ZStack(alignment: .top) {
                    PendingCheckInBanner(
                        experienceTitle: pending.title,
                        onConfirm: {
                            checkInCelebrationTrigger += 1
                            viewModel.confirmCheckIn()
                        },
                        onDismiss: { viewModel.dismissCheckIn() }
                    )
                    CompletionCelebrationView(trigger: checkInCelebrationTrigger)
                        .offset(y: -120)
                }
                .padding(.bottom, 4)
                .animation(.spring(response: 0.4), value: viewModel.pendingCheckIn != nil)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFilterActive)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.visibleExperiences.count)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.visibleExperiences.isEmpty && isFilterActive)
    }

    @ViewBuilder
    private var filterResultBadge: some View {
        let count = viewModel.visibleExperiences.count
        let dotColor: Color = {
            if let cat = viewModel.selectedCategory { return cat.color }
            if viewModel.isNowFilter { return CT.sunGold }
            return CT.accent
        }()

        if count == 0 {
            if viewModel.isNowFilter, let next = viewModel.nextBestExperience() {
                // "Now" filter is active, nothing is at its best, but something
                // is coming up soon — offer a one-tap jump to it. Wrap in a
                // TimelineView so the countdown decrements every minute without
                // user interaction, matching every other BestNow surface.
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let tickedNext = viewModel.nextBestExperience(now: context.date) ?? next
                    let minutesUntil = tickedNext.minutesUntil
                    let progress = CompassMapView.imminenceProgress(minutesUntil: minutesUntil)
                    let idleText = NSLocalizedString("filter.now.empty.idle", comment: "Nothing's at its best now")
                    let upcomingText = String(
                        format: NSLocalizedString("filter.now.empty.upcoming", comment: "%@ in %dm"),
                        tickedNext.experience.title, minutesUntil
                    )
                    let a11yText = String(
                        format: NSLocalizedString("filter.now.empty.a11y", comment: ""),
                        tickedNext.experience.title, minutesUntil
                    )

                    GlassmorphismCapsule(
                        horizontalPadding: 12,
                        verticalPadding: 6,
                        shadowRadius: 6,
                        shadowY: 3
                    ) {
                        HStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .stroke(CT.sunGold.opacity(0.25), lineWidth: 2)
                                Circle()
                                    .trim(from: 0, to: progress)
                                    .stroke(CT.sunGold, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                    .animation(reduceMotion ? nil : .easeInOut, value: progress)
                                Circle()
                                    .fill(CT.sunGold)
                                    .frame(width: 8, height: 8)
                            }
                            .frame(width: 14, height: 14)
                            Text(idleText)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(upcomingText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(CT.sunGold)
                                .contentTransition(.numericText())
                                .animation(reduceMotion ? nil : .easeInOut, value: minutesUntil)
                        }
                    }
                    .contentTransition(.opacity)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: count)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(a11yText))
                    .accessibilityAddTraits(.isButton)
                    // Tap → open detail directly (openExperienceDetail reframes
                    // the camera itself, so no separate focusOnExperience call).
                    .accessibilityAction {
                        Haptics.impact(.light)
                        viewModel.openExperienceDetail(tickedNext.experience)
                    }
                    // Long-press → float the quick preview card (former behavior).
                    .accessibilityAction(named: Text(NSLocalizedString("experience.card.preview.a11y", comment: "Preview action: float the quick preview card"))) {
                        viewModel.selectExperience(tickedNext.experience)
                    }
                    .onTapGesture {
                        Haptics.impact(.light)
                        viewModel.openExperienceDetail(tickedNext.experience)
                    }
                    .onLongPressGesture(minimumDuration: 0.4) {
                        Haptics.impact(.medium)
                        viewModel.selectExperience(tickedNext.experience)
                    }
                }
            } else {
                let noMatchText = NSLocalizedString("filter.matches.none", comment: "No matches")
                let clearText = NSLocalizedString("filter.clear", comment: "Clear filter")
                let a11yLabel = "\(noMatchText) · \(clearText)"

                GlassmorphismCapsule(
                    horizontalPadding: 12,
                    verticalPadding: 6,
                    shadowRadius: 6,
                    shadowY: 3
                ) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(dotColor)
                            .frame(width: 8, height: 8)
                        Text(noMatchText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            Haptics.impact(.light)
                            viewModel.clearFilters()
                        } label: {
                            Text(clearText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(dotColor)
                        }
                        .buttonStyle(PressableButtonStyle(haptic: false))
                    }
                }
                .scaleEffect(noMatchPop ? 1.06 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: noMatchPop)
                .contentTransition(.opacity)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: count)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(a11yLabel))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    Haptics.impact(.light)
                    viewModel.clearFilters()
                }
                .onChange(of: count) { _, newCount in
                    guard newCount == 0 else { return }
                    Haptics.notify(.warning)
                    guard !reduceMotion else { return }
                    noMatchPop = true
                    Task {
                        try? await Task.sleep(nanoseconds: 450_000_000)
                        noMatchPop = false
                    }
                }
            }
        } else {
            let countText = count == 1
                ? String(format: NSLocalizedString("filter.matches.one", comment: "1 match"), count)
                : String(format: NSLocalizedString("filter.matches.other", comment: "%d matches"), count)

            GlassmorphismCapsule(
                horizontalPadding: 12,
                verticalPadding: 6,
                shadowRadius: 6,
                shadowY: 3
            ) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                    Text(countText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                }
            }
            .contentTransition(.numericText())
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: count)
            .accessibilityLabel(Text(countText))
        }
    }

    @ViewBuilder
    private var cityPill: some View {
        let cityName: String = {
            if viewModel.isCustomLocation, let label = viewModel.customLocationLabel {
                return label
            }
            // Friendly fallback for the synthetic `osm_<lat>_<lon>` code that
            // MapViewModel emits when reverse-geocoding misses on an Explore
            // jump. Rendering "osm_18.8_99.0" in the city pill exposes an
            // internal sentinel to the user — we'd rather show a localized
            // "Nearby" and let the chevron offer the picker as the recovery.
            if let code = viewModel.selectedCity, code.hasPrefix("osm_") {
                return NSLocalizedString("city.nearby", comment: "Fallback city label for synthetic osm_ codes")
            }
            if let code = viewModel.selectedCity,
               let city = viewModel.availableCities.first(where: { $0.code == code }) {
                return city.name
            }
            // Resolve via alias table (e.g. CNX → cmi → "Chiang Mai")
            if let code = viewModel.selectedCity,
               let resolved = viewModel.resolvedCityName(for: code) {
                return resolved
            }
            if let code = viewModel.nearestSeededCity(to: viewModel.defaultCenterForSelectedCity),
               let city = viewModel.availableCities.first(where: { $0.code == code }) {
                return city.name
            }
            return NSLocalizedString("city.all", comment: "All cities option")
        }()

        Button {
            isShowingCityPicker = true
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(cityName)
                        .font(.subheadline.weight(.medium))
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(CT.accent)
                // City OS v3 · lifecycle line: mode + day + stage dots. The
                // pill stays one-line whenever there is nothing honest to add.
                if let cityModeLine {
                    HStack(spacing: 4) {
                        Text(cityModeLine)
                            .font(CT.mono(9, .medium))
                            .foregroundStyle(CT.sunGoldDeep)
                        if let cityStageIndex {
                            HStack(spacing: 2.5) {
                                ForEach(0..<4, id: \.self) { dot in
                                    Circle()
                                        .fill(dot <= cityStageIndex ? CT.sunGoldDeep : CT.borderSubtle)
                                        .frame(width: 3.5, height: 3.5)
                                }
                            }
                            .accessibilityHidden(true)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, cityModeLine == nil ? 6 : 4)
            .background(CT.surfaceWhite.opacity(0.78), in: Capsule())
            .frame(
                minWidth: MapOverlayMetrics.cityPillHitTarget,
                minHeight: MapOverlayMetrics.cityPillHitTarget
            )
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(cityModeLine.map { "\(cityName), \($0)" } ?? cityName))
        .accessibilityHint(Text(NSLocalizedString("city.picker.title", comment: "City picker sheet title")))
    }

    private var mapStyleButton: some View {
        // Demoted to secondary affordance (32pt + reduced opacity) so the
        // top-right cluster reads as a hierarchy — Recenter (44pt primary) >
        // Avatar (40pt identity) > MapStyle (32pt secondary). The previous
        // three-equal-circles layout pushed the city pill off-center and made
        // the column feel cluttered on cold-start screenshots.
        Button {
            Haptics.impact(.light)
            withAnimation(.easeInOut(duration: 0.2)) {
                mapStyleChoice.cycle()
            }
        } label: {
            Image(systemName: mapStyleChoice.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CT.accent.opacity(0.75))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                )
        }
        .accessibilityLabel(Text(mapStyleChoice.label))
    }

    private var recenterButton: some View {
        RecenterButton(located: viewModel.hasUserLocation, onTap: {
            viewModel.recenterOnUser()
        })
    }
}

/// Custom "locate me" control. Recenters the camera on the user's current
/// location. Shows a filled arrow when a GPS fix is available, an outline
/// (and disabled) when not. On tap (when located) fires an expanding accent
/// ring + icon scale-pop; respects Reduce Motion by skipping the animation
/// while keeping the existing haptic.
private struct RecenterButton: View {
    let located: Bool
    let onTap: () -> Void

    @State private var pulse = false
    @State private var iconPop = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !reduceMotion {
                Circle()
                    .stroke(CT.accent, lineWidth: 2)
                    .frame(width: 44, height: 44)
                    .scaleEffect(pulse ? 1.8 : 1.0)
                    .opacity(pulse ? 0 : 0.5)
                    .animation(
                        pulse ? .easeOut(duration: 0.6) : .default,
                        value: pulse
                    )
                    .allowsHitTesting(false)
            }

            Button {
                Haptics.impact(.light)
                onTap()
                guard !reduceMotion else { return }
                pulse = false
                iconPop = false
                withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                    iconPop = true
                }
                withAnimation(.easeOut(duration: 0.6)) {
                    pulse = true
                }
                Task {
                    try? await Task.sleep(for: .milliseconds(650))
                    pulse = false
                    iconPop = false
                }
            } label: {
                Image(systemName: located ? "location.fill" : "location")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(located ? CT.accent : CT.fgSubtle)
                    .scaleEffect(iconPop ? 1.18 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.5), value: iconPop)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.regularMaterial))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            }
            .disabled(!located)
            .accessibilityLabel(Text(NSLocalizedString("map.recenter", comment: "Recenter map on my location")))
        }
    }
}

#Preview("RecenterButton — located") {
    HStack(spacing: 24) {
        RecenterButton(located: true, onTap: {})
        RecenterButton(located: false, onTap: {})
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

private struct EmptyFilterBanner: View {
    let filterName: String
    let category: ExperienceCategory?
    let onShowAll: () -> Void

    @State private var nudge: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassmorphismCapsule(
            horizontalPadding: 12,
            verticalPadding: 8,
            shadowRadius: 6,
            shadowY: 3
        ) {
            HStack(spacing: 8) {
                if let cat = category {
                    Image(systemName: cat.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(cat.color.opacity(0.7))
                } else {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(String(
                    format: NSLocalizedString("filter.empty.message", comment: "No experiences match filter name"),
                    filterName
                ))
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    Haptics.selection()
                    onShowAll()
                } label: {
                    Text(NSLocalizedString("filter.empty.showAll", comment: "Show all experiences button"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CT.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(NSLocalizedString("filter.empty.showAll.a11y", comment: "Show all experiences")))
            }
        }
        .offset(x: nudge)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(String(
            format: NSLocalizedString("filter.empty.title.a11y", comment: "VoiceOver: no matches for filter"),
            filterName
        )))
        .accessibilityHint(Text(NSLocalizedString("filter.empty.message.a11y", comment: "VoiceOver hint for empty filter banner")))
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeOut(duration: 0.09)) { nudge = -5 }
                withAnimation(.easeInOut(duration: 0.09).delay(0.09)) { nudge = 5 }
                withAnimation(.easeIn(duration: 0.09).delay(0.18)) { nudge = 0 }
            }
            guard UIAccessibility.isVoiceOverRunning else { return }
            let message = String(
                format: NSLocalizedString("filter.empty.title.a11y", comment: "VoiceOver: no matches for filter"),
                filterName
            )
            UIAccessibility.post(
                notification: .announcement,
                argument: NSAttributedString(
                    string: message,
                    attributes: [.accessibilitySpeechQueueAnnouncement: true]
                )
            )
        }
    }
}

struct DismissibleBanner: View {
    let systemImage: String
    let text: String
    let color: Color
    var actionLabel: String?
    var onAction: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(color)
            Text(text).font(.caption).foregroundStyle(.primary).lineLimit(2)
            Spacer()
            if let actionLabel, let onAction {
                Button(action: onAction) {
                    Text(actionLabel)
                        .font(.caption.bold())
                        .foregroundStyle(color)
                        .frame(minWidth: HitTargetMetrics.minimum, minHeight: HitTargetMetrics.minimum)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text(actionLabel))
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.caption.bold()).foregroundStyle(.secondary)
                    // US-019: expand the small glyph to the 44pt HIG hit target.
                    .frame(
                        minWidth: HitTargetMetrics.minimum,
                        minHeight: HitTargetMetrics.minimum
                    )
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text(NSLocalizedString("common.dismiss", comment: "Dismiss")))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(text))
    }
}

/// Bottom control bar: settings, explore, spacer, "+" button.
///
/// Extracted from the `CompassMapView.body` to keep its type-checker happy.
/// The "+" button collapses tap and long-press into a single intent — open
/// the chat sheet — distinguished only by `ChatStartMode`.
private struct MapControlBar: View {
    let viewModel: MapViewModel
    let aiService: AIService
    let voiceService: VoiceService
    let preferences: UserPreferences
    @Binding var voiceOrchestrator: VoiceAgentOrchestrator?
    let onOpenChat: (CompassMapContentView.ChatStartMode) -> Void
    /// Bottom inset that keeps the controls clear of the BottomInfoSheet peek.
    /// Dynamic-Type-aware (peek height + gap), replacing a fixed 80pt that let
    /// the sheet occlude the lower half of these buttons.
    let bottomInset: CGFloat

    var body: some View {
        HStack(alignment: .bottom) {
            Button {
                viewModel.isShowingSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(.regularMaterial))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            }
            .buttonStyle(FABButtonStyle())
            .padding(.leading, 20)
            .padding(.bottom, bottomInset)
            .accessibilityLabel(Text(NSLocalizedString("settings.title", comment: "Settings")))

            Button {
                let anchor = viewModel.exploreAnchorCoordinate
                Task { await viewModel.exploreNearby(at: anchor) }
            } label: {
                Group {
                    if viewModel.isExploring || viewModel.isExploringFreeMode {
                        ProgressView().progressViewStyle(.circular)
                    } else if viewModel.isProUser {
                        Image(systemName: "sparkle.magnifyingglass").font(.title3)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill").font(.caption.weight(.semibold))
                            Text(NSLocalizedString("explore.button.pro", comment: "Explore (Pro)"))
                                .font(.caption.weight(.semibold)).lineLimit(1)
                        }.padding(.horizontal, 8)
                    }
                }
                .frame(minWidth: 48, minHeight: 48)
                .background(Capsule().fill(.regularMaterial))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            }
            .buttonStyle(FABButtonStyle())
            .padding(.leading, 12)
            .padding(.bottom, bottomInset)
            .disabled(viewModel.isExploring || viewModel.isExploringFreeMode)

            Spacer()

            VStack(spacing: 4) {
                PlusActionButton(
                    onShortTap: {
                        Haptics.impact(.medium)
                        onOpenChat(.text)
                    },
                    onLongPress: { onOpenChat(.voice) }
                )
                Text(NSLocalizedString("plus.button.label", comment: "FAB label"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.trailing, 20)
            .padding(.bottom, bottomInset)
        }
    }
}

/// `ButtonStyle` that applies the standard FAB press treatment:
/// scale-down to 0.92 on touch-down (spring) + soft haptic.
private struct FABButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.25), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed { Haptics.impact(.soft) }
            }
    }
}

/// Bottom-right "+" button. Tap opens the chat sheet in text mode (iOS convention).
/// Long press (≥0.6s) opens the chat sheet with the mic pre-armed for push-to-talk.
///
/// `onPressingChanged` fires immediately on touch-down so the ring + scale
/// animate within one frame — fixes the "looks frozen" bug where the user
/// had to wait for the full long-press window before seeing any feedback.
private struct PlusActionButton: View {
    let onShortTap: () -> Void
    let onLongPress: () -> Void

    @State private var isPressed: Bool = false
    @State private var ringPulse: Bool = false
    @State private var longPressFired: Bool = false

    var body: some View {
        ZStack {
            // Ring that grows during the hold to telegraph "almost there".
            Circle()
                .stroke(CT.accent.opacity(isPressed ? 0.5 : 0.0), lineWidth: 3)
                .frame(width: 64, height: 64)
                .scaleEffect(ringPulse ? 1.18 : 1.0)
                .opacity(ringPulse ? 0.0 : 1.0)
                .animation(
                    isPressed
                        ? .easeOut(duration: 0.9).repeatForever(autoreverses: false)
                        : .default,
                    value: ringPulse
                )

            Circle()
                // Amber-fill the Ask Solo FAB so it reads as the brand's own
                // primary action (matched to consent / onboarding CTAs) rather
                // than a generic "system action" black puck. The previous
                // .black.opacity(0.85) made the right side of the map look like
                // an Apple-default control sat next to red pin markers.
                .fill(CT.accent)
                .frame(width: 56, height: 56)
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                .scaleEffect(isPressed ? 1.08 : 1.0)
                .animation(.spring(response: 0.18, dampingFraction: 0.7), value: isPressed)

            // FAB glyph: the Solo mascot — the cartoon girl who IS Solo. She
            // greets the traveler and is the entry-point to Solo Chat, giving
            // the FAB brand identity + warmth that a bare "+" lacks. Scaled
            // down slightly + a touch of transparency so she reads as a
            // friendly companion without out-shouting the event bloom markers
            // + peek card the way the full-weight mascot once did. The amber
            // circle + shadow + press-ring above stay byte-identical, so
            // hit-target and FAB layout are unchanged. `isPressed` drives her
            // cheek sparkle.
            SoloMascotView(isPressed: isPressed)
                .scaleEffect(0.88)
                .opacity(0.95)
        }
        .contentShape(Circle())
        .onLongPressGesture(
            minimumDuration: 0.6,
            maximumDistance: .infinity,
            perform: {
                longPressFired = true
                onLongPress()
            },
            onPressingChanged: { pressing in
                if pressing {
                    // Immediate touch-down feedback: scale + ring + soft haptic.
                    isPressed = true
                    ringPulse = true
                    Haptics.impact(.soft)
                } else {
                    isPressed = false
                    ringPulse = false
                    // If the press ended without the long-press firing, treat it as a tap.
                    if !longPressFired {
                        onShortTap()
                    }
                    longPressFired = false
                }
            }
        )
        .accessibilityLabel(Text(NSLocalizedString("plus.button.a11y", comment: "Chat with Solo")))
        .accessibilityHint(Text(NSLocalizedString("plus.button.hint", comment: "Tap to open chat, hold to talk")))
    }
}

private struct EmptyStateOverlay: View {
    var viewModel: MapViewModel
    var preferences: UserPreferences
    var locationService: LocationService

    @Environment(\.colorScheme) private var colorScheme
    @State private var isVisible = false

    private var nearestCityName: String? {
        let anchor = locationService.currentLocation?.coordinate ?? viewModel.defaultCenterForSelectedCity
        guard let code = viewModel.nearestSeededCity(to: anchor),
              let city = viewModel.availableCities.first(where: { $0.code == code }) else {
            return nil
        }
        return city.name
    }

    var body: some View {
        let cardBg = colorScheme == .dark ? CT.warmCardDark : CT.surfaceWhite

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(CT.surfaceSunken)
                        .frame(width: 36, height: 36)
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(CT.fgMuted)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("map.empty.title", comment: "No experiences nearby"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colorScheme == .dark ? CT.fgPrimaryDark : CT.fgPrimary)
                    Text(String(
                        format: NSLocalizedString("map.empty.radius", comment: "No experiences within radius"),
                        preferences.maxDistanceKm
                    ))
                    .font(.caption)
                    .foregroundStyle(CT.fgMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 14)

            VStack(spacing: 8) {
                switch viewModel.emptyStateStage {
                case .tryExpand:
                    stageButton(
                        title: NSLocalizedString("map.empty.stage.tryExpand", comment: "Stage 1: expand search radius to 25km"),
                        action: { viewModel.emptyStateActionTryExpand() }
                    )
                case .tryExplore:
                    stageButton(
                        title: NSLocalizedString("map.empty.stage.tryExplore", comment: "Stage 2: widen Overpass explore to 12km"),
                        action: { viewModel.emptyStateActionTryExplore() }
                    )
                case .browseCity:
                    stageButton(
                        title: String(
                            format: NSLocalizedString("map.empty.stage.browseCity", comment: "Stage 3: jump to nearest seeded city"),
                            nearestCityName ?? ""
                        ),
                        action: { viewModel.emptyStateActionBrowseCity() }
                    )
                }

                Button {
                    viewModel.clearFilters()
                } label: {
                    Text(NSLocalizedString("map.empty.clearFilters", comment: "Clear all filters"))
                        .font(.subheadline)
                        .foregroundStyle(CT.fgMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(colorScheme == .dark ? CT.warmBorderDark : CT.borderDefault, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBg)
                .shadow(color: CT.scrimShadow, radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(colorScheme == .dark ? CT.warmBorderDark : CT.borderSubtle, lineWidth: 0.5)
        )
        .padding(.horizontal, 24)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 12)
        .accessibilityElement(children: .combine)
        .onAppear {
            viewModel.recordEmptyStateRender()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { isVisible = true }
        }
        .onChange(of: viewModel.visibleExperiences.count) { _, _ in
            viewModel.recordEmptyStateRender()
        }
    }

    private func stageButton(title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(CT.accent)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct FilteredEmptyOverlay: View {
    var viewModel: MapViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false
    @State private var iconPulse = false

    private var activeFilterName: String {
        if let category = viewModel.selectedCategory {
            return category.localizedTitle
        } else if let tag = viewModel.selectedCustomTag {
            return tag
        } else if viewModel.isNowFilter {
            return NSLocalizedString("filter.now", comment: "Now filter label")
        }
        return ""
    }

    var body: some View {
        let cardBg = colorScheme == .dark ? CT.warmCardDark : CT.surfaceWhite

        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(CT.surfaceSunken)
                    .frame(width: 36, height: 36)
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(CT.fgMuted)
                    .scaleEffect(reduceMotion ? 1.0 : (iconPulse ? 1.05 : 0.95))
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(NSLocalizedString("map.filtered.empty.title", comment: "Nothing matches this filter"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colorScheme == .dark ? CT.fgPrimaryDark : CT.fgPrimary)
                Text(String(
                    format: NSLocalizedString("map.filtered.empty.subtitle", comment: "Filter name subtitle"),
                    activeFilterName
                ))
                .font(.caption)
                .foregroundStyle(CT.fgMuted)
            }
            Spacer(minLength: 0)

            Button {
                Haptics.selection()
                viewModel.clearFilters()
            } label: {
                Text(NSLocalizedString("map.empty.clearFilters", comment: "Clear all filters"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CT.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(CT.accentSoft)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBg)
                .shadow(color: CT.scrimShadow, radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(colorScheme == .dark ? CT.warmBorderDark : CT.borderSubtle, lineWidth: 0.5)
        )
        .padding(.horizontal, 24)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .accessibilityElement(children: .combine)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { appeared = true }
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    iconPulse = true
                }
            }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced {
                withAnimation(nil) { iconPulse = false }
            } else {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    iconPulse = true
                }
            }
        }
    }
}

#if DEBUG
#Preview("FilteredEmptyOverlay") {
    let vm = MapViewModel(
        locationService: LocationService(),
        experienceService: ExperienceService(),
        aiService: AIService(),
        preferences: UserPreferences()
    )
    vm.selectedCategory = .coffee
    return FilteredEmptyOverlay(viewModel: vm)
        .padding()
}
#endif

/// Dedicated empty state for the "Now" filter. Unlike `FilteredEmptyOverlay`
/// (which offers "clear all filters"), the Now filter is time-based: an empty
/// result just means nothing is at its best *this hour*, so the useful recovery
/// is to point the traveler at the next worthwhile window — not to drop the
/// filter. Three cases, in order of helpfulness:
///   1. Something opens within 180 min → the filter-bar countdown capsule
///      (`filterResultBadge`) already owns that jump-to affordance, so this
///      overlay renders nothing to avoid two cards saying the same thing.
///   2. Nothing imminent, but a window opens later today → show it
///      ("Next best · Café X · 5–7pm") with a one-tap jump.
///   3. Nothing left today → "Quiet hours" message, still offering a one-tap
///      route back to browsing every nearby spot.
private struct NowEmptyOverlay: View {
    var viewModel: MapViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false
    @State private var iconPulse = false

    private static func relativeOpensIn(minutes: Int) -> String {
        let m = max(1, minutes)
        if m < 60 {
            return String(format: NSLocalizedString("filter.now.empty.opensIn.minutes", comment: "Opens in N minutes (compact)"), m)
        }
        return String(format: NSLocalizedString("filter.now.empty.opensIn.hours", comment: "Opens in ~N hours (compact)"), m / 60)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: context.date)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if viewModel.nextBestExperience(now: now) != nil {
            EmptyView()
        } else {
            quietHours(now: now)
        }
    }

    @ViewBuilder
    private func quietHours(now: Date) -> some View {
        let soonest = viewModel.soonestUpcomingExperience(now: now)
        let cardBg = colorScheme == .dark ? CT.warmCardDark : CT.surfaceWhite

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(CT.sunGoldSoft)
                        .frame(width: 36, height: 36)
                    Image(systemName: "moon.stars")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(CT.sunGoldDeep)
                        .scaleEffect(reduceMotion ? 1.0 : (iconPulse ? 1.05 : 0.95))
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("filter.now.empty.title", comment: "Quiet hours right now — nothing at its best"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colorScheme == .dark ? CT.fgPrimaryDark : CT.fgPrimary)
                    Text(NSLocalizedString("filter.now.empty.later.subtitle", comment: "Best times pick back up later today"))
                        .font(.caption)
                        .foregroundStyle(CT.fgMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, soonest != nil ? 10 : 12)

            if let soonest {
                let title = soonest.experience.title
                let timeHint = soonest.experience.bestTimeHint(at: now)
                let relative = Self.relativeOpensIn(minutes: soonest.minutesUntil)

                Divider()
                    .padding(.horizontal, 14)

                Button {
                    Haptics.impact(.light)
                    viewModel.openExperienceDetail(soonest.experience)
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("filter.now.empty.nextBest", comment: "Next best label"))
                                .font(CT.mono(10, .semibold))
                                .foregroundStyle(CT.sunGoldDeep)
                                .textCase(.uppercase)
                            Text(title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(colorScheme == .dark ? CT.fgPrimaryDark : CT.fgPrimary)
                                .lineLimit(1)
                            Text((timeHint.map { $0 + "  ·  " } ?? "") + relative)
                                .font(.caption)
                                .foregroundStyle(CT.fgMuted)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CT.fgSubtle)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(Text(String(
                    format: NSLocalizedString("filter.now.empty.nextBest.a11y", comment: "Next best %@ %@; tap to view"),
                    title, timeHint ?? relative
                )))
            }

            browseAllButton
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .padding(.top, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBg)
                .shadow(color: CT.scrimShadow, radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(colorScheme == .dark ? CT.warmBorderDark : CT.borderSubtle, lineWidth: 0.5)
        )
        .padding(.horizontal, 24)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { appeared = true }
            startIconPulseIfNeeded()
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced {
                withAnimation(nil) { iconPulse = false }
            } else {
                startIconPulseIfNeeded()
            }
        }
    }

    private var browseAllButton: some View {
        Button {
            Haptics.selection()
            viewModel.clearFilters()
        } label: {
            Text(NSLocalizedString("filter.now.empty.browseAll", comment: "Browse all nearby experiences"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(CT.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(CT.accentSoft)
                )
        }
        .buttonStyle(.plain)
    }

    private func startIconPulseIfNeeded() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            iconPulse = true
        }
    }
}

/// Direction 2 — first-frame curation cue.
///
/// Wraps a map marker so the 3 AI-ranked "smart picks" read as the only thing
/// worth looking at on cold start, and everything else recedes into context.
///
/// Behaviour
/// =========
/// * `highlightActive == false` → identity transform; this is the steady-state
///   once the user pans, zooms, or enters Explore mode.
/// * `highlightActive == true` + `isSmartPick == true` → keep full size +
///   opacity, layer a soft sun-gold ring + glow underneath, and (motion
///   permitting) a slow breathe. Tap target is untouched.
/// * `highlightActive == true` + `isSmartPick == false` → fade to 35% opacity
///   and 85% scale so the pin still has presence (geographic context, density
///   hint) but lets the gold picks do the talking.
///
/// Reduce Motion strips the breathe; the ring/glow + opacity/scale change are
/// purely static styling and stay on.
private struct SmartPickHighlightModifier: ViewModifier {
    let isSmartPick: Bool
    let highlightActive: Bool
    let reduceMotion: Bool
    /// 0-based rank within the smart-pick triple (0, 1, 2). Drives the numeric
    /// badge in the corner so the viewer reads "1, 2, 3" not "three identical
    /// glowing pins." `nil` for non-smart pins or when rank is unknown.
    var smartPickRank: Int? = nil

    @State private var breathe: Bool = false

    func body(content: Content) -> some View {
        // MapKit Annotation clips its overlay layer to the SwiftUI content's
        // intrinsic frame. Wrap the pin in an explicit 120pt frame so the
        // 112pt outer bloom + the corner rank badge both have room to draw
        // without being cropped to the pin's tiny native bounds.
        ZStack {
            highlightOrnament
                .compositingGroup()
            content
                .scaleEffect(scale, anchor: .center)
                .opacity(opacity)
            // Rank badge sits in the same ZStack, positioned via offset
            // relative to the 120pt canvas center so it lands at the upper-
            // right of the pin (pin is ~32pt; +16 right / -18 up lands the
            // badge just outside the pin's corner).
            rankBadge
                .offset(x: 18, y: -20)
        }
        .frame(width: 120, height: 120)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: highlightActive)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: isSmartPick)
            .onAppear {
                guard isSmartPick, highlightActive, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    breathe = true
                }
            }
            .onChange(of: highlightActive) { _, active in
                guard !reduceMotion else { return }
                if active && isSmartPick {
                    withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                        breathe = true
                    }
                } else {
                    withAnimation(nil) { breathe = false }
                }
            }
    }

    private var scale: CGFloat {
        guard highlightActive else { return 1.0 }
        return isSmartPick ? 1.0 : 0.85
    }

    private var opacity: Double {
        guard highlightActive else { return 1.0 }
        // Non-smart pins drop to 25% (was 35%) so the smart trio absolutely
        // pops. Anything above 30% on a busy OSM tile reads as "still active"
        // and steals attention from the curated picks.
        return isSmartPick ? 1.0 : 0.25
    }

    @ViewBuilder
    private var highlightOrnament: some View {
        if isSmartPick && highlightActive {
            ZStack {
                // Outermost soft bloom — wide, low-alpha gold reaching 100pt.
                // This is the layer the eye picks up first from across the map;
                // it's the "this region is special" cue before the user even
                // reads the pin shape.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                CT.sunGold.opacity(0.45),
                                CT.sunGold.opacity(0.0)
                            ],
                            center: .center,
                            startRadius: 12,
                            endRadius: 56
                        )
                    )
                    .frame(width: 112, height: 112)
                    .blur(radius: 6)
                // Core halo — tighter, brighter ring of sunGoldDeep. Bumped
                // from 0.75 → 0.95 alpha and grown to 92pt so the glow
                // survives on green/yellow OSM tiles where the previous
                // pass got eaten by the background.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                CT.sunGoldDeep.opacity(0.95),
                                CT.sunGold.opacity(0.55),
                                CT.sunGold.opacity(0.0)
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: 46
                        )
                    )
                    .frame(width: 92, height: 92)
                    .scaleEffect(reduceMotion ? 1.0 : (breathe ? 1.12 : 0.90))
                    .opacity(reduceMotion ? 0.92 : (breathe ? 1.0 : 0.78))
                // White contrast disc — sits between the glow and the inner
                // ring. Without this, the gold halo blends into the OSM
                // greens/yellows; with it, the smart pick reads as "lit from
                // within" against any tile.
                Circle()
                    .fill(Color.white.opacity(0.65))
                    .frame(width: 54, height: 54)
                    .blur(radius: 3)
                // Inner crisp ring — sun-gold stroke that hugs the pin so the
                // "this is curated" cue lands even without motion.
                Circle()
                    .strokeBorder(CT.sunGoldDeep, lineWidth: 2.4)
                    .frame(width: 52, height: 52)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Tiny numbered badge (1/2/3) anchored to the upper-right of the pin.
    /// Reads as a clear rank cue at a glance — three glowing pins look the
    /// same; "1 2 3" tells the viewer instantly which is the top pick.
    @ViewBuilder
    fileprivate var rankBadge: some View {
        if isSmartPick && highlightActive, let rank = smartPickRank {
            Text("\(rank + 1)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(
                    Circle()
                        .fill(CT.sunGoldDeep)
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                )
                .overlay(
                    Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.2)
                )
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }
}

#if DEBUG
#Preview("NowEmptyOverlay — later today") {
    let vm = MapViewModel(
        locationService: LocationService(),
        experienceService: ExperienceService(),
        aiService: AIService(),
        preferences: UserPreferences()
    )
    vm.isNowFilter = true
    return NowEmptyOverlay(viewModel: vm)
        .padding()
}
#endif
