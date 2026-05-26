import Foundation
import SwiftData

/// Schema v2 — adds `ExperienceRecord.userTagsBlob` (optional `Data` blob of
/// JSON-encoded `[String]`) so users can layer free-form labels on top of the
/// fixed `ExperienceCategory` enum (see PRD US-005).
///
/// The model classes themselves live at module scope so the two schema versions
/// can share the same Swift types — v1 simply omits `userTagsBlob` while v2
/// includes it. SwiftData treats this as a lightweight addition (new optional
/// column), and the v1→v2 stage in `SoloCompassMigrationPlan` backfills
/// existing rows so `userTags` reads back as `[]` rather than `nil`.
public enum SoloCompassSchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { .init(2, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            ExperienceRecord.self,
            UserCompletionRecord.self,
            UserFavoriteRecord.self,
            MicroSurveyRecord.self,
            PendingCheckInRecord.self,
            ExploreCacheRecord.self,
            AISynthesisCacheRecord.self,
            DiscoveredCityRecord.self,
            RecentExploreRegion.self,
            AIUsageRecord.self,
            PendingSyncRecord.self,
        ]
    }
}

/// Migration plan covering every shipped schema version. Each new schema
/// version appends a `MigrationStage` here.
public enum SoloCompassMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SoloCompassSchemaV1.self, SoloCompassSchemaV2.self]
    }

    public static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    /// v1→v2 — adds `ExperienceRecord.userTagsBlob`. Existing rows are migrated
    /// in-place: any record whose `userTagsBlob` is still `nil` after the
    /// lightweight column add gets an encoded empty array so the value layer
    /// reads `userTags == []` (matches the "absent ⇒ []" contract in TS).
    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: SoloCompassSchemaV1.self,
        toVersion: SoloCompassSchemaV2.self,
        willMigrate: nil,
        didMigrate: { context in
            let emptyTagsBlob = try JSONEncoder.iso8601Encoder.encode([String]())
            let descriptor = FetchDescriptor<ExperienceRecord>()
            let records = try context.fetch(descriptor)
            for record in records where record.userTagsBlob == nil {
                record.userTagsBlob = emptyTagsBlob
            }
            try context.save()
        }
    )
}
