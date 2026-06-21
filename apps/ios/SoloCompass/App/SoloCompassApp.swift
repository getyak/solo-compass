import SwiftUI
import SwiftData
import UIKit
import UserNotifications

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

    // US-023: a friend-request push delivered while the app is running (or woken
    // in the background). Route its payload to a deep link so the UI can present
    // the inbox. The completion handler is called once routing is dispatched.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            NotificationService.shared.handleRemotePayload(userInfo)
            completionHandler(.newData)
        }
    }
}

/// US-023: bridges UNUserNotificationCenter tap/foreground callbacks to the
/// NotificationService so tapping a `friend_request` banner deep-links to the
/// inbox, and a banner shown while the app is foregrounded is still visible.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let actionId = response.actionIdentifier
        Task { @MainActor in
            // US-026: a quick-action tap ("我已出发 / 查看路线 / 接受 / 查看申请")
            // routes through handleActionResponse; a plain banner tap
            // (UNNotificationDefaultActionIdentifier) keeps the prior behavior.
            if actionId == UNNotificationDefaultActionIdentifier
                || actionId == UNNotificationDismissActionIdentifier {
                NotificationService.shared.handleRemotePayload(userInfo)
            } else {
                NotificationService.shared.handleActionResponse(actionIdentifier: actionId, userInfo: userInfo)
            }
            completionHandler()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

@main
struct SoloCompassApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // #68: ExperienceCardView uses bare `AsyncImage(url:)`, which talks to
        // `URLSession.shared` and therefore shares `URLCache.shared`. The
        // system default is ~4MB memory / ~20MB disk — too small for a map
        // scrolling 40+ category thumbnails. Bumping the shared cache before
        // any image fires lets cards hit cache on the second pass instead of
        // re-downloading. 50MB mem / 200MB disk keeps disk usage modest
        // (images are small JPEGs). Must run before App body materializes any
        // view that triggers a fetch.
        URLCache.shared = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024
        )

        // Start Sentry as early as possible so we catch crashes during the
        // rest of App init / first render. No-op when DSN is empty.
        SentryService.bootstrap()

        // US-023: own the notification-center delegate so a tapped friend-request
        // banner routes to the inbox deep link (and foreground banners still show).
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared

        // US-026: register the departure / join-request categories so their quick
        // actions ("我已出发 / 查看路线", "接受 / 查看申请") attach to the banners.
        SCNotificationCategory.registerAll()
    }

    @State private var locationService = LocationService.shared
    @State private var experienceService = ExperienceService()
    @State private var routeStore = RouteStore()
    // Traveler co-build layer (notes + corrections). Shares the global SwiftData
    // container; the detail page reads it via @Environment.
    @State private var travelerNoteStore = TravelerNoteStore()
    // Share the global SwiftData container so AIService's quota tracking
    // (AIUsageRecord) and synthesis cache (AISynthesisCacheRecord) actually
    // persist. A bare AIService() leaves modelContext nil, silently disabling
    // both — which masks why Explore never escapes skeleton mode.
    @State private var aiService = AIService(useSharedCache: true)
    @State private var preferences = UserPreferences()
    @State private var notificationService = NotificationService.shared
    // US-026: Live Activities / Dynamic Island controller. Started/ended from
    // the route, companion-countdown, recording, and AI-compile flows.
    @State private var liveActivityService = LiveActivityService.shared
    @State private var subscriptionService = SubscriptionService()
    @State private var languageService = LanguageService.shared
    @State private var companionService = CompanionService.shared
    @State private var presenceService = PresenceService.shared
    // Single 60s clock feeding every BestNowBadge (US-023). One timer for all
    // badges instead of one TimelineView per badge.
    @State private var bestNowClock = BestNowClock.shared
    private let supabaseClient = SupabaseClient.shared
    private let themeService = ThemeService.shared

    /// First-launch Terms / Privacy gate. Reads UserDefaults at init so the
    /// gate fires synchronously before any data-touching code runs in body.
    /// Set to true via TermsConsentSheet.onAccept — same UserDefaults key
    /// the static `hasAccepted` reads, so the cover dismisses immediately.
    @State private var showingTermsSheet: Bool = !TermsConsentSheet.hasAccepted

    var body: some Scene {
        WindowGroup {
            CompassMapView()
                .environment(locationService)
                .environment(experienceService)
                .environment(travelerNoteStore)
                .environment(aiService)
                .environment(preferences)
                .environment(notificationService)
                .environment(liveActivityService)
                .environment(subscriptionService)
                .environment(languageService)
                .environment(companionService)
                .environment(presenceService)
                .environment(bestNowClock)
                .environment(supabaseClient)
                .environment(\.themeService, themeService)
                .onOpenURL { url in
                    // solocompass:// share-sheet / paste-link entry. Routes
                    // through the same pendingDeepLink mechanism APNs uses
                    // so CompassMapView's existing observer handles them.
                    NotificationService.shared.handleURL(url)
                }
                .fullScreenCover(isPresented: $showingTermsSheet) {
                    // Terms + data-use disclosure — App Store 5.1.1 / PIPL /
                    // GDPR require affirmative consent before any data is
                    // collected. fullScreenCover (not sheet) so the user
                    // can't swipe-dismiss; TermsConsentSheet also calls
                    // .interactiveDismissDisabled() for belt-and-suspenders.
                    TermsConsentSheet(
                        onAccept: {
                            showingTermsSheet = false
                            // First user-initiated tap is the right moment to
                            // ask for push permission — the iOS prompt now has
                            // context ("I just said yes to Solo Compass, of
                            // course it wants to notify me"). PushTokenService
                            // is idempotent so a re-grant on later launches
                            // is a no-op. Without this hook, push was never
                            // requested cold-start and the user discovered it
                            // only after opening Friends or Settings.
                            Task { await PushTokenService.shared.requestAuthorizationAndRegister() }
                        },
                        onDecline: {
                            // Per Apple HIG, declining is allowed — the app
                            // degrades to view-only / no-data-out mode. For
                            // now we just dismiss + leave the bit unset, so
                            // the gate re-fires next launch. A future task
                            // can route into a true "no data" mode.
                            showingTermsSheet = false
                        }
                    )
                }
                .onAppear {
                    // TipKit bootstrap — registers the tip database + bumps
                    // the cold-launch counter that `FilterBarTip.rules` reads.
                    // Idempotent / non-throwing; tips just no-op on failure.
                    SoloCompassTips.bootstrap()

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
