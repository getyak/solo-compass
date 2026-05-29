import Foundation
import os

/// Web-search enrichment for the top-N ranked experiences after synthesis.
///
/// Uses the existing AI channel (AIService) to ask for cross-verifiable,
/// objective information about each place. Runs only when:
///   - `FeatureFlags.webSearchEnrichment` is true
///   - An API key is available in AIService
///
/// Anti-hallucination contract:
///   - Only fills fields that are objectively verifiable: `openingHours`,
///     `website`, `phone`. Never invents menu items, owner names, or history.
///   - Returns the input unchanged on any error — callers can treat this as a
///     best-effort pass with zero blast radius.
@MainActor
public final class WebSearchEnrichmentSource {
    private static let logger = Logger(subsystem: "com.solocompass", category: "WebSearchEnrichmentSource")

    /// How many experiences to enrich in one pass. Callers pass the
    /// already-ranked slice; this is a hard safety cap.
    public static let defaultTopN = 5

    private let aiService: AIService

    public init(aiService: AIService) {
        self.aiService = aiService
    }

    /// Enrich the top-N experiences with web-verifiable objective fields.
    ///
    /// - Parameters:
    ///   - experiences: The full ranked list. Only the first `topN` entries
    ///     are processed; the rest are returned as-is.
    ///   - topN: Maximum number of experiences to enrich (default 5).
    /// - Returns: The same slice with objective fields filled where available.
    ///   Never throws — failures degrade silently to the original experience.
    public func enrich(
        _ experiences: [Experience],
        topN: Int = WebSearchEnrichmentSource.defaultTopN
    ) async -> [Experience] {
        guard FeatureFlags.webSearchEnrichment else { return experiences }

        let targetCount = min(topN, experiences.count)
        let tail = targetCount < experiences.count
            ? Array(experiences[targetCount...])
            : []

        var enriched: [Experience] = []
        for experience in experiences.prefix(targetCount) {
            let updated = await enrichOne(experience)
            enriched.append(updated)
        }
        return enriched + tail
    }

    // MARK: - Private

    private func enrichOne(_ experience: Experience) async -> Experience {
        let prompt = Self.prompt(for: experience)
        do {
            let raw = try await aiService.sendWebSearchQuery(prompt: prompt)
            return Self.apply(raw, to: experience)
        } catch {
            Self.logger.error("enrichment failed for '\(experience.title, privacy: .private)': \(String(describing: error), privacy: .public)")
            return experience
        }
    }

    /// Build a prompt asking ONLY for cross-verifiable objective facts.
    static func prompt(for experience: Experience) -> String {
        let coord = experience.coordinate
            .map { String(format: "%.5f, %.5f", $0.latitude, $0.longitude) }
            ?? "unknown"
        return """
        You are looking up objective, publicly verifiable information for a real place.

        Place: \(experience.title)
        Category: \(experience.category.rawValue)
        City: \(experience.location.cityCode)
        Coordinate (lat, lon): \(coord)

        Return ONLY a JSON object with these optional fields — leave a field out \
        entirely if you are not certain it is correct for THIS specific place:
        {
          "openingHours": "<OSM-style hours string, e.g. Mo-Fr 09:00-18:00>",
          "website": "<full URL>",
          "phone": "<international format>"
        }

        STRICT RULES:
        - Only include information you are certain is objectively correct for this place.
        - Do NOT invent menu items, owner names, historical claims, or interior details.
        - Do NOT guess opening hours if you are not sure.
        - If you cannot verify any field, return an empty JSON object: {}
        - No markdown fences. No prose. Only the JSON object.
        """
    }

    /// Parse the AI response and overlay only non-empty objective fields.
    static func apply(_ raw: String, to experience: Experience) -> Experience {
        // Find the first {...} block.
        guard
            let start = raw.firstIndex(of: "{"),
            let end = raw.lastIndex(of: "}"),
            start <= end,
            let data = String(raw[start...end]).data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return experience }

        let newHours   = json["openingHours"].flatMap { $0.isEmpty ? nil : $0 }
        let newWebsite = json["website"].flatMap { $0.isEmpty ? nil : $0 }
        let newPhone   = json["phone"].flatMap { $0.isEmpty ? nil : $0 }

        // Nothing new — skip the copy.
        guard newHours != nil || newWebsite != nil || newPhone != nil else {
            return experience
        }

        let loc = experience.location
        let updatedLocation = ExperienceLocation(
            coordinates: loc.coordinates,
            cityCode: loc.cityCode,
            addressHint: loc.addressHint,
            placeNameLocal: loc.placeNameLocal,
            placeNameRomanized: loc.placeNameRomanized,
            rating: loc.rating,
            openingHours: newHours ?? loc.openingHours,
            priceLevel: loc.priceLevel,
            website: newWebsite ?? loc.website,
            phone: newPhone ?? loc.phone
        )

        return Experience(
            id: experience.id,
            title: experience.title,
            oneLiner: experience.oneLiner,
            whyItMatters: experience.whyItMatters,
            category: experience.category,
            location: updatedLocation,
            bestTimes: experience.bestTimes,
            durationMinutes: experience.durationMinutes,
            howTo: experience.howTo,
            realInconveniences: experience.realInconveniences,
            soloScore: experience.soloScore,
            sources: experience.sources,
            confidence: experience.confidence,
            nearbyExperienceIds: experience.nearbyExperienceIds,
            stats: experience.stats,
            status: experience.status,
            createdAt: experience.createdAt,
            updatedAt: experience.updatedAt,
            userTags: experience.userTags
        )
    }
}
