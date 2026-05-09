import SwiftUI
import SwiftData

@main
struct SoloCompassApp: App {
    @State private var locationService = LocationService.shared
    @State private var experienceService = ExperienceService()
    @State private var aiService = AIService()
    @State private var preferences = UserPreferences()
    @State private var notificationService = NotificationService.shared

    var body: some Scene {
        WindowGroup {
            CompassMapView()
                .environment(locationService)
                .environment(experienceService)
                .environment(aiService)
                .environment(preferences)
                .environment(notificationService)
                .onAppear {
                    locationService.preferences = preferences
                    locationService.notificationService = notificationService
                    locationService.requestPermission()
                    preferences.pruneStaleCheckIns()
                    // Wire SwiftData mirroring for completion/favorite
                    // mutations and run the one-shot UserDefaults → SwiftData
                    // migration on first launch of v1.1.
                    preferences.attachRepository(experienceService.repo)
                    Task { await notificationService.checkAuthorizationStatus() }
                }
        }
        .modelContainer(SoloCompassModelContainer.shared)
    }
}
