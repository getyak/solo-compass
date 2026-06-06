import SwiftUI
import MapKit
import os

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
    @State private var voiceOrchestrator: VoiceAgentOrchestrator? = nil

    // US-017: Companion map layer (default off)
    @State private var isCompanionLayerOn: Bool = false
    @State private var nearbyCells: [NearbyCell] = []

    // US-025: Routes section in BottomInfoSheet
    @State private var routeStore = RouteStore()
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
    @State private var lastPanAt: Date = .distantPast
    @State private var panDebounceTask: Task<Void, Never>? = nil

    // Tracks whether we've seen a disconnect so the success haptic only fires
    // after a real offline→online transition, never on cold launch.
    @State private var hasDisconnected: Bool = false

    // US-021: the city-picker first-launch prompt used to be gated by the
    // `viewModel == nil` check (true only on the first onAppear). With the
    // eager view model that guard is gone, so this one-shot flag preserves the
    // "prompt only once" behaviour across repeat onAppear fires.
    @State private var hasRunFirstAppear: Bool = false

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
            overpassService: OverpassService(useSharedCache: true)
        )
        vm.attachSubscriptionService(subscriptionService)
        _viewModel = State(initialValue: vm)
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
        return sheetPeekClearance + controlSheetGap
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
                ?? viewModel.defaultCenterForSelectedCity
        )
    }

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
                #endif
                locationService.requestPermission()
                // US-021: `viewModel` is built eagerly in `init`, so there is no
                // lazy-creation block here anymore. We only run the one-shot
                // first-launch side effects that used to live behind the
                // `viewModel == nil` guard.
                if !hasRunFirstAppear {
                    hasRunFirstAppear = true
                    // On first launch with no saved city and no GPS, prompt city picker.
                    if preferences.lastSelectedCity == nil && locationService.currentLocation == nil {
                        isShowingCityPicker = true
                    }
                    // Populate the Routes section for the initial city. `selectedCity`
                    // is resolved in the view model's init (from a persisted city or
                    // the -startCity override), so `onChange(of:selectedCity)` never
                    // fires for that initial value — without this, a cold start that
                    // lands directly on a city with seeded routes shows an empty
                    // Routes section, and 开始路线 is unreachable from the map.
                    refreshNearbyRoutes(cityCode: viewModel.selectedCity)
                }
                viewModel.checkForPendingCheckIns()
            }
            .onChange(of: locationService.currentLocation) { _, _ in
                viewModel.bindToLocation()
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
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                } else if hasDisconnected {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
            .onChange(of: viewModel.isShowingDetail) { _, showing in
                if showing {
                    HapticService.shared.impact(style: .medium)
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
            .modifier(ExploreConsentSheetModifier(viewModel: viewModel, preferences: preferences))
            .fullScreenCover(isPresented: onboardingCoverBinding) { onboardingCoverContent }
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

                MapOverlayView(
                    viewModel: viewModel,
                    isAIProcessing: aiService.isProcessing,
                    isShowingCityPicker: $isShowingCityPicker,
                    dismissedAIError: $dismissedAIError,
                    dismissedExploreError: $dismissedExploreError,
                    dismissedQuotaInfo: $dismissedQuotaInfo,
                    dismissedLocationError: $dismissedLocationError,
                    isMapPanning: $isMapPanning
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

                if viewModel.visibleExperiences.isEmpty && !isFilterActive {
                    EmptyStateOverlay(
                        viewModel: viewModel,
                        preferences: preferences,
                        locationService: locationService
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeOut(duration: 0.35), value: viewModel.visibleExperiences.isEmpty)
                } else if viewModel.visibleExperiences.isEmpty && isFilterActive && viewModel.selectedExperience == nil {
                    FilteredEmptyOverlay(viewModel: viewModel)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.easeOut(duration: 0.35), value: viewModel.visibleExperiences.isEmpty)
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
                        // D 双卡片冲突: while the floating preview card is up for
                        // a user-selected experience, the peek summary card
                        // yields so only one "best pick" card is on screen.
                        isPreviewActive: viewModel.selectedExperience != nil
                            && !viewModel.isShowingDetail
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
                                    onSelectExperience: { exp in
                                        // Unified preview path: every entry
                                        // point floats the preview card first
                                        // (no longer jumps straight to detail),
                                        // so the list row and a map-pin tap
                                        // feel identical and backing out of the
                                        // detail lands on the same card.
                                        // withAnimation drives the card's
                                        // move+fade transition for a layered
                                        // reveal instead of a hard cut.
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                            viewModel.selectExperience(exp)
                                        }
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
                            isRecompiling: viewModel.recompilingExperienceId == selected.id
                        )
                        .padding(.bottom, cardBottomInset)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
                            onEnd: {
                                withAnimation(.easeInOut(duration: 0.25)) { activeRoute = nil }
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
        }
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

    private var onboardingCoverBinding: Binding<Bool> {
        Binding(
            get: { !preferences.hasCompletedOnboarding },
            set: { if $0 { } else { preferences.completeOnboarding() } }
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
                    }
                )
                // Bind SwiftUI identity to the experience so selecting a
                // different one rebuilds the detail view AND its @State
                // view model. Without this, ExperienceDetailView's @State
                // viewModel kept the original experience and an in-detail
                // "nearby" tap changed nothing on screen. The transition
                // gives the rebuild a visible cross-fade + slide.
                .id(exp.id)
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
        LocationPickerSheet(viewModel: viewModel) {
            isShowingCityPicker = false
        }
    }

    @ViewBuilder
    private var favoritesSheetContent: some View {
        FavoritesListView(
            onSelectExperience: { exp in
                isShowingFavorites = false
                // Unified preview path (see Nearby onSelectExperience): float
                // the preview card rather than jumping straight to detail.
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
    }

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

    @ViewBuilder
    private var onboardingCoverContent: some View {
        OnboardingView {
            // onComplete — preferences.hasCompletedOnboarding already set inside
        }
        .environment(locationService)
        .environment(preferences)
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
            preferences: preferences
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
            onDismiss: { chatOrchestratorBinding.wrappedValue = nil },
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
            }
        )
        .presentationDetents([.medium, .large])
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
                ForEach(viewModel.visibleExperiences) { exp in
                    if let coord = exp.coordinate {
                        // US-016: compute the marker state once per ForEach
                        // iteration — its six conditions are otherwise evaluated
                        // twice per visible marker per frame (icon + badge).
                        let state = viewModel.markerState(for: exp)
                        Annotation(exp.title, coordinate: coord) {
                            Button {
                                viewModel.selectExperience(exp)
                                HapticService.shared.impact(style: .light)
                            } label: {
                                VStack(spacing: 2) {
                                    MarkerIconView(
                                        category: exp.category,
                                        state: state,
                                        confidenceLevel: exp.confidence.level,
                                        isSelected: viewModel.selectedExperience?.id == exp.id,
                                        // US-035: light up best-now pins when the
                                        // Now filter pill is active so the two UIs
                                        // feel connected.
                                        nowFilterActive: viewModel.isNowFilter
                                    )
                                    if case .footprinted = state {
                                        Text("\(viewModel.footprintCount(for: exp))")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Capsule().fill(Color.gray.opacity(0.85)))
                                    }
                                }
                                // Fade+scale each pin as the visible set changes
                                // so filter/pan refreshes don't flash (#133).
                                .transition(.scale.combined(with: .opacity))
                            }
                            .buttonStyle(.plain)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                ForEach(viewModel.candidateExperiences) { cand in
                    if let coord = cand.coordinate {
                        Annotation(cand.title, coordinate: coord) {
                            MarkerIconView(
                                category: cand.category,
                                state: .default,
                                confidenceLevel: cand.confidence.level,
                                isSelected: viewModel.selectedExperience?.id == cand.id
                            )
                            .accessibilityLabel(Text(String(
                                format: NSLocalizedString("map.candidate.label", comment: "Candidate experience: %@"),
                                cand.title
                            )))
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
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
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
                viewModel.refreshForLocation(context.region.center)
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.6)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onEnded { value in
                        if case .second(true, let drag?) = value,
                           let coord = proxy.convert(drag.location, from: .local) {
                            viewModel.handleMapLongPress(at: coord)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
    @Binding var isShowingCityPicker: Bool
    @Binding var dismissedAIError: String?
    @Binding var dismissedExploreError: String?
    @Binding var dismissedQuotaInfo: String?
    @Binding var dismissedLocationError: Bool
    @Binding var isMapPanning: Bool

    @State private var checkInCelebrationTrigger = 0
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
                resultCount: viewModel.visibleExperiences.count
            )
            // US-026: reset the GPS-error dismissal once the error clears so a
            // later failure re-surfaces the banner. Anchored on the always-present
            // filter bar (the banner itself is conditional, so its own onChange
            // wouldn't fire on the nil transition that removes it).
            .onChange(of: viewModel.locationErrorBannerText) { _, newValue in
                if newValue == nil { dismissedLocationError = false }
            }

            let showEmptyFilterBanner = isFilterActive && viewModel.visibleExperiences.isEmpty
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

            if isFilterActive {
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
                    color: .orange,
                    onDismiss: { dismissedAIError = errorText }
                )
            }

            if let exploreError = viewModel.lastExploreError, exploreError != dismissedExploreError {
                DismissibleBanner(
                    // `airplane.slash` is not a real SF Symbol (rendered blank);
                    // match the sibling error banners' warning glyph.
                    systemImage: "exclamationmark.triangle.fill",
                    text: exploreError,
                    color: .orange,
                    onDismiss: { dismissedExploreError = exploreError }
                )
                .accessibilityIdentifier("exploreErrorBanner")
            }

            if let quotaInfo = viewModel.lastQuotaInfo, quotaInfo != dismissedQuotaInfo {
                DismissibleBanner(
                    systemImage: "clock.badge.exclamationmark",
                    text: quotaInfo,
                    color: Color(red: 0.8, green: 0.6, blue: 0),
                    onDismiss: { dismissedQuotaInfo = quotaInfo }
                )
                .accessibilityIdentifier("quotaBanner")
            }

            // US-026: GPS failure → explain why the map fell back to a region.
            if let locationError = viewModel.locationErrorBannerText, !dismissedLocationError {
                DismissibleBanner(
                    systemImage: "location.slash.fill",
                    text: locationError,
                    color: .orange,
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
                            ? Color.secondary : Color.green)
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
        let accentGold = Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255)
        let dotColor: Color = {
            if let cat = viewModel.selectedCategory { return cat.color }
            if viewModel.isNowFilter { return accentGold }
            return Color.accentColor
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
                            Circle()
                                .fill(accentGold)
                                .frame(width: 8, height: 8)
                            Text(idleText)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(upcomingText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(accentGold)
                                .contentTransition(.numericText())
                                .animation(reduceMotion ? nil : .easeInOut, value: minutesUntil)
                        }
                    }
                    .contentTransition(.opacity)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: count)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(a11yText))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.focusOnExperience(tickedNext.experience)
                        viewModel.selectExperience(tickedNext.experience)
                    }
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.focusOnExperience(tickedNext.experience)
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
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            viewModel.clearFilters()
                        } label: {
                            Text(clearText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(dotColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .contentTransition(.opacity)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: count)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(a11yLabel))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.clearFilters()
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
            // Custom location: use the resolved label stored by LocationPickerSheet.
            if viewModel.isCustomLocation, let label = viewModel.customLocationLabel {
                return label
            }
            if let code = viewModel.selectedCity,
               let city = viewModel.availableCities.first(where: { $0.code == code }) {
                return city.name
            }
            return NSLocalizedString("city.all", comment: "All cities option")
        }()

        Button {
            isShowingCityPicker = true
        } label: {
            HStack(spacing: 4) {
                Text(cityName)
                    .font(.subheadline.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(CT.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(CT.surfaceWhite.opacity(0.78), in: Capsule())
            .frame(
                minWidth: MapOverlayMetrics.cityPillHitTarget,
                minHeight: MapOverlayMetrics.cityPillHitTarget
            )
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(cityName))
        .accessibilityHint(Text(NSLocalizedString("city.picker.title", comment: "City picker sheet title")))
    }

    /// Custom "locate me" control. Recenters the camera on the user's current
    /// location. Shows a filled arrow when a GPS fix is available, an outline
    /// (and disabled) when not. Visual treatment matches the bottom FAB cluster
    /// (.regularMaterial circle + soft shadow) so the controls read as one set.
    private var recenterButton: some View {
        let located = viewModel.hasUserLocation
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            viewModel.recenterOnUser()
        } label: {
            Image(systemName: located ? "location.fill" : "location")
                .font(.body.weight(.semibold))
                .foregroundStyle(located ? CT.accent : CT.fgSubtle)
                .frame(width: 44, height: 44)
                .background(Circle().fill(.regularMaterial))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        }
        .disabled(!located)
        .accessibilityLabel(Text(NSLocalizedString("map.recenter", comment: "Recenter map on my location")))
    }
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
                    UISelectionFeedbackGenerator().selectionChanged()
                    onShowAll()
                } label: {
                    Text(NSLocalizedString("filter.empty.showAll", comment: "Show all experiences button"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
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

private struct DismissibleBanner: View {
    let systemImage: String
    let text: String
    let color: Color
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(color)
            Text(text).font(.caption).foregroundStyle(.primary).lineLimit(2)
            Spacer()
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

            PlusActionButton(
                onShortTap: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onOpenChat(.text)
                },
                onLongPress: { onOpenChat(.voice) }
            )
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
                if isPressed { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
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
                .stroke(Color.accentColor.opacity(isPressed ? 0.5 : 0.0), lineWidth: 3)
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
                .fill(Color.black.opacity(0.85))
                .frame(width: 56, height: 56)
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                .scaleEffect(isPressed ? 1.08 : 1.0)
                .animation(.spring(response: 0.18, dampingFraction: 0.7), value: isPressed)

            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
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
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
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
        VStack(spacing: 10) {
            Image(systemName: "mappin.slash")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("map.empty.title", comment: "No experiences nearby"))
                .font(.subheadline.weight(.medium))
            Text(String(
                format: NSLocalizedString("map.empty.radius", comment: "No experiences within radius"),
                preferences.maxDistanceKm
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                // US-012: a single stage-driven primary action replaces the old
                // static button stack. The view model picks which stage we're
                // in based on consecutive empty renders + whether the user
                // already tried Expand.
                switch viewModel.emptyStateStage {
                case .tryExpand:
                    Button {
                        viewModel.emptyStateActionTryExpand()
                    } label: {
                        Text(NSLocalizedString(
                            "map.empty.stage.tryExpand",
                            comment: "Stage 1: expand search radius to 25km"
                        ))
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                case .tryExplore:
                    Button {
                        viewModel.emptyStateActionTryExplore()
                    } label: {
                        Text(NSLocalizedString(
                            "map.empty.stage.tryExplore",
                            comment: "Stage 2: widen Overpass explore to 12km"
                        ))
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                case .browseCity:
                    Button {
                        viewModel.emptyStateActionBrowseCity()
                    } label: {
                        Text(String(
                            format: NSLocalizedString(
                                "map.empty.stage.browseCity",
                                comment: "Stage 3: jump to nearest seeded city"
                            ),
                            nearestCityName ?? ""
                        ))
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }

                Button {
                    viewModel.clearFilters()
                } label: {
                    Text(NSLocalizedString("map.empty.clearFilters", comment: "Clear all filters"))
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 32)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 16)
        .accessibilityElement(children: .combine)
        .onAppear {
            viewModel.recordEmptyStateRender()
            withAnimation(.easeOut(duration: 0.35)) { isVisible = true }
        }
        .onChange(of: viewModel.visibleExperiences.count) { _, _ in
            viewModel.recordEmptyStateRender()
        }
    }
}

private struct FilteredEmptyOverlay: View {
    var viewModel: MapViewModel

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
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("map.filtered.empty.title", comment: "Nothing matches this filter"))
                .font(.subheadline.weight(.medium))
            Text(String(
                format: NSLocalizedString("map.filtered.empty.subtitle", comment: "Filter name subtitle"),
                activeFilterName
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            Button {
                let feedback = UISelectionFeedbackGenerator()
                feedback.selectionChanged()
                viewModel.clearFilters()
            } label: {
                Text(NSLocalizedString("map.empty.clearFilters", comment: "Clear all filters"))
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 32)
        .accessibilityElement(children: .combine)
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
