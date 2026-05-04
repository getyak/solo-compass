import SwiftUI

@main
struct SoloCompassApp: App {
    @State private var locationService = LocationService.shared
    @State private var experienceService = ExperienceService()
    @State private var aiService = AIService()
    @State private var preferences = UserPreferences()

    var body: some Scene {
        WindowGroup {
            CompassMapView()
                .environment(locationService)
                .environment(experienceService)
                .environment(aiService)
                .environment(preferences)
                .onAppear {
                    locationService.requestPermission()
                }
        }
    }
}
