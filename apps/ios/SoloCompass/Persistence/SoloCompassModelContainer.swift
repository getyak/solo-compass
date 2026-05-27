import Foundation
import SwiftData

/// Versioned SwiftData schema for Solo Compass.
///
/// Wrapping the schema in a `VersionedSchema` from day 1 means every future
/// breaking change can be migrated rather than crashing at boot. v1.0 was the
/// schema we shipped with originally; v1.1 (US-005) adds the optional
/// `ExperienceRecord.userTagsBlob` column.
public enum SoloCompassSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { .init(1, 0, 0) }

    /// Models registered in v1.0 of the schema. Note: this references the
    /// *current* `ExperienceRecord` class. Because the field added in v1.1
    /// is an optional `Data?`, SwiftData treats the difference between the
    /// on-disk v1.0 store and the in-memory model as a lightweight automatic
    /// migration — the existing rows just get NULL for `userTagsBlob`, which
    /// the value-mapping layer (`ExperienceRecord.asValue`) surfaces as `[]`.
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
            ItineraryRecord.self,
        ]
    }
}

/// Schema v1.1 — adds the optional `ExperienceRecord.userTagsBlob` column
/// (US-005). v1.0 → v1.1 is a *lightweight* migration: the new column is
/// `Data?`, so existing rows migrate with NULL and no data is rewritten.
/// `asValue` treats a nil blob as the empty `[String]`, which satisfies the
/// "userTags = [] for existing rows" acceptance criterion in mapping rather
/// than at the storage layer.
// swiftlint:disable:next type_name
public enum SoloCompassSchemaV1_1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { .init(1, 1, 0) }

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
            ItineraryRecord.self,
        ]
    }
}

/// Migration plan stitching v1.0 → v1.1. The only change is the addition of
/// an optional `Data?` column on `ExperienceRecord`, which is a
/// lightweight migration.
public enum SoloCompassMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SoloCompassSchemaV1.self, SoloCompassSchemaV1_1.self]
    }

    public static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: SoloCompassSchemaV1.self,
                toVersion: SoloCompassSchemaV1_1.self
            )
        ]
    }
}

/// App-wide SwiftData container. Backed by an on-disk SQLite store under
/// the app's Application Support directory. Use `shared` everywhere — the
/// container is a singleton; only `ModelContext` should be instantiated
/// per-actor.
public enum SoloCompassModelContainer {
    public static let shared: ModelContainer = {
        do {
            // Build the container by passing model types directly. The
            // migration plan handles the on-disk v1.0 → v1.1 hop; fresh
            // installs jump straight to the latest versioned schema.
            let config = ModelConfiguration(
                "SoloCompassStore",
                isStoredInMemoryOnly: false
            )
            // Note: we intentionally do *not* pass `migrationPlan:` here.
            // The only on-disk change between v1.0 and v1.1 is a new optional
            // `Data?` column on `ExperienceRecord`, which SwiftData handles
            // as an implicit lightweight migration. `SoloCompassMigrationPlan`
            // exists for the schema-version history record, but the lightweight
            // migration stage isn't usable when both versions register the
            // same in-memory model class — declaring it explicitly trips
            // `NSLightweightMigrationStage` at boot.
            return try ModelContainer(
                for: ExperienceRecord.self,
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
                ItineraryRecord.self,
                configurations: config
            )
        } catch {
            // If we can't open the store at boot the app is unusable; crash
            // loud rather than silently degrading. This is intentional.
            fatalError("Failed to initialize SoloCompass SwiftData container: \(error)")
        }
    }()

    /// In-memory container for tests and previews. Each call returns a
    /// fresh isolated container so tests don't bleed into each other.
    public static func makeInMemory() -> ModelContainer {
        do {
            let config = ModelConfiguration(
                "SoloCompassStoreInMemory",
                isStoredInMemoryOnly: true
            )
            return try ModelContainer(
                for: ExperienceRecord.self,
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
                ItineraryRecord.self,
                configurations: config
            )
        } catch {
            fatalError("Failed to initialize in-memory SoloCompass container: \(error)")
        }
    }
}
