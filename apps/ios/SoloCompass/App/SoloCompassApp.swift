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

    /// First-launch gate state machine. Terms then Onboarding were previously
    /// driven by two separate `.fullScreenCover` modifiers on different views
    /// in the tree — SwiftUI silently drops one when stacked, which let a
    /// fresh install skip onboarding entirely. A single enum-driven cover
    /// keeps the sequence intact and transitions Terms → Onboarding without
    /// a dismiss/re-present race.
    private enum FirstLaunchCover: Identifiable {
        case terms
        case onboarding
        var id: Int { self == .terms ? 0 : 1 }
    }

    @State private var firstLaunchCover: FirstLaunchCover? = !TermsConsentSheet.hasAccepted ? .terms : nil

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
                .fullScreenCover(item: $firstLaunchCover) { cover in
                    // Terms + data-use disclosure — App Store 5.1.1 / PIPL /
                    // GDPR require affirmative consent before any data is
                    // collected. fullScreenCover (not sheet) so the user
                    // can't swipe-dismiss; TermsConsentSheet also calls
                    // .interactiveDismissDisabled() for belt-and-suspenders.
                    // Onboarding lives on the same cover so SwiftUI can't
                    // arbitrate two stacked fullScreenCovers and drop one.
                    switch cover {
                    case .terms:
                        TermsConsentSheet(
                            onAccept: {
                                // Transition straight to onboarding (or finish
                                // the gate if already done) instead of letting
                                // the cover fully dismiss and re-present —
                                // that race is exactly what hid onboarding on
                                // fresh installs.
                                firstLaunchCover = preferences.hasCompletedOnboarding ? nil : .onboarding
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
                                // Per Apple 5.1.1 / PIPL / GDPR: refusal must NOT
                                // grant silent access. Keep the cover up — the
                                // sheet itself swaps to a permanent disabled-state
                                // screen with a "Review again" button. The
                                // `acceptedKey` UserDefaults bit stays unset, so
                                // the gate also re-fires next launch.
                            }
                        )
                    case .onboarding:
                        OnboardingView {
                            // OnboardingView sets preferences.hasCompletedOnboarding
                            // internally via preferences.completeOnboarding().
                            firstLaunchCover = nil
                        }
                        .environment(locationService)
                        .environment(preferences)
                    }
                }
                .onAppear {
                    // If terms were accepted on a previous launch but the
                    // 4-step onboarding never completed (user killed the app
                    // mid-flow), surface onboarding now. The Terms-accept
                    // branch in the cover handles the same case for first
                    // launches; this covers warm re-entry.
                    if firstLaunchCover == nil
                        && TermsConsentSheet.hasAccepted
                        && !preferences.hasCompletedOnboarding {
                        firstLaunchCover = .onboarding
                    }

                    runBootstrapIfConsented()
                }
                .onChange(of: firstLaunchCover) { _, cover in
                    // Bridge consent → bootstrap. .onAppear fires once when
                    // CompassMapView first enters the hierarchy, which on a
                    // fresh install is BEFORE the user has tapped Accept; it
                    // does NOT fire again when the cover dismisses. Without
                    // this hook the user accepts → cover closes → map sits
                    // dark until next cold launch. Fires when the cover state
                    // settles to nil (terms accepted + onboarding done, or
                    // onboarding skipped). Idempotent: each service inside
                    // runBootstrapIfConsented re-entry-safe.
                    if cover == nil { runBootstrapIfConsented() }
                }
        }
        .modelContainer(SoloCompassModelContainer.shared)
    }

    /// Cold-start bootstrap, deferred until after the Terms gate clears.
    /// Touches location, push, AI cache, Supabase session, outbox sync, seed
    /// loaders — none of which may run before affirmative consent (App Store
    /// 5.1.1 / PIPL / GDPR). Idempotent across re-entry — each Task wraps a
    /// service that is itself idempotent.
    @MainActor
    private func runBootstrapIfConsented() {
        // Block bootstrap while EITHER cover (terms or onboarding) is up.
        // Terms is the legal gate; onboarding is the UX gate but doesn't
        // expose any data-out surface, so we only hard-block on terms.
        guard TermsConsentSheet.hasAccepted else { return }

        // TipKit bootstrap — registers the tip database + bumps the
        // cold-launch counter that `FilterBarTip.rules` reads. Idempotent
        // / non-throwing; tips just no-op on failure.
        SoloCompassTips.bootstrap()

        // Location wiring stays inline: it is cheap, must happen before any
        // region monitoring fires, and requestPermission() already hands off
        // to the system asynchronously.
        locationService.preferences = preferences
        locationService.notificationService = notificationService
        locationService.requestPermission()

        // US-020: cold-start TTI must not block on a serial main-thread
        // init chain. Each piece of bootstrap below is independent — no
        // ordering dependency between pruning check-ins, wiring the
        // repository, importing seed routes, loading the user directory,
        // or refreshing the subscription entitlement. Dispatching each
        // into its own Task lets the WindowGroup body complete (and the
        // map render) without waiting on any of them.

        Task { @MainActor in preferences.pruneStaleCheckIns() }

        Task { @MainActor in
            preferences.attachRepository(experienceService.repo)
        }

        Task { await notificationService.checkAuthorizationStatus() }

        // US-021: on a warm launch, re-register for remote push only when
        // the user already granted permission. Refreshes a possibly-rotated
        // APNs token without showing a prompt.
        Task { await PushTokenService.shared.registerIfAuthorized() }

        Task {
            await subscriptionService.loadProducts()
            await subscriptionService.refreshEntitlement()
        }
        Task { await DeviceIdentityService.shared.bootstrap() }
        SyncService.shared.start()

        Task { @MainActor in UserDirectory.shared.loadIfNeeded() }

        Task { @MainActor in
            let knownExperienceIds = Set(experienceService.allExperiences.map(\.id))
            routeStore.importSeedIfNeeded(knownExperienceIds: knownExperienceIds)
        }
    }
}
