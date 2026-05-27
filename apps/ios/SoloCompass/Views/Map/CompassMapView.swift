import SwiftUI
import MapKit

/// THE root view. Map-first means: this is what the app *is*. No tabs. No
/// drawer. Filters and the bottom info bar overlay it; an experience card
/// floats up when a marker is tapped.
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

    @State private var viewModel: MapViewModel?
    @State private var voiceService = VoiceService()
    @State private var dismissedAIError: String? = nil
    @State private var dismissedExploreError: String? = nil
    @State private var dismissedQuotaInfo: String? = nil

    @State private var isShowingCityPicker: Bool = false
    @State private var surveyExperience: Experience? = nil
    @State private var isShowingFavorites: Bool = false
    @State private var voiceOrchestrator: VoiceAgentOrchestrator? = nil

    // US-017: Companion map layer (default off)
    @State private var isCompanionLayerOn: Bool = false
    @State private var nearbyCells: [NearbyCell] = []

    // Single chat sheet (replaces former plus-menu + voice-overlay split).
    // Presentation is driven by `voiceOrchestrator` via `.sheet(item:)`.
    @State private var chatStartMode: ChatStartMode = .text
    @State private var isMapPanning: Bool = false
    @State private var lastPanAt: Date = .distantPast
    @State private var panDebounceTask: Task<Void, Never>? = nil

    // Tracks whether we've seen a disconnect so the success haptic only fires
    // after a real offline→online transition, never on cold launch.
    @State private var hasDisconnected: Bool = false

    private let networkMonitor = NetworkMonitor.shared

    private var isFilterActive: Bool {
        (viewModel?.selectedCategory != nil) || (viewModel?.selectedCustomTag != nil) || (viewModel?.isNowFilter == true)
    }

    private var activeFilterName: String {
        if let category = viewModel?.selectedCategory {
            return category.localizedTitle
        } else if let tag = viewModel?.selectedCustomTag {
            return tag
        } else if viewModel?.isNowFilter == true {
            return NSLocalizedString("filter.now", comment: "Now filter label")
        }
        return ""
    }

    /// Idle window after the last pan before POIs refresh. Lowered from 1.5s
    /// to cut the "dragged the map, nothing happened" lag (#133).
    private static let panRefreshDebounce: TimeInterval = 0.8

    enum ChatStartMode { case text, voice }

    public init() {}

    public var body: some View {
        AnyView(mapContent)
    }

    @ViewBuilder
    private var mapContent: some View {
        mapZStack
            .background(themeService.currentTheme.background)
            .onAppear {
                locationService.requestPermission()
                if viewModel == nil {
                    // Production-only: opt into the SwiftData-backed Overpass
                    // cache so warm starts skip the network. Tests construct
                    // MapViewModel directly and stay cache-isolated via the
                    // default `OverpassService()` (repository: nil).
                    let vm = MapViewModel(
                        locationService: locationService,
                        experienceService: experienceService,
                        aiService: aiService,
                        preferences: preferences,
                        overpassService: OverpassService(useSharedCache: true)
                    )
                    vm.attachSubscriptionService(subscriptionService)
                    viewModel = vm
                    // On first launch with no saved city and no GPS, prompt city picker.
                    if preferences.lastSelectedCity == nil && locationService.currentLocation == nil {
                        isShowingCityPicker = true
                    }
                }
                viewModel?.checkForPendingCheckIns()
            }
            .onChange(of: locationService.currentLocation) { _, _ in
                viewModel?.bindToLocation()
            }
            .onChange(of: preferences.pendingCheckIns) { _, _ in
                viewModel?.checkForPendingCheckIns()
            }
            .onChange(of: viewModel?.visibleExperiences.count) { _, count in
                guard isFilterActive, UIAccessibility.isVoiceOverRunning,
                      let count, let filterName = viewModel.map({ _ in activeFilterName })
                else { return }
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
            .sheet(isPresented: settingsSheetBinding) { settingsSheetContent }
            .sheet(item: $surveyExperience) { exp in surveySheetContent(exp: exp) }
            .alert(
                NSLocalizedString("addExperience.confirm.title", comment: "Add an experience here?"),
                isPresented: addExperienceAlertBinding
            ) {
                Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) {
                    viewModel?.cancelAddExperience()
                }
                Button(NSLocalizedString("addExperience.confirm.add", comment: "Add")) {
                    viewModel?.confirmAddExperience()
                }
            } message: {
                Text(NSLocalizedString("addExperience.confirm.message", comment: "Describe it with your voice"))
            }
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
            .sheet(isPresented: paywallSheetBinding, onDismiss: { viewModel?.onPaywallUnlocked = nil }) { paywallSheetContent }
            .modifier(ExploreConsentSheetModifier(viewModel: viewModel, preferences: preferences))
            .fullScreenCover(isPresented: onboardingCoverBinding) { onboardingCoverContent }
    }

    @ViewBuilder
    private var mapZStack: some View {
        ZStack {
            if let viewModel {
                // Backing tile bleeds under every edge so the map looks
                // edge-to-edge, but the actual `Map` view keeps its top
                // safe-area inset so `.mapControls` (MapCompass +
                // MapUserLocationButton) don't collide with the status bar.
                themeService.currentTheme.background
                    .ignoresSafeArea()
                mapLayer(viewModel: viewModel)
                    .ignoresSafeArea(edges: [.bottom, .horizontal])

                MapOverlayView(
                    viewModel: viewModel,
                    isAIProcessing: aiService.isProcessing,
                    isShowingCityPicker: $isShowingCityPicker,
                    dismissedAIError: $dismissedAIError,
                    dismissedExploreError: $dismissedExploreError,
                    dismissedQuotaInfo: $dismissedQuotaInfo,
                    isMapPanning: $isMapPanning
                )

                VStack {
                    Spacer()
                    // US-017: Companion layer toggle — only rendered when FF_COMPANION is on.
                    if FeatureFlags.companion {
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
                        }
                    )
                }
                .onChange(of: isCompanionLayerOn) { _, on in
                    if on {
                        Task { await fetchNearbyCells(viewModel: viewModel) }
                    } else {
                        nearbyCells = []
                    }
                }

                if let selected = viewModel.selectedExperience, !viewModel.isShowingDetail {
                    VStack {
                        Spacer()
                        ExperienceCardView(
                            experience: selected,
                            onExpand: { viewModel.isShowingDetail = true },
                            onDismiss: { viewModel.selectedExperience = nil }
                        )
                        .padding(.bottom, 80)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
                        OfflineBanner()
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
            } else {
                ProgressView()
                    .accessibilityLabel(Text(NSLocalizedString("map.loading", comment: "Loading map")))
            }
        }
    }

    // MARK: - Sheet Bindings

    private var settingsSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel?.isShowingSettings ?? false },
            set: { if !$0 { viewModel?.isShowingSettings = false } }
        )
    }

    private var addExperienceAlertBinding: Binding<Bool> {
        Binding(
            get: { (viewModel?.pendingAddCoordinate != nil) && (viewModel?.isRecordingNewExperience == false) },
            set: { if !$0 { viewModel?.cancelAddExperience() } }
        )
    }

    private var recordExperienceSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel?.isRecordingNewExperience ?? false },
            set: { if !$0 { viewModel?.cancelAddExperience() } }
        )
    }

    private var detailSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel?.isShowingDetail ?? false },
            set: { if !$0 { viewModel?.isShowingDetail = false } }
        )
    }

    private var paywallSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel?.isShowingPaywall ?? false },
            set: { if !$0 { viewModel?.isShowingPaywall = false } }
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
            onClose: { viewModel?.isShowingSettings = false },
            onShowFavorites: { isShowingFavorites = true },
            onDistanceCommitted: { viewModel?.reloadForDistanceChange() }
        )
        .environment(preferences)
        .environment(notificationService)
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
    private var recordExperienceSheetContent: some View {
        VStack(spacing: 24) {
            Text(NSLocalizedString("addExperience.record.title", comment: "Tell us about this place"))
                .font(.headline)
            Text(NSLocalizedString("addExperience.record.hint", comment: "Hold the mic and describe what makes it worth a solo visit"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VoiceButton(voiceService: voiceService) { transcript in
                Task { await viewModel?.handleNewExperienceTranscript(transcript) }
            }
        }
        .padding(32)
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private var detailSheetContent: some View {
        if let exp = viewModel?.selectedExperience, let vm = viewModel {
            NavigationStack {
                ExperienceDetailView(
                    viewModel: ExperienceDetailViewModel(
                        experience: exp,
                        experienceService: experienceService,
                        aiService: aiService,
                        preferences: preferences,
                        subscriptionService: subscriptionService
                    ),
                    onClose: { viewModel?.dismissDetail() },
                    onMarkDone: { experience in surveyExperience = experience },
                    // US-004: open ChatSheet bound to this experience. We
                    // dismiss the detail sheet first so the chat sheet can
                    // come up cleanly (iOS won't stack two .sheet()s on the
                    // same parent reliably). The orchestrator is lazily
                    // created if needed, then `rebindContext` injects the
                    // <experience_context> system block.
                    onAskSolo: { experience in
                        viewModel?.dismissDetail()
                        // Per-card chat stays text-first. Set mode before the
                        // orchestrator assignment presents the sheet, then
                        // rebind the experience scope (still synchronous, so it
                        // lands before the sheet content is evaluated).
                        chatStartMode = .text
                        ensureOrchestrator(viewModel: vm)
                        voiceOrchestrator?.rebindContext(experience)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var cityPickerSheetContent: some View {
        if let vm = viewModel {
            LocationPickerSheet(viewModel: vm) {
                isShowingCityPicker = false
            }
        }
    }

    @ViewBuilder
    private var favoritesSheetContent: some View {
        FavoritesListView { exp in
            isShowingFavorites = false
            viewModel?.selectExperience(exp)
            viewModel?.isShowingDetail = true
        }
        .environment(experienceService)
        .environment(preferences)
    }

    @ViewBuilder
    private var paywallSheetContent: some View {
        PaywallView(onUnlocked: {
            let resume = viewModel?.onPaywallUnlocked
            viewModel?.onPaywallUnlocked = nil
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


    /// Fetch nearby companion posts and convert geohash6 fields to cell centres
    /// for the companion map layer (US-017).
    private func fetchNearbyCells(viewModel: MapViewModel) async {
        let cityCode = viewModel.selectedCity ?? ""
        await companionService.fetchDiscovery(
            params: CompanionDiscoverParams(cityCode: cityCode, mode: .nearby)
        )
        // DiscoverPost doesn't expose geohash6 yet — build NearbyCell from
        // city centroid as a placeholder until the Edge Function returns geohash6.
        // When the backend returns geohash6, map post.geohash6 → NearbyCell(geohash:).
        nearbyCells = companionService.discoverPosts.compactMap { post in
            // Use the post id as a synthetic geohash placeholder when geohash6
            // is not yet in the DiscoverPost model. This keeps the layer compilable
            // while the full geohash6 field lands in a follow-up backend deploy.
            nil // placeholder — real mapping done once DiscoverPost.geohash6 is added
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
            onDismiss: { chatOrchestratorBinding.wrappedValue = nil }
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
                UserAnnotation()
                ForEach(viewModel.visibleExperiences) { exp in
                    if let coord = exp.coordinate {
                        Annotation(exp.title, coordinate: coord) {
                            Button {
                                viewModel.selectExperience(exp)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                VStack(spacing: 2) {
                                    MarkerIconView(
                                        category: exp.category,
                                        state: viewModel.markerState(for: exp),
                                        confidenceLevel: exp.confidence.level,
                                        isSelected: viewModel.selectedExperience?.id == exp.id
                                    )
                                    if case .footprinted = viewModel.markerState(for: exp) {
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
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .mapControls {
                MapCompass()
                MapUserLocationButton()
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
}

#Preview {
    CompassMapView()
        .environment(LocationService.shared)
        .environment(ExperienceService())
        .environment(AIService())
        .environment(UserPreferences())
        .environment(CompanionService.shared)
        .environment(PresenceService.shared)
}

private extension String {
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
}

private struct MapOverlayView: View {
    var viewModel: MapViewModel
    var isAIProcessing: Bool
    @Binding var isShowingCityPicker: Bool
    @Binding var dismissedAIError: String?
    @Binding var dismissedExploreError: String?
    @Binding var dismissedQuotaInfo: String?
    @Binding var isMapPanning: Bool

    @State private var checkInCelebrationTrigger = 0

    private var isFilterActive: Bool {
        viewModel.selectedCategory != nil || viewModel.selectedCustomTag != nil || viewModel.isNowFilter
    }

    var body: some View {
        VStack {
            HStack {
                cityPill
                    .padding(.leading, 12)
                    .padding(.top, 8)
                Spacer()
            }

            FilterBarView(
                selectedCategory: viewModel.selectedCategory,
                isNowSelected: viewModel.isNowFilter,
                selectedCustomTag: viewModel.selectedCustomTag,
                nowCount: viewModel.nowCount,
                onSelectNow: { viewModel.selectNowFilter() },
                onSelectAll: { viewModel.clearFilters() },
                onSelectCategory: { viewModel.selectCategory($0) },
                onSelectCustomTag: { viewModel.selectCustomTag($0) },
                isMapPanning: $isMapPanning,
                resultCount: viewModel.visibleExperiences.count
            )
            .padding(.top, 4)

            if isFilterActive {
                filterResultBadge
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
                    systemImage: "airplane.slash",
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

            if let progressText = CompassMapView.progressText(for: viewModel.exploreProgress) {
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
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(String(
                        format: NSLocalizedString("voice.processing", comment: "AI is thinking about your request"),
                        viewModel.currentVoiceTranscript.truncated(limit: 30)
                    ))
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
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

            BottomInfoBar(text: viewModel.bottomInfoText, nearbySoloCount: viewModel.nearbySoloCount)
                .padding(.bottom, 8)

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
            if viewModel.isNowFilter, let next = viewModel.nextBestExperience {
                // "Now" filter is active, nothing is at its best, but something
                // is coming up soon — offer a one-tap jump to it.
                let idleText = NSLocalizedString("filter.now.empty.idle", comment: "Nothing's at its best now")
                let upcomingText = String(
                    format: NSLocalizedString("filter.now.empty.upcoming", comment: "%@ in %dm"),
                    next.experience.title, next.minutesUntil
                )
                let a11yText = String(
                    format: NSLocalizedString("filter.now.empty.a11y", comment: ""),
                    next.experience.title, next.minutesUntil
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
                    }
                }
                .contentTransition(.opacity)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: count)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(a11yText))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.focusOnExperience(next.experience)
                    viewModel.selectExperience(next.experience)
                }
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.focusOnExperience(next.experience)
                    viewModel.selectExperience(next.experience)
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
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .frame(
                minWidth: MapOverlayMetrics.cityPillHitTarget,
                minHeight: MapOverlayMetrics.cityPillHitTarget
            )
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(cityName))
        .accessibilityHint(Text(NSLocalizedString("city.picker.title", comment: "City picker sheet title")))
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
    let onOpenChat: (CompassMapView.ChatStartMode) -> Void

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
            .padding(.bottom, 80)
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
            .padding(.bottom, 80)
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
            .padding(.bottom, 80)
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
