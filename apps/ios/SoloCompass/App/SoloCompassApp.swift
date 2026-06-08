import SwiftUI
import SwiftData
import UIKit

/// US-021: receives the APNs remote-notification callbacks that SwiftUI's
/// `App` lifecycle does not expose, and forwards the device token to
/// `PushTokenService`. Wired in via `@UIApplicationDelegateAdaptor`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in await PushTokenService.shared.handle(deviceToken: deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in PushTokenService.shared.handleRegistrationFailure(error) }
    }
}

@main
struct SoloCompassApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Start Sentry as early as possible so we catch crashes during the
        // rest of App init / first render. No-op when DSN is empty.
        SentryService.bootstrap()
    }

    @State private var locationService = LocationService.shared
    @State private var experienceService = ExperienceService()
    @State private var routeStore = RouteStore()
    // Share the global SwiftData container so AIService's quota tracking
    // (AIUsageRecord) and synthesis cache (AISynthesisCacheRecord) actually
    // persist. A bare AIService() leaves modelContext nil, silently disabling
    // both — which masks why Explore never escapes skeleton mode.
    @State private var aiService = AIService(useSharedCache: true)
    @State private var preferences = UserPreferences()
    @State private var notificationService = NotificationService.shared
    @State private var subscriptionService = SubscriptionService()
    @State private var languageService = LanguageService.shared
    @State private var companionService = CompanionService.shared
    @State private var presenceService = PresenceService.shared
    // Single 60s clock feeding every BestNowBadge (US-023). One timer for all
    // badges instead of one TimelineView per badge.
    @State private var bestNowClock = BestNowClock.shared
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
                .environment(companionService)
                .environment(presenceService)
                .environment(bestNowClock)
                .environment(supabaseClient)
                .environment(\.themeService, themeService)
                .onAppear {
                    // Location wiring stays inline: it is cheap, must happen
                    // before any region monitoring fires, and requestPermission()
                    // already hands off to the system asynchronously.
                    locationService.preferences = preferences
                    locationService.notificationService = notificationService
                    locationService.requestPermission()

                    // US-020: cold-start TTI must not block on a serial main-thread
                    // init chain. Each piece of bootstrap below is independent —
                    // there is no ordering dependency between pruning check-ins,
                    // wiring the repository, importing seed routes, loading the
                    // user directory, or refreshing the subscription entitlement.
                    // Dispatching each into its own Task lets the WindowGroup body
                    // complete (and the map render) without waiting for any of them
                    // to finish, while still running them on the main actor where
                    // the @MainActor services require it.

                    // Auto-clear stale pending check-ins.
                    Task { @MainActor in preferences.pruneStaleCheckIns() }

                    // Wire SwiftData mirroring for completion/favorite mutations
                    // and run the one-shot UserDefaults → SwiftData migration on
                    // first launch of v1.1.
                    Task { @MainActor in
                        preferences.attachRepository(experienceService.repo)
                    }

                    Task { await notificationService.checkAuthorizationStatus() }

                    // US-021: on a warm launch, re-register for remote push only
                    // when the user already granted permission. This refreshes a
                    // possibly-rotated APNs token without showing a prompt. The
                    // permission *request* itself happens later, from a social
                    // surface — never at cold start.
                    Task { await PushTokenService.shared.registerIfAuthorized() }

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

                    // Load seed user fixtures into the in-memory UserDirectory.
                    Task { @MainActor in UserDirectory.shared.loadIfNeeded() }

                    // Seed RouteStore from bundled `seed_routes.json` on first
                    // launch (no-op once any route exists). Routes referencing
                    // unknown experienceIds are skipped with an os_log warning.
                    Task { @MainActor in
                        let knownExperienceIds = Set(experienceService.allExperiences.map(\.id))
                        routeStore.importSeedIfNeeded(knownExperienceIds: knownExperienceIds)
                    }
                }
        }
        .modelContainer(SoloCompassModelContainer.shared)
    }
}
