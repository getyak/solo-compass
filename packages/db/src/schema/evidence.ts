import {
  pgEnum,
  pgTable,
  uuid,
  text,
  timestamp,
  doublePrecision,
  boolean,
  smallint,
  integer,
  jsonb,
  index,
  uniqueIndex,
  primaryKey,
  check,
} from "drizzle-orm/pg-core";
import { sql } from "drizzle-orm";
import { geographyPoint } from "./geo.js";

/** A place is only an evidence anchor. Experience remains the product unit. */
export const placeOperatingStatusEnum = pgEnum("place_operating_status", [
  "unknown",
  "active",
  "temporarily_closed",
  "permanently_closed",
]);

export const artifactRetentionPolicyEnum = pgEnum("artifact_retention_policy", [
  "metadata_only",
  "derived_only",
  "cacheable_content",
  "first_party",
]);

export const observationStateEnum = pgEnum("observation_state", [
  "observed",
  "reported_unknown",
  "not_applicable",
]);

export const resolvedFeatureStatusEnum = pgEnum("resolved_feature_status", [
  "resolved",
  "unknown",
  "conflicted",
  "stale",
]);

export const workSessionOutcomeEnum = pgEnum("work_session_outcome", [
  "completed",
  "partially_completed",
  "abandoned",
]);

export const workSessionFailureReasonEnum = pgEnum("work_session_failure_reason", [
  "place_closed",
  "no_seat",
  "wifi_unreliable",
  "too_noisy",
  "no_power",
  "video_call_not_allowed",
  "long_stay_pressure",
  "minimum_spend",
  "other",
]);

export const routeCompilationStatusEnum = pgEnum("route_compilation_status", [
  "solved",
  "unsatisfiable",
]);

export const places = pgTable(
  "places",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    canonicalName: text("canonical_name").notNull(),
    basicCategory: text("basic_category"),
    location: geographyPoint("location").notNull(),
    operatingStatus: placeOperatingStatusEnum("operating_status").notNull().default("unknown"),
    identityConfidence: doublePrecision("identity_confidence").notNull().default(0.5),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    index("idx_places_location").using("gist", table.location),
    index("idx_places_operating_status").on(table.operatingStatus),
  ],
);

/**
 * Provider identities are aliases, never our primary key. Keeping first/last
 * seen history protects us from provider ID churn and place merges/splits.
 */
export const placeExternalRefs = pgTable(
  "place_external_refs",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    placeId: uuid("place_id")
      .notNull()
      .references(() => places.id, { onDelete: "cascade" }),
    provider: text("provider").notNull(),
    externalId: text("external_id").notNull(),
    firstSeenAt: timestamp("first_seen_at", { withTimezone: true }).notNull().defaultNow(),
    lastSeenAt: timestamp("last_seen_at", { withTimezone: true }).notNull().defaultNow(),
    retiredAt: timestamp("retired_at", { withTimezone: true }),
    metadata: jsonb("metadata"),
  },
  (table) => [
    uniqueIndex("uq_place_external_refs_provider_id").on(table.provider, table.externalId),
    index("idx_place_external_refs_place_provider").on(table.placeId, table.provider),
  ],
);

/**
 * Metadata for fetched material. Restricted providers can use derived_only or
 * metadata_only without persisting their raw copyrighted response.
 */
export const sourceArtifacts = pgTable(
  "source_artifacts",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    provider: text("provider").notNull(),
    externalRef: text("external_ref").notNull(),
    sourceUrl: text("source_url"),
    contentHash: text("content_hash").notNull(),
    licenseCode: text("license_code"),
    retentionPolicy: artifactRetentionPolicyEnum("retention_policy").notNull(),
    rawStorageKey: text("raw_storage_key"),
    retrievedAt: timestamp("retrieved_at", { withTimezone: true }).notNull(),
    sourceObservedAt: timestamp("source_observed_at", { withTimezone: true }),
    expiresAt: timestamp("expires_at", { withTimezone: true }),
    metadata: jsonb("metadata"),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    uniqueIndex("uq_source_artifacts_version").on(
      table.provider,
      table.externalRef,
      table.contentHash,
    ),
    index("idx_source_artifacts_expiry").on(table.provider, table.expiresAt),
  ],
);

/** Append-only assertions. Resolvers may supersede conclusions, never evidence. */
export const placeObservations = pgTable(
  "place_observations",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    placeId: uuid("place_id")
      .notNull()
      .references(() => places.id, { onDelete: "cascade" }),
    artifactId: uuid("artifact_id").references(() => sourceArtifacts.id, {
      onDelete: "set null",
    }),
    featureKey: text("feature_key").notNull(),
    state: observationStateEnum("state").notNull().default("observed"),
    value: jsonb("value"),
    confidence: doublePrecision("confidence").notNull(),
    sourceWeight: doublePrecision("source_weight").notNull().default(1),
    independenceKey: text("independence_key").notNull(),
    timeScope: jsonb("time_scope"),
    observedAt: timestamp("observed_at", { withTimezone: true }).notNull(),
    expiresAt: timestamp("expires_at", { withTimezone: true }),
    extractorVersion: text("extractor_version").notNull(),
    dedupeKey: text("dedupe_key").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    uniqueIndex("uq_place_observations_dedupe_key").on(table.dedupeKey),
    index("idx_place_observations_feature_time").on(
      table.placeId,
      table.featureKey,
      table.observedAt,
    ),
    index("idx_place_observations_artifact").on(table.artifactId),
  ],
);

/** Fast serving projection derived entirely from place_observations. */
export const resolvedPlaceFeatures = pgTable(
  "resolved_place_features",
  {
    placeId: uuid("place_id")
      .notNull()
      .references(() => places.id, { onDelete: "cascade" }),
    featureKey: text("feature_key").notNull(),
    value: jsonb("value"),
    status: resolvedFeatureStatusEnum("status").notNull(),
    confidence: doublePrecision("confidence").notNull(),
    latestObservedAt: timestamp("latest_observed_at", { withTimezone: true }),
    freshUntil: timestamp("fresh_until", { withTimezone: true }),
    supportingObservationIds: uuid("supporting_observation_ids")
      .array()
      .notNull()
      .default(sql`'{}'::uuid[]`),
    conflictingObservationIds: uuid("conflicting_observation_ids")
      .array()
      .notNull()
      .default(sql`'{}'::uuid[]`),
    conflictDetails: jsonb("conflict_details"),
    resolverVersion: text("resolver_version").notNull(),
    resolutionFingerprint: text("resolution_fingerprint").notNull(),
    resolvedAt: timestamp("resolved_at", { withTimezone: true }).notNull(),
  },
  (table) => [
    primaryKey({ columns: [table.placeId, table.featureKey] }),
    index("idx_resolved_place_features_status_freshness").on(table.status, table.freshUntil),
  ],
);

/** Links the user-facing Experience to its evidence anchor without redefining it as a Place. */
export const experiencePlaceLinks = pgTable(
  "experience_place_links",
  {
    experienceId: text("experience_id").primaryKey(),
    placeId: uuid("place_id")
      .notNull()
      .references(() => places.id, { onDelete: "cascade" }),
    confidence: doublePrecision("confidence").notNull().default(1),
    method: text("method").notNull(),
    linkedAt: timestamp("linked_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [index("idx_experience_place_links_place").on(table.placeId)],
);

/**
 * First-party visit outcome. Exact records remain user-scoped; only derived,
 * source-anonymous feature observations feed the shared resolver.
 */
export const workSessions = pgTable(
  "work_sessions",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: uuid("user_id").notNull(),
    experienceId: text("experience_id").notNull(),
    placeId: uuid("place_id")
      .notNull()
      .references(() => places.id, { onDelete: "cascade" }),
    plannedTaskKind: text("planned_task_kind").notNull(),
    startedAt: timestamp("started_at", { withTimezone: true }).notNull(),
    endedAt: timestamp("ended_at", { withTimezone: true }).notNull(),
    outcome: workSessionOutcomeEnum("outcome").notNull(),
    failureReason: workSessionFailureReasonEnum("failure_reason"),
    placeWasOpen: boolean("place_was_open"),
    wifiReliability: smallint("wifi_reliability"),
    noiseLevel: smallint("noise_level"),
    powerAvailable: boolean("power_available"),
    videoCallWorked: boolean("video_call_worked"),
    longStayAccepted: boolean("long_stay_accepted"),
    minimumSpendAmount: doublePrecision("minimum_spend_amount"),
    minimumSpendCurrency: text("minimum_spend_currency"),
    idempotencyKey: text("idempotency_key").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    uniqueIndex("uq_work_sessions_user_idempotency").on(table.userId, table.idempotencyKey),
    index("idx_work_sessions_user_time").on(table.userId, table.endedAt),
    index("idx_work_sessions_place_time").on(table.placeId, table.endedAt),
    index("idx_work_sessions_experience_time").on(table.experienceId, table.endedAt),
    check(
      "work_sessions_time_check",
      sql`${table.endedAt} >= ${table.startedAt} AND ${table.endedAt} <= ${table.startedAt} + interval '24 hours'`,
    ),
    check(
      "work_sessions_wifi_check",
      sql`${table.wifiReliability} IS NULL OR ${table.wifiReliability} BETWEEN 1 AND 5`,
    ),
    check(
      "work_sessions_noise_check",
      sql`${table.noiseLevel} IS NULL OR ${table.noiseLevel} BETWEEN 1 AND 5`,
    ),
    check(
      "work_sessions_spend_check",
      sql`(${table.minimumSpendAmount} IS NULL AND ${table.minimumSpendCurrency} IS NULL) OR (${table.minimumSpendAmount} >= 0 AND ${table.minimumSpendCurrency} ~ '^[A-Z]{3}$')`,
    ),
  ],
);

/**
 * User-scoped cache of deterministic route compiler output. The cache key is
 * derived from both the requested intent and the materialized evidence input,
 * so a newly resolved fact naturally causes a miss without mutating history.
 */
export const routeCompilations = pgTable(
  "route_compilations",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: uuid("user_id").notNull(),
    cacheKey: text("cache_key").notNull(),
    requestFingerprint: text("request_fingerprint").notNull(),
    inputFingerprint: text("input_fingerprint").notNull(),
    status: routeCompilationStatusEnum("status").notNull(),
    planPayload: jsonb("plan_payload").notNull(),
    expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    uniqueIndex("uq_route_compilations_user_cache").on(table.userId, table.cacheKey),
    index("idx_route_compilations_expiry").on(table.expiresAt),
    index("idx_route_compilations_user_updated").on(table.userId, table.updatedAt),
  ],
);

/** Atomic hourly quota buckets protecting network-backed route compilation. */
export const routeCompileQuotas = pgTable(
  "route_compile_quotas",
  {
    userId: uuid("user_id").notNull(),
    bucketStart: timestamp("bucket_start", { withTimezone: true }).notNull(),
    attempts: integer("attempts").notNull().default(0),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    primaryKey({ columns: [table.userId, table.bucketStart] }),
    check("route_compile_quotas_attempts_check", sql`${table.attempts} >= 0`),
    index("idx_route_compile_quotas_expiry").on(table.bucketStart),
  ],
);
