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

    @State private var viewModel: MapViewModel?
    @State private var voiceService = VoiceService()
    @State private var dismissedAIError: String? = nil
    @State private var dismissedExploreError: String? = nil
    @State private var dismissedQuotaInfo: String? = nil

    @State private var isShowingCityPicker: Bool = false
    @State private var surveyExperience: Experience? = nil
    @State private var isShowingFavorites: Bool = false
    @State private var voiceOrchestrator: VoiceAgentOrchestrator? = nil

    // Single chat sheet (replaces former plus-menu + voice-overlay split).
    @State private var isShowingChat: Bool = false
    @State private var chatStartMode: ChatStartMode = .text
    @State private var isMapPanning: Bool = false
    @State private var lastPanAt: Date = .distantPast
    @State private var panDebounceTask: Task<Void, Never>? = nil

    private let networkMonitor = NetworkMonitor.shared

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
                    let vm = MapViewModel(
                        locationService: locationService,
                        experienceService: experienceService,
                        aiService: aiService,
                        preferences: preferences
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
            .sheet(isPresented: $isShowingChat, onDismiss: {
                // US-004: explicitly unscope before tearing down so a future
                // global "+" chat — even if we ever stop discarding the
                // orchestrator on dismiss — never inherits an <experience_context>
                // block from a per-card session.
                voiceOrchestrator?.rebindContext(nil)
                voiceOrchestrator?.stop()
                voiceOrchestrator = nil
            }) { chatSheetContent }
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
                    MapControlBar(
                        viewModel: viewModel,
                        aiService: aiService,
                        voiceService: voiceService,
                        preferences: preferences,
                        voiceOrchestrator: $voiceOrchestrator,
                        onOpenChat: { mode in
                            ensureOrchestrator(viewModel: viewModel)
                            chatStartMode = mode
                            isShowingChat = true
                        }
                    )
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

                if viewModel.visibleExperiences.isEmpty {
                    EmptyStateOverlay(
                        viewModel: viewModel,
                        preferences: preferences,
                        locationService: locationService
                    )
                }

                // Offline banner (US-041): amber pill when network is unavailable
                if !networkMonitor.isConnected {
                    VStack {
                        OfflineBanner()
                            .padding(.top, 8)
                        Spacer()
                    }
                    .animation(.easeInOut, value: networkMonitor.isConnected)
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
                        ensureOrchestrator(viewModel: vm)
                        voiceOrchestrator?.rebindContext(experience)
                        chatStartMode = .text
                        isShowingChat = true
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var cityPickerSheetContent: some View {
        if let vm = viewModel {
            CityPickerSheet(viewModel: vm) {
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

    @ViewBuilder
    private var chatSheetContent: some View {
        if let orch = voiceOrchestrator {
            ChatSheet(
                orchestrator: orch,
                voiceService: voiceService,
                startInVoiceMode: chatStartMode == .voice,
                onDismiss: {
                    // US-004: explicit unscope on close mirrors the .sheet
                    // `onDismiss` path so the in-view "X" button is just as
                    // safe as a swipe-down.
                    orch.rebindContext(nil)
                    orch.stop()
                    voiceOrchestrator = nil
                    isShowingChat = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
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
                                        confidenceLevel: exp.confidence.level
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
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                ForEach(viewModel.candidateExperiences) { cand in
                    if let coord = cand.coordinate {
                        Annotation(cand.title, coordinate: coord) {
                            MarkerIconView(
                                category: cand.category,
                                state: .default,
                                confidenceLevel: cand.confidence.level
                            )
                            .accessibilityLabel(Text(String(
                                format: NSLocalizedString("map.candidate.label", comment: "Candidate experience: %@"),
                                cand.title
                            )))
                        }
                    }
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
                        } while Date().timeIntervalSince(lastPanAt) < 1.5
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
        case .scanning(let done, let total):
            return String(
                format: NSLocalizedString("explore.progress.scanning", comment: "ring m of n"),
                done, total
            )
        case .synthesizing(let count):
            return String(
                format: NSLocalizedString("explore.progress.synthesizing", comment: "n places"),
                count
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
}

private extension String {
    func truncated(limit: Int) -> String {
        guard count > limit else { return self }
        return String(prefix(limit)) + "…"
    }
}

private struct MapOverlayView: View {
    var viewModel: MapViewModel
    var isAIProcessing: Bool
    @Binding var isShowingCityPicker: Bool
    @Binding var dismissedAIError: String?
    @Binding var dismissedExploreError: String?
    @Binding var dismissedQuotaInfo: String?
    @Binding var isMapPanning: Bool

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
                onSelectNow: { viewModel.selectNowFilter() },
                onSelectAll: { viewModel.clearFilters() },
                onSelectCategory: { viewModel.selectCategory($0) },
                isMapPanning: $isMapPanning
            )
            .padding(.top, 4)

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
                PendingCheckInBanner(
                    experienceTitle: pending.title,
                    onConfirm: { viewModel.confirmCheckIn() },
                    onDismiss: { viewModel.dismissCheckIn() }
                )
                .padding(.bottom, 4)
                .animation(.spring(response: 0.4), value: viewModel.pendingCheckIn != nil)
            }
        }
    }

    @ViewBuilder
    private var cityPill: some View {
        let cityName: String = {
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
                Button {
                    preferences.maxDistanceKm = 25
                    viewModel.loadNearbyExperiences()
                    viewModel.updateBottomInfo()
                } label: {
                    Text(NSLocalizedString("map.empty.expand", comment: "Expand search radius to 25km"))
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                if let nearestCode = viewModel.nearestSeededCity(
                    to: locationService.currentLocation?.coordinate ?? viewModel.defaultCenterForSelectedCity
                ),
                   let nearestCity = viewModel.availableCities.first(where: { $0.code == nearestCode }) {
                    Button {
                        viewModel.selectCity(nearestCode)
                    } label: {
                        Text(String(
                            format: NSLocalizedString("map.empty.browse", comment: "Browse nearest city"),
                            nearestCity.name
                        ))
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
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
        .accessibilityElement(children: .combine)
    }
}
