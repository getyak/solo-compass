import SwiftUI
import SwiftData

@main
struct SoloCompassApp: App {
    @State private var locationService = LocationService.shared
    @State private var experienceService = ExperienceService()
    @State private var aiService = AIService()
    @State private var preferences = UserPreferences()
    @State private var notificationService = NotificationService.shared
    @State private var subscriptionService = SubscriptionService()

    var body: some Scene {
        WindowGroup {
            CompassMapView()
                .environment(locationService)
                .environment(experienceService)
                .environment(aiService)
                .environment(preferences)
                .environment(notificationService)
                .environment(subscriptionService)
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
                    // Refresh subscription entitlement from StoreKit on launch.
                    // Pre-launch UI already reflects the Keychain-cached value
                    // so this just confirms / corrects it once the network is up.
                    Task {
                        await subscriptionService.loadProducts()
                        await subscriptionService.refreshEntitlement()
                    }
                }
        }
        .modelContainer(SoloCompassModelContainer.shared)
    }
}
