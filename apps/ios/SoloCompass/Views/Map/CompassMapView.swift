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

    @State private var viewModel: MapViewModel?
    @State private var voiceService = VoiceService()

    public init() {}

    public var body: some View {
        ZStack {
            if let viewModel {
                mapLayer(viewModel: viewModel)
                    .ignoresSafeArea()

                VStack {
                    FilterBarView(
                        selectedCategory: viewModel.selectedCategory,
                        isNowSelected: viewModel.isNowFilter,
                        onSelectNow: { viewModel.selectNowFilter() },
                        onSelectAll: { viewModel.clearFilters() },
                        onSelectCategory: { viewModel.selectCategory($0) }
                    )
                    .padding(.top, 4)
                    Spacer()
                    BottomInfoBar(text: viewModel.bottomInfoText, nearbySoloCount: viewModel.nearbySoloCount)
                        .padding(.bottom, 8)
                }

                VStack {
                    Spacer()
                    HStack {
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
                    VStack(spacing: 6) {
                        Image(systemName: "mappin.slash")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text(NSLocalizedString("map.empty.title", comment: "No experiences nearby"))
                            .font(.subheadline.weight(.medium))
                        Text(NSLocalizedString("map.empty.hint", comment: "Try adjusting filters or zooming out"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 32)
                    .accessibilityElement(children: .combine)
                }
            } else {
                ProgressView()
                    .accessibilityLabel(Text(NSLocalizedString("map.loading", comment: "Loading map")))
            }
        }
        .background(Color(red: 0xF5/255, green: 0xF0/255, blue: 0xE8/255))
        .onAppear {
            locationService.requestPermission()
            if viewModel == nil {
                viewModel = MapViewModel(
                    locationService: locationService,
                    experienceService: experienceService,
                    aiService: aiService,
                    preferences: preferences
                )
            }
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
                        onClose: { viewModel?.dismissDetail() }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func mapLayer(viewModel: MapViewModel) -> some View {
        let bindingCamera = Binding<MapCameraPosition>(
            get: { viewModel.cameraPosition },
            set: { viewModel.cameraPosition = $0 }
        )

        Map(position: bindingCamera) {
            UserAnnotation()
            ForEach(viewModel.visibleExperiences) { exp in
                Annotation(exp.title, coordinate: exp.coordinate) {
                    Button {
                        viewModel.selectExperience(exp)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        MarkerIconView(category: exp.category, state: viewModel.markerState(for: exp))
                    }
                    .buttonStyle(.plain)
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
    }
}

#Preview {
    CompassMapView()
        .environment(LocationService.shared)
        .environment(ExperienceService())
        .environment(AIService())
        .environment(UserPreferences())
}
