import Foundation
import SwiftData

/// SwiftData representation of an `Experience`.
///
/// Strategy: scalar fields are stored natively, but complex nested structs
/// (bestTimes, howTo, realInconveniences, sources, soloScore, confidence,
/// stats, nearbyExperienceIds) are encoded as JSON `Data` blobs. This keeps
/// the schema flat enough to query (no relationships, no joins) while the
/// `Experience` value type stays the canonical shape across the app.
///
/// Trade-off: blob fields are not directly queryable in SwiftData. We don't
/// need to query inside them (e.g. "experiences with bestTimes overlapping
/// 14:00") for v1 — those decisions happen in Swift after fetching. If
/// that changes, we promote individual fields to columns in a future schema
/// version.
@Model
public final class ExperienceRecord {
    @Attribute(.unique) public var id: String

    public var title: String
    public var oneLiner: String
    public var whyItMatters: String

    /// Raw value of `ExperienceCategory.rawValue` so the column is queryable.
    public var category: String

    /// GeoJSON convention (lon, lat) — stored as two doubles for spatial queries.
    public var longitude: Double
    public var latitude: Double

    public var cityCode: String
    public var addressHint: String?
    public var placeNameLocal: String?
    public var placeNameRomanized: String?

    public var durationMin: Int
    public var durationMax: Int

    /// Raw value of `Experience.Status`.
    public var status: String

    public var createdAt: Date
    public var updatedAt: Date

    // MARK: - Encoded blobs

    public var bestTimesBlob: Data
    public var howToBlob: Data
    public var realInconveniencesBlob: Data
    public var sourcesBlob: Data
    public var soloScoreBlob: Data
    public var confidenceBlob: Data
    public var statsBlob: Data
    public var nearbyExperienceIdsBlob: Data

    public init(
        id: String,
        title: String,
        oneLiner: String,
        whyItMatters: String,
        category: String,
        longitude: Double,
        latitude: Double,
        cityCode: String,
        addressHint: String?,
        placeNameLocal: String?,
        placeNameRomanized: String?,
        durationMin: Int,
        durationMax: Int,
        status: String,
        createdAt: Date,
        updatedAt: Date,
        bestTimesBlob: Data,
        howToBlob: Data,
        realInconveniencesBlob: Data,
        sourcesBlob: Data,
        soloScoreBlob: Data,
        confidenceBlob: Data,
        statsBlob: Data,
        nearbyExperienceIdsBlob: Data
    ) {
        self.id = id
        self.title = title
        self.oneLiner = oneLiner
        self.whyItMatters = whyItMatters
        self.category = category
        self.longitude = longitude
        self.latitude = latitude
        self.cityCode = cityCode
        self.addressHint = addressHint
        self.placeNameLocal = placeNameLocal
        self.placeNameRomanized = placeNameRomanized
        self.durationMin = durationMin
        self.durationMax = durationMax
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.bestTimesBlob = bestTimesBlob
        self.howToBlob = howToBlob
        self.realInconveniencesBlob = realInconveniencesBlob
        self.sourcesBlob = sourcesBlob
        self.soloScoreBlob = soloScoreBlob
        self.confidenceBlob = confidenceBlob
        self.statsBlob = statsBlob
        self.nearbyExperienceIdsBlob = nearbyExperienceIdsBlob
    }
}

// MARK: - Two-way mapping

extension ExperienceRecord {
    /// Build a record from an `Experience` value. Encoding errors are
    /// fatal — they only happen if the value violates the encoder's
    /// expectations, which would be a programmer error.
    public convenience init(from experience: Experience) {
        let encoder = JSONEncoder.iso8601Encoder
        let lon = experience.location.coordinates.first ?? 0
        let lat = experience.location.coordinates.dropFirst().first ?? 0
        do {
            self.init(
                id: experience.id,
                title: experience.title,
                oneLiner: experience.oneLiner,
                whyItMatters: experience.whyItMatters,
                category: experience.category.rawValue,
                longitude: lon,
                latitude: lat,
                cityCode: experience.location.cityCode,
                addressHint: experience.location.addressHint,
                placeNameLocal: experience.location.placeNameLocal,
                placeNameRomanized: experience.location.placeNameRomanized,
                durationMin: experience.durationMinutes.min,
                durationMax: experience.durationMinutes.max,
                status: experience.status.rawValue,
                createdAt: experience.createdAt,
                updatedAt: experience.updatedAt,
                bestTimesBlob: try encoder.encode(experience.bestTimes),
                howToBlob: try encoder.encode(experience.howTo),
                realInconveniencesBlob: try encoder.encode(experience.realInconveniences),
                sourcesBlob: try encoder.encode(experience.sources),
                soloScoreBlob: try encoder.encode(experience.soloScore),
                confidenceBlob: try encoder.encode(experience.confidence),
                statsBlob: try encoder.encode(experience.stats),
                nearbyExperienceIdsBlob: try encoder.encode(experience.nearbyExperienceIds)
            )
        } catch {
            fatalError("Failed to encode Experience \(experience.id): \(error)")
        }
    }

    /// Decode this record back into an `Experience` value. Decoding errors
    /// are fatal because a malformed row implies on-disk corruption that
    /// should crash loud rather than silently degrade.
    public var asValue: Experience {
        let decoder = JSONDecoder.iso8601Decoder
        do {
            return Experience(
                id: id,
                title: title,
                oneLiner: oneLiner,
                whyItMatters: whyItMatters,
                category: ExperienceCategory(rawValue: category) ?? .hidden,
                location: ExperienceLocation(
                    coordinates: [longitude, latitude],
                    cityCode: cityCode,
                    addressHint: addressHint,
                    placeNameLocal: placeNameLocal,
                    placeNameRomanized: placeNameRomanized
                ),
                bestTimes: try decoder.decode([TimeWindow].self, from: bestTimesBlob),
                durationMinutes: .init(min: durationMin, max: durationMax),
                howTo: try decoder.decode([HowToStep].self, from: howToBlob),
                realInconveniences: try decoder.decode([RealInconvenience].self, from: realInconveniencesBlob),
                soloScore: try decoder.decode(SoloScore.self, from: soloScoreBlob),
                sources: try decoder.decode([InformationSource].self, from: sourcesBlob),
                confidence: try decoder.decode(Confidence.self, from: confidenceBlob),
                nearbyExperienceIds: try decoder.decode([String].self, from: nearbyExperienceIdsBlob),
                stats: try decoder.decode(Experience.Stats.self, from: statsBlob),
                status: Experience.Status(rawValue: status) ?? .active,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        } catch {
            fatalError("Failed to decode ExperienceRecord \(id): \(error)")
        }
    }
}
