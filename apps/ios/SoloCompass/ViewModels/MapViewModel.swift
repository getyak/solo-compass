import Foundation
import CoreLocation
import MapKit
import Observation
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

    // MARK: - Dependencies
    private let locationService: LocationService
    private let experienceService: ExperienceService
    private let aiService: AIService
    private let overpassService: OverpassService
    private let foursquareService: FoursquareService
    private let geocodeService: any ReverseGeocoding
    private let preferences: UserPreferences

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
        aiService: aiService
    )
    /// Optional so existing tests / previews can construct without a
    /// real StoreKit-aware service. Production wires this from the
    /// environment in `CompassMapView` (Epic D US-024).
    private weak var subscriptionService: SubscriptionService?

    /// Wire the subscription service after init (called from
    /// CompassMapView.onAppear). Free tier gating only applies after
    /// this is set; pre-attach treats every caller as Pro to keep the
    /// existing test surface working.
    public func attachSubscriptionService(_ service: SubscriptionService) {
        self.subscriptionService = service
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

    // MARK: - Auto-recenter

    /// Set to true after the first successful auto-recenter so we don't fight
    /// subsequent user pan/zoom gestures.
    private var hasAutoCentered = false

    /// Recenter the camera to the user's current location ONCE, on the first
    /// non-nil GPS fix. Subsequent calls are no-ops so the user's manual
    /// pan/zoom is preserved.
    public func bindToLocation() {
        guard !hasAutoCentered,
              let coordinate = locationService.currentLocation?.coordinate else { return }
        hasAutoCentered = true
        recenter(on: coordinate)
        autoExploreIfEmpty(at: coordinate)
    }

    /// Auto-trigger Explore when the user lands in a data-sparse area
    /// (e.g. Vientiane with zero seed data). Fires once after the first
    /// GPS fix. Skips when there's already ≥3 experiences within 5 km,
    /// or when a recent (<7 day) offline region cache covers the spot.
    /// `exploreNearby` handles the paywall + consent gates internally.
    private func autoExploreIfEmpty(at coordinate: CLLocationCoordinate2D) {
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
            syncCameraToSelectedCity()
        }
    }

    /// Move `cameraPosition` to the selected city's center. Custom-pin
    /// selections keep their existing camera (set in `selectCustomLocation`).
    private func syncCameraToSelectedCity() {
        if selectedCity?.hasPrefix("custom_") == true { return }
        cameraPosition = .region(MKCoordinateRegion(
            center: defaultCenterForSelectedCity,
            span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
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
        customCoordinates = coordinate
        customLocationLabel = label
        selectedCity = cityCode
        preferences.lastSelectedCity = nil  // don't persist custom pins across restarts
        cameraPosition = .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
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
        let nameMap = cityNameMap
        var byCode: [String: (code: String, name: String, center: CLLocationCoordinate2D)] = [:] // swiftlint:disable:this large_tuple
        // Seed-derived rows first.
        for (code, coords) in cityExperiences where !coords.isEmpty {
            let avgLat = coords.map(\.latitude).reduce(0, +) / Double(coords.count)
            let avgLon = coords.map(\.longitude).reduce(0, +) / Double(coords.count)
            let name = nameMap[code] ?? code
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

        return Array(byCode.values).sorted { $0.name < $1.name }
    }

    /// Static seed-city names. Discovered-city names come from
    /// `DiscoveredCityRecord` via `availableCities`.
    private let cityNameMap: [String: String] = [
        "cmi": "Chiang Mai",
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
    ]

    /// Center coordinate for the selected city, or the default if none selected.
    /// Resolution order: live `availableCities` (seed + discovered) → the static
    /// `knownCityCenters` slug catalog → the global default (Chiang Mai).
    public var defaultCenterForSelectedCity: CLLocationCoordinate2D {
        guard let code = selectedCity else { return Self.defaultCenter }
        if let city = availableCities.first(where: { $0.code == code }) {
            return city.center
        }
        if let known = Self.knownCityCenters[code] {
            return known
        }
        return Self.defaultCenter
    }

    /// Selects a preset city, recenters the map, and reloads experiences.
    /// Clears any active custom-coordinate pin.
    public func selectCity(_ cityCode: String?) {
        customCoordinates = nil
        customLocationLabel = nil
        selectedCity = cityCode
        preferences.lastSelectedCity = cityCode
        let center = defaultCenterForSelectedCity
        cameraPosition = .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
        ))
        loadNearbyExperiences()
        updateBottomInfo()
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
        _nowCount = visibleExperiences.filter { $0.isBestNow() }.count
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
    public var isShowingDetail: Bool = false
    public var bottomInfoText: String = ""
    public var nearbySoloCount: Int = 0
    public var aiExplanation: String?
    public var lastAIError: String?

    // True when a "Now" filter is active (best-now experiences only).
    public var isNowFilter: Bool = false

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

    public func confirmCheckIn() {
        guard let pending = pendingCheckIn else { return }
        preferences.markCompleted(pending.id)
        preferences.clearPendingCheckIn(pending.id)
        pendingCheckIn = nil
        checkForPendingCheckIns()
    }

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
    /// Candidate experiences added via long-press → voice → AI. Rendered with
    /// `.hidden` category and a distinct (dashed) marker.
    public var candidateExperiences: [Experience] = []

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
        self.selectedCity = preferences.lastSelectedCity
        let initialCenter: CLLocationCoordinate2D
        if let savedCity = preferences.lastSelectedCity {
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
            } else {
                initialCenter = Self.defaultCenter
            }
        } else {
            initialCenter = Self.defaultCenter
        }
        self._cameraPosition = .region(MKCoordinateRegion(
            center: initialCenter,
            span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
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

    public func loadNearbyExperiences() {
        // US-017: the experience set (and thus discovered cities) may have
        // changed since the last load — e.g. after an Explore added pins.
        // Drop the city cache so the next `availableCities` read recomputes.
        invalidateCityCache()
        let center = customCoordinates
            ?? locationService.currentLocation?.coordinate
            ?? defaultCenterForSelectedCity
        let radiusKm = max(1.0, preferences.maxDistanceKm)
        let nearby = applyFilters(near: center, radiusKm: radiusKm)
        withAnimation(Self.markerSetAnimation) {
            visibleExperiences = nearby
            nearbySoloCount = computeNearbySoloCount(in: nearby)
        }
        aiSmartPickIds = []
        recomputeNowCount()
        updateBottomInfo()
    }

    private func applyFilters(near coordinate: CLLocationCoordinate2D, radiusKm: Double) -> [Experience] {
        var nearby = experienceService.getExperiences(near: coordinate, radiusKm: radiusKm)
        // Custom locations have no matching cityCode — show all nearby experiences instead.
        if let cityCode = selectedCity, !cityCode.hasPrefix("custom_") {
            nearby = nearby.filter { $0.location.cityCode == cityCode }
        }
        if let category = selectedCategory {
            nearby = nearby.filter { $0.category == category }
        }
        if let tag = selectedCustomTag {
            nearby = nearby.filter { ($0.userTags ?? []).contains(tag) }
        }
        if isNowFilter {
            nearby = nearby.filter { $0.isBestNow() }
        }
        if !preferences.dislikedCategories.isEmpty {
            let disliked = Set(preferences.dislikedCategories)
            nearby = nearby.filter { !disliked.contains($0.category) }
        }
        return nearby
    }

    public func selectCategory(_ category: ExperienceCategory?) {
        selectedCategory = category
        selectedCustomTag = nil
        isNowFilter = false
        loadNearbyExperiences()
        updateBottomInfo()
        // US-011: empty category inside a seeded city → debounced auto-Explore.
        scheduleAutoExploreForEmptyCategoryIfNeeded()
    }

    public func selectNowFilter() {
        isNowFilter = true
        selectedCategory = nil
        selectedCustomTag = nil
        loadNearbyExperiences()
        updateBottomInfo()
    }

    public func clearFilters() {
        selectedCategory = nil
        selectedCustomTag = nil
        isNowFilter = false
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
        }
        loadNearbyExperiences()
        updateBottomInfo()
    }

    public func selectExperience(_ experience: Experience) {
        selectedExperience = experience
        // isShowingDetail stays false — card shows first, detail sheet on expand
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

    public func dismissDetail() {
        isShowingDetail = false
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
                span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
            ))
        }
        loadNearbyExperiences()
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
    public var nextBestExperience: (experience: Experience, minutesUntil: Int)? {
        let now = Date()
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

    // MARK: - Bottom info bar

    public func updateBottomInfo() {
        // US-018: refresh the cached now-count here too — `isBestNow()` is
        // time-dependent, so a fresh count is needed whenever the bottom info
        // is recomputed. This is the single recompute checkpoint for this path.
        recomputeNowCount()
        let hour = Calendar.current.component(.hour, from: Date())
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

    public func cancelAddExperience() {
        pendingAddCoordinate = nil
        isRecordingNewExperience = false
    }

    public func confirmAddExperience() {
        guard pendingAddCoordinate != nil else { return }
        isRecordingNewExperience = true
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
            candidateExperiences.append(candidate)
            aiExplanation = response.explanation
            lastAIError = nil
        } catch {
            lastAIError = error.localizedDescription
        }
    }

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
        guard !isExploring else { return }
        // Track center so expandOneStage can reuse it (US-021).
        lastExploreCenter = coordinate

        // US-024: free-tier gate. Park the original action so the
        // paywall's onUnlocked can resume it after purchase, then bail.
        if !isProUser {
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
            onExploreConsentAccepted = { [weak self] in
                Task { await self?.exploreNearby(at: coordinate, radiusMeters: radiusMeters, category: category) }
            }
            isShowingExploreConsent = true
            return
        }

        isExploring = true
        lastExploreError = nil
        lastExploreAddedCount = 0
        lastQuotaInfo = nil
        lastExploreToast = nil
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
                        #if DEBUG
                        print("[MapViewModel] Foursquare fallback failed: \(error)")
                        #endif
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
                selectCity(cityCode)
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
            }

            recenter(on: coordinate)
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
        }
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
                selectCity(cityCode)
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
            print("[Analytics] \(line)")
        }
        #endif
    }
}
