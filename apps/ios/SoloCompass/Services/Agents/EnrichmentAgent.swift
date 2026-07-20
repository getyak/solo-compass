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

    /// Progress callback fired at each stage of the enrichment loop so a UI can
    /// render a live feed instead of an opaque spinner. Always invoked on the
    /// main actor. Optional — passing `nil` (the default) keeps the silent path
    /// for background auto-upgrades and tests.
    public typealias ProgressHandler = @MainActor (
        CompileProgressEvent.Stage,
        CompileProgressEvent.Status,
        String
    ) -> Void

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
        topN: Int = EnrichmentAgent.defaultTopN,
        onProgress: ProgressHandler? = nil
    ) async throws -> [Experience] {
        // Which base provider is authoritative here — reported to the feed so
        // the user sees "Amap" in China vs "OpenStreetMap" overseas.
        let inCN = CoordinateConverter.isInsideChinaMainland(coordinate)
        let baseStage: CompileProgressEvent.Stage =
            (inCN && amapService != nil && DataSourceSettings.policy.allowsAmap) ? .amap : .overpass

        // 1. Base collection, routed by region: Amap inside mainland China
        //    (authoritative there), Overpass overseas / on fallback. MapKit is
        //    folded in best-effort. Returns WGS84 regardless of source.
        onProgress?(baseStage, .running, "")
        onProgress?(.mapKit, .running, "")
        var pois = try await basePOIs(
            near: coordinate, radiusMeters: radiusMeters, category: category
        )
        guard !pois.isEmpty else {
            onProgress?(baseStage, .failure, NSLocalizedString("recompile.feed.noPOIs", comment: "No POIs found nearby"))
            onProgress?(.mapKit, .failure, "")
            return []
        }
        onProgress?(baseStage, .success, String(format: NSLocalizedString("recompile.feed.poiCount", comment: "N places found"), pois.count))
        onProgress?(.mapKit, .success, "")

        // 2. Fold Foursquare hard signals into the matching base POIs. One
        //    region call (with fields) covers the whole small radius. Skipped
        //    when no key is configured.
        if !Secrets.resolvedFoursquareKey.isEmpty {
            onProgress?(.foursquare, .running, "")
            do {
                let fsq = try await foursquareService.fetchPOIs(
                    near: coordinate, radiusMeters: radiusMeters, category: category
                )
                pois = FoursquareService.enrichMerge(base: pois, enrichment: fsq)
                onProgress?(.foursquare, .success, String(format: NSLocalizedString("recompile.feed.signalCount", comment: "N signals"), fsq.count))
            } catch {
                Self.logger.error("Foursquare enrichment failed: \(String(describing: error), privacy: .public)")
                onProgress?(.foursquare, .failure, "")
            }
        } else {
            onProgress?(.foursquare, .skipped, NSLocalizedString("recompile.feed.noKey", comment: "No API key configured"))
        }

        // 3. Fold the ephemeral Amap enrichment channel (rating / hours /
        //    phone / address per ADR §3.2) into each POI's tags map BEFORE
        //    ranking — read-once-and-discard via `consumeEnrichments`. This
        //    used to happen after step 4 (post-ranking), which meant the
        //    rating signal existed but never influenced which POIs survived
        //    the topN cut: Amap POIs were ranked essentially blind, so a
        //    rated-4.8 izakaya and a nameless snack stall scored the same.
        pois = foldAmapEnrichments(into: pois)

        // 4. Rank by signal richness (now rating-aware), keep the deepest N.
        onProgress?(.ranking, .running, "")
        let ranked = Array(
            pois.sorted { Self.signalScore($0) > Self.signalScore($1) }.prefix(topN)
        )
        onProgress?(.ranking, .success, String(format: NSLocalizedString("recompile.feed.keptCount", comment: "kept top N"), ranked.count))

        // 5. Backfill a street-level address on survivors missing one.
        onProgress?(.address, .running, "")
        let enriched = await backfillAddresses(ranked)
        onProgress?(.address, .success, "")

        // 6. Synthesize. The (already-relaxed) prompt cites the real signals.
        onProgress?(.synthesis, .running, "")
        let synthesized = try await aiService.synthesizeExperiences(
            from: enriched, cityCode: cityCode, locale: locale
        )
        // Honest signal: an AI-enriched result means the model actually ran; a
        // pure skeleton (no key / quota) leaves `isAIEnriched` false everywhere.
        let didSynthesize = synthesized.contains { $0.isAIEnriched }
        onProgress?(
            .synthesis,
            didSynthesize ? .success : .skipped,
            didSynthesize ? "" : NSLocalizedString("recompile.feed.noAI", comment: "AI unavailable, used local ranking")
        )
        return synthesized
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
        locale: Locale = .current,
        onProgress: ProgressHandler? = nil
    ) async -> Experience? {
        guard let coordinate = experience.coordinate else {
            onProgress?(.adopt, .failure, NSLocalizedString("recompile.feed.noCoordinate", comment: "Place has no coordinate"))
            return nil
        }

        let candidates: [Experience]
        do {
            candidates = try await enrich(
                at: coordinate,
                radiusMeters: radiusMeters,
                category: experience.category,
                cityCode: experience.location.cityCode,
                locale: locale,
                topN: EnrichmentAgent.recompileTopN,
                onProgress: onProgress
            )
        } catch {
            Self.logger.error("Re-compile failed for \(experience.id, privacy: .public): \(String(describing: error), privacy: .public)")
            onProgress?(.adopt, .failure, NSLocalizedString("recompile.feed.pipelineError", comment: "Pipeline error"))
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
            .min { $0.1 < $1.1 }

        guard let (enrichedMatch, matchDistance) = best else {
            onProgress?(.adopt, .failure, NSLocalizedString("recompile.feed.noMatch", comment: "No matching venue nearby"))
            return nil
        }

        // Only return an upgrade if it actually went through AI synthesis with
        // real cross-source signals. A skeleton fallback is not an upgrade.
        guard enrichedMatch.isAIEnriched else {
            onProgress?(.adopt, .failure, NSLocalizedString("recompile.feed.skeletonOnly", comment: "Only skeleton data, not an upgrade"))
            return nil
        }

        onProgress?(.adopt, .running, "")
        guard Self.shouldAdoptRecompiled(
            original: experience,
            candidate: enrichedMatch,
            distanceMeters: matchDistance
        ) else {
            Self.logger.info("Re-compile match rejected for \(experience.id, privacy: .public): different venue or lower quality")
            onProgress?(.adopt, .failure, NSLocalizedString("recompile.feed.rejected", comment: "Different venue or lower quality"))
            return nil
        }

        onProgress?(.adopt, .success, "")
        return experience.adoptingContent(of: enrichedMatch)
    }

    /// Whether a re-compiled candidate may replace the original card. Guards
    /// the two failure modes a re-compile can introduce: identity drift (the
    /// closest POI in the ring is a *different* venue, so adopting it would
    /// silently turn the card into another place) and quality downgrades (the
    /// synthesis produced a thinner card than what the user already has).
    nonisolated static func shouldAdoptRecompiled(
        original: Experience,
        candidate: Experience,
        distanceMeters: Double
    ) -> Bool {
        // Same venue: physically colocated, or names clearly refer to the
        // same place (coordinates from different providers drift).
        let sameVenue = distanceMeters <= Self.sameVenueMaxDistanceMeters
            || namesLikelyMatch(original, candidate)
        guard sameVenue else { return false }
        // Never downgrade: a re-compile is an upgrade or a no-op. The small
        // tolerance lets re-scored cards through while blocking the
        // curated-9.7 → skeleton-7.0 collapse seen in the field audit.
        return candidate.soloScore.overall >= original.soloScore.overall - Self.recompileScoreTolerance
    }

    /// Case/whitespace-insensitive containment across title and place names,
    /// in either direction — "旧天堂书店" vs "旧天堂书店（华侨城店）" matches.
    nonisolated private static func namesLikelyMatch(_ a: Experience, _ b: Experience) -> Bool {
        func names(_ e: Experience) -> [String] {
            [e.title, e.location.placeNameLocal, e.location.placeNameRomanized]
                .compactMap { $0 }
                .map { $0.lowercased().filter { !$0.isWhitespace } }
                .filter { $0.count >= 2 }
        }
        let lhs = names(a), rhs = names(b)
        return lhs.contains { l in rhs.contains { r in l.contains(r) || r.contains(l) } }
    }

    /// Max distance between the original coordinate and the best re-compile
    /// candidate to still count as the same physical venue without a name match.
    public static let sameVenueMaxDistanceMeters: Double = 60

    /// How far a candidate's solo score may sit below the original before the
    /// re-compile is treated as a downgrade and dropped.
    public static let recompileScoreTolerance: Double = 0.5

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

            // Fold Amap's transient rating/hours signals in BEFORE ranking —
            // the progressive path previously never consumed them at all, so
            // every mainland-China explore card was ranked and synthesized
            // signal-blind (the root of the "乱七八糟" garbage cards).
            let signalled = foldAmapEnrichments(into: novel)

            // Rank and synthesize only the novel POIs for this ring.
            let ranked = Array(
                signalled.sorted { Self.signalScore($0) > Self.signalScore($1) }.prefix(Self.defaultTopN)
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

    /// Fold the transient Amap enrichment bag (rating / opentimeToday / phone /
    /// address — ADR §3.2: in-memory only, read-once-and-discard) into the POI
    /// tags map, keyed to the tag names AIService and `signalScore` already
    /// read (`fsq_rating`, `opening_hours`, `phone`, `addr`). Must run BEFORE
    /// ranking so a real rating influences which POIs survive the topN cut.
    /// No-op when the Amap service is absent or holds nothing for these ids.
    private func foldAmapEnrichments(
        into pois: [OverpassService.POI]
    ) -> [OverpassService.POI] {
        guard let amap = amapService else { return pois }
        let bag = amap.consumeEnrichments(for: pois.map(\.osmId))
        guard !bag.isEmpty else { return pois }
        Self.logger.info("🔗 fed \(bag.count, privacy: .public) transient amap enrichments into ranking + synthesis")
        return pois.map { poi in
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
    }

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
    /// The rating contribution is value-aware: a 4.5+ place outranks a 3.5
    /// place, instead of "any rating = +4" treating a confirmed-mediocre spot
    /// the same as a beloved one. 精品 means the score must read the score.
    static func signalScore(_ poi: OverpassService.POI) -> Int {
        var score = 0
        if let ratingStr = poi.tags["fsq_rating"], let rating = Double(ratingStr) {
            switch rating {
            case 4.5...:        score += 8
            case 4.0..<4.5:     score += 6
            case 3.5..<4.0:     score += 4
            default:            score += 1  // rated but mediocre: barely above unrated
            }
        } else if poi.tags["fsq_rating"] != nil { score += 4 }
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
