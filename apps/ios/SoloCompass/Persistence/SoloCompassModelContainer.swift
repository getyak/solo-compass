import Foundation
import SwiftData

/// Versioned SwiftData schema for Solo Compass.
///
/// Wrapping the schema in a `VersionedSchema` from day 1 means every future
/// breaking change can be migrated rather than crashing at boot. v1 is the
/// schema we ship with; v2+ will be added as new enums conforming to
/// `VersionedSchema` next to this one and stitched together by a
/// `SchemaMigrationPlan`.
public enum SoloCompassSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { .init(1, 0, 0) }

    /// Models registered in v1.0 of the schema. Adding a new model in a
    /// later release means a new VersionedSchema (v2) + a SchemaMigrationPlan.
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
            let config = ModelConfiguration(
                "SoloCompassStore",
                schema: Schema(versionedSchema: SoloCompassSchemaV1.self),
                isStoredInMemoryOnly: false
            )
            return try ModelContainer(
                for: Schema(versionedSchema: SoloCompassSchemaV1.self),
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
                schema: Schema(versionedSchema: SoloCompassSchemaV1.self),
                isStoredInMemoryOnly: true
            )
            return try ModelContainer(
                for: Schema(versionedSchema: SoloCompassSchemaV1.self),
                configurations: config
            )
        } catch {
            fatalError("Failed to initialize in-memory SoloCompass container: \(error)")
        }
    }
}
