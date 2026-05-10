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

    @State private var isShowingCityPicker: Bool = false
    @State private var surveyExperience: Experience? = nil
    @State private var isShowingFavorites: Bool = false


    public init() {}

    public var body: some View {
        ZStack {
            if let viewModel {
                mapLayer(viewModel: viewModel)
                    .ignoresSafeArea()

                VStack {
                    HStack {
                        cityPill(viewModel: viewModel)
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

                    // AI / voice error banner — dismissible, shown below filter bar.
                    if let errorText = viewModel.lastAIError, errorText != dismissedAIError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(errorText)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Spacer()
                            Button {
                                dismissedAIError = errorText
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityLabel(Text(NSLocalizedString("common.dismiss", comment: "Dismiss error")))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(Text(errorText))
                    }

                    Spacer()

                    // AI processing indicator — shown above the bottom info bar.
                    if aiService.isProcessing {
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

                    BottomInfoBar(text: viewModel.bottomInfoText, nearbySoloCount: viewModel.nearbySoloCount)
                        .padding(.bottom, 8)

                    // Pending check-in banner (geofence fired while user was nearby)
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
                        // Free users see a lock overlay; tapping triggers the
                        // paywall (Epic D US-024) instead of an actual call.
                        Button {
                            let anchor = viewModel.exploreAnchorCoordinate
                            Task { await viewModel.exploreNearby(at: anchor) }
                        } label: {
                            Group {
                                if viewModel.isExploring {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                } else {
                                    ZStack(alignment: .topTrailing) {
                                        Image(systemName: "sparkle.magnifyingglass")
                                            .font(.title3)
                                        if !viewModel.isProUser {
                                            Image(systemName: "lock.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.white)
                                                .padding(3)
                                                .background(Circle().fill(Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255)))
                                                .offset(x: 8, y: -8)
                                        }
                                    }
                                }
                            }
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(.regularMaterial))
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 12)
                        .padding(.bottom, 80)
                        .disabled(viewModel.isExploring)
                        .accessibilityLabel(Text(
                            viewModel.isProUser
                                ? NSLocalizedString("explore.button", comment: "Explore here")
                                : NSLocalizedString("explore.button.pro", comment: "Explore (Pro)")
                        ))

                        Spacer()

                        VoiceButton(voiceService: voiceService) { transcript in
                            Task { await viewModel.handleVoiceTranscript(transcript) }
                        }
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

                if viewModel.visibleExperiences.isEmpty {
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
                            preferences: preferences
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

    // MARK: - City pill

    @ViewBuilder
    private func cityPill(viewModel: MapViewModel) -> some View {
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
                            Circle()
                                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                                .frame(width: 36, height: 36)
                                .foregroundStyle(Color.gray)
                                .background(Circle().fill(Color.white.opacity(0.6)))
                                .overlay(
                                    Image(systemName: "plus")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.gray)
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
}

#Preview {
    CompassMapView()
        .environment(LocationService.shared)
        .environment(ExperienceService())
        .environment(AIService())
        .environment(UserPreferences())
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
