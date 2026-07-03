import Foundation
import CoreLocation
import os

/// Deep-dive enrichment orchestrator. Where the legacy `exploreNearby` pipeline
/// fetched a wide ring of shallow POIs and synthesized them in one pass, this
/// agent does the opposite: a SMALL radius, a SHORT list of high-signal places,
/// each cross-referenced across every available channel before synthesis.
///
/// Pipeline:
///   1. Collect POIs in a small radius from Overpass (OSM) + Apple MapKit,
///      concurrently. Merge by coordinate cell.
///   2. Fold Foursquare hard signals (rating/hours/price) INTO the matching
///      POIs via `FoursquareService.enrichMerge` — not a winner-takes-all merge.
///   3. Rank by signal richness and keep the top N. Fewer, deeper entries beat
///      a long list of skeletons.
///   4. Backfill a street-level address on any survivor that still lacks one,
///      using reverse geocoding, so howTo orientation steps can be concrete.
///   5. Hand the enriched, ranked POIs to `AIService.synthesizeExperiences`,
///      which now cites the real signals instead of writing generic filler.
///
/// Returns strongly-typed `[Experience]` rather than free-form text — it is
/// not part of any voice/chat agent protocol; it stands alone.
@MainActor
public final class EnrichmentAgent {
    private static let logger = Logger(subsystem: "com.solocompass", category: "EnrichmentAgent")

    /// Default search radius. Deliberately small — the whole point is depth
    /// over breadth. Callers can widen it for a sparse area.
    public static let defaultRadiusMeters = 800

    /// How many enriched POIs survive ranking and reach synthesis.
    ///
    /// Rubric fix: 6 was the old cap. In a dense Amap area (75 raw POIs in a
    /// 5 km Futian query) that discarded 92% of the coverage before the user
    /// ever saw anything — filter chip surfaced "All 6". 15 keeps the AI call
    /// still cheap (well under `AIService.synthesisLimit=60`) while giving
    /// the map cluster and the handoff summary "N places found" some room to
    /// breathe. The AI cost delta is trivial vs the UX gain.
    public static let defaultTopN = 15

    /// Progressive radius ladder in meters: start tight, expand when sparse.
    public static let progressiveRadii: [Int] = [5_000, 10_000, 25_000, 100_000]

    /// Minimum POI count considered "enough" at a given radius stage before
    /// moving to the next rung of the ladder.
    public static let enoughThreshold = 8

    /// Keeps POIs whose distance from `center` falls in `[beyond, within)` meters.
    /// Use `beyond = 0` for the innermost ring.
    public static func ringFilter(
        pois: [OverpassService.POI],
        center: CLLocationCoordinate2D,
        within: Double,
        beyond: Double = 0
    ) -> [OverpassService.POI] {
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return pois.filter { poi in
            let poiLocation = CLLocation(latitude: poi.lat, longitude: poi.lon)
            let distance = centerLocation.distance(from: poiLocation)
            return distance >= beyond && distance < within
        }
    }

    private let overpassService: OverpassService
    private let mapKitService: MapKitPOIService
    private let foursquareService: FoursquareService
    private let geocodeService: any ReverseGeocoding
    private let aiService: AIService
    /// Mainland-China POI source. Optional so existing tests / previews can
    /// construct without it; when nil (or its key is absent) the China branch
    /// transparently degrades to Overpass.
    private let amapService: AmapPOIService?

    public init(
        overpassService: OverpassService,
        mapKitService: MapKitPOIService,
        foursquareService: FoursquareService,
        geocodeService: any ReverseGeocoding,
        aiService: AIService,
        amapService: AmapPOIService? = nil
    ) {
        self.overpassService = overpassService
        self.mapKitService = mapKitService
        self.foursquareService = foursquareService
        self.geocodeService = geocodeService
        self.aiService = aiService
        self.amapService = amapService
    }

    /// Authoritative base-POI collection with China-vs-overseas routing, gated
    /// by the developer `DataSourceSettings.policy`.
    ///
    /// Under the default `.both` policy: inside mainland China
    /// (`CoordinateConverter.isInsideChinaMainland`) the authoritative source is
    /// Amap, because OSM coverage there is ~9× thinner than reality. Amap is
    /// best-effort: a missing key or any failure falls back to Overpass so the
    /// China branch never crashes (ADR §3.3). Overseas (and on fallback)
    /// Overpass remains authoritative.
    ///
    /// The tester can pin the pipeline to a single provider (`.amapOnly` /
    /// `.openMapOnly`); the disabled provider is then never queried and never
    /// used as a fallback. MapKit is always folded in as a best-effort
    /// enrichment via the same coordinate-cell merge, and is the final skeleton
    /// fallback so the map is never blank.
    ///
    /// Returns WGS84 POIs regardless of source — Amap's GCJ-02 conversion is
    /// confined to `AmapPOIService`, so callers downstream see only WGS84.
    private func basePOIs(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: Int,
        category: ExperienceCategory?
    ) async throws -> [OverpassService.POI] {
        // MapKit runs concurrently with the primary source (Amap or Overpass) in
        // every branch — serializing them would add the slower source's latency
        // to every explore call (a regression for the overseas majority).
        async let mapKitTask = mapKitPOIsBestEffort(
            near: coordinate, radiusMeters: radiusMeters, category: category
        )

        let policy = DataSourceSettings.policy
        let inCN = CoordinateConverter.isInsideChinaMainland(coordinate)
        let amapAvailable = policy.allowsAmap && amapService != nil
        let openMapAvailable = policy.allowsOpenMap
        Self.logger.info("🌐 inCN(\(coordinate.latitude, privacy: .public),\(coordinate.longitude, privacy: .public))=\(inCN, privacy: .public) policy=\(policy.rawValue, privacy: .public) amap=\(amapAvailable, privacy: .public) openMap=\(openMapAvailable, privacy: .public)")

        // Amap goes first inside China (authoritative there) OR whenever OpenMap
        // is disabled and Amap is the only base we're allowed to use.
        let amapFirst = amapAvailable && (inCN || !openMapAvailable)

        if amapFirst, let amap = amapService {
            let amapPois = await fetchAmapBase(
                amap: amap, coordinate: coordinate, radiusMeters: radiusMeters, category: category
            )
            if !amapPois.isEmpty {
                let mapKitPois = await mapKitTask
                return FoursquareService.enrichMerge(base: amapPois, enrichment: mapKitPois)
            }
            // Amap yielded nothing. Fall back to OpenMap only if the policy still
            // permits it — under `.amapOnly` we degrade straight to MapKit.
            if !openMapAvailable {
                return await mapKitTask
            }
            // else: fall through to the Overpass branch below.
        }

        // Overseas, China fallback, or `.openMapOnly`: Overpass is authoritative.
        // Best-effort: if Overpass throws (timeout / 429 / decode), drop to
        // MapKit-only results so the user still sees *something* on the map
        // instead of an empty error state.
        if openMapAvailable {
            let overpassPois = await fetchOverpassBase(
                coordinate: coordinate, radiusMeters: radiusMeters, category: category
            )
            let mapKitPois = await mapKitTask
            if overpassPois.isEmpty {
                // Overpass failed AND we want feedback: surface to Sentry so we
                // can monitor Overpass mirror health from the dashboard.
                SentryService.capture(
                    message: "overpass.fetch.empty",
                    level: .warning,
                    context: [
                        "lat": coordinate.latitude,
                        "lon": coordinate.longitude,
                        "radius_m": radiusMeters,
                        "category": category?.rawValue ?? "nil",
                        "mapkit_fallback_count": mapKitPois.count
                    ]
                )
                // MapKit alone is the skeleton — name + coords, no rich tags.
                return mapKitPois
            }
            return FoursquareService.enrichMerge(base: overpassPois, enrichment: mapKitPois)
        }

        // No configured base source produced anything usable (e.g. `.amapOnly`
        // with an empty Amap result). MapKit skeletons keep the map populated.
        return await mapKitTask
    }

    /// Best-effort Amap base fetch: returns its WGS84 POIs, or `[]` on failure /
    /// empty. Emits the same observability breadcrumbs (`amap.fetch.failed` /
    /// `amap.fetch.empty`) the inline routing used to, from EnrichmentAgent's
    /// @MainActor so `SentryService` is reachable.
    private func fetchAmapBase(
        amap: AmapPOIService,
        coordinate: CLLocationCoordinate2D,
        radiusMeters: Int,
        category: ExperienceCategory?
    ) async -> [OverpassService.POI] {
        let outcome: (pois: [OverpassService.POI], error: String?)
        do {
            let pois = try await amap.fetchPOIs(
                near: coordinate, radiusMeters: radiusMeters, category: category
            )
            outcome = (pois, nil)
        } catch {
            Self.logger.error("Amap fetch failed, falling back per policy: \(String(describing: error), privacy: .public)")
            outcome = ([], String(describing: error))
        }

        if let errMsg = outcome.error {
            SentryService.capture(
                message: "amap.fetch.failed",
                level: .warning,
                context: [
                    "lat": coordinate.latitude,
                    "lon": coordinate.longitude,
                    "radius_m": radiusMeters,
                    "category": category?.rawValue ?? "nil",
                    "error": errMsg
                ]
            )
        }

        if !outcome.pois.isEmpty {
            // Transient enrichment channel (ADR §3.2 compliant): the count here
            // is the surface area available to a future AIService prompt.
            let enrichedCount = outcome.pois.filter { amap.transientEnrichments[$0.osmId] != nil }.count
            Self.logger.info("✅ amap returned \(outcome.pois.count, privacy: .public) POIs (\(enrichedCount, privacy: .public) with transient rating/hours/tel/addr), using as base")
            return outcome.pois
        }

        Self.logger.warning("⚠️ amap returned 0 POIs at (\(coordinate.latitude, privacy: .public),\(coordinate.longitude, privacy: .public)) r=\(radiusMeters, privacy: .public)m. Check AmapPOIService logs for infocode.")
        if outcome.error == nil {
            // Only emit "empty" if we didn't already emit "failed" above.
            SentryService.capture(
                message: "amap.fetch.empty",
                level: .info,
                context: [
                    "lat": coordinate.latitude,
                    "lon": coordinate.longitude,
                    "radius_m": radiusMeters,
                    "category": category?.rawValue ?? "nil"
                ]
            )
        }
        return []
    }

    /// Best-effort Overpass base fetch: returns its POIs, or `[]` on any failure
    /// so the caller can degrade to MapKit skeletons.
    private func fetchOverpassBase(
        coordinate: CLLocationCoordinate2D,
        radiusMeters: Int,
        category: ExperienceCategory?
    ) async -> [OverpassService.POI] {
        do {
            return try await overpassService.fetchPOIs(
                near: coordinate, radiusMeters: radiusMeters, category: category
            )
        } catch {
            Self.logger.error("Overpass fetch failed, falling back to MapKit-only: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// Run the deep-dive enrichment for a coordinate. Returns synthesized
    /// Experiences (already enriched with real signals where available).
    /// Throws only on a hard Overpass failure; MapKit / Foursquare / geocoding
    /// are best-effort and degrade silently to whatever signal we did get.
    public func enrich(
        at coordinate: CLLocationCoordinate2D,
        radiusMeters: Int = EnrichmentAgent.defaultRadiusMeters,
        category: ExperienceCategory? = nil,
        cityCode: String,
        locale: Locale = .current,
        topN: Int = EnrichmentAgent.defaultTopN
    ) async throws -> [Experience] {
        // 1. Base collection, routed by region: Amap inside mainland China
        //    (authoritative there), Overpass overseas / on fallback. MapKit is
        //    folded in best-effort. Returns WGS84 regardless of source.
        var pois = try await basePOIs(
            near: coordinate, radiusMeters: radiusMeters, category: category
        )
        guard !pois.isEmpty else { return [] }

        // 2. Fold Foursquare hard signals into the matching base POIs. One
        //    region call (with fields) covers the whole small radius. Skipped
        //    when no key is configured.
        if !Secrets.resolvedFoursquareKey.isEmpty {
            do {
                let fsq = try await foursquareService.fetchPOIs(
                    near: coordinate, radiusMeters: radiusMeters, category: category
                )
                pois = FoursquareService.enrichMerge(base: pois, enrichment: fsq)
            } catch {
                Self.logger.error("Foursquare enrichment failed: \(String(describing: error), privacy: .public)")
            }
        }

        // 3. Rank by signal richness, keep the deepest N.
        let ranked = Array(
            pois.sorted { Self.signalScore($0) > Self.signalScore($1) }.prefix(topN)
        )

        // 4. Backfill a street-level address on survivors missing one.
        var enriched = await backfillAddresses(ranked)

        // 4b. Rubric fix: fold the ephemeral Amap enrichment channel
        //     (rating / opentimeToday / phone / address per ADR §3.2) into
        //     each POI's tags map — read-once-and-discard via
        //     `consumeEnrichments`. Without this, `AmapPOIService` populated
        //     `transientEnrichments` for 75/75 POIs but nothing ever fed it
        //     to the AI prompt, so `synthesizeExperiences` saw generic
        //     tag-less inputs and defaulted to "9–21 · Solo ~7 · no signals"
        //     for every Amap card. Map to the tag keys AIService already
        //     reads at line 1656–1661 so the change is transparent to it.
        if let amap = amapService {
            let ids = enriched.map(\.osmId)
            let bag = amap.consumeEnrichments(for: ids)
            if !bag.isEmpty {
                enriched = enriched.map { poi in
                    guard let e = bag[poi.osmId] else { return poi }
                    var tags = poi.tags
                    if let r = e.rating,
                       tags["fsq_rating"] == nil { tags["fsq_rating"] = r }
                    if let h = e.opentimeToday,
                       tags["opening_hours"] == nil { tags["opening_hours"] = h }
                    if let p = e.phone,
                       tags["phone"] == nil { tags["phone"] = p }
                    if let a = e.address,
                       tags["addr"] == nil { tags["addr"] = a }
                    return OverpassService.POI(
                        osmId: poi.osmId, name: poi.name, nameEn: poi.nameEn,
                        lat: poi.lat, lon: poi.lon, tags: tags
                    )
                }
                let consumed = bag.count
                Self.logger.info("🔗 fed \(consumed, privacy: .public) transient amap enrichments into synthesis")
            }
        }

        // 5. Synthesize. The (already-relaxed) prompt cites the real signals.
        return try await aiService.synthesizeExperiences(
            from: enriched, cityCode: cityCode, locale: locale
        )
    }

    // MARK: - Single-entry Re-compile

    /// Deep-dive re-compile for ONE existing experience. Runs the same
    /// cross-source enrichment as `enrich`, but in a tight radius around the
    /// experience's own coordinate, then returns the synthesized result that
    /// best matches it — re-keyed onto the original experience's identity via
    /// `adoptingContent`, so favorites/completions survive (US: single-card
    /// deep cross-compile).
    ///
    /// Returns `nil` when the experience has no coordinate, when enrichment
    /// yields nothing, or on a hard failure — callers leave the card unchanged.
    /// Best-effort: never throws.
    public func recompile(
        experience: Experience,
        radiusMeters: Int = EnrichmentAgent.recompileRadiusMeters,
        locale: Locale = .current
    ) async -> Experience? {
        guard let coordinate = experience.coordinate else { return nil }

        let candidates: [Experience]
        do {
            candidates = try await enrich(
                at: coordinate,
                radiusMeters: radiusMeters,
                category: experience.category,
                cityCode: experience.location.cityCode,
                locale: locale,
                topN: EnrichmentAgent.recompileTopN
            )
        } catch {
            Self.logger.error("Re-compile failed for \(experience.id, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }

        // Pick the candidate physically closest to the original place. The
        // tight radius keeps these tightly clustered, but a place can resolve
        // to several nearby POIs (e.g. a cafe inside a mall), so distance is
        // the most reliable match signal we have without a stable external id.
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let best = candidates
            .compactMap { candidate -> (Experience, Double)? in
                guard let c = candidate.coordinate else { return nil }
                let d = origin.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
                return (candidate, d)
            }
            .min { $0.1 < $1.1 }?
            .0

        guard let enrichedMatch = best else { return nil }

        // Only return an upgrade if it actually went through AI synthesis with
        // real cross-source signals. A skeleton fallback is not an upgrade.
        guard enrichedMatch.isAIEnriched else { return nil }

        return experience.adoptingContent(of: enrichedMatch)
    }

    /// Tight radius for single-entry re-compile. Smaller than `enrich`'s
    /// default because we already know exactly where the place is.
    public static let recompileRadiusMeters = 400

    /// Keep a few candidates so the closest-match picker has options, but stay
    /// cheap — one re-compile is one AI synthesis call.
    public static let recompileTopN = 4

    // MARK: - Progressive Explore

    /// Loops over `progressiveRadii`, collecting only the new ring at each stage,
    /// dedupes across stages, and stops once `enoughThreshold` results accumulate.
    /// Each batch of synthesized Experiences is delivered via `onBatch` before the
    /// next ring is attempted, so callers can drop pins incrementally.
    ///
    /// Never throws: MapKit/Foursquare failures degrade silently per-stage;
    /// Overpass failures skip the stage rather than aborting the loop.
    /// Returns the full accumulated `[Experience]` when done.
    public func exploreProgressively(
        at coordinate: CLLocationCoordinate2D,
        categories: [ExperienceCategory] = [],
        cityCode: String,
        locale: Locale = .current,
        onProgress: @MainActor @Sendable (MapViewModel.ExploreProgress) async -> Void = { _ in },
        onBatch: @MainActor @Sendable ([Experience]) async -> Void = { _ in }
    ) async -> [Experience] {
        var accumulated: [Experience] = []
        // Coordinate-cell key: round lat/lon to 4 decimal places (~11 m precision).
        var seenCells: Set<String> = []
        var seenOsmIds: Set<Int64> = []
        // Total novel POIs collected so far across stages (used for short-circuit).
        var novelPoiCount = 0

        var prevRadius = 0

        for radius in Self.progressiveRadii {
            // Short-circuit: already enough novel POIs from inner rings.
            if novelPoiCount >= Self.enoughThreshold { break }

            let radiusKm = radius / 1_000
            // Emit expanding state when advancing beyond the first ring.
            if prevRadius > 0 {
                await onProgress(.expanding(toRadiusKm: radiusKm))
            }
            // Emit scanning state at the start of each stage.
            await onProgress(.scanning(radiusKm: radiusKm))

            // Fetch the full disk at this radius; then keep only the new annulus.
            // `basePOIs` routes Amap (mainland China) vs Overpass (overseas).
            let category = categories.first  // single category per source call
            let allPois: [OverpassService.POI]
            do {
                allPois = try await basePOIs(
                    near: coordinate, radiusMeters: radius, category: category
                )
            } catch {
                Self.logger.error("Stage \(radius, privacy: .public)m base fetch failed: \(String(describing: error), privacy: .public)")
                prevRadius = radius
                continue
            }

            // Keep only the new ring introduced by this radius step.
            let stageInner = Double(prevRadius)
            let ringPois = Self.ringFilter(
                pois: allPois,
                center: coordinate,
                within: Double(radius),
                beyond: stageInner
            )
            prevRadius = radius

            guard !ringPois.isEmpty else { continue }

            // Optional Foursquare enrichment of ring POIs.
            var stagePois = ringPois
            if !Secrets.resolvedFoursquareKey.isEmpty {
                do {
                    let fsq = try await foursquareService.fetchPOIs(
                        near: coordinate, radiusMeters: radius, category: category
                    )
                    let ringFsq = Self.ringFilter(
                        pois: fsq,
                        center: coordinate,
                        within: Double(radius),
                        beyond: stageInner
                    )
                    stagePois = FoursquareService.enrichMerge(base: stagePois, enrichment: ringFsq)
                } catch {
                    Self.logger.error("Stage \(radius, privacy: .public)m Foursquare enrichment failed: \(String(describing: error), privacy: .public)")
                }
            }

            // Dedupe: skip any POI whose osmId or coord cell we've already seen.
            let novel = stagePois.filter { poi in
                let cell = coordCell(lat: poi.lat, lon: poi.lon)
                guard !seenOsmIds.contains(poi.osmId) && !seenCells.contains(cell) else {
                    return false
                }
                return true
            }
            for poi in novel {
                seenOsmIds.insert(poi.osmId)
                seenCells.insert(coordCell(lat: poi.lat, lon: poi.lon))
            }
            novelPoiCount += novel.count

            guard !novel.isEmpty else { continue }

            // Rank and synthesize only the novel POIs for this ring.
            let ranked = Array(
                novel.sorted { Self.signalScore($0) > Self.signalScore($1) }.prefix(Self.defaultTopN)
            )
            let enriched = await backfillAddresses(ranked)

            let batch: [Experience]
            do {
                batch = try await aiService.synthesizeExperiences(
                    from: enriched, cityCode: cityCode, locale: locale
                )
            } catch {
                Self.logger.error("Stage \(radius, privacy: .public)m synthesis failed: \(String(describing: error), privacy: .public)")
                continue
            }

            accumulated.append(contentsOf: batch)
            await onBatch(batch)
        }

        return accumulated
    }

    /// Rounds lat/lon to 4 decimal places to form a deduplication cell key.
    private func coordCell(lat: Double, lon: Double) -> String {
        let roundedLat = (lat * 10_000).rounded() / 10_000
        let roundedLon = (lon * 10_000).rounded() / 10_000
        return "\(roundedLat),\(roundedLon)"
    }

    // MARK: - Helpers

    private func mapKitPOIsBestEffort(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: Int,
        category: ExperienceCategory?
    ) async -> [OverpassService.POI] {
        do {
            return try await mapKitService.fetchPOIs(
                near: coordinate, radiusMeters: radiusMeters, category: category
            )
        } catch {
            Self.logger.error("MapKit fetch failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// Reverse-geocode each POI that still lacks an `addr` tag. Best-effort and
    /// rate-limited by the OS; failures leave the POI without an address rather
    /// than blocking the whole run.
    private func backfillAddresses(_ pois: [OverpassService.POI]) async -> [OverpassService.POI] {
        var result: [OverpassService.POI] = []
        for poi in pois {
            guard poi.tags["addr"] == nil else {
                result.append(poi)
                continue
            }
            let coord = CLLocationCoordinate2D(latitude: poi.lat, longitude: poi.lon)
            if let resolved = await geocodeService.resolve(coordinate: coord) {
                var tags = poi.tags
                tags["addr"] = resolved.name
                result.append(OverpassService.POI(
                    osmId: poi.osmId, name: poi.name, nameEn: poi.nameEn,
                    lat: poi.lat, lon: poi.lon, tags: tags
                ))
            } else {
                result.append(poi)
            }
        }
        return result
    }

    /// Heuristic richness score: each real hard signal is worth more than a
    /// raw OSM tag, so signal-bearing POIs float to the top of the ranking.
    static func signalScore(_ poi: OverpassService.POI) -> Int {
        var score = 0
        if poi.tags["fsq_rating"] != nil { score += 4 }
        if poi.tags["opening_hours"] != nil { score += 3 }
        if poi.tags["fsq_price"] != nil { score += 2 }
        if poi.tags["fsq_popularity"] != nil { score += 2 }
        if poi.tags["website"] != nil { score += 1 }
        if poi.tags["phone"] != nil { score += 1 }
        if poi.tags["addr"] != nil { score += 1 }
        // A named place with a real category is inherently more useful than a
        // bare node, so reward those too (smaller weight than hard signals).
        if poi.tags["amenity"] != nil || poi.tags["tourism"] != nil || poi.tags["leisure"] != nil {
            score += 1
        }
        return score
    }
}
