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
    private let geocodeService: any ReverseGeocoding
    private let preferences: UserPreferences
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
    }

    // MARK: - City selection

    /// Currently selected city code (e.g. "cmi"), nil = all cities.
    public var selectedCity: String?

    /// All cities the user can pick from: seed-derived ones (centroid of
    /// matching experiences) plus reverse-geocoded discoveries from
    /// previous Explore sessions (Epic C US-016/017). Discovered cities
    /// override seed-derived names when the codes match.
    public var availableCities: [(code: String, name: String, center: CLLocationCoordinate2D)] { // swiftlint:disable:this large_tuple
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

    /// Center coordinate for the selected city, or the default if none selected.
    public var defaultCenterForSelectedCity: CLLocationCoordinate2D {
        guard let code = selectedCity,
              let city = availableCities.first(where: { $0.code == code }) else {
            return Self.defaultCenter
        }
        return city.center
    }

    /// Selects a city, recenters the map, and reloads experiences.
    public func selectCity(_ cityCode: String?) {
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
    public var visibleExperiences: [Experience] = []
    public var selectedExperience: Experience?
    public var isShowingDetail: Bool = false
    public var bottomInfoText: String = ""
    public var nearbySoloCount: Int = 0
    public var aiExplanation: String?
    public var lastAIError: String?

    // True when a "Now" filter is active (best-now experiences only).
    public var isNowFilter: Bool = false

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
        geocodeService: any ReverseGeocoding = ReverseGeocodeService()
    ) {
        self.locationService = locationService
        self.experienceService = experienceService
        self.aiService = aiService
        self.overpassService = overpassService
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
        loadNearbyExperiences()
        updateBottomInfo()
    }

    // MARK: - Loading

    public func loadNearbyExperiences() {
        let center = locationService.currentLocation?.coordinate ?? defaultCenterForSelectedCity
        let radiusKm = max(1.0, preferences.maxDistanceKm)
        var nearby = experienceService.getExperiences(near: center, radiusKm: radiusKm)

        if let cityCode = selectedCity {
            nearby = nearby.filter { $0.location.cityCode == cityCode }
        }

        if let category = selectedCategory {
            nearby = nearby.filter { $0.category == category }
        }
        if isNowFilter {
            nearby = nearby.filter { $0.isBestNow() }
        }
        if !preferences.dislikedCategories.isEmpty {
            let disliked = Set(preferences.dislikedCategories)
            nearby = nearby.filter { !disliked.contains($0.category) }
        }
        visibleExperiences = nearby
        nearbySoloCount = computeNearbySoloCount(in: nearby)
    }

    public func selectCategory(_ category: ExperienceCategory?) {
        selectedCategory = category
        isNowFilter = false
        loadNearbyExperiences()
        updateBottomInfo()
    }

    public func selectNowFilter() {
        isNowFilter = true
        selectedCategory = nil
        loadNearbyExperiences()
        updateBottomInfo()
    }

    public func clearFilters() {
        selectedCategory = nil
        isNowFilter = false
        loadNearbyExperiences()
        updateBottomInfo()
    }

    public func selectExperience(_ experience: Experience) {
        selectedExperience = experience
        // isShowingDetail stays false — card shows first, detail sheet on expand
    }

    public func dismissDetail() {
        isShowingDetail = false
    }

    /// Recenter the camera and refresh experiences for the given coordinate.
    /// Use this for explicit recentering (e.g. "locate me" button), NOT for
    /// reacting to user pan/zoom — that would create a feedback loop where
    /// every gesture resets the zoom level.
    public func recenter(on coordinate: CLLocationCoordinate2D) {
        cameraPosition = .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
        ))
        loadNearbyExperiences()
        updateBottomInfo()
    }

    /// Refresh visible experiences when the user pans/zooms the map. Does NOT
    /// touch `cameraPosition`, to avoid fighting the user's gesture.
    public func refreshForLocation(_ coordinate: CLLocationCoordinate2D) {
        let radiusKm = max(1.0, preferences.maxDistanceKm)
        var nearby = experienceService.getExperiences(near: coordinate, radiusKm: radiusKm)

        if let cityCode = selectedCity {
            nearby = nearby.filter { $0.location.cityCode == cityCode }
        }

        if let category = selectedCategory {
            nearby = nearby.filter { $0.category == category }
        }
        if isNowFilter {
            nearby = nearby.filter { $0.isBestNow() }
        }
        if !preferences.dislikedCategories.isEmpty {
            let disliked = Set(preferences.dislikedCategories)
            nearby = nearby.filter { !disliked.contains($0.category) }
        }
        visibleExperiences = nearby
        nearbySoloCount = computeNearbySoloCount(in: nearby)
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

    // MARK: - Bottom info bar

    public func updateBottomInfo() {
        let hour = Calendar.current.component(.hour, from: Date())
        let count = visibleExperiences.count

        switch hour {
        case 6..<12:
            let coffeeCount = visibleExperiences.filter { $0.category == .coffee && $0.isBestNow() }.count
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
            let openLate = visibleExperiences.filter { $0.isBestNow() }.count
            bottomInfoText = String(
                format: NSLocalizedString("info.night", comment: "Night info"),
                openLate
            )
        }
    }

    // MARK: - AI

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
        do {
            let response = try await aiService.processVoiceIntent(transcript: transcript, near: coordinate)
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
        } catch {
            // Keep current state on error; record for UI to optionally surface.
            lastAIError = error.localizedDescription
        }
    }

    /// Number of experiences in a given city (for the city picker row subtitle).
    public func experienceCount(for cityCode: String) -> Int {
        experienceService.allExperiences.filter { $0.location.cityCode == cityCode }.count
    }

    // MARK: - Explore Here

    /// Pull real OSM POIs near `coordinate`, hand them to AIService for
    /// solo-traveler enrichment, append the generated Experiences to the
    /// store, and refresh the visible set. No-op if already exploring.
    /// `cityCode` defaults to a stable hash of the coordinate so generated
    /// experiences group together in city pills.
    public func exploreNearby(
        at coordinate: CLLocationCoordinate2D,
        radiusMeters: Int = 3000
    ) async {
        guard !isExploring else { return }

        // US-024: free-tier gate. Park the original action so the
        // paywall's onUnlocked can resume it after purchase, then bail.
        if !isProUser {
            onPaywallUnlocked = { [weak self] in
                Task { await self?.exploreNearby(at: coordinate, radiusMeters: radiusMeters) }
            }
            isShowingPaywall = true
            return
        }

        // US-034: surface the first-run data-use disclosure before the
        // first OSM + Anthropic call. Same park-and-resume pattern as
        // the paywall.
        if !preferences.hasAcceptedExploreConsent {
            onExploreConsentAccepted = { [weak self] in
                Task { await self?.exploreNearby(at: coordinate, radiusMeters: radiusMeters) }
            }
            isShowingExploreConsent = true
            return
        }

        isExploring = true
        lastExploreError = nil
        lastExploreAddedCount = 0
        lastQuotaInfo = nil
        lastExploreToast = nil
        defer { isExploring = false }

        // Propagate current subscription tier so AIService applies
        // the right daily cap (Pro: 30/60, Free: 0/0).
        aiService.isProTier = isProUser

        do {
            let pois = try await overpassService.fetchPOIs(near: coordinate, radiusMeters: radiusMeters)
            guard !pois.isEmpty else {
                lastExploreError = NSLocalizedString("explore.error.nothingFound", comment: "No POIs found nearby")
                return
            }

            // US-016: try a real city name first; fall back to the
            // synthetic osm_<lat>_<lon> only when the geocoder fails.
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

            let generated = try await aiService.synthesizeExperiences(
                from: pois,
                cityCode: cityCode,
                locale: .current
            )
            let added = experienceService.appendGenerated(generated)
            lastExploreAddedCount = added

            // US-022: record a successful region so offline fallback can reuse it.
            experienceService.repo.recordRecentExploreRegion(
                centerLat: coordinate.latitude,
                centerLon: coordinate.longitude,
                radiusMeters: radiusMeters
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
            // US-022: on network failure, look for a recent nearby region and
            // surface its cached SwiftData pins instead of showing an error.
            if let region = experienceService.repo.closestRecentRegion(to: coordinate) {
                let offline = experienceService.repo.experiences(in: region)
                if !offline.isEmpty {
                    visibleExperiences = offline
                    nearbySoloCount = 0
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

    /// Free-tier OSM-only explore: fetches Overpass POIs and converts them
    /// through the AIService skeleton fallback (no Anthropic call). Wired to
    /// `isExploringFreeMode` so the paywall button stays visible as the upgrade hook.
    public func exploreNearbyFreeMode(
        at coordinate: CLLocationCoordinate2D,
        radiusMeters: Int = 3000
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
            let pois = try await overpassService.fetchPOIs(near: coordinate, radiusMeters: radiusMeters)
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
                locale: .current
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

    // MARK: - Helpers

    private func computeNearbySoloCount(in experiences: [Experience]) -> Int {
        // Approximation for MVP: completion count in last 24h is unknown locally,
        // so we use a heuristic — average reports/30d divided down.
        let signals = experiences.reduce(0) { $0 + $1.confidence.signals.passiveGpsHits30d }
        return max(0, signals / 30) // per-day estimate
    }
}
