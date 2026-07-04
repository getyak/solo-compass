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

    // MARK: - Cross-channel hard signals (enriched from Foursquare / MapKit)
    // All optional so rows migrated from earlier schema versions decode as nil.
    public var rating: Double?
    public var openingHours: String?
    public var priceLevel: Double?
    public var website: String?
    public var phone: String?

    public var durationMin: Int
    public var durationMax: Int

    /// Raw value of `Experience.Status`.
    public var status: String

    public var createdAt: Date
    public var updatedAt: Date

    // MARK: - Server-aggregated Solo Score (US-035)

    /// Mean overall Solo Score computed nightly by the `aggregate-solo-scores`
    /// Edge Function over `solo_score_signals` rows in the last 90 days.
    /// Nil until the first pull that returns a value with signal_count >= 3.
    public var serverAggregatedSoloScore: Double?

    /// Number of `solo_score_signals` rows that contributed to
    /// `serverAggregatedSoloScore`. Used as a quality gate: the app only
    /// trusts the server aggregate when this is >= 3.
    public var serverSignalCount: Int?

    // MARK: - Encoded blobs

    public var bestTimesBlob: Data
    public var howToBlob: Data
    public var realInconveniencesBlob: Data
    public var sourcesBlob: Data
    public var soloScoreBlob: Data
    public var confidenceBlob: Data
    public var statsBlob: Data
    public var nearbyExperienceIdsBlob: Data

    /// User-defined free-form tags (US-005). Added in SchemaV2.
    /// JSON-encoded `[String]`. Optional so rows migrated from v1 (without this
    /// column written) decode as `nil`, which the value-mapping layer treats
    /// as the empty array — see `asValue` below.
    public var userTagsBlob: Data?

    /// Photos attached to a user-created place. JSON-encoded `[String]` of URL
    /// strings (local `file://` then remote https after sync). Optional so rows
    /// migrated from earlier schema versions decode as `nil`.
    public var photoUrlsBlob: Data?

    /// Category-specific scannable facts (SchemaV1_5). JSON-encoded
    /// `[CategoryHighlight]`. Optional so rows migrated from earlier schema
    /// versions decode as `nil`, treated as empty by `asValue`.
    public var categoryHighlightsBlob: Data?

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
        rating: Double? = nil,
        openingHours: String? = nil,
        priceLevel: Double? = nil,
        website: String? = nil,
        phone: String? = nil,
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
        nearbyExperienceIdsBlob: Data,
        userTagsBlob: Data? = nil,
        photoUrlsBlob: Data? = nil,
        categoryHighlightsBlob: Data? = nil
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
        self.rating = rating
        self.openingHours = openingHours
        self.priceLevel = priceLevel
        self.website = website
        self.phone = phone
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
        self.userTagsBlob = userTagsBlob
        self.photoUrlsBlob = photoUrlsBlob
        self.categoryHighlightsBlob = categoryHighlightsBlob
    }

    #if DEBUG
    /// Overwrite every mutable field from another record. Rubric harness uses
    /// this to hot-reload seed edits (oneLiner / whyItMatters keyword changes)
    /// into SwiftData without deleting and re-inserting the row — deletion
    /// leaves lingering ghosts under the same context flush in some Swift
    /// versions, doubling the row count.
    func copyContent(from other: ExperienceRecord) {
        self.title = other.title
        self.oneLiner = other.oneLiner
        self.whyItMatters = other.whyItMatters
        self.category = other.category
        self.longitude = other.longitude
        self.latitude = other.latitude
        self.cityCode = other.cityCode
        self.addressHint = other.addressHint
        self.placeNameLocal = other.placeNameLocal
        self.placeNameRomanized = other.placeNameRomanized
        self.rating = other.rating
        self.openingHours = other.openingHours
        self.priceLevel = other.priceLevel
        self.website = other.website
        self.phone = other.phone
        self.durationMin = other.durationMin
        self.durationMax = other.durationMax
        self.status = other.status
        self.updatedAt = other.updatedAt
        self.bestTimesBlob = other.bestTimesBlob
        self.howToBlob = other.howToBlob
        self.realInconveniencesBlob = other.realInconveniencesBlob
        self.sourcesBlob = other.sourcesBlob
        self.soloScoreBlob = other.soloScoreBlob
        self.confidenceBlob = other.confidenceBlob
        self.statsBlob = other.statsBlob
        self.nearbyExperienceIdsBlob = other.nearbyExperienceIdsBlob
        self.userTagsBlob = other.userTagsBlob
        self.photoUrlsBlob = other.photoUrlsBlob
        self.categoryHighlightsBlob = other.categoryHighlightsBlob
    }
    #endif
}

// MARK: - Two-way mapping

/// Encode optional photo URLs to a JSON blob, or `nil` when there are none.
/// Kept as a free function so the `init(from:)` call site stays a simple
/// expression the Swift type-checker can resolve quickly.
private func encodedPhotoUrls(_ urls: [String]?, encoder: JSONEncoder) -> Data? {
    guard let urls else { return nil }
    return try? encoder.encode(urls)
}

/// Encode optional category highlights to a JSON blob, or `nil` when there are
/// none. Free function for the same fast-type-check reason as `encodedPhotoUrls`.
private func encodedHighlights(_ highlights: [CategoryHighlight]?, encoder: JSONEncoder) -> Data? {
    guard let highlights, !highlights.isEmpty else { return nil }
    return try? encoder.encode(highlights)
}

extension ExperienceRecord {
    // MARK: - Beta-P0-B safe defaults
    //
    // Used by `asValue` and the `init(from:)` fallback path when a blob is
    // malformed. These deliberately read as "neutral / unknown" so the row
    // stays renderable without misleading the user with confident numbers.
    static let neutralBreakdown = SoloScore.Breakdown(
        seatingFriendly: 5,
        soloPatronRatio: 5,
        staffPressure: 5,
        soloPortioning: 5,
        ambianceFit: 5,
        safety: 5
    )
    static let neutralSoloScore = SoloScore(
        overall: 5,
        breakdown: neutralBreakdown,
        hint: nil,
        basedOnCount: 0
    )
    static let neutralSignals = Confidence.Signals(
        aiScrapeAgeDays: 999,
        passiveGpsHits30d: 0,
        activeReports30d: 0,
        trustedVerifications: 0
    )
    static let neutralConfidence = Confidence(
        level: 0,
        lastVerifiedAt: Date(timeIntervalSince1970: 0),
        reason: "schema_fallback",
        signals: neutralSignals
    )
    static let neutralStats = Experience.Stats(
        completionCount: 0,
        averageRating: 0,
        lastCompletedAt: nil
    )

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
                rating: experience.location.rating,
                openingHours: experience.location.openingHours,
                priceLevel: experience.location.priceLevel,
                website: experience.location.website,
                phone: experience.location.phone,
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
                nearbyExperienceIdsBlob: try encoder.encode(experience.nearbyExperienceIds),
                userTagsBlob: try encoder.encode(experience.userTags ?? []),
                photoUrlsBlob: encodedPhotoUrls(experience.location.photoUrls, encoder: encoder),
                categoryHighlightsBlob: encodedHighlights(experience.categoryHighlights, encoder: encoder)
            )
        } catch {
            // Schema-evolution safety: an unencodable Experience used to
            // crash on save. Now we log to Sentry and fall back to a
            // minimal record so the surrounding transaction succeeds.
            PersistenceLog.recordDecodeFailure(
                PersistenceCodecError(
                    context: "ExperienceRecord.init(from:)",
                    recordId: experience.id,
                    underlying: error
                )
            )
            let empty = Data("[]".utf8)
            let neutralScore = (try? JSONEncoder.iso8601Encoder.encode(ExperienceRecord.neutralSoloScore)) ?? Data("{}".utf8)
            let neutralConfidence = (try? JSONEncoder.iso8601Encoder.encode(ExperienceRecord.neutralConfidence)) ?? Data("{}".utf8)
            let neutralStats = (try? JSONEncoder.iso8601Encoder.encode(ExperienceRecord.neutralStats)) ?? Data("{}".utf8)
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
                rating: experience.location.rating,
                openingHours: experience.location.openingHours,
                priceLevel: experience.location.priceLevel,
                website: experience.location.website,
                phone: experience.location.phone,
                durationMin: experience.durationMinutes.min,
                durationMax: experience.durationMinutes.max,
                status: experience.status.rawValue,
                createdAt: experience.createdAt,
                updatedAt: experience.updatedAt,
                bestTimesBlob: empty,
                howToBlob: empty,
                realInconveniencesBlob: empty,
                sourcesBlob: empty,
                soloScoreBlob: neutralScore,
                confidenceBlob: neutralConfidence,
                statsBlob: neutralStats,
                nearbyExperienceIdsBlob: empty,
                userTagsBlob: nil,
                photoUrlsBlob: nil,
                categoryHighlightsBlob: nil
            )
            return
        }
    }

    /// Decode this record back into an `Experience` value. Decoding errors
    /// are fatal because a malformed row implies on-disk corruption that
    /// should crash loud rather than silently degrade.
    public var asValue: Experience {
        let decoder = JSONDecoder.iso8601Decoder
        // Decode the optional highlights blob up front so the big Experience
        // initializer below stays within the type-checker's time budget.
        let highlights: [CategoryHighlight]? = categoryHighlightsBlob.flatMap {
            try? decoder.decode([CategoryHighlight].self, from: $0)
        }
        // Schema-evolution safety: previously a single bad blob would
        // crash the app via `fatalError`. We now degrade each field to
        // a safe default (empty arrays, neutral score/confidence) and
        // log via Sentry so the row stays readable.
        let bestTimes = decodeOrLog([TimeWindow].self, from: bestTimesBlob, field: "bestTimes", fallback: { [] })
        let howTo = decodeOrLog([HowToStep].self, from: howToBlob, field: "howTo", fallback: { [] })
        let realInconveniences = decodeOrLog([RealInconvenience].self, from: realInconveniencesBlob, field: "realInconveniences", fallback: { [] })
        let soloScore = decodeOrLog(SoloScore.self, from: soloScoreBlob, field: "soloScore", fallback: { ExperienceRecord.neutralSoloScore })
        let sources = decodeOrLog([InformationSource].self, from: sourcesBlob, field: "sources", fallback: { [] })
        let confidence = decodeOrLog(Confidence.self, from: confidenceBlob, field: "confidence", fallback: { ExperienceRecord.neutralConfidence })
        let nearbyExperienceIds = decodeOrLog([String].self, from: nearbyExperienceIdsBlob, field: "nearbyExperienceIds")
        let stats = decodeOrLog(Experience.Stats.self, from: statsBlob, field: "stats", fallback: { ExperienceRecord.neutralStats })
        let userTagsList: [String] = {
            guard let blob = userTagsBlob else { return [] }
            return (try? decoder.decode([String].self, from: blob)) ?? []
        }()
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
                placeNameRomanized: placeNameRomanized,
                rating: rating,
                openingHours: openingHours,
                priceLevel: priceLevel,
                website: website,
                phone: phone,
                photoUrls: photoUrlsBlob.flatMap { try? decoder.decode([String].self, from: $0) }
            ),
            bestTimes: bestTimes,
            durationMinutes: .init(min: durationMin, max: durationMax),
            howTo: howTo,
            realInconveniences: realInconveniences,
            soloScore: soloScore,
            sources: sources,
            confidence: confidence,
            nearbyExperienceIds: nearbyExperienceIds,
            stats: stats,
            status: Experience.Status(rawValue: status) ?? .active,
            createdAt: createdAt,
            updatedAt: updatedAt,
            userTags: userTagsList,
            categoryHighlights: highlights
        )
    }
}
