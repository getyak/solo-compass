import Foundation

/// Nomad OS A2: pulls a city's already-synthesized experiences from the backend
/// so a traveler in a non-seed city isn't stuck with an empty map.
///
/// The gap this closes: `synthesize-experiences` writes every batch it compiles
/// into the public-read `synthesized_experiences` table, keyed by `city_code` —
/// but the client never read it. Seed ships 8 cities; everywhere else stayed
/// empty unless the user personally ran Explore. This fetcher is the missing
/// read side: any city another traveler has already synthesized becomes
/// available to the next person who opens it.
///
/// ## Why two tables
/// The stored `payload` is the raw AI item array (title / category / soloOverall
/// …) — it carries `osmId` but **no coordinates or place name**. The write path
/// (`AIService.synthesizeViaEdge`) backfills those from the Overpass POI batch it
/// holds in memory; a pure read has no such batch. So we join the equally
/// public-read `osm_pois` table by `osm_id` to recover lat/lon, names, and the
/// `source` tag. Without the join the experiences would have no coordinate and
/// could neither be pinned on the map nor feed the Today three-things
/// (`workReadySpots` / `nowScore` both need a location).
///
/// The item→Experience mapping mirrors `AIService.synthesizeViaEdge` exactly
/// (same clamps, same flat solo-score breakdown, `status: .candidate`,
/// `confidence.level: 1`, `id: "exp_osm_<osmId>"`) so a synthesized experience
/// read here is byte-identical to one produced by Explore — they share the
/// `appendGenerated` id-dedup and never diverge.
@MainActor
final class CityExperienceFetcher {
    private let supabase: SupabaseClientProtocol

    init(supabase: SupabaseClientProtocol = SupabaseClient.shared) {
        self.supabase = supabase
    }

    /// One `synthesized_experiences` row's `payload`: the raw AI item array the
    /// Edge function stored. Field-for-field identical to `AIService`'s private
    /// `EdgeItem`; only `osmId` links back to a place.
    struct SynthItem: Decodable, Sendable {
        let osmId: Int64
        let title: String
        let oneLiner: String
        let whyItMatters: String
        let category: String
        let bestStartHour: Int?
        let bestEndHour: Int?
        let durationMinMinutes: Int?
        let durationMaxMinutes: Int?
        let howTo: [String]?
        let soloHint: String?
        let soloOverall: Double?
    }

    /// One `synthesized_experiences` row — we only select `payload`.
    private struct SynthRow: Decodable {
        let payload: [SynthItem]
    }

    /// One `osm_pois` row: the place facts the payload lacks.
    private struct PoiRow: Decodable {
        let osmId: Int64
        let name: String
        let nameEn: String?
        let lat: Double
        let lon: Double
        let tags: [String: String]

        enum CodingKeys: String, CodingKey {
            case osmId = "osm_id"
            case name
            case nameEn = "name_en"
            case lat, lon, tags
        }
    }

    /// Fetch and assemble the full `[Experience]` for a city, or `[]` on any
    /// miss (backend off, no session, offline, empty city, or the POI join
    /// coming up dry). Never throws — a read failure is "nothing to add", never
    /// a reason to disturb what's already on the map (mirrors
    /// `CityBriefService`'s "failure = no update" invariant).
    func fetchCityExperiences(cityCode: String) async -> [Experience] {
        let code = cityCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return [] }

        // 1. Pull every synthesized row for the city; flatten the per-batch
        //    payload arrays into one item list, de-duped by osmId (later
        //    batches win — an id re-synthesized keeps its newest copy).
        guard let synthData = await get(
            table: "synthesized_experiences",
            query: [
                URLQueryItem(name: "city_code", value: "eq.\(code)"),
                URLQueryItem(name: "select", value: "payload"),
            ]
        ), !synthData.isEmpty else {
            return []
        }
        guard let rows = await Self.decode([SynthRow].self, from: synthData) else {
            return []
        }
        var itemByOsmId: [Int64: SynthItem] = [:]
        for row in rows {
            for item in row.payload {
                itemByOsmId[item.osmId] = item
            }
        }
        guard !itemByOsmId.isEmpty else { return [] }

        // 2. Recover coordinates + names from osm_pois for exactly those ids.
        let poiById = await fetchPois(osmIds: Array(itemByOsmId.keys))
        guard !poiById.isEmpty else { return [] }

        // 3. Join. An item whose POI didn't come back is dropped — without a
        //    coordinate it can't be pinned or ranked, so a half-experience is
        //    worse than absence.
        let now = Date()
        return itemByOsmId.values.compactMap { item -> Experience? in
            guard let poi = poiById[item.osmId] else { return nil }
            return Self.makeExperience(item: item, poi: poi, cityCode: code, now: now)
        }
    }

    // MARK: - osm_pois join

    /// Read `osm_pois` for the given ids via a single `osm_id=in.(...)` query.
    /// PostgREST caps URL length, so we chunk the id list to stay well under it.
    private func fetchPois(osmIds: [Int64]) async -> [Int64: PoiRow] {
        var result: [Int64: PoiRow] = [:]
        // 100 bigints ≈ under 2 KB of query — comfortably within limits.
        for chunk in osmIds.chunked(into: 100) {
            let list = chunk.map(String.init).joined(separator: ",")
            guard let data = await get(
                table: "osm_pois",
                query: [
                    URLQueryItem(name: "osm_id", value: "in.(\(list))"),
                    URLQueryItem(name: "select", value: "osm_id,name,name_en,lat,lon,tags"),
                ]
            ), !data.isEmpty else {
                continue
            }
            guard let poiRows = await Self.decode([PoiRow].self, from: data) else { continue }
            for poi in poiRows {
                result[poi.osmId] = poi
            }
        }
        return result
    }

    // MARK: - Mapping (parity with AIService.synthesizeViaEdge)

    /// Build one `Experience` from a synthesized item + its POI facts, using the
    /// identical rules the write path applies (clamps, flat breakdown, provenance
    /// source, candidate/level-1 defaults). Kept in lockstep so read and write
    /// produce the same shape.
    private static func makeExperience(
        item: SynthItem,
        poi: PoiRow,
        cityCode: String,
        now: Date
    ) -> Experience {
        let category = ExperienceCategory(rawValue: item.category)
            ?? OverpassService.category(for: poi.tags)
        let startHour = item.bestStartHour.map { max(0, min(23, $0)) } ?? 9
        let endHour = item.bestEndHour.map { max(0, min(23, $0)) } ?? 21
        let dMin = item.durationMinMinutes ?? 30
        let dMax = max(dMin, item.durationMaxMinutes ?? 90)
        let overall = max(6.0, min(9.5, item.soloOverall ?? 7.0))
        let breakdown = SoloScore.Breakdown(
            seatingFriendly: overall, soloPatronRatio: overall, staffPressure: overall,
            soloPortioning: overall, ambianceFit: overall, safety: overall
        )
        let howTo = (item.howTo ?? []).enumerated().map { HowToStep(order: $0.offset + 1, text: $0.element) }
        let isAmap = poi.tags["source"] == "amap"
        return Experience(
            id: "exp_osm_\(poi.osmId)",
            title: item.title,
            oneLiner: item.oneLiner,
            whyItMatters: item.whyItMatters,
            category: category,
            location: ExperienceLocation(
                coordinates: [poi.lon, poi.lat],
                cityCode: cityCode,
                addressHint: nil,
                placeNameLocal: poi.name,
                placeNameRomanized: poi.nameEn
            ),
            bestTimes: [TimeWindow(startHour: startHour, endHour: endHour)],
            durationMinutes: .init(min: dMin, max: dMax),
            howTo: howTo,
            realInconveniences: [],
            soloScore: SoloScore(overall: overall, breakdown: breakdown, hint: item.soloHint, basedOnCount: 0),
            sources: [
                InformationSource(
                    type: isAmap ? .amap : .user,
                    url: isAmap ? nil : URL(string: "https://www.openstreetmap.org/node/\(poi.osmId)"),
                    attribution: isAmap ? "© AutoNavi (Amap) + AI" : "© OpenStreetMap contributors + AI",
                    verifiedAt: now
                )
            ],
            confidence: Confidence(
                level: 1,
                lastVerifiedAt: now,
                reason: "AI-synthesized via Edge Function, unverified",
                signals: .init(aiScrapeAgeDays: 0, passiveGpsHits30d: 0, activeReports30d: 0, trustedVerifications: 0)
            ),
            nearbyExperienceIds: [],
            stats: .init(completionCount: 0, averageRating: 0),
            status: .candidate,
            createdAt: now,
            updatedAt: now
        )
    }

    // MARK: - Plumbing

    private func get(table: String, query: [URLQueryItem]) async -> Data? {
        switch await supabase.get(table: table, query: query) {
        case .success(let data):
            return data
        case .failure:
            return nil
        }
    }

    /// Decode off the main actor so a large city's payload doesn't hitch the UI.
    nonisolated static func decode<T: Decodable & Sendable>(
        _ type: T.Type,
        from data: Data
    ) async -> T? {
        await Task.detached(priority: .userInitiated) {
            try? JSONDecoder().decode(type, from: data)
        }.value
    }
}

private extension Array {
    /// Split into fixed-size chunks (last may be shorter). Used to keep the
    /// `osm_id=in.(...)` query under PostgREST's URL length ceiling.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
