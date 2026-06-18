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
            RouteRecord.self,
            ConversationRecord.self,
            WeatherCacheRecord.self,
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
            RouteRecord.self,
            ConversationRecord.self,
            WeatherCacheRecord.self,
        ]
    }
}

/// Schema v1.2 — adds the optional `ExperienceRecord.photoUrlsBlob` column
/// for user-created places. Like v1.1, this is a *lightweight* migration: the
/// new column is `Data?`, so existing rows migrate with NULL and no data is
/// rewritten. `asValue` treats a nil blob as `nil` photoUrls.
// swiftlint:disable:next type_name
public enum SoloCompassSchemaV1_2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { .init(1, 2, 0) }

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
            RouteRecord.self,
            ConversationRecord.self,
            WeatherCacheRecord.self,
            // Chat history (saved conversations). New @Model tables are an
            // additive, lightweight migration — existing stores just gain two
            // empty tables, no data is rewritten.
            ChatSessionRecord.self,
            ChatMessageRecord.self,
        ]
    }
}

/// Schema v1.3 — adds the friends/social graph tables `FriendRequestRecord`
/// and `FriendshipRecord` (FRD-003). Like the chat-history tables in v1.2,
/// adding new @Model tables is an additive, lightweight migration — existing
/// stores just gain two empty tables, no data is rewritten.
// swiftlint:disable:next type_name
public enum SoloCompassSchemaV1_3: VersionedSchema {
    public static var versionIdentifier: Schema.Version { .init(1, 3, 0) }

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
            RouteRecord.self,
            ConversationRecord.self,
            WeatherCacheRecord.self,
            ChatSessionRecord.self,
            ChatMessageRecord.self,
            // Friends & social graph (FRD-003). Additive lightweight migration.
            FriendRequestRecord.self,
            FriendshipRecord.self,
        ]
    }
}

/// Schema v1.4 — relaxes `ConversationRecord.requestId` from a required column
/// to an optional one so `friendDirect` conversations (US-011), which have no
/// backing CompanionRequest, can persist with a null `request_id`. Dropping a
/// NOT NULL constraint is a lightweight migration: existing rows keep their
/// value, no data is rewritten. The model set is identical to v1.3.
// swiftlint:disable:next type_name
public enum SoloCompassSchemaV1_4: VersionedSchema {
    public static var versionIdentifier: Schema.Version { .init(1, 4, 0) }

    public static var models: [any PersistentModel.Type] {
        SoloCompassSchemaV1_3.models
    }
}

/// Schema v1.5 — adds the optional `ExperienceRecord.categoryHighlightsBlob`
/// column carrying category-specific scannable facts (Wi-Fi for cafés,
/// signature dish for food, best light for sights). Like v1.2's photoUrls, the
/// new column is `Data?`, so existing rows migrate with NULL and no data is
/// rewritten. `asValue` treats a nil blob as `nil` highlights. The model set is
/// identical to v1.4 — only the column is new.
// swiftlint:disable:next type_name
public enum SoloCompassSchemaV1_5: VersionedSchema {
    public static var versionIdentifier: Schema.Version { .init(1, 5, 0) }

    public static var models: [any PersistentModel.Type] {
        SoloCompassSchemaV1_4.models
    }
}

/// Schema v1.6 — adds the traveler co-build tables `TravelerNoteRecord` and
/// `PlaceCorrectionRecord` (per-experience notes + pending field corrections).
/// Like the chat-history (v1.2) and friends (v1.3) tables, adding new @Model
/// tables is an additive, lightweight migration — existing stores just gain two
/// empty tables, no data is rewritten.
// swiftlint:disable:next type_name
public enum SoloCompassSchemaV1_6: VersionedSchema {
    public static var versionIdentifier: Schema.Version { .init(1, 6, 0) }

    public static var models: [any PersistentModel.Type] {
        SoloCompassSchemaV1_5.models + [
            TravelerNoteRecord.self,
            PlaceCorrectionRecord.self,
        ]
    }
}

/// Migration plan stitching v1.0 → v1.1 → … → v1.6. Each change is additive (an
/// optional `Data?` column, new @Model tables) or a NOT NULL relaxation, so every
/// hop is a lightweight migration.
public enum SoloCompassMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [
            SoloCompassSchemaV1.self,
            SoloCompassSchemaV1_1.self,
            SoloCompassSchemaV1_2.self,
            SoloCompassSchemaV1_3.self,
            SoloCompassSchemaV1_4.self,
            SoloCompassSchemaV1_5.self,
            SoloCompassSchemaV1_6.self,
        ]
    }

    public static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: SoloCompassSchemaV1.self,
                toVersion: SoloCompassSchemaV1_1.self
            ),
            .lightweight(
                fromVersion: SoloCompassSchemaV1_1.self,
                toVersion: SoloCompassSchemaV1_2.self
            ),
            .lightweight(
                fromVersion: SoloCompassSchemaV1_2.self,
                toVersion: SoloCompassSchemaV1_3.self
            ),
            .lightweight(
                fromVersion: SoloCompassSchemaV1_3.self,
                toVersion: SoloCompassSchemaV1_4.self
            ),
            .lightweight(
                fromVersion: SoloCompassSchemaV1_4.self,
                toVersion: SoloCompassSchemaV1_5.self
            ),
            .lightweight(
                fromVersion: SoloCompassSchemaV1_5.self,
                toVersion: SoloCompassSchemaV1_6.self
            ),
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
            // Every hop in `SoloCompassMigrationPlan` so far has been either
            // a new optional `Data?` column or an additive @Model table,
            // which SwiftData handles as an implicit lightweight migration.
            // Declaring `.lightweight(from:to:)` explicitly while both
            // versions register the same in-memory model classes trips
            // `NSLightweightMigrationStage` at boot, so the plan is kept
            // only as a historical record of which versions have shipped.
            //
            // *** DANGER, future devs: ***
            //
            // The moment you introduce a non-lightweight migration step
            // (column rename, type change, table split, NOT NULL→required
            // promotion), this implicit-only path will silently drop or
            // corrupt that change because SwiftData never sees the explicit
            // stage. Before adding a non-lightweight step you MUST:
            //   1. Pass `migrationPlan: SoloCompassMigrationPlan.self` here
            //   2. Add a `.custom(from:to:willMigrate:didMigrate:)` stage
            //   3. Write an XCTest that opens a copy of a real prior-version
            //      sqlite fixture under `Tests/Fixtures/` and asserts the
            //      migrated values — see audit task H13 in the audit log.
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
                RouteRecord.self,
                ConversationRecord.self,
                WeatherCacheRecord.self,
                ChatSessionRecord.self,
                ChatMessageRecord.self,
                FriendRequestRecord.self,
                FriendshipRecord.self,
                TravelerNoteRecord.self,
                PlaceCorrectionRecord.self,
                configurations: config
            )
        } catch {
            // Disk-full / sandbox / corrupt-store cases used to fatalError
            // here. For Beta we fall back to an in-memory container so the
            // app stays launchable; the user just sees a clean state.
            // Sentry receives both the original error and the fallback
            // breadcrumb so the on-call has the full chain.
            PersistenceLog.recordDecodeFailure(
                PersistenceCodecError(
                    context: "SoloCompassModelContainer.shared.diskInit",
                    recordId: "ModelContainer",
                    underlying: error
                )
            )
            return makeInMemory()
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
                RouteRecord.self,
                ConversationRecord.self,
                WeatherCacheRecord.self,
                ChatSessionRecord.self,
                ChatMessageRecord.self,
                FriendRequestRecord.self,
                FriendshipRecord.self,
                TravelerNoteRecord.self,
                PlaceCorrectionRecord.self,
                configurations: config
            )
        } catch {
            // In-memory container init should never fail in practice. If it
            // does, we have no usable fallback — surface a clear error to
            // Sentry and re-throw via fatalError as a last resort.
            PersistenceLog.recordDecodeFailure(
                PersistenceCodecError(
                    context: "SoloCompassModelContainer.makeInMemory",
                    recordId: "InMemoryContainer",
                    underlying: error
                )
            )
            fatalError("Failed to initialize in-memory SoloCompass container: \(error)")
        }
    }
}
