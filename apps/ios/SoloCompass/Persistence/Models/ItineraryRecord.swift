import Foundation
import SwiftData

/// SwiftData representation of an `Itinerary`.
///
/// Strategy: all scalar fields stored natively. `experienceIds` is a
/// JSON-encoded `[String]` blob — arrays of scalars are not directly
/// queryable anyway, so a blob avoids a relationship while staying flat.
@Model
public final class ItineraryRecord {
    @Attribute(.unique) public var id: String

    public var ownerId: String
    public var title: String
    public var cityCode: String
    /// ISO 8601 date string (YYYY-MM-DD).
    public var startDate: String
    /// ISO 8601 date string (YYYY-MM-DD).
    public var endDate: String
    /// JSON-encoded `[String]`.
    public var experienceIdsBlob: Data
    public var note: String?
    /// Default false per US-003 acceptance criteria.
    public var openToCompanions: Bool
    /// ISO 8601 UTC timestamp.
    public var createdAt: String
    /// ISO 8601 UTC timestamp.
    public var updatedAt: String

    public init(
        id: String,
        ownerId: String,
        title: String,
        cityCode: String,
        startDate: String,
        endDate: String,
        experienceIdsBlob: Data,
        note: String?,
        openToCompanions: Bool,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.ownerId = ownerId
        self.title = title
        self.cityCode = cityCode
        self.startDate = startDate
        self.endDate = endDate
        self.experienceIdsBlob = experienceIdsBlob
        self.note = note
        self.openToCompanions = openToCompanions
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Two-way mapping

extension ItineraryRecord {
    public convenience init(from itinerary: Itinerary) {
        // Encoding `[String]` cannot realistically fail. We keep the
        // do/catch as a safety net: a malformed value persists as an
        // empty blob plus Sentry breadcrumb instead of crashing.
        let blob: Data
        if let encoded = try? JSONEncoder().encode(itinerary.experienceIds) {
            blob = encoded
        } else {
            PersistenceLog.recordDecodeFailure(
                PersistenceCodecError(
                    context: "ItineraryRecord.init(from:)",
                    recordId: itinerary.id.rawValue,
                    underlying: NSError(
                        domain: "PersistenceCodec",
                        code: -5,
                        userInfo: [NSLocalizedDescriptionKey: "experienceIds encode failed; persisted as []"]
                    )
                )
            )
            blob = Data("[]".utf8)
        }
        self.init(
            id: itinerary.id.rawValue,
            ownerId: itinerary.ownerId,
            title: itinerary.title,
            cityCode: itinerary.cityCode,
            startDate: itinerary.startDate,
            endDate: itinerary.endDate,
            experienceIdsBlob: blob,
            note: itinerary.note,
            openToCompanions: itinerary.openToCompanions,
            createdAt: itinerary.createdAt,
            updatedAt: itinerary.updatedAt
        )
    }

    public var asValue: Itinerary {
        // Schema-evolution safety: an unreadable experienceIds blob used
        // to crash the app on launch. We now degrade to `[]` and log.
        let ids: [String] = decodeOrLog([String].self, from: experienceIdsBlob, field: "experienceIds")
        return Itinerary(
            id: ItineraryId(rawValue: id),
            ownerId: ownerId,
            title: title,
            cityCode: cityCode,
            startDate: startDate,
            endDate: endDate,
            experienceIds: ids,
            note: note,
            openToCompanions: openToCompanions,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
