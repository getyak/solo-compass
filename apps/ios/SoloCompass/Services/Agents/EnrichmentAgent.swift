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

    /// How many enriched POIs survive ranking and reach synthesis. Keeps the
    /// AI call cheap and the result set curated rather than overwhelming.
    public static let defaultTopN = 6

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

    /// Authoritative base-POI collection with China-vs-overseas routing.
    ///
    /// Inside mainland China (`CoordinateConverter.isInsideChinaMainland`) the
    /// authoritative source is Amap, because OSM coverage there is ~9× thinner
    /// than reality. Amap is best-effort: a missing key or any failure falls
    /// back to Overpass so the China branch never crashes (ADR §3.3). Overseas
    /// (and on fallback) Overpass remains authoritative. MapKit is always
    /// folded in as a best-effort enrichment via the same coordinate-cell merge.
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

        if CoordinateConverter.isInsideChinaMainland(coordinate), let amap = amapService {
            // Amap is authoritative on the mainland; run it in parallel with
            // MapKit. Best-effort: any failure resolves to [] so we fall through
            // to Overpass without crashing (ADR §3.3).
            async let amapTask: [OverpassService.POI] = {
                do {
                    return try await amap.fetchPOIs(
                        near: coordinate, radiusMeters: radiusMeters, category: category
                    )
                } catch {
                    Self.logger.error("Amap fetch failed, falling back to Overpass: \(String(describing: error), privacy: .public)")
                    return []
                }
            }()
            let amapPois = await amapTask
            if !amapPois.isEmpty {
                let mapKitPois = await mapKitTask
                return FoursquareService.enrichMerge(base: amapPois, enrichment: mapKitPois)
            }
            // Empty Amap result (quota / no match / error): fall through to
            // Overpass. `mapKitTask` is still in flight and consumed below.
        }

        // Overseas, or China fallback: Overpass is authoritative.
        async let overpassTask = overpassService.fetchPOIs(
            near: coordinate, radiusMeters: radiusMeters, category: category
        )
        let overpassPois = try await overpassTask
        let mapKitPois = await mapKitTask
        return FoursquareService.enrichMerge(base: overpassPois, enrichment: mapKitPois)
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
        let enriched = await backfillAddresses(ranked)

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
