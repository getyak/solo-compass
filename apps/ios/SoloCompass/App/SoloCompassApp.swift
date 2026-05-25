import SwiftUI
import SwiftData

@main
struct SoloCompassApp: App {
    init() {
        // Start Sentry as early as possible so we catch crashes during the
        // rest of App init / first render. No-op when DSN is empty.
        SentryService.bootstrap()
    }

    @State private var locationService = LocationService.shared
    @State private var experienceService = ExperienceService()
    @State private var aiService = AIService()
    @State private var preferences = UserPreferences()
    @State private var notificationService = NotificationService.shared
    @State private var subscriptionService = SubscriptionService()
    @State private var languageService = LanguageService.shared
    private let supabaseClient = SupabaseClient.shared
    private let themeService = ThemeService.shared

    var body: some Scene {
        WindowGroup {
            CompassMapView()
                .environment(locationService)
                .environment(experienceService)
                .environment(aiService)
                .environment(preferences)
                .environment(notificationService)
                .environment(subscriptionService)
                .environment(languageService)
                .environment(supabaseClient)
                .environment(\.themeService, themeService)
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
                    // Bootstrap anonymous Supabase session (Epic E US-028).
                    // No-op when FF_BACKEND_SYNC is off.
                    Task { await DeviceIdentityService.shared.bootstrap() }
                    // Start the outbox sync timer (Epic E US-029).
                    // Idempotent across re-renders.
                    SyncService.shared.start()
                }
        }
        .modelContainer(SoloCompassModelContainer.shared)
    }
}
