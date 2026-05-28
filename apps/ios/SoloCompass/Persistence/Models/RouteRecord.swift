import Foundation
import SwiftData

/// SwiftData representation of a `Route`.
///
/// Strategy mirrors `ItineraryRecord`: scalar fields stored natively;
/// array fields (`experienceIds`, `tags`, and the verification's `walkedBy`)
/// stored as JSON-encoded `Data` blobs. The `RouteVerification` struct is
/// flattened into scalar columns (`verificationStatus`, `walkedByCount`,
/// `walkedByBlob`) so the verification status is queryable without decoding
/// a blob. `RouteCompanion` is still a placeholder in US-013, so it is
/// stored as an optional JSON blob to forward-compat without a schema bump.
@Model
public final class RouteRecord {
    @Attribute(.unique) public var id: String

    public var title: String
    public var summary: String
    public var cityCode: String
    public var region: String
    public var estimatedDuration: Int
    public var distanceMeters: Int
    /// Raw value of `Pace`.
    public var pace: String
    /// Raw value of `RouteSource`.
    public var source: String
    public var authorId: String?
    public var bestStartHour: Double?
    public var bestNow: Bool
    /// Raw value of `VerificationStatus`.
    public var verificationStatus: String
    public var walkedByCount: Int

    /// JSON-encoded `[String]`.
    public var experienceIdsBlob: Data
    /// JSON-encoded `[String]`.
    public var walkedByBlob: Data
    /// JSON-encoded `[String]`.
    public var tagsBlob: Data
    /// JSON-encoded `RouteCompanion?` — nil when no companion attached.
    public var companionBlob: Data?

    public init(
        id: String,
        title: String,
        summary: String,
        cityCode: String,
        region: String,
        estimatedDuration: Int,
        distanceMeters: Int,
        pace: String,
        source: String,
        authorId: String?,
        bestStartHour: Double?,
        bestNow: Bool,
        verificationStatus: String,
        walkedByCount: Int,
        experienceIdsBlob: Data,
        walkedByBlob: Data,
        tagsBlob: Data,
        companionBlob: Data?
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.cityCode = cityCode
        self.region = region
        self.estimatedDuration = estimatedDuration
        self.distanceMeters = distanceMeters
        self.pace = pace
        self.source = source
        self.authorId = authorId
        self.bestStartHour = bestStartHour
        self.bestNow = bestNow
        self.verificationStatus = verificationStatus
        self.walkedByCount = walkedByCount
        self.experienceIdsBlob = experienceIdsBlob
        self.walkedByBlob = walkedByBlob
        self.tagsBlob = tagsBlob
        self.companionBlob = companionBlob
    }
}

// MARK: - Two-way mapping

extension RouteRecord {
    public static func fromValue(_ route: Route) -> RouteRecord {
        let encoder = JSONEncoder()
        let experienceIdsBlob: Data
        let walkedByBlob: Data
        let tagsBlob: Data
        let companionBlob: Data?
        do {
            experienceIdsBlob = try encoder.encode(route.experienceIds)
            walkedByBlob = try encoder.encode(route.verification.walkedBy)
            tagsBlob = try encoder.encode(route.tags)
            if let companion = route.companion {
                companionBlob = try encoder.encode(companion)
            } else {
                companionBlob = nil
            }
        } catch {
            fatalError("Failed to encode Route \(route.id.rawValue) for persistence: \(error)")
        }
        return RouteRecord(
            id: route.id.rawValue,
            title: route.title,
            summary: route.summary,
            cityCode: route.cityCode,
            region: route.region,
            estimatedDuration: route.estimatedDuration,
            distanceMeters: route.distanceMeters,
            pace: route.pace.rawValue,
            source: route.source.rawValue,
            authorId: route.authorId,
            bestStartHour: route.bestStartHour,
            bestNow: route.bestNow,
            verificationStatus: route.verification.status.rawValue,
            walkedByCount: route.verification.walkedByCount,
            experienceIdsBlob: experienceIdsBlob,
            walkedByBlob: walkedByBlob,
            tagsBlob: tagsBlob,
            companionBlob: companionBlob
        )
    }

    public var asValue: Route {
        let decoder = JSONDecoder()
        let experienceIds: [String]
        let walkedBy: [String]
        let tags: [String]
        let companion: RouteCompanion?
        do {
            experienceIds = try decoder.decode([String].self, from: experienceIdsBlob)
            walkedBy = try decoder.decode([String].self, from: walkedByBlob)
            tags = try decoder.decode([String].self, from: tagsBlob)
            if let blob = companionBlob {
                companion = try decoder.decode(RouteCompanion.self, from: blob)
            } else {
                companion = nil
            }
        } catch {
            fatalError("Failed to decode blobs for RouteRecord \(id): \(error)")
        }
        let paceValue = Pace(rawValue: pace) ?? .standard
        let sourceValue = RouteSource(rawValue: source) ?? .editorial
        let statusValue = VerificationStatus(rawValue: verificationStatus) ?? .proposed
        return Route(
            id: RouteId(rawValue: id),
            title: title,
            summary: summary,
            experienceIds: experienceIds,
            cityCode: cityCode,
            region: region,
            estimatedDuration: estimatedDuration,
            distanceMeters: distanceMeters,
            pace: paceValue,
            tags: tags,
            source: sourceValue,
            authorId: authorId,
            bestStartHour: bestStartHour,
            bestNow: bestNow,
            verification: RouteVerification(
                status: statusValue,
                walkedByCount: walkedByCount,
                walkedBy: walkedBy
            ),
            companion: companion
        )
    }
}
