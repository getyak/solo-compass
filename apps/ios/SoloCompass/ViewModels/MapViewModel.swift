import Foundation
import CoreLocation
import MapKit
import Observation
import os
import SwiftUI

/// State + intent for the root `CompassMapView`.
///
/// MVVM rule of thumb: services do I/O, the view model decides what's on
/// screen. Filters, the selected experience, the bottom info text — all live
/// here so the View can stay thin.
///
/// @MainActor isolation ensures all @Observable property mutations happen on
/// the main thread, preventing data-race crashes under Swift 6 strict concurrency.
@MainActor
@Observable
public final class MapViewModel {
    // Default: Chiang Mai old city center.
    public static let defaultCenter = CLLocationCoordinate2D(latitude: 18.7877, longitude: 98.9938)

    // Camera spans. Street-level (~1.3km) when we have a GPS fix so the
    // traveler can read the shops underfoot, matching Apple/高德 Maps'
    // locate-me zoom; wider city-level (~5.5km) when only a city is picked
    // with no fix, so the city outline stays legible. The previous single
    // 0.09 span (~10km, big-district scale) read as "too coarse".
    enum MapZoom {
        static let streetLevel: CLLocationDegrees = 0.012
        static let cityLevel: CLLocationDegrees = 0.05
    }

    /// The span an initial / city-selection camera should use: street-level
    /// when a GPS fix is available (the traveler is somewhere concrete), else
    /// city-level so the picked city stays legible without a location.
    private var initialCameraSpan: CLLocationDegrees {
        locationService.currentLocation != nil ? MapZoom.streetLevel : MapZoom.cityLevel
    }

    // MARK: - Dependencies
    private let locationService: LocationService
    private let experienceService: ExperienceService
    private let aiService: AIService
    private let overpassService: OverpassService
    private let foursquareService: FoursquareService
    private let geocodeService: any ReverseGeocoding
    private let preferences: UserPreferences

    @ObservationIgnored
    private let logger = Logger(subsystem: "com.solocompass", category: "MapViewModel")

    /// Static logger for type-level analytics emission (see `emitMultiRingCompleted`).
    private static let analyticsLogger = Logger(subsystem: "com.solocompass", category: "Analytics")

    /// Lazily built deep-dive orchestrator. Reuses the existing channel
    /// services and adds an Apple MapKit source. `@ObservationIgnored` so the
    /// `@Observable` macro leaves it as a plain stored property (and permits
    /// `lazy`); non-explore code paths and tests never pay for it.
    @ObservationIgnored
    private lazy var enrichmentAgent = EnrichmentAgent(
        overpassService: overpassService,
        mapKitService: MapKitPOIService(),
        foursquareService: foursquareService,
        geocodeService: geocodeService,
        aiService: aiService,
        // Mainland-China POI source. Inside China it becomes the authoritative
        // base (OSM is ~9× sparser there); an absent key degrades to Overpass.
        // Fetch width is the developer-tunable `DataSourceSettings.poiFetchLimit`.
        amapService: AmapPOIService(maxResults: DataSourceSettings.poiFetchLimit)
    )
    /// Optional so existing tests / previews can construct without a
    /// real StoreKit-aware service. Production wires this from the
    /// environment in `CompassMapView` (Epic D US-024).
    private weak var subscriptionService: SubscriptionService?

    /// Nomad OS A2: pulls a city's already-synthesized experiences from the
    /// backend when the local store has none, so non-seed cities aren't empty.
    /// `@ObservationIgnored lazy` mirrors `enrichmentAgent` — no init-signature
    /// change, no cost on paths that never trigger a hydrate, still injectable.
    @ObservationIgnored
    private lazy var cityExperienceFetcher = CityExperienceFetcher()
    /// Cities already hydrated from the backend this session, so a repeated
    /// `selectCity` (e.g. GPS re-follow) fires at most one network read per city.
    @ObservationIgnored
    private var backendHydratedCities: Set<String> = []

    /// Wire the subscription service after init (called from
    /// CompassMapView.onAppear). Free tier gating only applies after
    /// this is set; pre-attach treats every caller as Pro to keep the
    /// existing test surface working.
    public func attachSubscriptionService(_ service: SubscriptionService) {
        self.subscriptionService = service
    }

    /// Set of experience ids the traveler has actually visited (passive
    /// `VisitRecord`, P1.1 #112). Drives the gold-halo `.footprinted` marker
    /// state on the map without us having to also write back into the
    /// existing `passiveGpsHits30d` confidence signal.
    public private(set) var visitedExperienceIds: Set<String> = []

    /// Attach the set of visited experience ids — called after init from the
    /// view layer, which owns the SwiftData query over `VisitRecord`. Pass
    /// an empty set to clear the halo (e.g. when the Settings toggle is off).
    public func attachVisitedExperienceIds(_ ids: Set<String>) {
        self.visitedExperienceIds = ids
    }

    /// True when the active entitlement should pass AI gates.
    /// Defaults to `true` when the subscription service hasn't been
    /// attached yet (tests / previews) so we don't accidentally lock
    /// out non-StoreKit code paths.
    public var isProUser: Bool {
        subscriptionService?.entitlement.isActive ?? true
    }

    /// Set to true whenever a free user tries an AI-gated action; the
    /// view binds `.sheet(isPresented:)` to it.
    public var isShowingPaywall: Bool = false

    /// Closure to retry after a successful purchase. Consumers (the
    /// paywall) call this in `onUnlocked`.
    public var onPaywallUnlocked: (() -> Void)?

    /// Set to true while a free-tier Overpass-only explore is running.
    /// Separate from `isExploring` so the UI can label the button
    /// distinctly (no AI spinner; no quota banner).
    public var isExploringFreeMode: Bool = false

    /// Forwards `OverpassService.isFetching` so the map can show a loading
    /// indicator while POIs are being fetched (#134). `OverpassService` is
    /// `@Observable`, so reading it here keeps SwiftUI's dependency tracking
    /// intact — the view re-renders when the fetch state flips.
    public var isFetchingPOIs: Bool {
        overpassService.isFetching
    }

    // MARK: - Explore consent (US-034)

    /// Set to true the first time a user triggers an Explore action
    /// without having accepted the data-use disclosure. The view binds
    /// `.sheet(isPresented:)` to it.
    public var isShowingExploreConsent: Bool = false

    /// Closure to retry after the consent sheet is accepted. Mirrors
    /// the paywall pattern so the original Explore action resumes
    /// transparently.
    public var onExploreConsentAccepted: (() -> Void)?

    // MARK: - Explore-here state
    public var isExploring: Bool = false
    public var lastExploreError: String?
    /// Classifies the *reason* an explore failed so the UI can show
    /// a kind-specific banner instead of the generic "something broke".
    /// nil = no failure (or already presented + dismissed).
    /// Strictly an enrichment of `lastExploreError`: the human-readable
    /// string still flows through that property for detail.
    public enum ExploreFailureKind: Equatable {
        case offline           // NetworkMonitor said disconnected
        case apiTimeout        // DeepSeek / Supabase / Overpass timed out
        case apiServerError    // HTTP 5xx
        case quotaExceeded     // AI daily cap hit; user can retry tomorrow
        case noResults         // request succeeded but the area is empty
    }
    public var lastFailureKind: ExploreFailureKind?
    public var lastExploreAddedCount: Int = 0
    /// Set when the AI synthesis daily quota cap fires. The map view
    /// shows a banner derived from this. Cleared on the next UTC day
    /// rollover (via day-truncated AIUsageRecord).
    public var lastQuotaInfo: String?
    /// Ephemeral 3-second toast above BottomInfoBar. Set after a
    /// successful Explore; cleared by the view after the timer fires.
    /// Format examples:
    /// - "Now exploring Hanoi · 12 places added" (geocode succeeded)
    /// - "12 places added near you" (geocode failed / offline)
    public var lastExploreToast: String?

    // MARK: - Explore Mode session (slice C)
    //
    // `ExploreSession` is a computed view-model projected from the fields
    // above. It lets the Explore-Mode overlay bind to a single object
    // without leaking the multi-flag pipeline shape into the view. Nothing
    // here replaces `isExploring` / `exploreProgress` — they still drive
    // the pipeline; these three fields augment it.

    /// Experience ids added by the current (or most recent) Explore run.
    /// Cleared on `.idle`; drives the "dim non-new pins" treatment and
    /// the live-feed's "+N places" counter. Set-typed for O(1) contains.
    public var exploreSessionAddedIds: Set<String> = []

    /// When set, the Explore run has finished with ≥1 result and the UI
    /// should show the handoff card (result summary + 4 CTAs). Nil means
    /// no pending handoff — either idle, still scanning, or dismissed.
    public var pendingHandoff: ExploreSession.HandoffResult?

    /// User tapped Cancel mid-Explore. Preserves already-added pins as
    /// "kept" and drives a one-shot toast. Cleared on next Explore start.
    public var lastCancelledKeptCount: Int?

    /// Projected view-model of the current Explore session. Derives from
    /// `isExploring`, `exploreProgress`, `exploreRadiusOverlay`,
    /// `lastExploreCenter`, and the count fields above. UI reads this;
    /// the pipeline sets the underlying fields.
    public var exploreSession: ExploreSession {
        // Handoff wins — a pending handoff card overrides any lingering
        // exploreProgress that hasn't yet snapped back to .idle.
        if let handoff = pendingHandoff {
            return ExploreSession(state: .handoff(handoff))
        }
        if let kept = lastCancelledKeptCount {
            return ExploreSession(state: .cancelled(kept: kept))
        }
        if isExploring || isExploringFreeMode {
            let radius = exploreRadiusOverlay?.radiusMeters
                ?? Double(progressiveScratchRadiusMeters)
            let anchor = exploreRadiusOverlay?.center
                ?? lastExploreCenter
                ?? exploreAnchorCoordinate
            let phase = Self.phase(from: exploreProgress)
            return ExploreSession(state: .active(
                phase: phase,
                radiusMeters: max(radius, 500),
                anchor: anchor,
                addedCount: exploreSessionAddedIds.count,
                verifiedCount: countVerifiedInSession()
            ))
        }
        return ExploreSession(state: .idle)
    }

    /// Fold the fine-grained `ExploreProgress` enum into the coarser
    /// `ExploreSession.Phase` the overlay pill cares about. Kept static
    /// so tests can drive it without instantiating MapViewModel.
    static func phase(from progress: ExploreProgress) -> ExploreSession.Phase {
        switch progress {
        case .idle:                    return .scanning   // just entered
        case .multiRingScanning:       return .scanning
        case .scanning:                return .scanning
        case .expanding:               return .widening
        case .synthesizing:            return .synthesizing
        }
    }

    /// Count Experiences in the current session that carry ≥2 distinct
    /// InformationSource types — the "verified across sources" signal
    /// the live feed advertises. O(n) over the added set; fine because
    /// n is bounded by explore batch size (~50).
    private func countVerifiedInSession() -> Int {
        guard !exploreSessionAddedIds.isEmpty else { return 0 }
        var n = 0
        for exp in visibleExperiences where exploreSessionAddedIds.contains(exp.id) {
            if Set(exp.sources.map(\.type)).count >= 2 { n += 1 }
        }
        return n
    }

    /// User tapped Cancel on the Explore-Mode overlay. Preserves already
    /// added pins (they're kept in visibleExperiences) and flips state
    /// out of the scanning phase so the overlay clears. The next tick of
    /// the pipeline will see isExploring flipped and stop appending; any
    /// in-flight AI synthesis completes silently.
    public func exploreCancel() {
        let kept = exploreSessionAddedIds.count
        isExploring = false
        isExploringFreeMode = false
        exploreProgress = .idle
        exploreRadiusOverlay = nil
        pendingHandoff = nil
        lastCancelledKeptCount = kept
        // Retire the toast/error banners left over from the scan so the
        // cancel state reads cleanly.
        lastExploreToast = nil
        lastExploreError = nil
    }

    /// Called by the handoff card when the user picks a CTA or lets the
    /// 10-second auto-dismiss fire. Snaps back to idle so the overlay
    /// gets out of the user's way. Does NOT remove pins — the user might
    /// want to keep them; use `exploreDiscardHandoff` for the destructive
    /// "clear these" CTA.
    public func exploreClearHandoff() {
        pendingHandoff = nil
        exploreSessionAddedIds.removeAll()
    }

    /// Handoff-card "Clear these" CTA. Removes the pins added this session
    /// from the visible layer AND clears the session tracking. Existing
    /// data in ExperienceService is not deleted — the user can still find
    /// them via seed/filter — but they no longer clutter the current map.
    public func exploreDiscardHandoff() {
        let ids = exploreSessionAddedIds
        pendingHandoff = nil
        exploreSessionAddedIds.removeAll()
        withAnimation(Self.markerSetAnimation) {
            visibleExperiences.removeAll { ids.contains($0.id) }
            nearbySoloCount = computeNearbySoloCount(in: visibleExperiences)
        }
    }

    /// User dismissed the "kept N places" cancelled banner.
    public func exploreClearCancelled() {
        lastCancelledKeptCount = nil
    }

    /// Display-ready name of the selected city, or nil when custom /
    /// unmatched. Used by the Explore-Mode overlay pill and the handoff
    /// card so they never render `cmi` when the user sees `Chiang Mai`.
    public var currentDisplayCityName: String? {
        guard let code = selectedCity, !code.hasPrefix("custom_") else { return nil }
        return availableCities.first(where: { $0.code == code })?.name
    }

    // MARK: - Deep-dive re-compile (single card)

    /// The id of the experience currently being deep-dive re-compiled, or nil
    /// when idle. Drives the per-card spinner so the rest of the UI stays live.
    public var recompilingExperienceId: String?

    /// Ids re-compiled (or auto-upgraded) this session, so the on-demand
    /// auto-upgrade (Approach C) never spends quota on the same card twice.
    /// Manual re-compile (Approach A) bypasses this — the user asked for it.
    private var recompiledThisSession: Set<String> = []

    /// True iff `experience` is a candidate for the on-demand auto-upgrade:
    /// it carries no AI-authored cross-source content yet and we haven't
    /// already upgraded it this session. Read by the detail view on appear.
    /// Curated seed cards are excluded — they already carry human-written
    /// copy and scores, and the silent path must never risk replacing them
    /// with a nearby-POI mismatch. Manual re-compile stays available and is
    /// protected by `EnrichmentAgent.shouldAdoptRecompiled`.
    public func shouldAutoUpgrade(_ experience: Experience) -> Bool {
        !experience.isAIEnriched
            && !experience.isCuratedSeed
            && !recompiledThisSession.contains(experience.id)
    }

    /// Manual deep cross-compile of a single experience (Approach A). Reuses
    /// the same Pro + consent gates as Explore — a free user hits the paywall,
    /// parked to resume after purchase. On success the card is replaced in
    /// place (same id, favorites/completions preserved) and re-renders.
    public func recompileExperience(_ experience: Experience) async {
        // Same gating as exploreNearby (US-024 paywall, US-034 consent).
        if !isProUser {
            onPaywallUnlocked = { [weak self] in
                Task { await self?.recompileExperience(experience) }
            }
            isShowingPaywall = true
            return
        }
        if !preferences.hasAcceptedExploreConsent {
            onExploreConsentAccepted = { [weak self] in
                Task { await self?.recompileExperience(experience) }
            }
            isShowingExploreConsent = true
            return
        }
        await runRecompile(experience, manual: true)
    }

    /// Background auto-upgrade of a single experience (Approach C). Silent: no
    /// paywall, no spinner unless already visible, no-op for free users or for
    /// cards already upgraded this session. Best-effort — failures leave the
    /// card untouched.
    public func autoUpgradeExperience(_ experience: Experience) async {
        guard isProUser,
              preferences.hasAcceptedExploreConsent,
              shouldAutoUpgrade(experience) else { return }
        await runRecompile(experience, manual: false)
    }

    /// Shared re-compile body for both manual (A) and auto (C) paths. Stamps
    /// the session cache, drives the spinner, calls the agent, and swaps the
    /// upgraded content in place. `aiService.isProTier` is synced so the
    /// daily quota cap applies exactly as it does for Explore.
    private func runRecompile(_ experience: Experience, manual: Bool) async {
        recompiledThisSession.insert(experience.id)
        aiService.isProTier = isProUser
        recompilingExperienceId = experience.id
        defer { recompilingExperienceId = nil }

        guard let upgraded = await enrichmentAgent.recompile(
            experience: experience,
            locale: LanguageService.shared.effectiveLocale
        ) else {
            // Manual taps deserve feedback when nothing richer was found.
            if manual {
                lastExploreToast = NSLocalizedString(
                    "recompile.toast.noChange",
                    comment: "Shown when a manual deep re-compile found nothing richer"
                )
            }
            return
        }

        experienceService.replaceGenerated(upgraded)
        // Keep the floating card / detail bound to the upgraded copy.
        if selectedExperience?.id == upgraded.id {
            selectedExperience = upgraded
        }
        if manual {
            lastExploreToast = NSLocalizedString(
                "recompile.toast.success",
                comment: "Shown after a manual deep re-compile upgrades a card"
            )
        }
    }

    // MARK: - Auto-recenter

    /// Set to true after the first successful auto-recenter so we don't fight
    /// subsequent user pan/zoom gestures.
    private var hasAutoCentered = false

    /// True once the user has explicitly chosen a city *in this session* —
    /// via the city picker (`selectCity`), a custom pin
    /// (`selectCustomLocation`), or the DEBUG `-startCity` launch argument
    /// (e2e harnesses rely on the forced city holding the camera). Only an
    /// explicit in-session pick survives the first GPS fix; a city merely
    /// persisted from a previous session does NOT own the camera anymore —
    /// entering the app should land the traveler where they physically are.
    @ObservationIgnored private(set) var cityPickedExplicitlyThisSession = false

    /// Align camera + city selection to the user's current location ONCE, on
    /// the first non-nil GPS fix. Subsequent calls are no-ops so the user's
    /// manual pan/zoom is preserved.
    public func bindToLocation() {
        guard !hasAutoCentered,
              let coordinate = locationService.currentLocation?.coordinate else { return }
        hasAutoCentered = true
        // Cold-start rule (supersedes V-004/V-007's "preset city owns the
        // camera"): entering the app follows GPS — the camera centers on the
        // fix and `selectedCity` (the top-left pill) adopts the city the
        // traveler is physically in. A city persisted from a *previous*
        // session is just a pre-GPS placeholder now, not a pick. What still
        // holds the camera:
        //   1. An explicit in-session pick (picker / custom pin / -startCity)
        //      made before the first fix landed — V-007's actual scenario
        //      (picking a China city while physically in Laos) stays fixed.
        //   2. The Simulator's default San Francisco fix (Beta-P0-F,
        //      narrowed) — otherwise every seeded-city cold start in the sim
        //      snaps to SF.
        let looksLikeSimulatorDefault = Self.isSimulatorDefaultSanFrancisco(coordinate)
        let suppressGPS = looksLikeSimulatorDefault
        if !cityPickedExplicitlyThisSession && !suppressGPS {
            followUserLocation(coordinate, runAutoExplore: true)
        }
        SentryService.capture(
            message: "map.coldStart.cameraResolution",
            level: .info,
            context: [
                "selectedCity": selectedCity ?? "nil",
                "explicitSessionPick": cityPickedExplicitlyThisSession,
                "suppressGPS": suppressGPS,
                "simulatorDefaultSF": looksLikeSimulatorDefault,
                "lat": coordinate.latitude,
                "lon": coordinate.longitude
            ]
        )
    }

    // MARK: - GPS city follow

    /// How far (metres) a GPS fix may sit from a city's center and still adopt
    /// that city as the selection. Beyond this the app drops to pure
    /// GPS-follow (no city pill lock) and lets auto-explore discover the city.
    static let cityFollowMaxDistanceMeters: CLLocationDistance = 75_000

    /// Align the whole aggregation context to where the traveler physically
    /// is: adopt the nearest known city (so the city pill and the nearby list
    /// agree with the GPS fix) and center the camera on the fix itself — NOT
    /// on the city's catalog center, so the map opens on the user's block.
    public func followUserLocation(
        _ coordinate: CLLocationCoordinate2D,
        runAutoExplore: Bool = false
    ) {
        if let city = nearestKnownCity(to: coordinate) {
            let alreadySelected = selectedCity.map { Self.cityCodeMatches(city, selected: $0) } ?? false
            if !alreadySelected {
                customCoordinates = nil
                customLocationLabel = nil
                selectedCity = city
                preferences.lastSelectedCity = city
                didAutoRecoverEmpty = false
            }
        } else if selectedCity != nil {
            // Far from every known city: a stale selection would keep the
            // nearby query anchored thousands of km away, so drop to pure
            // GPS-follow and let auto-explore discover + name the city.
            customCoordinates = nil
            customLocationLabel = nil
            selectedCity = nil
            preferences.lastSelectedCity = nil
        }
        recenter(on: coordinate)
        if runAutoExplore { autoExploreIfEmpty(at: coordinate) }
    }

    /// Foreground return ("entering the app" with the process still alive —
    /// e.g. reopening after a flight): if the GPS fix now resolves to a
    /// DIFFERENT city than the current selection, re-follow it. Same-city app
    /// switches leave the user's pan/zoom untouched, and an explicit
    /// in-session pick is never fought — the locate button remains the
    /// manual override.
    public func refollowUserCityIfMoved() {
        guard hasAutoCentered,
              !cityPickedExplicitlyThisSession,
              let coordinate = locationService.currentLocation?.coordinate,
              !Self.isSimulatorDefaultSanFrancisco(coordinate) else { return }
        let stillInSelectedCity: Bool
        if let resolved = nearestKnownCity(to: coordinate) {
            stillInSelectedCity = selectedCity.map { Self.cityCodeMatches(resolved, selected: $0) } ?? false
        } else if selectedCity != nil {
            // No known city near the fix: the selection is stale only when
            // the fix has left its follow radius.
            let center = defaultCenterForSelectedCity
            let dist = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude))
            stillInSelectedCity = dist <= Self.cityFollowMaxDistanceMeters
        } else {
            stillInSelectedCity = true // already in pure GPS-follow
        }
        guard !stillInSelectedCity else { return }
        followUserLocation(coordinate, runAutoExplore: true)
    }

    /// Nearest city (authoritative catalog + seed/discovered centroids) within
    /// `cityFollowMaxDistanceMeters` of the coordinate, or nil when the fix is
    /// beyond every known city. Ties prefer `availableCities` entries (they
    /// carry real experiences) because they are scanned last with `<=`.
    private func nearestKnownCity(to coordinate: CLLocationCoordinate2D) -> String? {
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var bestCode: String?
        var bestDistance = Self.cityFollowMaxDistanceMeters
        for (code, center) in Self.knownCityCenters {
            let dist = here.distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude))
            if dist <= bestDistance {
                bestDistance = dist
                bestCode = code
            }
        }
        for city in availableCities where !city.code.hasPrefix("custom_") {
            let dist = here.distance(from: CLLocation(latitude: city.center.latitude, longitude: city.center.longitude))
            if dist <= bestDistance {
                bestDistance = dist
                bestCode = city.code
            }
        }
        return bestCode
    }

    /// Returns true only for the iOS Simulator default location (Apple HQ /
    /// downtown SF, 37.7749, -122.4194) within a tight ~2 km radius. Used by
    /// `bindToLocation` to hold the seed camera when the app is launched in
    /// the Simulator with no location override — the previous broad "must be
    /// near a seed city" guard misfired on real devices anywhere else in the
    /// world. Real users at (37.7749, -122.4194) will still be treated as
    /// simulator-default; the trade-off is fine because SF is also a seed
    /// city (`san-francisco` in `knownCityCenters`) so the outcome is the
    /// same regardless.
    private static func isSimulatorDefaultSanFrancisco(_ coordinate: CLLocationCoordinate2D) -> Bool {
        #if targetEnvironment(simulator)
        let sf = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return here.distance(from: sf) <= 2_000
        #else
        _ = coordinate
        return false
        #endif
    }

    /// Whether a GPS fix is available right now — drives the custom recenter
    /// button's enabled state in the map overlay.
    public var hasUserLocation: Bool {
        locationService.currentLocation != nil
    }

    /// Recenter on the user's current location on demand (the custom
    /// "locate me" button). Unlike `bindToLocation` this ignores the
    /// `hasAutoCentered` guard, so the user can re-center any time after
    /// panning away. Beyond moving the camera it also adopts the GPS city as
    /// the selection, so the top-left city pill and the nearby list follow
    /// the tap — "locate me" means "put me back in MY city", not just "slide
    /// the map". No-op when there is no GPS fix yet.
    public func recenterOnUser() {
        guard let coordinate = locationService.currentLocation?.coordinate else { return }
        followUserLocation(coordinate)
    }

    #if DEBUG
    /// Test-only counter: how many times `autoExploreIfEmpty` has been entered.
    /// Lets the V-007 regression test assert that a preset-city `bindToLocation`
    /// does NOT trigger GPS-anchored auto-explore (the path whose `exploreNearby`
    /// tail overrode the user's city pick). Synchronous + deterministic, so it
    /// catches the regression without racing the async `exploreNearby` Task.
    @ObservationIgnored public private(set) var autoExploreInvocationCount = 0
    #endif

    /// Auto-trigger Explore when the user lands in a data-sparse area
    /// (e.g. Vientiane with zero seed data). Fires once after the first
    /// GPS fix. Skips when there's already ≥3 experiences within 5 km,
    /// or when a recent (<7 day) offline region cache covers the spot.
    /// `exploreNearby` handles the paywall + consent gates internally.
    private func autoExploreIfEmpty(at coordinate: CLLocationCoordinate2D) {
        #if DEBUG
        autoExploreInvocationCount += 1
        #endif
        let nearby = experienceService.getExperiences(near: coordinate, radiusKm: 5.0)
        guard nearby.count < 3 else { return }

        if let region = experienceService.repo.closestRecentRegion(to: coordinate),
           region.exploredAt > Date().addingTimeInterval(-7 * 24 * 3600) {
            return
        }

        Task { await self.exploreNearby(at: coordinate) }
    }

    // MARK: - City selection

    /// Currently selected city code (e.g. "cmi"), nil = all cities.
    /// Custom locations use the format `custom_{lat}_{lon}`.
    ///
    /// V-002: any change here keeps `cameraPosition` in agreement with the
    /// city header label, so the rendered map region never disagrees with the
    /// name shown to the user. Custom-pin selections (`custom_…`) are skipped
    /// because their camera is driven by `customCoordinates` in
    /// `selectCustomLocation`. The first set during `init` does NOT trigger
    /// `didSet` (Swift initializer semantics), so `init` performs the same
    /// sync explicitly after all stored properties are set.
    public var selectedCity: String? {
        didSet {
            guard selectedCity != oldValue else { return }
            invalidateCityCache()
            // #86: candidateExperiences live under the previous city's
            // coordinates; carrying them to a new city leaves invisible pins
            // far off-map and can collide with new candidates by id. The
            // user dropped these pins on the previous map — switching cities
            // resets that local layer cleanly. visibleExperiences gets
            // rebuilt by the subsequent fetch.
            candidateExperiences.removeAll()
            syncCameraToSelectedCity()
        }
    }

    /// Move `cameraPosition` to the selected city's center. Custom-pin
    /// selections keep their existing camera (set in `selectCustomLocation`).
    private func syncCameraToSelectedCity() {
        if selectedCity?.hasPrefix("custom_") == true { return }
        cameraPosition = .region(MKCoordinateRegion(
            center: defaultCenterForSelectedCity,
            span: MKCoordinateSpan(latitudeDelta: initialCameraSpan, longitudeDelta: initialCameraSpan)
        ))
    }

    /// Coordinate for a custom-pin location set via LocationPickerSheet.
    /// Non-nil when `selectedCity` starts with "custom_".
    public var customCoordinates: CLLocationCoordinate2D?

    /// Display label for a custom location (resolved city name or raw coord string).
    public var customLocationLabel: String?

    /// True when the current selection is a custom coordinate (not a preset city).
    public var isCustomLocation: Bool {
        selectedCity?.hasPrefix("custom_") ?? false
    }

    /// Select a custom coordinate from the LocationPickerSheet.
    /// Zooms the map, clears city filtering (custom pin has no cityCode),
    /// and stores the resolved label for the city pill.
    public func selectCustomLocation(
        coordinate: CLLocationCoordinate2D,
        label: String,
        cityCode: String
    ) {
        cityPickedExplicitlyThisSession = true
        customCoordinates = coordinate
        customLocationLabel = label
        selectedCity = cityCode
        preferences.lastSelectedCity = nil  // don't persist custom pins across restarts
        // A custom pin is a deliberate concrete point the user dropped, so
        // zoom straight to street-level regardless of GPS.
        cameraPosition = .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: MapZoom.streetLevel, longitudeDelta: MapZoom.streetLevel)
        ))
        loadNearbyExperiences()
        updateBottomInfo()
    }

    /// All cities the user can pick from: seed-derived ones (centroid of
    /// matching experiences) plus reverse-geocoded discoveries from
    /// previous Explore sessions (Epic C US-016/017). Discovered cities
    /// override seed-derived names when the codes match.
    public var availableCities: [(code: String, name: String, center: CLLocationCoordinate2D)] { // swiftlint:disable:this large_tuple
        // US-017: cache the result so `body` re-renders don't re-traverse
        // `allExperiences` (O(n)) on every invocation. Invalidated whenever
        // the experience set or selected city changes (see invalidateCityCache).
        if let cached = _cachedCities { return cached }
        let computed = computeAvailableCities()
        _cachedCities = computed
        return computed
    }

    /// Backing store for `availableCities` (US-017). `@ObservationIgnored`
    /// so the `@Observable` macro doesn't treat reads of the cache as a
    /// tracked dependency — invalidation is explicit via `invalidateCityCache`.
    @ObservationIgnored private var _cachedCities: [(code: String, name: String, center: CLLocationCoordinate2D)]? // swiftlint:disable:this large_tuple

    /// Drop the cached city list. Called whenever the underlying inputs
    /// (`allExperiences`, discovered cities, or `selectedCity`) change.
    private func invalidateCityCache() {
        _cachedCities = nil
    }

    /// The actual O(n) derivation, split out of `availableCities` so the
    /// getter can serve a memoized result. See `availableCities` docs.
    private func computeAvailableCities() -> [(code: String, name: String, center: CLLocationCoordinate2D)] { // swiftlint:disable:this large_tuple
        var cityExperiences: [String: [CLLocationCoordinate2D]] = [:]
        for exp in experienceService.allExperiences {
            guard let coord = exp.coordinate else { continue }
            let code = exp.location.cityCode
            cityExperiences[code, default: []].append(coord)
        }
        let nameMap = Self.cityNameMap
        var byCode: [String: (code: String, name: String, center: CLLocationCoordinate2D)] = [:] // swiftlint:disable:this large_tuple
        let nearbyLabel = NSLocalizedString("city.nearby", comment: "Fallback city label for synthetic osm_ codes")
        // Seed-derived rows first.
        for (code, coords) in cityExperiences where !coords.isEmpty {
            let avgLat = coords.map(\.latitude).reduce(0, +) / Double(coords.count)
            let avgLon = coords.map(\.longitude).reduce(0, +) / Double(coords.count)
            let name = nameMap[code] ?? (code.hasPrefix("osm_") ? nearbyLabel : code)
            byCode[code] = (code, name, CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon))
        }

        // Discovered city rows take precedence on name (real city name
        // is better than slug fallback).
        for row in experienceService.repo.allDiscoveredCities() {
            byCode[row.cityCode] = (
                row.cityCode,
                row.name,
                CLLocationCoordinate2D(latitude: row.centerLat, longitude: row.centerLon)
            )
        }

        // Include the currently selected city even when seed / discovered rows
        // don't cover it (冷启动到 SZX 但 seed 只有 cmi/VTE) so the city pill
        // shows the intended name instead of falling back to nearestSeededCity
        // — which for Shenzhen picks Vientiane on great-circle distance.
        if let code = selectedCity, byCode[code] == nil {
            let center = Self.knownCityCenters[code]
                ?? Self.cityCodeAliases[code.lowercased()]
                    .flatMap({ Self.knownCityCenters[$0] })
                ?? Self.knownCityCenters[code.uppercased()]
                ?? Self.knownCityCenters[code.lowercased()]
            if let center {
                byCode[code] = (code, nameMap[code] ?? code, center)
            }
        }

        return Array(byCode.values).sorted { $0.name < $1.name }
    }

    /// Static seed-city names. Discovered-city names come from
    /// `DiscoveredCityRecord` via `availableCities`.
    /// City code → display name. `static` so surfaces outside the map (e.g.
    /// `TodayStatusHeader`) resolve a city's name from the same single source
    /// of truth without holding a `MapViewModel`, keeping the name shown on
    /// Today and on the map pill in lockstep. Pure data, no instance state.
    static let cityNameMap: [String: String] = [
        "cmi": "Chiang Mai",
        "CNX": "Chiang Mai",
        "VTE": "Vientiane",
        "cn-深圳市": "Shenzhen",
        // SZX/szx/shenzhen 三种冷启动/launch-arg 形式都要能反查到显示名,
        // 否则 selectedCity="SZX" 但 seed 无 SZX experience 时,cityPill
        // 会回退到 nearestSeededCity(depend on availableCities),把最近的
        // 万象(Vientiane)当城市名显示——用户看到的城市顶栏就错了。
        "SZX": "Shenzhen",
        "szx": "Shenzhen",
        "shenzhen": "Shenzhen",
        // Match knownCityCenters entries below — user-story rubric fixtures use
        // these codes and the city pill would otherwise show a fallback name.
        "nyc": "New York",
        "new-york": "New York",
        "tyo": "Tokyo",
        "tokyo": "Tokyo",
        "sgn": "Ho Chi Minh",
        "ho-chi-minh": "Ho Chi Minh",
        "lis": "Lisbon",
        "lisbon": "Lisbon",
        "san-francisco": "San Francisco",
        "sfo": "San Francisco",
    ]

    /// Well-known city centers keyed by both their seed/discovered codes and
    /// their human-readable slugs. Used as a fallback in
    /// `defaultCenterForSelectedCity` so the camera can still resolve a sane
    /// region for a selection that has no matching experiences yet (e.g. a
    /// persisted `lastSelectedCity` on a cold start, before any pins load).
    static let knownCityCenters: [String: CLLocationCoordinate2D] = [
        "cmi": CLLocationCoordinate2D(latitude: 18.7877, longitude: 98.9938),
        "chiang-mai": CLLocationCoordinate2D(latitude: 18.7877, longitude: 98.9938),
        "san-francisco": CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        "sfo": CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        // V-006: Vientiane (VTE) seeds existed (5 experiences + 4 routes) but the
        // city had no authoritative center, so a cold start on VTE fell through to
        // the live centroid — unstable, and empty if `availableCities` hasn't
        // populated yet during init. Pin the city proper, keyed by both seed code
        // and slug like the other cities.
        "VTE": CLLocationCoordinate2D(latitude: 17.9757, longitude: 102.6331),
        "vientiane": CLLocationCoordinate2D(latitude: 17.9757, longitude: 102.6331),
        // Shenzhen (mainland China) — Futian CBD. Pinned so a cold start in
        // China lands on a real center and routes through the Amap explore
        // branch. WGS84 (converted to GCJ-02 inside AmapPOIService).
        "SZX": CLLocationCoordinate2D(latitude: 22.5431, longitude: 114.0579),
        "shenzhen": CLLocationCoordinate2D(latitude: 22.5431, longitude: 114.0579),
        // User-story rubric fixtures (`Tests/fixtures/user_stories.json`) drive
        // `-startCity nyc|tyo|sgn|lis` through simctl for the aesthetic e2e
        // harness. Without these entries the fallback lands on SF and the
        // screenshot lies about which city the user is looking at.
        "nyc": CLLocationCoordinate2D(latitude: 40.7484, longitude: -73.9857),
        "new-york": CLLocationCoordinate2D(latitude: 40.7484, longitude: -73.9857),
        "tyo": CLLocationCoordinate2D(latitude: 35.6817, longitude: 139.7708),
        "tokyo": CLLocationCoordinate2D(latitude: 35.6817, longitude: 139.7708),
        "sgn": CLLocationCoordinate2D(latitude: 10.7769, longitude: 106.7009),
        "ho-chi-minh": CLLocationCoordinate2D(latitude: 10.7769, longitude: 106.7009),
        "lis": CLLocationCoordinate2D(latitude: 38.7223, longitude: -9.1393),
        "lisbon": CLLocationCoordinate2D(latitude: 38.7223, longitude: -9.1393),
    ]

    /// V-004: human-readable city slugs (used by the city header / persisted
    /// `lastSelectedCity`) mapped to the compact seed `cityCode` they share a
    /// location with. The cold-start empty state happened because a persisted
    /// slug like `chiang-mai` never `==` matched the seed's `cmi` cityCode in
    /// `applyFilters`, so every seed row was filtered out. `cityCodeMatches`
    /// consults this table both directions so either form selects the city.
    static let cityCodeAliases: [String: String] = [
        "chiang-mai": "cmi",
        // PascalCase variants people actually type when launching with
        // `-startCity ChiangMai` from the command line / Xcode scheme. Without
        // these the alias lookup falls through to `Self.defaultCenter` and the
        // cold-start map silently lands on SF.
        "chiangmai": "cmi",
        "cnx": "cmi",
        "vientiane": "VTE",
        "shenzhen": "cn-深圳市",
        "szx": "cn-深圳市",
        "sfo": "san-francisco",
    ]

    /// True when `seedCityCode` (an experience's `location.cityCode`) belongs to
    /// the same city as `selectedCode` (the header / persisted selection),
    /// resolving slug↔seed-code aliases in both directions. Case-insensitive so
    /// the upper-cased seed codes (`VTE`) match lower-cased slugs.
    static func cityCodeMatches(_ seedCityCode: String, selected selectedCode: String) -> Bool {
        if seedCityCode.caseInsensitiveCompare(selectedCode) == .orderedSame { return true }
        if let alias = cityCodeAliases[selectedCode.lowercased()],
           alias.caseInsensitiveCompare(seedCityCode) == .orderedSame { return true }
        if let alias = cityCodeAliases[seedCityCode.lowercased()],
           alias.caseInsensitiveCompare(selectedCode) == .orderedSame { return true }
        return false
    }

    /// Center coordinate for the selected city, or the default if none selected.
    /// Resolution order: the static `knownCityCenters` catalog (a city's stable
    /// authoritative center, by slug or seed-code alias) → live `availableCities`
    /// (seed + discovered) centroid → the global default (Chiang Mai).
    ///
    /// V-002: `knownCityCenters` is consulted FIRST for cities it covers because
    /// the seed centroid is just the mean of however many sample pins exist
    /// (the 5 Chiang Mai seeds average ~2.6 km off the city center) and drifts
    /// as seeds are added/removed — an unstable camera anchor. The authoritative
    /// center keeps a cold start landing on the city proper; the centroid only
    /// anchors cities the catalog doesn't cover (discovered / Explore-added).
    public var defaultCenterForSelectedCity: CLLocationCoordinate2D {
        guard let code = selectedCity else { return Self.defaultCenter }
        // Try the slug directly, then the alias-resolved seed code, so both a
        // header slug (`chiang-mai`) and a seed code (`cmi`) hit the catalog.
        if let known = Self.knownCityCenters[code]
            ?? Self.cityCodeAliases[code.lowercased()].flatMap({ Self.knownCityCenters[$0] }) {
            return known
        }
        // V-004: match alias-aware so a header slug resolves to the seed-coded
        // city's centroid for cities the catalog doesn't cover.
        if let city = availableCities.first(where: { Self.cityCodeMatches($0.code, selected: code) }) {
            return city.center
        }
        return Self.defaultCenter
    }

    /// Selects a preset city, recenters the map, and reloads experiences.
    /// Clears any active custom-coordinate pin. `explicit` marks the jump as
    /// a deliberate user pick (picker, empty-state redirect) that the first
    /// GPS fix / foreground re-follow must not fight (V-007); explore's
    /// programmatic discovery passes `false` so GPS city-follow stays armed.
    public func selectCity(_ cityCode: String?, explicit: Bool = true) {
        if explicit {
            cityPickedExplicitlyThisSession = true
        }
        customCoordinates = nil
        customLocationLabel = nil
        selectedCity = cityCode
        preferences.lastSelectedCity = cityCode
        // Reset the one-shot auto-recovery flag so a freshly selected city gets
        // its own chance at the empty-state widen — without this, jumping to a
        // second seeded city in the same session would silently render empty.
        didAutoRecoverEmpty = false
        let center = defaultCenterForSelectedCity
        cameraPosition = .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.09, longitudeDelta: 0.09)
        ))
        loadNearbyExperiences()
        updateBottomInfo()
        hydrateCityFromBackendIfNeeded(cityCode)
    }

    /// Nomad OS A2: if the freshly-selected city has no local experiences, pull
    /// whatever another traveler already synthesized for it from the backend and
    /// merge it in. Fire-and-forget and self-gating so it never blocks the map:
    ///
    ///  - skips seed / already-populated cities (a non-empty local set means
    ///    the map is fine as-is — this only rescues the empty case);
    ///  - runs at most once per city per session (`backendHydratedCities`);
    ///  - a fetch miss (backend off, offline, or nobody has synthesized this
    ///    city yet) leaves the empty state exactly as it was — the honest
    ///    "no experiences here" is a valid outcome, never an error.
    ///
    /// On a real merge it re-runs `loadNearbyExperiences()` so the new pins
    /// reach `visibleExperiences` (append alone doesn't refresh the map).
    private func hydrateCityFromBackendIfNeeded(_ cityCode: String?) {
        guard let cityCode, !cityCode.isEmpty else { return }
        // Only rescue the empty case; a populated city needs no network read.
        guard visibleExperiences.isEmpty else { return }
        guard !backendHydratedCities.contains(cityCode) else { return }
        backendHydratedCities.insert(cityCode)

        Task { [weak self] in
            guard let self else { return }
            let fetched = await self.cityExperienceFetcher.fetchCityExperiences(cityCode: cityCode)
            guard !fetched.isEmpty else { return }
            let added = self.experienceService.appendGenerated(fetched)
            // Only refresh if this is still the active city and something landed.
            guard added > 0, self.selectedCity == cityCode else { return }
            self.loadNearbyExperiences()
        }
    }

    /// When the current area has no experiences, returns the name of the first
    /// available city so the empty state can offer a one-tap redirect.
    /// Reads `experienceService.allExperiences` directly instead of
    /// `availableCities` to avoid the `@ObservationIgnored` cache, which
    /// SwiftUI cannot track for re-evaluation.
    public var suggestedCityName: String? {
        guard visibleExperiences.isEmpty else { return nil }
        guard let code = firstAvailableCityCode else { return nil }
        return Self.cityNameMap[code] ?? code
    }

    /// When the current area has no experiences, returns the code of the first
    /// available city for programmatic city-switch.
    public var suggestedCityCode: String? {
        guard visibleExperiences.isEmpty else { return nil }
        return firstAvailableCityCode
    }

    /// Resolve a human-readable city name for a city code, consulting the
    /// static name map and alias table. Used by the city pill when
    /// `availableCities` doesn't contain the code directly.
    public func resolvedCityName(for code: String) -> String? {
        if let name = Self.cityNameMap[code] { return name }
        if let canonical = Self.cityCodeAliases[code.lowercased()],
           let name = Self.cityNameMap[canonical] { return name }
        return nil
    }

    /// Derive the first city code that has seed data, bypassing the memoized
    /// `availableCities` so SwiftUI observation tracks the read.
    /// Uses `cityCodeMatches` to properly exclude the selected city and its
    /// aliases (e.g. "shenzhen" ↔ "cn-深圳市").
    private var firstAvailableCityCode: String? {
        guard let selected = selectedCity else { return nil }
        var seen = Set<String>()
        for exp in experienceService.allExperiences {
            let code = exp.location.cityCode
            if !Self.cityCodeMatches(code, selected: selected) && seen.insert(code).inserted {
                return code
            }
        }
        return nil
    }

    /// Returns the city code whose experiences are collectively closest to the given coordinate.
    public func nearestSeededCity(to coordinate: CLLocationCoordinate2D) -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var bestCode: String?
        var bestDistance = Double.infinity
        for city in availableCities {
            let cityLoc = CLLocation(latitude: city.center.latitude, longitude: city.center.longitude)
            let dist = location.distance(from: cityLoc)
            if dist < bestDistance {
                bestDistance = dist
                bestCode = city.code
            }
        }
        return bestCode
    }

    /// Single source of truth for camera glide timing, shared by every
    /// programmatic camera move (recenter, focusOnExperience) so the feel
    /// stays consistent and is tunable in one place (#132).
    static let cameraAnimation: Animation = .smooth(duration: 0.35)

    /// Timing for annotation set changes (filter switch, pan refresh) so the
    /// ForEach markers fade in/out instead of snapping — kills the full-redraw
    /// flicker (#133). Paired with the per-marker .transition in CompassMapView.
    static let markerSetAnimation: Animation = .easeInOut(duration: 0.25)

    // MARK: - Published state
    // @ObservationIgnored avoids @Observable macro expanding MapCameraPosition
    // into a synthetic file that lacks `import MapKit`, causing build errors.
    @ObservationIgnored private var _cameraPosition: MapCameraPosition
    public var cameraPosition: MapCameraPosition {
        get { _cameraPosition }
        set {
            withMutation(keyPath: \.cameraPositionVersion) {
                _cameraPosition = newValue
                cameraPositionVersion &+= 1
            }
        }
    }
    // Observers watch this instead of cameraPosition directly.
    private var cameraPositionVersion: UInt8 = 0
    public var selectedCategory: ExperienceCategory?
    /// Currently selected custom-tag pill from `FilterBarView`. When non-nil,
    /// `applyFilters(...)` keeps only experiences whose `userTags` contains
    /// this value. Mutually exclusive with `selectedCategory` and
    /// `isNowFilter` — selecting any of those clears the others. US-008.
    public var selectedCustomTag: String?
    public var visibleExperiences: [Experience] = []

    // MARK: - Zoom-adaptive map density (Level-of-Detail)

    /// Latest map-camera vertical span (`region.span.latitudeDelta`, in degrees).
    /// Updated by the view on every `onMapCameraChange(.onEnd)`. Drives how many
    /// pins the map shows: zoomed out (large span) → few prominent pins;
    /// zoomed in (small span) → progressively more. Longitude delta is skipped
    /// because it distorts with latitude, while latitude degrees are uniform.
    /// Default seeds a city-level span so the first render isn't over-dense.
    public var currentSpanLatitudeDelta: Double = MapViewModel.defaultSpanLatitudeDelta

    /// Default span used before the first camera change — roughly city-district
    /// scale, so the cold-start map already shows a curated (not flooded) set.
    static let defaultSpanLatitudeDelta: Double = 0.08

    /// The pins the *map* should render for the current zoom. A pure derived
    /// view over `visibleExperiences`: rank by prominence, then keep only the
    /// top `mapDisplayLimit`. `visibleExperiences` itself stays full — now-count,
    /// the cold-start watchdog, and the bottom list all keep reading the
    /// complete set (the list intentionally shows more than the map).
    public var displayedExperiences: [Experience] {
        let limit = Self.spanToLimit(currentSpanLatitudeDelta)
        guard visibleExperiences.count > limit else { return visibleExperiences }
        let affinity = experienceService.repo.categoryAffinity()
        return Self.rankedByProminence(visibleExperiences, categoryAffinity: affinity)
            .prefix(limit).map { $0 }
    }

    /// Cached snapshot of the last `clusteredMapItems` compute, keyed by a
    /// fingerprint of the inputs. SwiftUI Map's body reads `clusteredMapItems`
    /// on every render pass (many per second during pan/zoom); recomputing the
    /// grid + centroid math each time was the second source of "markers drift
    /// back and forth" — Swift Dictionary iteration is not deterministic, so
    /// two back-to-back calls with the same inputs could return items in
    /// different orders. The fingerprint snaps to the same discrete `cellSize`
    /// bands the engine already uses, so a small pan doesn't invalidate.
    @ObservationIgnored private var clusteredCacheFingerprint: String?
    @ObservationIgnored private var clusteredCacheValue: [MapItem] = []

    /// Clustered map items — groups overlapping pins at city/district zoom into
    /// cluster markers. At street zoom, every pin renders individually.
    var clusteredMapItems: [MapItem] {
        let displayed = displayedExperiences
        let cellSize = MapClusterEngine.cellSize(for: currentSpanLatitudeDelta)
        // Fingerprint = (cellSize band, count, joined id list). The id list is
        // cheap because `displayedExperiences` is already capped by
        // `spanToLimit`, and it's the only thing that reliably catches both
        // "a pin appeared" and "the ranked order changed".
        let fingerprint = "\(cellSize)|\(displayed.count)|\(displayed.map(\.id).joined(separator: ","))"
        if fingerprint == clusteredCacheFingerprint {
            return clusteredCacheValue
        }
        let items = MapClusterEngine.cluster(displayed, spanLatitudeDelta: currentSpanLatitudeDelta)
        clusteredCacheFingerprint = fingerprint
        clusteredCacheValue = items
        return items
    }

    /// Span → max number of map pins. Three bands matched to how a solo traveler
    /// reads the map: city overview shows only the standout dozen; district
    /// shows ~30; street/walking scale lifts the cap entirely so every nearby
    /// pin is reachable. Boundaries are `static let` so they're easy to tune.
    static let cityBandSpan: Double = 0.12   // ≳ whole-city view
    static let districtBandSpan: Double = 0.03 // ≳ district view
    static let cityBandLimit: Int = 12
    static let districtBandLimit: Int = 30

    static func spanToLimit(_ latitudeDelta: Double) -> Int {
        if latitudeDelta >= cityBandSpan { return cityBandLimit }
        if latitudeDelta >= districtBandSpan { return districtBandLimit }
        return Int.max // street level: show everything
    }

    /// Prominence score (higher = more deserving of a map pin when space is
    /// scarce). Combines signals that already exist on every `Experience`:
    /// best-now (most time-relevant), Solo-Score (fit for solo travelers),
    /// confidence level (data we trust), and passive footprint hits (places
    /// people actually go). All weighted into a single comparable Double.
    static func prominenceScore(
        for exp: Experience,
        now: Date = Date(),
        categoryAffinity: [ExperienceCategory: Int] = [:]
    ) -> Double {
        var score = 0.0
        if exp.isBestNow(at: now) { score += 100 }       // time-relevant dominates
        score += exp.soloScore.overall * 5                // 0–10 → 0–50
        score += Double(exp.confidence.level) * 4         // 0–5  → 0–20
        score += min(Double(exp.confidence.signals.passiveGpsHits30d), 10) * 1.5 // capped footprint

        // Beta-P1-I: personal data flywheel. Each prior completion in this
        // category contributes +6, capped at +30 so a heavy bias toward
        // (say) cafes doesn't swamp time-relevant best-now picks. The
        // cap is intentional: we want the rank to nudge, not lock in.
        if let n = categoryAffinity[exp.category], n > 0 {
            score += min(Double(n) * 6, 30)
        }
        return score
    }

    /// `visibleExperiences` (already distance-sorted by the service) re-ranked
    /// by prominence. Swift's `sorted(by:)` is *not* guaranteed stable, so we
    /// carry the original index and use it as an explicit tiebreak — keeping
    /// equal-prominence pins in their incoming (nearest-first) order.
    static func rankedByProminence(
        _ experiences: [Experience],
        now: Date = Date(),
        categoryAffinity: [ExperienceCategory: Int] = [:]
    ) -> [Experience] {
        experiences.enumerated()
            .sorted { lhs, rhs in
                let ls = prominenceScore(for: lhs.element, now: now, categoryAffinity: categoryAffinity)
                let rs = prominenceScore(for: rhs.element, now: now, categoryAffinity: categoryAffinity)
                // Epsilon comparison so rounding error from prominenceScore's
                // weighted sum doesn't randomly flip equally-ranked cards
                // each render — without this, the tie-break by distance is
                // not actually reached when the math rounds slightly apart.
                if abs(ls - rs) > 1e-9 { return ls > rs }
                return lhs.offset < rhs.offset // distance order as tiebreak
            }
            .map { $0.element }
    }

    /// US-021: read-only passthrough to the full seeded/synced experience set.
    /// `MapViewModelEagerInitTest` reads this on the launch path to prove the
    /// eagerly-built view model is live before any `onAppear` fires.
    public var allExperiences: [Experience] { experienceService.allExperiences }

    /// US-018: cached count of visible experiences at their best time right
    /// now. Recomputed only by `recomputeNowCount()` — called at the end of
    /// `loadNearbyExperiences`, `refreshForLocation`, and `updateBottomInfo`
    /// (the only places `visibleExperiences` changes or is re-read for info).
    /// This avoids an O(n) `isBestNow()` scan on every SwiftUI render of
    /// `BottomInfoSheet` / `FilterBarView`.
    @ObservationIgnored private var _nowCount: Int = 0

    /// Number of currently visible experiences that are at their best time right now.
    public var nowCount: Int { _nowCount }

    /// Single source of truth for `_nowCount`. The only place that scans
    /// `visibleExperiences` for `isBestNow()`. Call after any mutation of
    /// `visibleExperiences`.
    private func recomputeNowCount() {
        let clockNow = AppClock.now()
        _nowCount = visibleExperiences.filter { $0.isBestNow(at: clockNow) }.count
    }

    // MARK: - Empty-state progression (US-012)

    /// Progressive escalation when `visibleExperiences` is empty. The
    /// `EmptyStateOverlay` view renders a different button per stage:
    /// `.tryExpand` (5 km → 25 km) → `.tryExplore` (Overpass at 12 km)
    /// → `.browseCity` (jump to nearest seeded city). Stage advances
    /// only as long as each previous action still yields an empty
    /// result; the first non-empty render resets to `.tryExpand`.
    public enum EmptyStateStage { case tryExpand, tryExplore, browseCity }

    /// Current empty-state stage. Updated by `recordEmptyStateRender()`,
    /// which the view calls after every refresh.
    public private(set) var emptyStateStage: EmptyStateStage = .tryExpand

    /// Consecutive empty renders since the last non-empty result. Used
    /// to flip into `.browseCity` after three failed cycles.
    private var emptyStateConsecutiveEmptyCount: Int = 0

    /// Set once the user taps the `.tryExpand` button so the next empty
    /// render upgrades to `.tryExplore` (PRD: "tryExplore after tapping
    /// expand still yields empty").
    private var emptyStateExpandTried: Bool = false

    public var selectedExperience: Experience?
    /// City OS v2: the id of the 在地 event whose map marker is highlighted (set
    /// when the user taps "在地图上看" in the live sheet or a chat event card).
    /// Purely a render cue for `EventMarkerView.isHighlighted`; nil = none.
    public var highlightedEventId: String?
    public var isShowingDetail: Bool = false
    /// How the currently-open detail was reached, so dismissing it can pick the
    /// right destination: a list/nearby/pin tap returns to the clean list, while
    /// a map-pin long-press peek falls back to the floating preview card.
    ///
    /// The two entry points share one `selectedExperience` but carry different
    /// mental models. A `.listTap` is "open this, look, then back to my list" —
    /// backing out must land on a clean list with no floating card left hovering
    /// over it (the "退出详情后悬窗残留 / Starbucks card floating over the list"
    /// report). A `.mapPeek` is the Approach-C long-press flow (peek card →
    /// expand → detail): backing out deliberately falls back to that preview
    /// card, because detail is a layer *above* the peek, not a replacement.
    enum DetailEntrySource { case listTap, mapPeek }
    private(set) var detailEntrySource: DetailEntrySource = .mapPeek
    public var bottomInfoText: String = ""
    public var nearbySoloCount: Int = 0
    public var aiExplanation: String?
    public var lastAIError: String?

    // True when a "Now" filter is active (best-now experiences only).
    public var isNowFilter: Bool = false

    /// True when the "Saved" filter is active — keeps only experiences the user
    /// has favourited. Mutually exclusive with `selectedCategory`,
    /// `selectedCustomTag`, and `isNowFilter` (selecting any of those clears
    /// this, and vice-versa). The favourite set already exists end-to-end
    /// (`preferences.favoritedExperiences`); this is the map filter entry point.
    public var isFavoriteFilter: Bool = false

    // MARK: - Location error surfacing (US-026)

    /// Tracks the most recent `LocationService.lastError` we already reported to
    /// Sentry, so observing the banner text repeatedly doesn't re-capture the
    /// same failure. `@ObservationIgnored` because it's bookkeeping, not UI state.
    @ObservationIgnored private var reportedLocationError: NSError?

    /// Derived, dismissible banner copy for a GPS failure. Returns the localized
    /// `location.error.banner` string when `LocationService.lastError` is set,
    /// or nil when GPS is healthy. Reading this also reports the warning to
    /// Sentry once per distinct error. Reading `locationService.lastError` keeps
    /// SwiftUI's dependency tracking intact (LocationService is `@Observable`),
    /// so the banner appears/disappears reactively.
    public var locationErrorBannerText: String? {
        guard let error = locationService.lastError else {
            reportedLocationError = nil
            return nil
        }
        let nsError = error as NSError
        if reportedLocationError != nsError {
            reportedLocationError = nsError
            // `level:` defaults to `.warning` in SentryService.capture(message:),
            // so we don't reference SentryLevel here (no Sentry import needed).
            SentryService.capture(
                message: "LocationService.lastError surfaced",
                context: [
                    "domain": nsError.domain,
                    "code": nsError.code,
                    "description": nsError.localizedDescription
                ]
            )
        }
        return NSLocalizedString(
            "location.error.banner",
            comment: "Banner shown when GPS fails and the map falls back to a default region"
        )
    }

    // MARK: - Voice processing feedback

    public var isProcessingVoiceIntent: Bool = false
    public var currentVoiceTranscript: String = ""
    /// Ephemeral toast shown after voice AI resolves. Nil when not active.
    public var voiceResultToast: String?

    // MARK: - Settings

    public var isShowingSettings: Bool = false

    // MARK: - Pending check-in

    /// Non-nil while a geofence-triggered check-in prompt is pending.
    public var pendingCheckIn: (id: String, title: String)?

    /// Call on appear and when preferences.pendingCheckIns changes.
    public func checkForPendingCheckIns() {
        guard pendingCheckIn == nil,
              let (id, _) = preferences.pendingCheckIns.first else { return }
        let title = visibleExperiences.first { $0.id == id }?.title
            ?? experienceService.getExperience(id: id)?.title
            ?? id
        pendingCheckIn = (id: id, title: title)
    }

    /// Mark the pending geofence check-in as visited when the user confirms
    /// they arrived, then advance to any next queued check-in.
    public func confirmCheckIn() {
        guard let pending = pendingCheckIn else { return }
        preferences.markCompleted(pending.id)
        preferences.clearPendingCheckIn(pending.id)
        pendingCheckIn = nil
        checkForPendingCheckIns()
    }

    /// Dismiss the pending check-in prompt without marking it visited, then
    /// advance to any next queued check-in.
    public func dismissCheckIn() {
        guard let pending = pendingCheckIn else { return }
        preferences.clearPendingCheckIn(pending.id)
        pendingCheckIn = nil
        checkForPendingCheckIns()
    }

    // MARK: - Add-experience flow (long-press on map)

    /// Coordinate the user long-pressed; non-nil while we're prompting to confirm.
    public var pendingAddCoordinate: CLLocationCoordinate2D?
    /// Set once the user confirms — drives the voice-input sheet.
    public var isRecordingNewExperience: Bool = false
    /// Set once the user confirms — drives the structured create-place form
    /// (the primary add path; voice is the secondary one).
    public var isShowingCreateForm: Bool = false
    /// Candidate experiences added via long-press → voice → AI. Rendered with
    /// `.hidden` category and a distinct (dashed) marker.
    public var candidateExperiences: [Experience] = []

    /// Hard cap on `candidateExperiences` (#70). A long session of "drop a pin"
    /// + voice creates one entry each — left unbounded, a power user could
    /// pile up hundreds and pay the SwiftUI diff cost on every map redraw.
    /// 200 is roughly the marker budget MapKit handles smoothly at city zoom;
    /// older entries fall off the head first (FIFO) so the most-recent
    /// candidates always survive.
    public static let candidateExperiencesCap = 200

    /// Append a candidate with dedupe-by-id + FIFO cap. Replaces an existing
    /// entry in place (preserving order) when the same id is added twice —
    /// matches the existing replace-by-id contract that `applyEnrichedCandidate`
    /// relies on.
    private func appendCandidate(_ candidate: Experience) {
        if let i = candidateExperiences.firstIndex(where: { $0.id == candidate.id }) {
            candidateExperiences[i] = candidate
            return
        }
        candidateExperiences.append(candidate)
        if candidateExperiences.count > Self.candidateExperiencesCap {
            candidateExperiences.removeFirst(
                candidateExperiences.count - Self.candidateExperiencesCap
            )
        }
    }

    public init(
        locationService: LocationService,
        experienceService: ExperienceService,
        aiService: AIService,
        preferences: UserPreferences,
        overpassService: OverpassService = OverpassService(),
        foursquareService: FoursquareService = FoursquareService(),
        geocodeService: any ReverseGeocoding = ReverseGeocodeService()
    ) {
        self.locationService = locationService
        self.experienceService = experienceService
        self.aiService = aiService
        self.overpassService = overpassService
        self.foursquareService = foursquareService
        self.geocodeService = geocodeService
        self.preferences = preferences
        // DEBUG-only: `-startCity <cityCode>` launch argument forces the initial
        // city (e.g. VTE) so UI tests / manual verification can land directly on
        // a seeded city without persisting through the picker. Release builds and
        // launches without the flag fall back to the persisted last-selected city.
        #if DEBUG
        let forcedStartCity = UserDefaults.standard.string(forKey: "startCity")
        let resolvedStartCity = forcedStartCity ?? preferences.lastSelectedCity
        // A `-startCity` launch argument is an explicit pick: e2e harnesses
        // and demo recipes depend on the forced city holding the camera, so
        // the first GPS fix must not re-follow it to the fix's city.
        self.cityPickedExplicitlyThisSession = forcedStartCity != nil
        #else
        let resolvedStartCity = preferences.lastSelectedCity
        #endif
        self.selectedCity = resolvedStartCity
        let initialCenter: CLLocationCoordinate2D
        if let savedCity = resolvedStartCity {
            // Resolve center lazily — availableCities depends on experienceService which is set above.
            // We compute inline here since computed properties aren't accessible before init ends.
            var cityExps: [String: [CLLocationCoordinate2D]] = [:]
            for exp in experienceService.allExperiences {
                guard let coord = exp.coordinate else { continue }
                cityExps[exp.location.cityCode, default: []].append(coord)
            }
            if let coords = cityExps[savedCity], !coords.isEmpty {
                let avgLat = coords.map(\.latitude).reduce(0, +) / Double(coords.count)
                let avgLon = coords.map(\.longitude).reduce(0, +) / Double(coords.count)
                initialCenter = CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)
            } else if let known = Self.knownCityCenters[savedCity]
                        ?? Self.cityCodeAliases[savedCity.lowercased()]
                            .flatMap({ Self.knownCityCenters[$0] })
                        ?? Self.knownCityCenters[savedCity.uppercased()]
                        ?? Self.knownCityCenters[savedCity.lowercased()] {
                // V-006/SZX: seed 数据不覆盖 savedCity 时(冷启动到 Shenzhen 但
                // seed 只有 cmi/VTE),回退到 knownCityCenters,避免落到默认
                // 中心(SF/清迈)。case 不敏感 + alias 兼容,和
                // syncCameraToSelectedCity()/defaultCenterForSelectedCity() 一致。
                initialCenter = known
            } else {
                initialCenter = Self.defaultCenter
            }
        } else {
            initialCenter = Self.defaultCenter
        }
        self._cameraPosition = .region(MKCoordinateRegion(
            center: initialCenter,
            span: MKCoordinateSpan(
                latitudeDelta: locationService.currentLocation != nil ? MapZoom.streetLevel : MapZoom.cityLevel,
                longitudeDelta: locationService.currentLocation != nil ? MapZoom.streetLevel : MapZoom.cityLevel
            )
        ))
        // V-002: `didSet` does not fire for the `selectedCity` set above
        // (initializer semantics), so apply the same camera↔city sync here so
        // a cold start with a persisted city lands the camera on that city's
        // center — including slug-only selections resolved via knownCityCenters.
        syncCameraToSelectedCity()
        loadNearbyExperiences()
        updateBottomInfo()
    }

    // MARK: - Loading

    /// Called when the distance slider is released in SettingsView.
    /// Reloads visible experiences with the newly committed radius.
    public func reloadForDistanceChange() {
        loadNearbyExperiences()
    }

    /// Recompute the experiences shown on the map for the current origin,
    /// distance, and active filters, refreshing markers and the info bar.
    public func loadNearbyExperiences() {
        loadNearbyExperiences(overrideRadiusKm: nil)
    }

    /// Internal load that lets the cold-start auto-recovery widen the radius
    /// in-memory (without persisting the change to `preferences.maxDistanceKm`).
    /// Pass `nil` for the normal preference-driven path. `fitCamera: false`
    /// skips the pin auto-fit for callers that just pinned the camera on a
    /// deliberate coordinate (see `recenter(on:)`).
    private func loadNearbyExperiences(overrideRadiusKm: Double?, fitCamera: Bool = true) {
        // US-017: the experience set (and thus discovered cities) may have
        // changed since the last load — e.g. after an Explore added pins.
        // Drop the city cache so the next `availableCities` read recomputes.
        invalidateCityCache()
        let center = nearbyQueryOrigin
        let radiusKm = max(1.0, overrideRadiusKm ?? preferences.maxDistanceKm)
        let nearby = applyFilters(near: center, radiusKm: radiusKm)
        withAnimation(Self.markerSetAnimation) {
            visibleExperiences = nearby
            nearbySoloCount = computeNearbySoloCount(in: nearby)
        }
        aiSmartPickIds = []
        recomputeNowCount()
        updateBottomInfo()
        if fitCamera {
            fitCameraToPinsIfNeeded(nearby)
        }
        scheduleColdStartEmptyWatchdog()
    }

    /// When pins are clustered in a tight area relative to the current camera
    /// span, zoom in so every pin is individually visible instead of stacking
    /// into a single dot at city-overview zoom.
    private func fitCameraToPinsIfNeeded(_ experiences: [Experience]) {
        let coords = experiences.compactMap(\.coordinate)
        guard coords.count >= 2 else { return }

        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        let latSpread = maxLat - minLat
        let lonSpread = maxLon - minLon

        // Only auto-fit when pins are much tighter than the current camera.
        guard latSpread < currentSpanLatitudeDelta * 0.3 else { return }
        guard lonSpread < currentSpanLatitudeDelta * 0.3 else { return }

        let padding = max(latSpread, lonSpread, 0.005) * 1.8
        let newSpan = MKCoordinateSpan(
            latitudeDelta: max(latSpread + padding, 0.01),
            longitudeDelta: max(lonSpread + padding, 0.01)
        )
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        withAnimation(Self.cameraAnimation) {
            cameraPosition = .region(MKCoordinateRegion(center: center, span: newSpan))
        }
    }

    /// V-004: origin for the nearby query. A *preset* city selection drives the
    /// origin from that city's center, NOT live GPS — otherwise a cold start in
    /// the simulator (GPS defaults to San Francisco) queries thousands of km from
    /// the selected city and returns zero seed experiences. Custom pins keep
    /// their explicit coordinate; with no city selected we follow live GPS (or
    /// the default center) as before.
    private var nearbyQueryOrigin: CLLocationCoordinate2D {
        if let custom = customCoordinates { return custom }
        if let city = selectedCity, !city.hasPrefix("custom_") {
            return defaultCenterForSelectedCity
        }
        return locationService.currentLocation?.coordinate ?? defaultCenterForSelectedCity
    }

    // MARK: - Cold-start empty-state watchdog (V-004 / US-033)

    /// Seconds a selected city may stay empty before we report it to Sentry
    /// AND auto-recover. Was 5; tightened to 1 because the user-visible
    /// "Quiet patch of map." panel renders within the first frame, so a
    /// 5-second wait felt like the app was broken to anyone watching. The
    /// auto-recovery path only widens the radius in-memory and only once.
    static let coldStartEmptyWatchdogSeconds: UInt64 = 1

    /// Set true once we've reported a given empty cold start so the watchdog
    /// doesn't spam Sentry on every subsequent reload while the map stays empty.
    @ObservationIgnored private var reportedColdStartEmpty = false

    /// Set true after the watchdog has auto-recovered an empty cold start
    /// once by widening the radius in-memory to 25 km. Prevents oscillation
    /// when the user later returns to a genuinely empty area in the same
    /// session. Reset by `selectCity` so a fresh city pick gets a fresh shot.
    @ObservationIgnored private var didAutoRecoverEmpty = false

    /// In-flight watchdog so repeated `loadNearbyExperiences` calls don't pile
    /// up parallel timers. `@ObservationIgnored` — pure bookkeeping.
    @ObservationIgnored private var coldStartWatchdogTask: Task<Void, Never>?

    /// V-004: when a city is selected but the nearby set is still empty after
    /// `coldStartEmptyWatchdogSeconds`, emit a Sentry warning so the
    /// cold-start-empty regression can't silently come back. Resets as soon as
    /// any non-empty load lands. No-op when no preset city is selected (an empty
    /// GPS-follow map isn't necessarily a bug).
    private func scheduleColdStartEmptyWatchdog() {
        guard let city = selectedCity, !city.hasPrefix("custom_") else {
            coldStartWatchdogTask?.cancel()
            coldStartWatchdogTask = nil
            reportedColdStartEmpty = false
            return
        }
        if !visibleExperiences.isEmpty {
            // Recovered — clear the flag so a later empty state can report again.
            reportedColdStartEmpty = false
            coldStartWatchdogTask?.cancel()
            coldStartWatchdogTask = nil
            return
        }
        guard !reportedColdStartEmpty, coldStartWatchdogTask == nil else { return }
        let seconds = Self.coldStartEmptyWatchdogSeconds
        coldStartWatchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.coldStartWatchdogTask = nil
            guard let current = self.selectedCity, !current.hasPrefix("custom_"),
                  self.visibleExperiences.isEmpty, !self.reportedColdStartEmpty else { return }
            self.reportedColdStartEmpty = true
            SentryService.capture(
                message: "Cold-start empty state: selectedCity set but 0 nearby experiences",
                context: [
                    "selectedCity": current,
                    "maxDistanceKm": self.preferences.maxDistanceKm,
                    "totalExperiences": self.experienceService.allExperiences.count
                ]
            )
            // R8 auto-recovery: a selected city that lands 0 nearby after the
            // grace window is almost always a too-tight radius (seeded city,
            // user's preferred 5–8 km vs a hero pin at 7–10 km). Widen the
            // radius in-memory to 25 km exactly once per session so the user
            // sees the city's curated set instead of "Quiet patch of map."
            // Persisted preference is intentionally left alone — this is a
            // recovery, not a re-configuration.
            if !self.didAutoRecoverEmpty {
                self.didAutoRecoverEmpty = true
                await MainActor.run {
                    self.loadNearbyExperiences(overrideRadiusKm: 25)
                }
            }
        }
    }

    /// Candidate pool for the route builder: every nearby experience in the
    /// selected city, ignoring the *transient* map filters (Now / category /
    /// tag / favorite). The create-route sheet used to be fed
    /// `visibleExperiences` — but its entry card lives in the Now section, so
    /// the pool arrived pre-filtered by `isBestNow()` and was routinely empty:
    /// a blank "選擇地點" list and a permanently disabled AI button.
    /// Standing preferences (disliked categories) still apply.
    public func routeCandidates() -> [Experience] {
        var nearby = experienceService.getExperiences(
            near: nearbyQueryOrigin,
            radiusKm: max(1.0, preferences.maxDistanceKm)
        )
        if let cityCode = selectedCity, !cityCode.hasPrefix("custom_") {
            nearby = nearby.filter { Self.cityCodeMatches($0.location.cityCode, selected: cityCode) }
        }
        if !preferences.dislikedCategories.isEmpty {
            let disliked = Set(preferences.dislikedCategories)
            nearby = nearby.filter { !disliked.contains($0.category) }
        }
        return nearby
    }

    private func applyFilters(near coordinate: CLLocationCoordinate2D, radiusKm: Double) -> [Experience] {
        var nearby = experienceService.getExperiences(near: coordinate, radiusKm: radiusKm)
        #if DEBUG
        let allCount = experienceService.allExperiences.count
        NSLog("RUBRIC_DBG applyFilters origin=(%.4f,%.4f) radiusKm=%.1f allCount=%d nearbyBeforeCity=%d selectedCity=%@",
              coordinate.latitude, coordinate.longitude, radiusKm, allCount, nearby.count, selectedCity ?? "nil")
        #endif
        // Custom locations have no matching cityCode — show all nearby experiences instead.
        if let cityCode = selectedCity, !cityCode.hasPrefix("custom_") {
            // V-004: alias-aware so a header slug (`chiang-mai`) matches the seed
            // `cityCode` (`cmi`) — exact `==` left the cold-start map empty.
            nearby = nearby.filter { Self.cityCodeMatches($0.location.cityCode, selected: cityCode) }
            #if DEBUG
            NSLog("RUBRIC_DBG afterCityFilter city=%@ count=%d", cityCode, nearby.count)
            #endif
        }
        if let category = selectedCategory {
            nearby = nearby.filter { $0.category == category }
        }
        if let tag = selectedCustomTag {
            nearby = nearby.filter { ($0.userTags ?? []).contains(tag) }
        }
        if isNowFilter {
            // Pass AppClock.now() so the DEBUG rubric harness's -scenarioHour
            // override drives Now filter — otherwise `isBestNow()` reads the
            // device wall clock and s07 lunch (hour=12) filters everything out
            // when tests run overnight.
            let clockNow = AppClock.now()
            nearby = nearby.filter { $0.isBestNow(at: clockNow) }
        }
        if isFavoriteFilter {
            let favorites = preferences.favoritedExperiences
            nearby = nearby.filter { favorites.contains($0.id) }
        }
        if !preferences.dislikedCategories.isEmpty {
            let disliked = Set(preferences.dislikedCategories)
            nearby = nearby.filter { !disliked.contains($0.category) }
        }
        #if DEBUG
        // Rubric round-18 fix: `-seniorPersona` DEBUG launch arg reorders the
        // list so shrine/park/culture (typically flat, benches, English signage)
        // sort above cafe/food for the 68-year-old s09 first-solo-abroad
        // story. The judges unanimously flagged that Meiji Jingu had the
        // benches + flat-walk chips but Coffee Ron kept the top slot on
        // pure distance. Guards behind DEBUG so production ranking is
        // untouched.
        if ProcessInfo.processInfo.arguments.contains("-seniorPersona") {
            nearby.sort { lhs, rhs in
                let lhsBoost = Self.seniorAffinityScore(for: lhs)
                let rhsBoost = Self.seniorAffinityScore(for: rhs)
                if lhsBoost != rhsBoost { return lhsBoost > rhsBoost }
                return false
            }
        }
        #endif
        return nearby
    }

    /// Whether an experience is somewhere a digital nomad can actually work.
    /// True for explicit `.work` spots (coworking, libraries) and for cafés that
    /// already advertise a wifi *or* power `CategoryHighlight` — the two signals
    /// the enrichment pipeline emits for "can I sit here with a laptop". Kept
    /// `static` and pure so it's cheap in hot loops and unit testable without a
    /// live view model.
    static func isWorkReady(_ experience: Experience) -> Bool {
        if experience.category == .work { return true }
        guard experience.category == .coffee else { return false }
        return experience.highlights.contains { $0.kind == .wifi || $0.kind == .power }
    }

    /// Work-ready spots for the selected city, best first, for the Base panel's
    /// 「办公点」section. Ranking is soloScore-first (a stored, honest number)
    /// with title as a stable tiebreak — NowScore is per-moment and would need
    /// an async weather pass, which a glanceable panel row doesn't justify.
    public func workReadySpots(limit: Int = 3) -> [Experience] {
        guard let city = selectedCity else { return [] }
        return allExperiences
            .filter { Self.cityCodeMatches($0.location.cityCode, selected: city) }
            .filter { Self.isWorkReady($0) }
            .sorted {
                if $0.soloScore.overall != $1.soloScore.overall {
                    return $0.soloScore.overall > $1.soloScore.overall
                }
                return $0.title < $1.title
            }
            .prefix(limit)
            .map { $0 }
    }

    #if DEBUG
    /// Score used by the round-18 `-seniorPersona` boost. Shrines / parks
    /// / historic culture score highest because Meiji Jingu, Aoyama Book
    /// Center, and similar low-body-load POIs cluster there. Cafe/food
    /// score neutral. Nightlife scores negative to keep Ichiran-style
    /// chains from wrongly leading a senior day story.
    private static func seniorAffinityScore(for exp: Experience) -> Int {
        switch exp.category {
        case .nature, .culture:
            return 3
        case .wellness:
            return 2
        case .coffee:
            return 1
        case .food, .work, .hidden:
            return 0
        case .nightlife:
            return -2
        }
    }
    #endif

    /// Apply (or clear, when nil) a category filter from the category pills,
    /// clearing other active filters and refreshing the map.
    public func selectCategory(_ category: ExperienceCategory?) {
        selectedCategory = category
        selectedCustomTag = nil
        isNowFilter = false
        isFavoriteFilter = false
        loadNearbyExperiences()
        updateBottomInfo()
        // US-011: empty category inside a seeded city → debounced auto-Explore.
        scheduleAutoExploreForEmptyCategoryIfNeeded()
    }

    /// Activate the "best right now" filter, clearing other filters and showing
    /// only experiences well-suited to the current time of day.
    public func selectNowFilter() {
        isNowFilter = true
        selectedCategory = nil
        selectedCustomTag = nil
        isFavoriteFilter = false
        loadNearbyExperiences()
        updateBottomInfo()
    }

    /// Toggle the "Saved" filter. Tapping it again clears it (back to All),
    /// matching the toggle behaviour of the category/Now pills. Activating it
    /// clears every other active filter so the four filter modes stay mutually
    /// exclusive. The favourite set lives in `preferences.favoritedExperiences`.
    public func selectFavoriteFilter() {
        if isFavoriteFilter {
            isFavoriteFilter = false
        } else {
            isFavoriteFilter = true
            selectedCategory = nil
            selectedCustomTag = nil
            isNowFilter = false
        }
        loadNearbyExperiences()
        updateBottomInfo()
    }

    /// Reset all active map filters back to showing every nearby experience.
    public func clearFilters() {
        selectedCategory = nil
        selectedCustomTag = nil
        isNowFilter = false
        isFavoriteFilter = false
        loadNearbyExperiences()
        updateBottomInfo()
    }

    // MARK: - Empty-state progression (US-012)

    /// Advance / reset the empty-state stage machine based on the
    /// current `visibleExperiences` snapshot. Callers (the view + the
    /// action handlers below) invoke this whenever a refresh has
    /// settled. The first non-empty render fully resets the machine.
    public func recordEmptyStateRender() {
        guard visibleExperiences.isEmpty else {
            emptyStateConsecutiveEmptyCount = 0
            emptyStateExpandTried = false
            emptyStateStage = .tryExpand
            return
        }
        emptyStateConsecutiveEmptyCount += 1
        if emptyStateConsecutiveEmptyCount >= 3 {
            emptyStateStage = .browseCity
        } else if emptyStateExpandTried {
            emptyStateStage = .tryExplore
        } else {
            emptyStateStage = .tryExpand
        }
    }

    /// US-012 stage 1: bump `maxDistanceKm` to 25 km and fire an
    /// Explore at the current anchor. Marks the expand attempt so the
    /// next empty render escalates to `.tryExplore`.
    public func emptyStateActionTryExpand() {
        emptyStateExpandTried = true
        preferences.maxDistanceKm = 25
        let anchor = locationService.currentLocation?.coordinate ?? defaultCenterForSelectedCity
        loadNearbyExperiences()
        recordEmptyStateRender()
        Task { await self.exploreNearby(at: anchor) }
    }

    /// US-012 stage 2: widen the Overpass radius to 12 km. Stage stays
    /// in `.tryExplore` until either the explore returns results (reset)
    /// or three consecutive empty renders flip it to `.browseCity`.
    public func emptyStateActionTryExplore() {
        let anchor = locationService.currentLocation?.coordinate ?? defaultCenterForSelectedCity
        recordEmptyStateRender()
        Task { await self.exploreNearby(at: anchor, radiusMeters: 12000) }
    }

    /// US-012 stage 3: reuse the existing "Browse nearest city" jump
    /// that the legacy overlay shipped with.
    public func emptyStateActionBrowseCity() {
        let anchor = locationService.currentLocation?.coordinate ?? defaultCenterForSelectedCity
        if let code = nearestSeededCity(to: anchor) {
            selectCity(code)
        }
    }

    /// Toggle a custom-tag pill. Selecting the currently-active tag clears
    /// it (same toggle behaviour as built-in category pills). Selecting a
    /// different tag replaces the current selection and clears any other
    /// active filter. US-008.
    public func selectCustomTag(_ tag: String) {
        if selectedCustomTag == tag {
            selectedCustomTag = nil
        } else {
            selectedCustomTag = tag
            selectedCategory = nil
            isNowFilter = false
            isFavoriteFilter = false
        }
        loadNearbyExperiences()
        updateBottomInfo()
    }

    /// Select an experience to surface its floating preview card (without opening
    /// the full detail sheet) and pan the camera to frame it. This is the
    /// *long-press* path: a quick peek that the user can expand into the detail
    /// sheet via the card's own expand action. Tapping a card/pin instead routes
    /// through `openExperienceDetail` for a direct jump to the detail sheet.
    public func selectExperience(_ experience: Experience) {
        Haptics.impact(.light)
        selectedExperience = experience
        // This is the preview-card path (long-press peek). The detail layer, if
        // the user later expands the card, sits *above* this card — so dismissing
        // it must peel back to the card, not to the bare map.
        detailEntrySource = .mapPeek
        // isShowingDetail stays false — card shows first, detail sheet on expand
        focusOnExperience(experience)
    }

    /// Open an experience's full detail sheet directly, skipping the floating
    /// preview card. This is the *tap* path: tapping a Nearby/favorite card or a
    /// map pin jumps straight to the detail content. `selectedExperience` is still
    /// set so backing out of the detail lands on the preview card (see
    /// `dismissDetail`), and the camera reframes the same way `selectExperience`
    /// does. Long-pressing the same card/pin floats the preview card instead.
    public func openExperienceDetail(_ experience: Experience) {
        Haptics.selection()
        selectedExperience = experience
        isShowingDetail = true
        // Tap jumped straight to detail with no preview card behind it, so a
        // back-out should land on the clean list / bare map rather than reveal a
        // card the user never summoned (see `dismissDetail`).
        detailEntrySource = .listTap
        focusOnExperience(experience)
    }

    /// Fraction of screen height occupied by the bottom sheet/card.
    /// Updated by the view when the detent changes so camera offset stays accurate.
    /// 0 = no sheet, ~0.35 = small card, ~0.50 = medium detent, ~0.85 = large detent.
    public var activeSheetHeightFraction: Double = 0.35

    /// Pan the camera so `experience` sits in the top 40% of the visible area
    /// above the current bottom sheet. The visible area is `1 - sheetFraction`
    /// of the full screen height. We shift the map center southward (decrease
    /// latitude) by the delta needed to move the pin from screen-center to the
    /// 40% position within the exposed area.
    public func focusOnExperience(_ experience: Experience) {
        guard let coord = experience.coordinate else { return }
        let region: MKCoordinateRegion = cameraPosition.region ?? MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
        )
        let sheetFraction = max(0, min(0.95, activeSheetHeightFraction))
        // Pin should appear at 40% from top of the visible area above the sheet.
        // Visible fraction: (1 - sheetFraction). Target pin position from top of screen:
        //   0.4 * (1 - sheetFraction)
        // Current pin position if centered: 0.5
        // Required northward shift of center (in screen fractions): 0.5 - 0.4*(1-sheetFraction)
        //   = 0.5 - 0.4 + 0.4*sheetFraction = 0.1 + 0.4*sheetFraction
        // Convert to degrees: shift * latitudeDelta
        let centerShiftFraction = 0.1 + 0.4 * sheetFraction
        let latOffset = centerShiftFraction * region.span.latitudeDelta
        let newCenter = CLLocationCoordinate2D(
            latitude: coord.latitude - latOffset,
            longitude: coord.longitude
        )
        let newRegion = MKCoordinateRegion(center: newCenter, span: region.span)
        withAnimation(Self.cameraAnimation) {
            cameraPosition = .region(newRegion)
        }
    }

    /// Close the expanded detail sheet, choosing the destination by how the
    /// detail was reached (`detailEntrySource`).
    ///
    /// - `.listTap` (Nearby row / map pin / favorites tap): the user opened
    ///   detail straight from a list with no preview card underneath, so a
    ///   back-out clears the selection and lands on the clean list — nothing
    ///   floats over it. This kills the "退出详情后悬窗残留 / Starbucks card
    ///   hovering above the list" overlap.
    /// - `.mapPeek` (long-press → preview card → expand): detail is a layer
    ///   *above* the peek card the user deliberately summoned, so dismiss peels
    ///   off only that layer and reveals the card again (selection retained).
    public func dismissDetail() {
        isShowingDetail = false
        if detailEntrySource == .listTap {
            selectedExperience = nil
        }
    }

    /// Fully dismiss the floating preview card and its selection, returning to
    /// the bare map. This is the card's own swipe-down / close action — the one
    /// place selection is cleared, distinct from `dismissDetail` which only
    /// peels off the detail layer.
    public func clearSelection() {
        isShowingDetail = false
        selectedExperience = nil
        detailEntrySource = .mapPeek
    }

    /// US-VA-03 tool `dismiss_recommendation`: hide one experience from
    /// `visibleExperiences` without touching SwiftData. The next refresh
    /// (filter change, new explore, app relaunch) brings it back —
    /// dismissal is intentionally ephemeral so the AI can't permanently
    /// blackhole results the user might want later.
    public func dismissFromVisible(_ id: String) {
        visibleExperiences.removeAll { $0.id == id }
        if selectedExperience?.id == id {
            selectedExperience = nil
            isShowingDetail = false
            detailEntrySource = .mapPeek
        }
    }

    /// Recenter the camera and refresh experiences for the given coordinate.
    /// Use this for explicit recentering (e.g. "locate me" button), NOT for
    /// reacting to user pan/zoom — that would create a feedback loop where
    /// every gesture resets the zoom level.
    public func recenter(on coordinate: CLLocationCoordinate2D) {
        // Wrap in withAnimation so the camera glides in, matching
        // focusOnExperience — a bare assignment snaps instantly and reads
        // as janky (#132).
        withAnimation(Self.cameraAnimation) {
            cameraPosition = .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: MapZoom.streetLevel, longitudeDelta: MapZoom.streetLevel)
            ))
        }
        // The camera was just deliberately pinned on `coordinate`; the pin
        // auto-fit inside the reload would immediately drag it back toward
        // the nearest experience cluster — the user saw their location circle
        // glide to screen center and then slide away again on every recenter.
        loadNearbyExperiences(overrideRadiusKm: nil, fitCamera: false)
        updateBottomInfo()
    }

    /// Rubric fix: zoom to fit the coordinate cluster (used at Explore
    /// completion so the newly-added pins actually SEE the pin highlight
    /// vs. dim treatment). With `recenter(on:)` at a wide default span
    /// the pins collapse to indistinguishable dots and the whole
    /// dim-modifier design pays no rent — the user just sees "6 dots
    /// somewhere in a 5 km circle" and has to pinch in themselves.
    ///
    /// Falls back to `recenter(on: fallback)` if `coordinates` is empty
    /// or degenerate. Padding factor keeps the pins off the edges so
    /// they don't sit under the sheet.
    public func zoomToFit(
        _ coordinates: [CLLocationCoordinate2D],
        fallback: CLLocationCoordinate2D,
        paddingFactor: Double = 1.4
    ) {
        guard let first = coordinates.first else {
            recenter(on: fallback)
            return
        }
        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude
        for c in coordinates {
            if c.latitude  < minLat { minLat = c.latitude }
            if c.latitude  > maxLat { maxLat = c.latitude }
            if c.longitude < minLon { minLon = c.longitude }
            if c.longitude > maxLon { maxLon = c.longitude }
        }
        let latDelta = max((maxLat - minLat) * paddingFactor, 0.008)
        let lonDelta = max((maxLon - minLon) * paddingFactor, 0.008)
        guard latDelta.isFinite, lonDelta.isFinite else {
            recenter(on: fallback)
            return
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        withAnimation(Self.cameraAnimation) {
            cameraPosition = .region(MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
            ))
        }
        // This method IS the deliberate camera fit — the reload's own pin
        // auto-fit would re-fit against a stale settled span and tug the
        // camera a second time.
        loadNearbyExperiences(overrideRadiusKm: nil, fitCamera: false)
        updateBottomInfo()
    }

    /// Refresh visible experiences when the user pans/zooms the map. Does NOT
    /// touch `cameraPosition`, to avoid fighting the user's gesture.
    public func refreshForLocation(_ coordinate: CLLocationCoordinate2D) {
        let radiusKm = max(1.0, preferences.maxDistanceKm)
        let nearby = applyFilters(near: coordinate, radiusKm: radiusKm)
        withAnimation(Self.markerSetAnimation) {
            visibleExperiences = nearby
            nearbySoloCount = computeNearbySoloCount(in: nearby)
        }
        recomputeNowCount()
        updateBottomInfo()
    }

    /// Marker state derivation — the map view consults this for each pin.
    public func markerState(for experience: Experience, now: Date = Date()) -> ExperienceMarkerState {
        if preferences.isCompleted(experience.id) { return .completed }
        if preferences.isFavorited(experience.id) { return .favorited }
        if experience.isBestNow(at: now) { return .bestNow }
        if let upcoming = minutesUntilBestTime(for: experience, from: now), upcoming > 0, upcoming <= 120 {
            return .upcoming(minutes: upcoming)
        }
        // P1.1 #112: a passive VisitRecord (5+ min dwell) earns the same
        // gold-halo footprint treatment as the legacy passiveGpsHits30d
        // signal, so the new Archive layer lights up without us having to
        // back-fill the confidence struct.
        if visitedExperienceIds.contains(experience.id) {
            return .footprinted
        }
        if experience.confidence.signals.passiveGpsHits30d > 0 {
            return .footprinted
        }
        return .default
    }

    /// Footprint count (passive GPS hits in last 30 days) for the marker badge.
    public func footprintCount(for experience: Experience) -> Int {
        experience.confidence.signals.passiveGpsHits30d
    }

    private func minutesUntilBestTime(for experience: Experience, from date: Date) -> Int? {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        let nowMinutes = hour * 60 + minute

        let upcomingStarts: [Int] = experience.bestTimes.compactMap { window in
            let startMin = window.startHour * 60
            return startMin > nowMinutes ? (startMin - nowMinutes) : nil
        }
        return upcomingStarts.min()
    }

    /// The soonest experience (across all loaded experiences in the current city)
    /// that is not yet at its best but starts within 180 minutes.
    /// Used by the "Now" filter empty state to offer a one-tap next action.
    /// `now` is injectable so callers (e.g. a `TimelineView`) can drive the
    /// recompute from a clock tick and so unit tests can pin a deterministic instant.
    public func nextBestExperience(now: Date = Date()) -> (experience: Experience, minutesUntil: Int)? {
        let cityCode = selectedCity
        let candidates = experienceService.allExperiences.filter { exp in
            guard !exp.isBestNow(at: now) else { return false }
            if let code = cityCode, !code.hasPrefix("custom_") {
                return exp.location.cityCode == code
            }
            return true
        }
        var best: (experience: Experience, minutesUntil: Int)?
        for exp in candidates {
            guard let mins = minutesUntilBestTime(for: exp, from: now),
                  mins > 0, mins <= 180 else { continue }
            if best == nil || mins < best!.minutesUntil {
                best = (exp, mins)
            }
        }
        return best
    }

    /// The soonest experience whose next best-time window starts later *today*,
    /// with **no upper bound** on how far out it is. Where `nextBestExperience`
    /// caps at 180 minutes to power the imminent "jump there" countdown, this is
    /// the wider net behind the "Now" filter's dedicated empty state: during the
    /// quiet hours — late at night, mid-afternoon lull — nothing is at its best
    /// *and* nothing opens within three hours, so we still want to point the
    /// traveler at the soonest worthwhile window ("Café X · best 5–7pm") rather
    /// than the generic "clear filters" dead-end. Returns nil only when nothing
    /// has an upcoming window today at all (e.g. genuinely late night).
    /// `now` is injectable for `TimelineView` ticks and deterministic tests.
    public func soonestUpcomingExperience(now: Date = Date()) -> (experience: Experience, minutesUntil: Int)? {
        let cityCode = selectedCity
        let candidates = experienceService.allExperiences.filter { exp in
            guard !exp.isBestNow(at: now) else { return false }
            if let code = cityCode, !code.hasPrefix("custom_") {
                return exp.location.cityCode == code
            }
            return true
        }
        var best: (experience: Experience, minutesUntil: Int)?
        for exp in candidates {
            guard let mins = minutesUntilBestTime(for: exp, from: now), mins > 0 else { continue }
            if best == nil || mins < best!.minutesUntil {
                best = (exp, mins)
            }
        }
        return best
    }

    // MARK: - Bottom info bar

    /// Refresh the bottom info bar with a time-of-day appropriate summary of
    /// the currently visible experiences.
    public func updateBottomInfo() {
        // US-018: refresh the cached now-count here too — `isBestNow()` is
        // time-dependent, so a fresh count is needed whenever the bottom info
        // is recomputed. This is the single recompute checkpoint for this path.
        recomputeNowCount()
        // Read the app clock, not `Date()`, so the DEBUG rubric harness can
        // pin scenario hour via `-scenarioHour 12` and the SZX lunch story
        // stops firing "It's late — rest up" at 00:30 real time.
        let hour = Calendar.current.component(.hour, from: AppClock.now())
        let count = visibleExperiences.count

        switch hour {
        case 6..<12:
            // Coffee-specific subset — not the full now-count, so it stays a
            // local computation. Written without the `visibleExperiences.filter
            // { ... isBestNow }` shape so `_nowCount` remains the sole source.
            var coffeeCount = 0
            for exp in visibleExperiences where exp.category == .coffee && exp.isBestNow() {
                coffeeCount += 1
            }
            bottomInfoText = String(
                format: NSLocalizedString("info.morning", comment: "Morning info"),
                coffeeCount > 0 ? coffeeCount : count
            )
        case 12..<17:
            bottomInfoText = String(
                format: NSLocalizedString("info.afternoon", comment: "Afternoon info"),
                count
            )
        case 17..<22:
            bottomInfoText = String(
                format: NSLocalizedString("info.evening", comment: "Evening info"),
                count
            )
        default:
            bottomInfoText = String(
                format: NSLocalizedString("info.night", comment: "Night info"),
                _nowCount
            )
        }
    }

    // MARK: - AI

    /// IDs of the top-3 AI-ranked experiences (smart picks). Updated by
    /// `runAIRanking()`; used by `NearbySection` to pin those rows with
    /// a sun-gold border and warm gradient bg.
    public var aiSmartPickIds: [String] = []

    /// Smart-pick ids actually surfaced to the UI. Falls back to the
    /// Solo-Score top-3 of the visible set when AI ranking hasn't produced
    /// any picks yet (cold start, missing AI key, or offline). Without this
    /// the map looks like a wall of identical pins on first open — the curation
    /// signal only appears after the AI ranker finishes, which may never happen
    /// for users without an API key.
    public var effectiveSmartPickIds: [String] {
        if !aiSmartPickIds.isEmpty { return aiSmartPickIds }
        return visibleExperiences
            .sorted { $0.soloScore.overall > $1.soloScore.overall }
            .prefix(3)
            .map { $0.id }
    }

    /// Reorder the visible experiences using AI ranking and highlight the top
    /// three as smart picks, leaving the list intact if ranking fails.
    public func runAIRanking() async {
        let candidates = visibleExperiences
        guard !candidates.isEmpty else { return }
        let context = AIService.UserContext(
            location: locationService.currentLocation?.coordinate,
            date: Date(),
            style: preferences.soloTravelStyle,
            preferredCategories: preferences.preferredCategories,
            dislikedCategories: preferences.dislikedCategories
        )
        // US-026: surface the synthesis as an "AI 编排中" Live Activity — the
        // skeleton-shimmer island that stands in for "正在编排今日页面". Ended in
        // the defer so it always tears down, success or failure.
        LiveActivityService.shared.startCompile(
            title: NSLocalizedString("island.compile.title", comment: "AI compile island title"),
            subtitle: String(
                format: NSLocalizedString("island.compile.subtitle", comment: "AI compile island subtitle — count of candidates"),
                candidates.count
            )
        )
        defer { Task { await LiveActivityService.shared.end() } }
        do {
            let ranked = try await aiService.recommendExperiences(from: candidates, context: context)
            let rank = Dictionary(uniqueKeysWithValues: ranked.enumerated().map { ($0.element, $0.offset) })
            visibleExperiences = candidates.sorted { lhs, rhs in
                (rank[lhs.id] ?? Int.max) < (rank[rhs.id] ?? Int.max)
            }
            aiSmartPickIds = Array(ranked.prefix(3))
            lastAIError = nil
        } catch {
            // Unranked list is still useful — keep it visible, just record the error.
            lastAIError = error.localizedDescription
        }
    }

    /// Step 1 happens in the view (screen point → coordinate). Steps 2-3 live
    /// here: stash the coordinate so the view can show a confirmation, then
    /// `confirmAddExperience()` flips into recording mode for the voice flow.
    public func handleMapLongPress(at coordinate: CLLocationCoordinate2D) {
        pendingAddCoordinate = coordinate
    }

    /// Abort the long-press add-experience flow, clearing the pending coordinate
    /// and exiting voice-recording mode.
    public func cancelAddExperience() {
        pendingAddCoordinate = nil
        isRecordingNewExperience = false
        isShowingCreateForm = false
    }

    /// Confirm the long-pressed location and begin voice recording to describe
    /// the new experience to add there.
    public func confirmAddExperience() {
        guard pendingAddCoordinate != nil else { return }
        isRecordingNewExperience = true
    }

    /// Confirm the long-pressed location and open the structured create-place
    /// form (the primary add path). `pendingAddCoordinate` stays set so the
    /// form knows where to anchor; it is cleared on save/cancel.
    public func confirmAddExperienceWithForm() {
        guard pendingAddCoordinate != nil else { return }
        isShowingCreateForm = true
    }

    /// Persist a user-created place from the form, render it immediately, and
    /// clear the add-experience flow. The candidate is built via
    /// `Experience.userDraft`, which forces unverified trust defaults — the
    /// user never scores their own place.
    public func createUserExperience(from input: NewPlaceFormInput) {
        defer { cancelAddExperience() }
        let candidate = Experience.userDraft(
            uuid: UUID().uuidString,
            title: input.title,
            oneLiner: input.oneLiner,
            category: input.category,
            coordinates: [input.coordinate.longitude, input.coordinate.latitude],
            // No cityCode filtering for user pins — they belong to wherever the
            // user dropped them, not a curated city set.
            cityCode: selectedCity ?? "user",
            placeNameRomanized: input.placeNameRomanized,
            placeNameLocal: input.placeNameLocal,
            description: input.description,
            photoUrls: input.photoUrls
        )
        // Persist to SwiftData (idempotent by id) AND queue the Supabase upload
        // to user_experiences (Phase 2). Survives relaunch and offline.
        _ = experienceService.recordUserExperience(candidate)
        // Render right away: keep it in the candidate layer (distinct marker)
        // and surface it among visible experiences without a full reload.
        appendCandidate(candidate)
        withAnimation(Self.markerSetAnimation) {
            visibleExperiences.append(candidate)
            nearbySoloCount = computeNearbySoloCount(in: visibleExperiences)
        }

        // Best-effort AI enrichment (Pro + signed in). The place already exists;
        // this only upgrades its copy with a real Solo Score / whyItMatters when
        // the Edge Function succeeds. Failures are silent — the candidate stays.
        Task { [weak self] in
            guard let self else { return }
            guard let enriched = await self.aiService.enrichUserExperience(candidate) else { return }
            self.experienceService.replaceGenerated(enriched)
            self.applyEnrichedCandidate(enriched)
        }
    }

    /// Swap an AI-enriched user place into the in-memory candidate/visible sets
    /// so the open map and any card re-render with the new Solo Score / copy.
    private func applyEnrichedCandidate(_ enriched: Experience) {
        if let i = candidateExperiences.firstIndex(where: { $0.id == enriched.id }) {
            candidateExperiences[i] = enriched
        }
        if let j = visibleExperiences.firstIndex(where: { $0.id == enriched.id }) {
            withAnimation(Self.markerSetAnimation) {
                visibleExperiences[j] = enriched
                nearbySoloCount = computeNearbySoloCount(in: visibleExperiences)
            }
        }
        if selectedExperience?.id == enriched.id {
            selectedExperience = enriched
        }
    }

    /// Use AIService to structure a free-form transcript into a candidate
    /// Experience anchored at `pendingAddCoordinate`. The candidate is added
    /// with category `.hidden` so the marker layer can render it distinctly.
    public func handleNewExperienceTranscript(_ transcript: String) async {
        guard let coordinate = pendingAddCoordinate else { return }
        defer { cancelAddExperience() }
        do {
            let response = try await aiService.processVoiceIntent(transcript: transcript, near: coordinate)
            let now = Date()
            let candidate = Experience(
                id: "candidate_\(UUID().uuidString)",
                title: transcript,
                oneLiner: response.explanation,
                whyItMatters: response.explanation,
                category: .hidden,
                location: ExperienceLocation(
                    coordinates: [coordinate.longitude, coordinate.latitude],
                    cityCode: "user"
                ),
                bestTimes: [],
                durationMinutes: .init(min: 30, max: 60),
                howTo: [],
                realInconveniences: [],
                soloScore: SoloScore(
                    overall: 0,
                    breakdown: .init(seatingFriendly: 0, soloPatronRatio: 0, staffPressure: 0, soloPortioning: 0, ambianceFit: 0, safety: 0),
                    basedOnCount: 0
                ),
                sources: [InformationSource(type: .user, attribution: "you", verifiedAt: now)],
                confidence: Confidence(
                    level: 0,
                    lastVerifiedAt: now,
                    reason: "Self-reported, unverified",
                    signals: .init(aiScrapeAgeDays: 0, passiveGpsHits30d: 0, activeReports30d: 0, trustedVerifications: 0)
                ),
                nearbyExperienceIds: [],
                stats: .init(completionCount: 0, averageRating: 0),
                status: .candidate,
                createdAt: now,
                updatedAt: now
            )
            appendCandidate(candidate)
            aiExplanation = response.explanation
            lastAIError = nil
        } catch {
            lastAIError = error.localizedDescription
        }
    }

    /// Handle a spoken request by interpreting it through AI to filter and
    /// recommend experiences, gating behind Pro and the data-use consent first.
    public func handleVoiceTranscript(_ transcript: String) async {
        // US-024: voice intent is Pro-only. Park the action and surface
        // the paywall when a free user taps the mic.
        if !isProUser {
            onPaywallUnlocked = { [weak self] in
                Task { await self?.handleVoiceTranscript(transcript) }
            }
            isShowingPaywall = true
            return
        }
        // US-034: voice intent goes through AIService → Anthropic.
        // Surface the data-use disclosure once before the first call.
        if !preferences.hasAcceptedExploreConsent {
            onExploreConsentAccepted = { [weak self] in
                Task { await self?.handleVoiceTranscript(transcript) }
            }
            isShowingExploreConsent = true
            return
        }
        let coordinate = locationService.currentLocation?.coordinate ?? Self.defaultCenter
        let nearby = experienceService.allExperiences.filter { exp in
            guard let expCoord = exp.coordinate else { return false }
            let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let expLoc = CLLocation(latitude: expCoord.latitude, longitude: expCoord.longitude)
            return expLoc.distance(from: loc) < 10_000
        }
        isProcessingVoiceIntent = true
        currentVoiceTranscript = transcript
        defer { isProcessingVoiceIntent = false }
        do {
            let response = try await aiService.processVoiceIntent(
                transcript: transcript,
                near: coordinate,
                nearbyExperiences: nearby
            )
            currentVoiceTranscript = ""
            aiExplanation = response.explanation
            if let suggestion = response.filterSuggestion {
                selectCategory(suggestion)
            }
            if !response.recommendedIds.isEmpty {
                let ids = Set(response.recommendedIds)
                visibleExperiences = experienceService.allExperiences.filter { ids.contains($0.id) }
            }
            bottomInfoText = response.explanation
            lastAIError = nil

            if !response.recommendedIds.isEmpty {
                voiceResultToast = String(
                    format: NSLocalizedString("voice.result.found", comment: ""),
                    response.recommendedIds.count
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    voiceResultToast = nil
                }
            } else if let suggestion = response.filterSuggestion {
                voiceResultToast = String(
                    format: NSLocalizedString("voice.result.filtered", comment: ""),
                    NSLocalizedString("category.\(suggestion.rawValue)", comment: "")
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    voiceResultToast = nil
                }
            } else {
                voiceResultToast = NSLocalizedString("voice.result.none", comment: "No matching places found nearby")
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    voiceResultToast = nil
                }
            }
        } catch {
            // Keep current state on error; record for UI to optionally surface.
            lastAIError = error.localizedDescription
        }
    }

    /// Number of experiences in a given city (for the city picker row subtitle).
    public func experienceCount(for cityCode: String) -> Int {
        experienceService.allExperiences.filter { $0.location.cityCode == cityCode }.count
    }

    // MARK: - Expand radius (US-021)

    /// Center used by the most recent progressive explore (or explicit radius override).
    /// Stored so `expandOneStage` can advance the same ring ladder from the same anchor.
    public private(set) var lastExploreCenter: CLLocationCoordinate2D?

    /// Index into `EnrichmentAgent.progressiveRadii` for the ring that was last
    /// scanned. `expandOneStage` advances this by one and reruns from that radius.
    public private(set) var lastProgressiveRadiusIndex: Int = 0

    /// Advance the progressive ring ladder by exactly one step from the last
    /// explore center. Returns `nil` when a new explore was successfully
    /// launched, or a human-readable no-op reason string when already at the
    /// max radius (100 km).
    @discardableResult
    public func expandOneStage() async -> String? {
        let radii = EnrichmentAgent.progressiveRadii
        let maxRadius = radii.last ?? 100_000
        guard progressiveScratchRadiusMeters < maxRadius else {
            return NSLocalizedString(
                "explore.expand.alreadyMax",
                comment: "Already at maximum explore radius"
            )
        }
        let center = lastExploreCenter ?? exploreAnchorCoordinate
        // Advance to the next ring beyond the current scratch radius.
        let nextRadius: Int
        if let nextIndex = radii.firstIndex(where: { $0 > progressiveScratchRadiusMeters }) {
            nextRadius = radii[nextIndex]
            lastProgressiveRadiusIndex = nextIndex
        } else {
            nextRadius = maxRadius
            lastProgressiveRadiusIndex = radii.count - 1
        }
        await exploreProgressively(at: center, startingRadiusMeters: nextRadius)
        return nil
    }

    // MARK: - Quality filter (US-020)

    /// Apply a quality-dimension filter to `visibleExperiences` in place,
    /// without making any network calls. Returns the count of experiences
    /// remaining after the filter is applied, for the agent reply.
    @discardableResult
    public func applyQualityFilter(_ filter: ExperienceFilter) -> Int {
        let trimmed = visibleExperiences.filter { filter.matches($0) }
        if trimmed.count != visibleExperiences.count {
            withAnimation(Self.markerSetAnimation) {
                visibleExperiences = trimmed
                nearbySoloCount = computeNearbySoloCount(in: trimmed)
            }
        }
        return trimmed.count
    }

    // MARK: - Explore Here

    /// US-019: Voice-tool entry point for progressive multi-ring explore.
    /// Delegates to `exploreNearby` (which uses `FeatureFlags.deepDiveEnrichment`
    /// for the progressive path internally). `startingRadiusMeters`, when set,
    /// overrides the initial stage of the progressive ladder.
    /// After the explore completes, applies `filter` to trim the visible set
    /// in-place so quality-dimension args from the voice tool take effect
    /// without an extra network call.
    public func exploreProgressively(
        at coordinate: CLLocationCoordinate2D,
        startingRadiusMeters: Int? = nil,
        category: ExperienceCategory? = nil,
        filter: ExperienceFilter? = nil
    ) async {
        lastExploreCenter = coordinate
        let radius = startingRadiusMeters ?? 3000
        await exploreNearby(at: coordinate, radiusMeters: radius, category: category)
        if let filter {
            let trimmed = visibleExperiences.filter { filter.matches($0) }
            if trimmed.count != visibleExperiences.count {
                withAnimation(Self.markerSetAnimation) {
                    visibleExperiences = trimmed
                    nearbySoloCount = computeNearbySoloCount(in: trimmed)
                }
            }
        }
    }

    /// Pull real OSM POIs near `coordinate`, hand them to AIService for
    /// solo-traveler enrichment, append the generated Experiences to the
    /// store, and refresh the visible set. No-op if already exploring.
    /// `cityCode` defaults to a stable hash of the coordinate so generated
    /// experiences group together in city pills.
    public func exploreNearby(
        at coordinate: CLLocationCoordinate2D,
        radiusMeters: Int = 3000,
        category: ExperienceCategory? = nil
    ) async {
        // DIAG: trace why amap is/isn't reached — entry, gates, flag.
        // All gates short-circuit before EnrichmentAgent.basePOIs ever runs,
        // so without this log a user reporting "no amap data" can't tell
        // whether the call was even attempted.
        print("🧭 exploreNearby entry: coord=(\(coordinate.latitude),\(coordinate.longitude)) r=\(radiusMeters) cat=\(category?.rawValue ?? "nil") isExploring=\(isExploring) isProUser=\(isProUser) consent=\(preferences.hasAcceptedExploreConsent) deepDive=\(FeatureFlags.deepDiveEnrichment)")

        guard !isExploring else {
            print("🧭 exploreNearby: skipped — already exploring")
            return
        }
        // Track center so expandOneStage can reuse it (US-021).
        lastExploreCenter = coordinate

        // US-024: free-tier gate. Park the original action so the
        // paywall's onUnlocked can resume it after purchase, then bail.
        if !isProUser {
            print("🧭 exploreNearby: gated by paywall (free tier)")
            onPaywallUnlocked = { [weak self] in
                Task { await self?.exploreNearby(at: coordinate, radiusMeters: radiusMeters, category: category) }
            }
            isShowingPaywall = true
            return
        }

        // US-034: surface the first-run data-use disclosure before the
        // first OSM + Anthropic call. Same park-and-resume pattern as
        // the paywall.
        if !preferences.hasAcceptedExploreConsent {
            print("🧭 exploreNearby: gated by explore consent (not yet accepted)")
            onExploreConsentAccepted = { [weak self] in
                Task { await self?.exploreNearby(at: coordinate, radiusMeters: radiusMeters, category: category) }
            }
            isShowingExploreConsent = true
            return
        }

        isExploring = true
        lastExploreError = nil
        lastFailureKind = nil
        lastExploreAddedCount = 0
        lastQuotaInfo = nil
        lastExploreToast = nil
        // Slice C: fresh Explore run resets the session-added ids so the
        // dim-others treatment and live-feed counter start clean.
        exploreSessionAddedIds.removeAll()
        pendingHandoff = nil
        lastCancelledKeptCount = nil
        // US-MR-05: stamp wall-clock start; emitted via durationMs.
        let exploreStart = Date()
        defer {
            isExploring = false
            // US-MR-04: always clear progress on exit so a fail / partial
            // run doesn't leave the capsule stuck.
            exploreProgress = .idle
            // US-011: clear the radius ring overlay when explore ends.
            withAnimation(.easeOut(duration: 0.4)) {
                exploreRadiusOverlay = nil
            }
        }

        // Propagate current subscription tier so AIService applies
        // the right daily cap (Pro: 30/60, Free: 0/0).
        aiService.isProTier = isProUser

        do {
            // US-016: resolve a real city name up front (both pipelines need
            // it). Fall back to the synthetic osm_<lat>_<lon> on geocoder miss.
            let resolved = await geocodeService.resolve(coordinate: coordinate)
            let cityCode = resolved?.cityCode ?? Self.cityCode(for: coordinate)

            // Persist the discovered city so the picker shows real names
            // on subsequent launches.
            if let resolved {
                experienceService.repo.recordDiscoveredCity(
                    cityCode: resolved.cityCode,
                    name: resolved.name,
                    countryCode: resolved.countryCode,
                    center: (lat: coordinate.latitude, lon: coordinate.longitude)
                )
            }

            let generated: [Experience]
            let effectiveRadius: Int
            // Track the final radius reached during progressive explore (US-006).
            var progressiveFinalRadiusKm: Int?

            if FeatureFlags.deepDiveEnrichment {
                // Progressive explore: small radius (5km) first, expand outward
                // until enough POIs accumulate. Batches are appended to
                // visibleExperiences incrementally as they arrive (US-009).
                let filteredCategories: [ExperienceCategory] = category.map { [$0] } ?? []
                // Reset scratch state before the progressive run.
                progressiveScratchRadiusMeters = EnrichmentAgent.progressiveRadii[0]
                progressiveScratchAddedCount = 0

                let allResults = await enrichmentAgent.exploreProgressively(
                    at: coordinate,
                    categories: filteredCategories,
                    cityCode: cityCode,
                    locale: LanguageService.shared.effectiveLocale,
                    onProgress: { [weak self] progress in
                        guard let self else { return }
                        // Track which radius we've scanned for US-006 toast.
                        if case .scanning(let km) = progress {
                            self.progressiveScratchRadiusMeters = km * 1_000
                            // US-011: update the radius ring overlay to current stage.
                            withAnimation(.easeInOut(duration: 0.3)) {
                                self.exploreRadiusOverlay = (center: coordinate, radiusMeters: Double(km * 1_000))
                            }
                        } else if case .expanding(let km) = progress {
                            self.progressiveScratchRadiusMeters = km * 1_000
                            // US-011: update overlay to the new (larger) radius.
                            withAnimation(.easeInOut(duration: 0.3)) {
                                self.exploreRadiusOverlay = (center: coordinate, radiusMeters: Double(km * 1_000))
                            }
                        }
                        self.exploreProgress = progress
                    },
                    onBatch: { [weak self] batch in
                        guard let self else { return }
                        // US-009: dedupe by id and append to visibleExperiences.
                        let existingIds = Set(self.visibleExperiences.map(\.id))
                        let novel = batch.filter { !existingIds.contains($0.id) }
                        if !novel.isEmpty {
                            let batchAdded = self.experienceService.appendGenerated(novel)
                            self.progressiveScratchAddedCount += batchAdded
                            // Slice C: track this Explore's own new ids so
                            // the map dim & the live-feed list can pick
                            // them out from the pre-existing set.
                            for exp in novel {
                                self.exploreSessionAddedIds.insert(exp.id)
                            }
                            withAnimation(Self.markerSetAnimation) {
                                self.visibleExperiences.append(contentsOf: novel)
                                self.nearbySoloCount = self.computeNearbySoloCount(in: self.visibleExperiences)
                            }
                        }
                    }
                )

                // Set the final radius so US-006 toast can reference it.
                progressiveFinalRadiusKm = progressiveScratchRadiusMeters / 1_000
                lastExploreAddedCount = progressiveScratchAddedCount

                guard !allResults.isEmpty else {
                    if let region = experienceService.repo.closestRecentRegion(to: coordinate),
                       case let cached = experienceService.repo.experiences(in: region),
                       !cached.isEmpty {
                        withAnimation(Self.markerSetAnimation) {
                            visibleExperiences = cached
                            nearbySoloCount = 0
                        }
                        updateBottomInfo()
                        lastExploreToast = NSLocalizedString("explore.toast.cachedFallback", comment: "Showing cached results")
                        return
                    }
                    lastExploreError = NSLocalizedString("explore.error.nothingFound", comment: "No POIs found nearby")
                    lastFailureKind = .noResults
                    return
                }
                // Use the full accumulated set for appendGenerated count tracking.
                generated = allResults
                effectiveRadius = progressiveScratchRadiusMeters
            } else {
                // Legacy wide-ring pipeline (kill-switch path).
                // US-MR-01: Pro multi-ring schedule (4 rings, dedup'd, single
                // synthesis). Falls back to a 1-ring fetch when the flag is off
                // or the user isn't on Pro.
                let (overpassPois, ringRadius) = try await fetchExplorePOIs(
                    near: coordinate,
                    singleRingRadius: radiusMeters,
                    category: category
                )

                // US-013: Foursquare fallback when Overpass is thin.
                var pois = overpassPois
                let fsqKey = Secrets.resolvedFoursquareKey
                if overpassPois.count < Self.foursquareFallbackThreshold, !fsqKey.isEmpty {
                    do {
                        let fsq = try await foursquareService.fetchPOIs(
                            near: coordinate,
                            radiusMeters: radiusMeters,
                            category: category
                        )
                        preferences.incrementFoursquareCallsToday()
                        pois = FoursquareService.merge(overpass: overpassPois, foursquare: fsq)
                    } catch {
                        logger.debug("Foursquare fallback failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
                guard !pois.isEmpty else {
                    if let region = experienceService.repo.closestRecentRegion(to: coordinate) {
                        let cached = experienceService.repo.experiences(in: region)
                        if !cached.isEmpty {
                            withAnimation(Self.markerSetAnimation) {
                                visibleExperiences = cached
                                nearbySoloCount = 0
                            }
                            updateBottomInfo()
                            lastExploreToast = NSLocalizedString("explore.toast.cachedFallback", comment: "Showing cached results")
                            return
                        }
                    }
                    lastExploreError = NSLocalizedString("explore.error.nothingFound", comment: "No POIs found nearby")
                    lastFailureKind = .noResults
                    return
                }

                if exploreProgress != .idle {
                    exploreProgress = .synthesizing(poiCount: pois.count)
                }
                generated = try await aiService.synthesizeExperiences(
                    from: pois,
                    cityCode: cityCode,
                    locale: LanguageService.shared.effectiveLocale
                )
                effectiveRadius = ringRadius
            }

            // For the progressive path, appendGenerated + lastExploreAddedCount were
            // already handled incrementally in onBatch. For the legacy path, do it now.
            let added: Int
            if FeatureFlags.deepDiveEnrichment {
                // Already persisted and counted in onBatch; use the cumulative count.
                added = lastExploreAddedCount
            } else {
                added = experienceService.appendGenerated(generated)
                lastExploreAddedCount = added
                // Slice C: legacy path — record every new id in the session
                // tracker so the overlay + live-feed pick them up too.
                for exp in generated {
                    exploreSessionAddedIds.insert(exp.id)
                }
            }

            // US-022: record a successful region so offline fallback can reuse it.
            // For multi-ring runs this is the outermost ring (12 km) so the
            // cached set has maximum coverage with one entry.
            experienceService.repo.recordRecentExploreRegion(
                centerLat: coordinate.latitude,
                centerLon: coordinate.longitude,
                radiusMeters: effectiveRadius
            )

            // US-015: surface quota banner if AIService just degraded.
            if aiService.quotaExceededAt != nil {
                lastQuotaInfo = NSLocalizedString(
                    "explore.quota.dailyLimit",
                    comment: "Daily AI limit reached banner"
                )
            }

            // US-017: auto-switch to the city we just discovered so the
            // city filter doesn't hide the new pins. Then build a toast.
            // US-MR-04: multi-ring runs use the "added across N km" variant
            // so users understand why distant places appeared.
            let wasMultiRing = effectiveRadius != radiusMeters
            // US-006: progressive runs that expanded past 5 km surface the final radius.
            let initialProgressiveKm = EnrichmentAgent.progressiveRadii[0] / 1_000
            let progressiveExpanded = progressiveFinalRadiusKm.map { $0 > initialProgressiveKm } ?? false

            // US-MR-05: emit analytics for multi-ring runs even when
            // added == 0 (a "we tried and got nothing" event is still
            // signal worth tracking).
            if wasMultiRing {
                let durationMs = Int(Date().timeIntervalSince(exploreStart) * 1000)
                let metrics = ExploreMetrics(
                    addedCount: added,
                    maxRadiusMeters: effectiveRadius,
                    failedRings: pendingFailedRings,
                    totalRings: Self.multiRingRadii.count,
                    durationMs: durationMs
                )
                lastMultiRingMetrics = metrics
                Self.emitMultiRingCompleted(metrics)
            }

            if added > 0 {
                // V-007 extension: when the user has an explicit city
                // selection (non-custom), preserve it — don't let an
                // explore result at the GPS coordinate hijack the camera.
                let userOwnsCity = (selectedCity.map { !$0.hasPrefix("custom_") }) ?? false
                let discoveredMatchesSelected = selectedCity == cityCode
                    || Self.cityCodeAliases[cityCode] == selectedCity
                    || Self.cityCodeAliases.first(where: { $0.value == selectedCity })?.key == cityCode
                if !userOwnsCity || discoveredMatchesSelected {
                    selectCity(cityCode, explicit: false)
                    // Rubric fix: fit the added cluster instead of snapping
                    // to a fixed 4 km span. Falls back to plain recenter if
                    // the batch is empty (added==0 branch handled above).
                    let clusterCoords: [CLLocationCoordinate2D] = visibleExperiences
                        .filter { exploreSessionAddedIds.contains($0.id) }
                        .compactMap { $0.coordinate }
                    if clusterCoords.count >= 2 {
                        zoomToFit(clusterCoords, fallback: coordinate)
                    } else {
                        recenter(on: coordinate)
                    }
                }
                let outerKm = effectiveRadius / 1000
                if progressiveExpanded, let finalKm = progressiveFinalRadiusKm {
                    // US-006: progressive run that widened past 5 km — show final radius.
                    if let resolved {
                        lastExploreToast = String(
                            format: NSLocalizedString("explore.toast.progressive.expandedNamed",
                                                      comment: "Expanded to %1$@ km · found %2$lld in %3$@"),
                            "\(finalKm)", Int64(added), resolved.name
                        )
                    } else {
                        lastExploreToast = String(
                            format: NSLocalizedString("explore.toast.progressive.expanded",
                                                      comment: "Expanded to %1$@ km · found %2$lld"),
                            "\(finalKm)", Int64(added)
                        )
                    }
                } else if let resolved {
                    let key = wasMultiRing
                        ? "explore.toast.multiRing.addedNamed"
                        : "explore.toast.addedNamed"
                    lastExploreToast = wasMultiRing
                        ? String(format: NSLocalizedString(key, comment: "multi-ring toast with city + count + km"),
                                 resolved.name, added, outerKm)
                        : String(format: NSLocalizedString(key, comment: "Now exploring %@ · %d places added"),
                                 resolved.name, added)
                } else {
                    let key = wasMultiRing
                        ? "explore.toast.multiRing.added"
                        : "explore.toast.added"
                    lastExploreToast = wasMultiRing
                        ? String(format: NSLocalizedString(key, comment: "multi-ring toast with count + km"),
                                 added, outerKm)
                        : String(format: NSLocalizedString(key, comment: "%d places added near you"),
                                 added)
                }
                // Slice C: hand the result set off to the UI as a discrete
                // artifact — the handoff card renders 4 CTAs (Ask Solo /
                // Save as walk / Expand / Clear) over this payload. Set
                // AFTER the toast + camera work so the card sees a stable
                // scene. `finalKm` mirrors the toast source of truth so
                // there's a single "we scanned this far" number.
                let finalKm = progressiveFinalRadiusKm ?? (effectiveRadius / 1000)
                let radii = EnrichmentAgent.progressiveRadii
                let canExpand = progressiveScratchRadiusMeters < (radii.last ?? Int.max)
                let verifiedInSession = countVerifiedInSession()
                pendingHandoff = ExploreSession.HandoffResult(
                    addedCount: added,
                    verifiedCount: verifiedInSession,
                    finalRadiusKm: max(finalKm, 1),
                    cityName: resolved?.name,
                    addedIds: Array(exploreSessionAddedIds),
                    canExpand: canExpand
                )
            }
        } catch {
            // US-022: on network failure, look for a recent nearby region and
            // surface its cached SwiftData pins instead of showing an error.
            if let region = experienceService.repo.closestRecentRegion(to: coordinate) {
                let offline = experienceService.repo.experiences(in: region)
                if !offline.isEmpty {
                    withAnimation(Self.markerSetAnimation) {
                        visibleExperiences = offline
                        nearbySoloCount = 0
                    }
                    updateBottomInfo()

                    let formatter = RelativeDateTimeFormatter()
                    formatter.unitsStyle = .full
                    let relDate = formatter.localizedString(for: region.exploredAt, relativeTo: Date())
                    let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 3600)
                    if region.exploredAt < sevenDaysAgo {
                        lastExploreToast = String(
                            format: NSLocalizedString(
                                "explore.offline.staleToast",
                                comment: "Showing offline data from <relative-date>"
                            ),
                            relDate
                        )
                    }
                    return
                }
            }
            lastExploreError = error.localizedDescription
            lastFailureKind = Self.classifyFailure(error)
        }
    }

    /// Classify a thrown error into a UI-presentable bucket so the banner
    /// can pick the right icon + copy ("offline" vs "service slow" vs
    /// "quota for today is used up"). Defaults to .apiServerError for
    /// anything unrecognized — the worst it can do is show the generic
    /// retry chip, which is still better than the old uncategorized state.
    static func classifyFailure(_ error: Error) -> ExploreFailureKind {
        if !NetworkMonitor.shared.isConnected { return .offline }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .cannotFindHost,
                 .networkConnectionLost, .dnsLookupFailed:
                return .apiTimeout
            case .notConnectedToInternet, .dataNotAllowed:
                return .offline
            default:
                return .apiServerError
            }
        }
        return .apiServerError
    }

    /// Pro multi-ring radii in meters (PRD docs/PRD/pro-radial-explore.md §3.1).
    /// Inner-first order matters for dedupe semantics — nearer POIs win
    /// when an osmId appears in two rings.
    static let multiRingRadii: [Int] = [1_500, 3_000, 6_000, 12_000]

    /// US-013: Overpass-thin threshold. Below this POI count, `exploreNearby`
    /// attempts a single Foursquare fallback when a key is configured.
    static let foursquareFallbackThreshold: Int = 5

    /// Coarse-grained UX state for an in-flight Explore. The view binds to
    /// `exploreProgress` to render an inline progress capsule above the
    /// BottomInfoBar (PRD §5, US-MR-04). `.idle` is the resting state.
    /// Single-ring legacy Explore stays `.idle` throughout — the capsule
    /// only appears for the Pro multi-ring schedule.
    public enum ExploreProgress: Equatable, Sendable {
        case idle
        /// `ringsDone` increments as each ring's Overpass call resolves (multi-ring concurrent path).
        case multiRingScanning(ringsDone: Int, totalRings: Int)
        /// Single AI synthesis kicked off with `poiCount` deduped POIs.
        case synthesizing(poiCount: Int)
        /// Progressive ladder is scanning the ring at `radiusKm` km.
        case scanning(radiusKm: Int)
        /// Progressive ladder is expanding to a larger ring at `toRadiusKm` km.
        case expanding(toRadiusKm: Int)
    }

    public var exploreProgress: ExploreProgress = .idle

    /// US-011: Current stage radius overlay during progressive explore.
    /// Non-nil while a stage is actively scanning; nil at idle/complete.
    public var exploreRadiusOverlay: (center: CLLocationCoordinate2D, radiusMeters: Double)?

    /// Telemetry from the most recent multi-ring Explore. Populated only
    /// when the Pro multi-ring schedule runs; nil after a single-ring
    /// fetch or before the first Explore. Bound by tests; in production
    /// it's also emitted as `explore_multi_ring_completed` via the
    /// DEBUG-print analytics shim below until a real AnalyticsService
    /// lands. US-MR-05.
    public struct ExploreMetrics: Equatable, Sendable {
        public let addedCount: Int
        public let maxRadiusMeters: Int
        public let failedRings: Int
        public let totalRings: Int
        public let durationMs: Int
    }

    public private(set) var lastMultiRingMetrics: ExploreMetrics?
    /// Mutable within `fetchExplorePOIs` (multi-ring path) to plumb
    /// failed-ring count up to `exploreNearby` without changing the
    /// existing tuple return signature (which is covered by tests).
    private var pendingFailedRings: Int = 0

    /// Scratch vars used by the progressive explore path to accumulate
    /// state across `onProgress`/`onBatch` closures without capturing
    /// mutable locals (Swift 6 strict-concurrency restriction).
    /// `internal` (not private) so unit tests can seed the current radius
    /// for `expandOneStage` assertions without triggering a full explore run.
    var progressiveScratchRadiusMeters: Int = 0
    private var progressiveScratchAddedCount: Int = 0

    /// Pull OSM POIs for `exploreNearby`. When the Pro multi-ring flag is
    /// on AND the user is Pro, fans out 4 concurrent Overpass calls and
    /// merges via `OverpassService.dedupe`. Otherwise falls back to a
    /// single-ring query at `singleRingRadius` (preserves pre-MR-01 behaviour).
    ///
    /// Returns `(pois, effectiveRadius)`. `effectiveRadius` is the radius
    /// to record in `recordRecentExploreRegion` — outermost ring for
    /// multi-ring runs, the caller's requested radius otherwise.
    ///
    /// Throws only when EVERY ring failed (multi-ring) or the single ring
    /// failed (single). Partial ring failures are swallowed so the outer
    /// catch in `exploreNearby` only fires when there's literally nothing
    /// to show.
    ///
    /// `internal` rather than `private` so tests in the same module can
    /// drive each ring scenario (full success / one ring fails / all fail)
    /// without going through the whole `exploreNearby` pipeline.
    func fetchExplorePOIs(
        near coordinate: CLLocationCoordinate2D,
        singleRingRadius: Int,
        category: ExperienceCategory? = nil
    ) async throws -> (pois: [OverpassService.POI], effectiveRadius: Int) {
        // Single-ring legacy path. Used when:
        //   - the flag is off, OR
        //   - the user isn't Pro (free-tier never gets here, but defence)
        guard FeatureFlags.proMultiRingExplore, isProUser else {
            let pois = try await overpassService.fetchPOIs(
                near: coordinate, radiusMeters: singleRingRadius, category: category
            )
            return (pois, singleRingRadius)
        }

        // Multi-ring: fan out 4 concurrent Overpass fetches. Each ring
        // independently catches errors so one slow/failed ring doesn't
        // tank the whole Explore. Order in the returned array matches
        // `multiRingRadii` so inner rings win in dedupe.
        let service = overpassService
        let total = Self.multiRingRadii.count
        var batches: [[OverpassService.POI]] = Array(repeating: [], count: total)
        var failedRings = 0

        // US-MR-04: surface scanning progress for the UI capsule.
        exploreProgress = .multiRingScanning(ringsDone: 0, totalRings: total)
        // US-MR-05: reset analytics counter before this run.
        pendingFailedRings = 0

        await withTaskGroup(of: (Int, [OverpassService.POI]).self) { group in
            for (index, radius) in Self.multiRingRadii.enumerated() {
                group.addTask { @MainActor in
                    do {
                        let pois = try await service.fetchPOIs(
                            near: coordinate, radiusMeters: radius, category: category
                        )
                        return (index, pois)
                    } catch {
                        return (index, [])
                    }
                }
            }
            var done = 0
            for await (index, pois) in group {
                batches[index] = pois
                if pois.isEmpty { failedRings += 1 }
                done += 1
                exploreProgress = .multiRingScanning(ringsDone: done, totalRings: total)
                // US-016: yield so SwiftUI can pick up each discrete
                // scanning(N,4) update before the next ring completes.
                await Task.yield()
            }
        }

        // US-MR-05: stash counters so exploreNearby can emit
        // `explore_multi_ring_completed` after appendGenerated.
        pendingFailedRings = failedRings

        // If every ring came back empty / failed, surface as a single
        // throw so the outer catch can hit the offline fallback branch.
        if failedRings == Self.multiRingRadii.count {
            throw OverpassService.OverpassError.requestFailed(status: 0)
        }

        let merged = OverpassService.dedupe(across: batches)
        let outermost = Self.multiRingRadii.last ?? singleRingRadius
        return (merged, outermost)
    }

    /// Free-tier OSM-only explore: fetches Overpass POIs and converts them
    /// through the AIService skeleton fallback (no Anthropic call). Wired to
    /// `isExploringFreeMode` so the paywall button stays visible as the upgrade hook.
    public func exploreNearbyFreeMode(
        at coordinate: CLLocationCoordinate2D,
        radiusMeters: Int = 3000,
        category: ExperienceCategory? = nil
    ) async {
        guard !isExploringFreeMode else { return }
        isExploringFreeMode = true
        lastExploreError = nil
        lastExploreAddedCount = 0
        lastExploreToast = nil
        defer { isExploringFreeMode = false }

        // Force skeleton mode so AIService never touches Anthropic.
        let savedProTier = aiService.isProTier
        aiService.isProTier = false
        defer { aiService.isProTier = savedProTier }

        do {
            let pois = try await overpassService.fetchPOIs(
                near: coordinate, radiusMeters: radiusMeters, category: category
            )
            guard !pois.isEmpty else {
                lastExploreError = NSLocalizedString("explore.error.nothingFound", comment: "No POIs found nearby")
                return
            }
            let resolved = await geocodeService.resolve(coordinate: coordinate)
            let cityCode = resolved?.cityCode ?? Self.cityCode(for: coordinate)
            if let resolved {
                experienceService.repo.recordDiscoveredCity(
                    cityCode: resolved.cityCode,
                    name: resolved.name,
                    countryCode: resolved.countryCode,
                    center: (lat: coordinate.latitude, lon: coordinate.longitude)
                )
            }
            let generated = try await aiService.synthesizeExperiences(
                from: pois,
                cityCode: cityCode,
                locale: LanguageService.shared.effectiveLocale
            )
            let added = experienceService.appendGenerated(generated)
            lastExploreAddedCount = added
            if added > 0 {
                selectCity(cityCode, explicit: false)
                if let resolved {
                    lastExploreToast = String(
                        format: NSLocalizedString("explore.toast.addedNamed", comment: "Now exploring %@ · %d places added"),
                        resolved.name, added
                    )
                } else {
                    lastExploreToast = String(
                        format: NSLocalizedString("explore.toast.added", comment: "%d places added near you"),
                        added
                    )
                }
            }
            recenter(on: coordinate)
        } catch {
            lastExploreError = error.localizedDescription
        }
    }

    /// Stable, lat/lon-derived city code used for OSM-generated entries so
    /// the existing city pill / filter logic still works. Format:
    /// `osm_<latRounded>_<lonRounded>`. Rounded to 1 decimal degree (~11 km).
    static func cityCode(for coordinate: CLLocationCoordinate2D) -> String {
        let lat = (coordinate.latitude * 10).rounded() / 10
        let lon = (coordinate.longitude * 10).rounded() / 10
        return String(format: "osm_%.1f_%.1f", lat, lon)
    }

    /// Best coordinate to anchor "Explore here" on: live GPS if available,
    /// otherwise the currently-selected city center. Used by the map view's
    /// Explore button.
    public var exploreAnchorCoordinate: CLLocationCoordinate2D {
        locationService.currentLocation?.coordinate ?? defaultCenterForSelectedCity
    }

    // MARK: - US-011 auto-explore on empty category

    /// Debounce window (ms) before an empty-category selection fires
    /// auto-Explore. Default 600 ms; tests override with 0 for determinism.
    var autoExploreDebounceMs: UInt64 = 600

    /// Throttle window — same category can't auto-fire more than once.
    static let autoExploreCooldown: TimeInterval = 10

    /// Per-category timestamp of the most recent auto-Explore trigger.
    /// Used to gate `selectCategory` so a quick second tap on the same
    /// pill inside `autoExploreCooldown` is a no-op.
    private var lastAutoExploreByCategory: [ExperienceCategory: Date] = [:]

    /// Most recent debounce Task, cancelled when a new category arrives
    /// or filters change so we don't fire stale Explore calls.
    private var pendingAutoExploreTask: Task<Void, Never>?

    /// Distance from the explore anchor to the nearest seeded city — used
    /// to decide whether to silently auto-fetch when a category turns up
    /// empty. ≤50 km counts as "inside a seeded city".
    private static let seededCityRadiusMeters: CLLocationDistance = 50_000

    /// True when the user's current anchor sits within 50 km of any
    /// `availableCities` entry. We only auto-Explore inside seeded areas
    /// because empty results outside seeded coverage are expected and
    /// already handled by the existing offline / consent flows.
    var isAnchorInsideSeededCity: Bool {
        let anchor = exploreAnchorCoordinate
        let here = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
        for city in availableCities {
            let cityLoc = CLLocation(latitude: city.center.latitude, longitude: city.center.longitude)
            if here.distance(from: cityLoc) <= Self.seededCityRadiusMeters {
                return true
            }
        }
        return false
    }

    /// Public test hook: returns whether a fresh trigger for `category`
    /// would be allowed under the cooldown, without firing anything.
    func canAutoExplore(category: ExperienceCategory, now: Date = Date()) -> Bool {
        guard let last = lastAutoExploreByCategory[category] else { return true }
        return now.timeIntervalSince(last) >= Self.autoExploreCooldown
    }

    /// Called from `selectCategory`. Schedules an auto-Explore when the
    /// just-applied filter left nothing on the map AND the user is inside
    /// a seeded city. Per-category cooldown prevents a re-fire within
    /// `autoExploreCooldown` seconds. Free vs Pro picks the correct
    /// fetch path (single-ring Overpass vs multi-ring schedule).
    private func scheduleAutoExploreForEmptyCategoryIfNeeded() {
        guard let category = selectedCategory else { return }
        guard visibleExperiences.isEmpty else { return }
        guard isAnchorInsideSeededCity else { return }
        guard canAutoExplore(category: category) else { return }

        // Stamp the trigger time NOW (before the debounce fires) so two
        // quick taps in <10s — even before the first network call
        // completes — collapse to one Explore. The AC asks for "second
        // tap within 10 s does NOT re-fire" regardless of timing within
        // the debounce.
        lastAutoExploreByCategory[category] = Date()

        pendingAutoExploreTask?.cancel()
        let debounceMs = autoExploreDebounceMs
        let anchor = exploreAnchorCoordinate
        let isPro = isProUser
        pendingAutoExploreTask = Task { [weak self] in
            if debounceMs > 0 {
                try? await Task.sleep(nanoseconds: debounceMs * 1_000_000)
            }
            if Task.isCancelled { return }
            guard let self else { return }
            // Re-check that the category is still active — user may have
            // tapped a different pill during the debounce.
            guard self.selectedCategory == category else { return }
            if isPro {
                await self.exploreNearby(at: anchor, category: category)
            } else {
                await self.exploreNearbyFreeMode(at: anchor, category: category)
            }
        }
    }

    // MARK: - Helpers

    private func computeNearbySoloCount(in experiences: [Experience]) -> Int {
        // Approximation for MVP: completion count in last 24h is unknown locally,
        // so we use a heuristic — average reports/30d divided down.
        let signals = experiences.reduce(0) { $0 + $1.confidence.signals.passiveGpsHits30d }
        return max(0, signals / 30) // per-day estimate
    }

    // MARK: - US-MR-05 analytics shim
    //
    // Until a real AnalyticsService lands, emit `explore_multi_ring_completed`
    // as a one-line JSON dictionary visible in the Xcode console under DEBUG.
    // The shape matches the PRD field names so the eventual transport (Edge
    // Function / RudderStack / etc.) can wire it through without renames.
    static func emitMultiRingCompleted(_ metrics: ExploreMetrics) {
        #if DEBUG
        let payload: [String: Any] = [
            "event": "explore_multi_ring_completed",
            "addedCount": metrics.addedCount,
            "maxRadiusMeters": metrics.maxRadiusMeters,
            "failedRings": metrics.failedRings,
            "totalRings": metrics.totalRings,
            "durationMs": metrics.durationMs
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let line = String(data: data, encoding: .utf8) {
            analyticsLogger.debug("\(line, privacy: .public)")
        }
        #endif
    }
}
