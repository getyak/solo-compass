import Foundation
import os

// MARK: - Experience image resolution

/// Resolves the most *accurate* photo URLs for a place from its OpenStreetMap
/// tags, in descending order of trust:
///
/// 1. `image` — a direct photo URL the mapper attached. Most specific.
/// 2. `wikimedia_commons` — a `File:…` on Wikimedia Commons. Free, CC-licensed,
///    and tied to the exact place. Resolved via the stable `Special:FilePath`
///    redirect (no API call), with a `width` so we fetch a thumbnail, not a 20MB
///    original.
/// 3. `wikidata` — a `Q…` entity. The actual image lives in property `P18`,
///    which needs one network round-trip. Used as a last resort and resolved
///    lazily so it never blocks the Explore first paint.
///
/// We deliberately do NOT invent images (no stock photos, no AI generation):
/// every URL here is anchored to real provider data for the specific place, so
/// a café card never shows a generic "coffee" stock shot that misleads.
///
/// Distinct from `PlacePhotoStore`, which persists user-captured photos to disk
/// as `file://` URLs. This service only *reads* remote, place-specific sources.
public enum ExperienceImageService {
    private static let logger = Logger(subsystem: "com.solocompass.app", category: "ExperienceImageService")

    /// Thumbnail width requested from Commons. Cards show a small image; this
    /// keeps payloads tiny and avoids downloading multi-MB originals.
    private static let commonsThumbWidth = 800

    // MARK: Synchronous resolution (no network)

    /// Build photo URL strings from OSM tags using only the zero-cost sources
    /// (`image`, `wikimedia_commons`). Returns `nil` when neither tag is present
    /// so callers can leave `photoUrls` nil rather than an empty array.
    ///
    /// Order matters: a direct `image` is the single best photo, so it leads;
    /// the Commons thumbnail follows as a reliable fallback/second shot.
    public static func syncPhotoURLs(from tags: [String: String]) -> [String]? {
        var urls: [String] = []

        if let direct = tags["image"], let normalized = normalizedDirectImageURL(direct) {
            urls.append(normalized)
        }

        if let commons = tags["wikimedia_commons"],
           let commonsURL = commonsFilePathURL(from: commons) {
            urls.append(commonsURL)
        }

        return urls.isEmpty ? nil : urls
    }

    /// True when the tags carry a `wikidata` entity but no cheaper image source,
    /// i.e. the only way to get a photo is the async P18 lookup. Lets callers
    /// batch just the POIs that actually need a network round-trip.
    public static func needsWikidataLookup(tags: [String: String]) -> Bool {
        guard tags["wikidata"] != nil else { return false }
        return syncPhotoURLs(from: tags) == nil
    }

    // MARK: Async resolution (Wikidata P18)

    /// Resolve the `P18` image of a `wikidata` entity to a Commons thumbnail URL,
    /// or `nil` when the entity has no image / the lookup fails. One network
    /// round-trip; safe to call off the main actor. Never throws — image
    /// enrichment is best-effort and must never fail an Explore.
    public static func wikidataImageURL(
        entityId rawId: String,
        session: URLSession = .shared
    ) async -> String? {
        // Accept "Q42", "wikidata=Q42", or a stray "https://www.wikidata.org/...Q42".
        guard let qid = normalizedWikidataQID(rawId) else { return nil }
        guard let endpoint = URL(
            string: "https://www.wikidata.org/wiki/Special:EntityData/\(qid).json"
        ) else { return nil }

        do {
            // Per-request timeout so one slow/hung entity can't stall the
            // bounded enrichment group that calls this concurrently.
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 5
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            guard let fileName = Self.parseP18FileName(data, qid: qid) else { return nil }
            // P18 stores a bare "File name.jpg" without the File: prefix.
            return commonsFilePathURL(from: fileName)
        } catch {
            logger.debug("wikidata image lookup failed for \(qid, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: - URL construction helpers

    /// Normalize a direct `image` tag value into an https URL string, or nil.
    ///
    /// The value is untrusted third-party data (OSM tags anyone can edit), so we
    /// require **https** specifically — not just any http(s) scheme. This blocks
    /// three things a hostile `image` tag could otherwise do via `AsyncImage`:
    /// mixed-content `http://` loads, IP-based user tracking, and pointing the
    /// client at internal hosts (`http://192.168.x.x`). Commons/Wikidata URLs are
    /// hardcoded-host https, so this only constrains the direct-tag path.
    static func normalizedDirectImageURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false else {
            return nil
        }
        return url.absoluteString
    }

    /// Turn a Commons `File:Example.jpg` (or bare `Example.jpg`) into a stable
    /// thumbnail URL via `Special:FilePath`, which 302-redirects to the current
    /// file location — no API key, no API call.
    static func commonsFilePathURL(from raw: String) -> String? {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        // Strip an optional "File:" / "Image:" prefix (any case).
        for prefix in ["File:", "Image:", "file:", "image:"] {
            if name.hasPrefix(prefix) {
                name = String(name.dropFirst(prefix.count))
                break
            }
        }
        // Commons normalizes spaces to underscores; FilePath accepts either but
        // we percent-encode to be safe.
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return "https://commons.wikimedia.org/wiki/Special:FilePath/\(encoded)?width=\(commonsThumbWidth)"
    }

    /// Extract a `Q…` id from various raw forms (bare, tag=value, or a URL).
    static func normalizedWikidataQID(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Pull the last "Q<digits>" token — covers "Q42", "wikidata=Q42",
        // and full wikidata.org URLs ending in the qid.
        guard let range = trimmed.range(
            of: "Q[0-9]+",
            options: [.regularExpression, .backwards]
        ) else { return nil }
        return String(trimmed[range])
    }

    /// Parse the `P18` (image) claim's filename out of a Wikidata EntityData
    /// JSON blob. Returns the bare "File name.jpg" or nil when absent.
    static func parseP18FileName(_ data: Data, qid: String) -> String? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entities = root["entities"] as? [String: Any],
            let entity = entities[qid] as? [String: Any],
            let claims = entity["claims"] as? [String: Any],
            let p18 = claims["P18"] as? [[String: Any]],
            let first = p18.first,
            let mainsnak = first["mainsnak"] as? [String: Any],
            let datavalue = mainsnak["datavalue"] as? [String: Any],
            let fileName = datavalue["value"] as? String
        else { return nil }
        return fileName
    }
}
