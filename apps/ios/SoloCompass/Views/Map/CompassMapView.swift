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

    @State private var viewModel: MapViewModel?
    @State private var voiceService = VoiceService()
    @State private var dismissedAIError: String? = nil
    @State private var dismissedExploreError: String? = nil
    @State private var dismissedQuotaInfo: String? = nil

    @State private var isShowingCityPicker: Bool = false
    @State private var surveyExperience: Experience? = nil
    @State private var isShowingFavorites: Bool = false
    @State private var voiceOrchestrator: VoiceAgentOrchestrator? = nil

    // "+" quick-action menu state
    @State private var isShowingPlusMenu: Bool = false

    // Voice agent inline overlay (long-press path)
    @State private var isShowingVoiceOverlay: Bool = false


    public init() {}

    public var body: some View {
        ZStack {
            if let viewModel {
                mapLayer(viewModel: viewModel)
                    .ignoresSafeArea()

                MapOverlayView(
                    viewModel: viewModel,
                    isAIProcessing: aiService.isProcessing,
                    isShowingCityPicker: $isShowingCityPicker,
                    dismissedAIError: $dismissedAIError,
                    dismissedExploreError: $dismissedExploreError,
                    dismissedQuotaInfo: $dismissedQuotaInfo
                )

                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        Button {
                            viewModel.isShowingSettings = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.title3)
                                .frame(width: 48, height: 48)
                                .background(Circle().fill(.regularMaterial))
                                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 20)
                        .padding(.bottom, 80)
                        .accessibilityLabel(Text(NSLocalizedString("settings.title", comment: "Settings")))

                        // Explore-here button — pulls real OSM POIs near the
                        // current location and asks AIService to enrich them.
                        // US-026: free users see "Explore (Pro)" with a lock icon;
                        // tapping triggers the paywall instead of an actual Pro call.
                        Button {
                            let anchor = viewModel.exploreAnchorCoordinate
                            Task { await viewModel.exploreNearby(at: anchor) }
                        } label: {
                            Group {
                                if viewModel.isExploring || viewModel.isExploringFreeMode {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                } else if viewModel.isProUser {
                                    Image(systemName: "sparkle.magnifyingglass")
                                        .font(.title3)
                                } else {
                                    HStack(spacing: 4) {
                                        Image(systemName: "lock.fill")
                                            .font(.caption.weight(.semibold))
                                        Text(NSLocalizedString("explore.button.pro", comment: "Explore (Pro)"))
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 8)
                                }
                            }
                            .frame(minWidth: 48, minHeight: 48)
                            .background(Capsule().fill(.regularMaterial))
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 12)
                        .padding(.bottom, 80)
                        .disabled(viewModel.isExploring || viewModel.isExploringFreeMode)
                        .accessibilityLabel(Text(
                            viewModel.isProUser
                                ? NSLocalizedString("explore.button", comment: "Explore here")
                                : NSLocalizedString("explore.button.pro", comment: "Explore (Pro)")
                        ))

                        Spacer()

                        // "+" button: short tap → quick-action menu,
                        // long press (≥0.8s) → inline voice agent mode.
                        PlusActionButton(
                            isShowingMenu: $isShowingPlusMenu,
                            onShortTap: {
                                guard !isShowingVoiceOverlay else { return }
                                isShowingPlusMenu = true
                            },
                            onLongPress: {
                                guard !isShowingVoiceOverlay, voiceOrchestrator == nil else { return }
                                isShowingPlusMenu = false
                                let orch = VoiceAgentOrchestrator(
                                    aiService: aiService,
                                    voiceService: voiceService,
                                    mapViewModel: viewModel,
                                    preferences: preferences
                                )
                                orch.start()
                                voiceOrchestrator = orch
                                isShowingVoiceOverlay = true
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            }
                        )
                        .padding(.trailing, 20)
                        .padding(.bottom, 80)
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

                // Inline voice agent overlay (long-press path — no sheet)
                if isShowingVoiceOverlay, let orch = voiceOrchestrator {
                    ZStack(alignment: .bottom) {
                        Color.black.opacity(0.25)
                            .ignoresSafeArea()
                            .onTapGesture { } // absorb taps to map

                        VStack(spacing: 0) {
                            // Thinking overlay at top of safe area
                            ThinkingOverlay(
                                stepLabel: orch.thinkingStep,
                                streamingText: orch.streamingContent,
                                isExecutingTool: orch.isExecutingTool,
                                errorMessage: orch.errorMessage
                            )
                            .padding(.top, 100)

                            Spacer()

                            VoiceAgentOverlay(
                                orchestrator: orch,
                                voiceService: voiceService,
                                onDismiss: {
                                    orch.stop()
                                    voiceOrchestrator = nil
                                    isShowingVoiceOverlay = false
                                }
                            )
                        }
                    }
                    .transition(.opacity)
                }

                if viewModel.visibleExperiences.isEmpty && !isShowingVoiceOverlay {
                    EmptyStateOverlay(
                        viewModel: viewModel,
                        preferences: preferences,
                        locationService: locationService
                    )
                }
            } else {
                ProgressView()
                    .accessibilityLabel(Text(NSLocalizedString("map.loading", comment: "Loading map")))
            }
        }
        .background(Color(.systemBackground))
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
        // Settings sheet
        .sheet(isPresented: Binding(
            get: { viewModel?.isShowingSettings ?? false },
            set: { if !$0 { viewModel?.isShowingSettings = false } }
        )) {
            SettingsView(
                onClose: { viewModel?.isShowingSettings = false },
                onShowFavorites: { isShowingFavorites = true }
            )
            .environment(preferences)
            .environment(notificationService)
        }
        // MicroSurvey sheet (shown after marking an experience done)
        .sheet(item: $surveyExperience) { exp in
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
        .alert(
            NSLocalizedString("addExperience.confirm.title", comment: "Add an experience here?"),
            isPresented: Binding(
                get: { (viewModel?.pendingAddCoordinate != nil) && (viewModel?.isRecordingNewExperience == false) },
                set: { if !$0 { viewModel?.cancelAddExperience() } }
            )
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
        .sheet(isPresented: Binding(
            get: { viewModel?.isRecordingNewExperience ?? false },
            set: { if !$0 { viewModel?.cancelAddExperience() } }
        )) {
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
        .sheet(isPresented: Binding(
            get: { viewModel?.isShowingDetail ?? false },
            set: { if !$0 { viewModel?.isShowingDetail = false } }
        )) {
            if let exp = viewModel?.selectedExperience {
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
                        onMarkDone: { experience in surveyExperience = experience }
                    )
                }
            }
        }
        .sheet(isPresented: $isShowingCityPicker) {
            if let vm = viewModel {
                CityPickerSheet(viewModel: vm) {
                    isShowingCityPicker = false
                }
            }
        }
        // Favorites list sheet
        .sheet(isPresented: $isShowingFavorites) {
            FavoritesListView { exp in
                isShowingFavorites = false
                viewModel?.selectExperience(exp)
                viewModel?.isShowingDetail = true
            }
            .environment(experienceService)
            .environment(preferences)
        }
        // "+" quick-action menu sheet
        .sheet(isPresented: $isShowingPlusMenu) {
            if let vm = viewModel {
                PlusMenuSheet(
                    isPresented: $isShowingPlusMenu,
                    onQuickAsk: { text in
                        isShowingPlusMenu = false
                        // Create orchestrator for text-based quick ask
                        let orch = VoiceAgentOrchestrator(
                            aiService: aiService,
                            voiceService: voiceService,
                            mapViewModel: vm,
                            preferences: preferences
                        )
                        orch.start()
                        voiceOrchestrator = orch
                        orch.handleTextInput(text)
                        isShowingVoiceOverlay = true
                    },
                    onFilter: {
                        isShowingPlusMenu = false
                        // FilterBarView is already visible; scroll/highlight it
                    },
                    onNavigate: { destination in
                        isShowingPlusMenu = false
                        Task { await vm.handleVoiceTranscript("Navigate to \(destination)") }
                    },
                    onVoiceAgent: {
                        isShowingPlusMenu = false
                        let orch = VoiceAgentOrchestrator(
                            aiService: aiService,
                            voiceService: voiceService,
                            mapViewModel: vm,
                            preferences: preferences
                        )
                        orch.start()
                        voiceOrchestrator = orch
                        isShowingVoiceOverlay = true
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
        // ConversationSheet kept for text-mode multi-turn (fallback / text input path via overlay)
        // Voice agent conversation sheet — opened by tapping "Ask Solo" in + menu when already running.
        .sheet(isPresented: Binding(
            get: {
                // Only show sheet when orchestrator is running but NOT showing inline overlay
                voiceOrchestrator != nil && !isShowingVoiceOverlay
            },
            set: { showing in
                if !showing {
                    voiceOrchestrator?.stop()
                    voiceOrchestrator = nil
                }
            }
        )) {
            if let orch = voiceOrchestrator {
                ConversationSheet(
                    onClose: {
                        orch.stop()
                        voiceOrchestrator = nil
                    },
                    onSubmitText: { orch.handleTextInput($0) },
                    voiceService: voiceService,
                    onVoiceTranscript: { orch.handleTranscript($0) },
                    orchestrator: orch
                )
                .environment(orch.session)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        // US-024 paywall sheet — shown when a free user taps an AI-gated
        // action. The view's onUnlocked closure resumes the original
        // action (saved by MapViewModel as `onPaywallUnlocked`).
        .sheet(isPresented: Binding(
            get: { viewModel?.isShowingPaywall ?? false },
            set: { if !$0 { viewModel?.isShowingPaywall = false } }
        )) {
            PaywallView(onUnlocked: {
                let resume = viewModel?.onPaywallUnlocked
                viewModel?.onPaywallUnlocked = nil
                resume?()
            })
            .environment(subscriptionService)
        }
        .modifier(ExploreConsentSheetModifier(
            viewModel: viewModel,
            preferences: preferences
        ))
        // First-run onboarding
        .fullScreenCover(isPresented: Binding(
            get: { !preferences.hasCompletedOnboarding },
            set: { if $0 { } else { preferences.completeOnboarding() } }
        )) {
            OnboardingView {
                // onComplete — preferences.hasCompletedOnboarding already set inside
            }
            .environment(locationService)
            .environment(preferences)
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
                onSelectCategory: { viewModel.selectCategory($0) }
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

/// Bottom-right "+" button. Short tap fires `onShortTap`; long press (≥0.8s)
/// fires `onLongPress` and provides haptic feedback.
/// Bottom-right "+" button. Short tap fires `onShortTap`; long press (≥0.8s)
/// fires `onLongPress` and provides haptic feedback.
///
/// Uses a sequenced ExclusiveGesture: long press takes priority over tap so
/// a held gesture doesn't also fire the menu.
private struct PlusActionButton: View {
    @Binding var isShowingMenu: Bool
    let onShortTap: () -> Void
    let onLongPress: () -> Void

    @State private var longPressFired = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.85))
                .frame(width: 56, height: 56)
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                .scaleEffect(longPressFired ? 1.12 : 1.0)
                .animation(.spring(response: 0.25), value: longPressFired)

            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in
                    defer { longPressFired = false }
                    guard !longPressFired else { return }
                    onShortTap()
                }
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.8)
                .onEnded { _ in
                    longPressFired = true
                    onLongPress()
                }
        )
        .accessibilityLabel(Text(NSLocalizedString("plus.button.a11y", comment: "Quick actions")))
        .accessibilityHint(Text(NSLocalizedString("plus.button.hint", comment: "Tap for quick actions, hold for voice")))
    }
}

/// Quick-action sheet opened by tapping the "+" button.
private struct PlusMenuSheet: View {
    @Binding var isPresented: Bool
    let onQuickAsk: (String) -> Void
    let onFilter: () -> Void
    let onNavigate: (String) -> Void
    let onVoiceAgent: () -> Void

    @State private var askText: String = ""
    @State private var navigateText: String = ""
    @FocusState private var askFieldFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Quick Ask
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            NSLocalizedString("plus.menu.ask", comment: "Ask Solo"),
                            systemImage: "bubble.left.fill"
                        )
                        .font(.subheadline.weight(.semibold))

                        HStack(spacing: 8) {
                            TextField(
                                NSLocalizedString("plus.menu.ask.placeholder", comment: "What are you looking for?"),
                                text: $askText
                            )
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.send)
                            .focused($askFieldFocused)
                            .onSubmit { submitAsk() }

                            Button(action: submitAsk) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(askText.isEmpty ? Color.secondary : Color.accentColor)
                            }
                            .disabled(askText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(.vertical, 4)

                    // Voice agent
                    Button(action: onVoiceAgent) {
                        Label(
                            NSLocalizedString("plus.menu.voice", comment: "Voice Agent"),
                            systemImage: "mic.fill"
                        )
                    }
                    .foregroundStyle(.primary)
                }

                Section {
                    // Filter Map
                    Button(action: onFilter) {
                        Label(
                            NSLocalizedString("plus.menu.filter", comment: "Filter Map"),
                            systemImage: "line.3.horizontal.decrease.circle"
                        )
                    }
                    .foregroundStyle(.primary)

                    // Navigate To
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            NSLocalizedString("plus.menu.navigate", comment: "Navigate To…"),
                            systemImage: "arrow.triangle.turn.up.right.circle.fill"
                        )
                        .font(.subheadline.weight(.semibold))

                        HStack(spacing: 8) {
                            TextField(
                                NSLocalizedString("plus.menu.navigate.placeholder", comment: "Destination…"),
                                text: $navigateText
                            )
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.go)
                            .onSubmit { submitNavigate() }

                            Button(action: submitNavigate) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(navigateText.isEmpty ? Color.secondary : Color.accentColor)
                            }
                            .disabled(navigateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(NSLocalizedString("plus.menu.title", comment: "Quick Actions"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("common.close", comment: "Close")) {
                        isPresented = false
                    }
                }
            }
        }
        .onAppear { askFieldFocused = true }
    }

    private func submitAsk() {
        let trimmed = askText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onQuickAsk(trimmed)
    }

    private func submitNavigate() {
        let trimmed = navigateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onNavigate(trimmed)
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
