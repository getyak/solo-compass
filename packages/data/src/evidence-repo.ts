import type { SupabaseClient } from "@supabase/supabase-js";
import type {
  ArtifactRetentionPolicy,
  Database,
  ExperiencePlaceLinkRow,
  PlaceObservationRow,
  PlaceRow,
  ResolvedPlaceFeatureRow,
  SourceArtifactRow,
} from "./db";
import {
  type EvidenceObservation,
  type FeatureKey,
  type JsonValue,
  type ObservationState,
  type ResolvedPlaceFeature,
} from "./evidence";
import { resolveFeature } from "./feature-resolver";

export interface UpsertPlaceIdentityInput {
  readonly provider: string;
  readonly externalId: string;
  readonly canonicalName: string;
  /** GeoJSON order. */
  readonly coordinates: readonly [longitude: number, latitude: number];
  readonly basicCategory?: string;
  readonly identityConfidence?: number;
  readonly metadata?: JsonValue;
}

export interface RegisterSourceArtifactInput {
  readonly provider: string;
  readonly externalRef: string;
  readonly sourceUrl?: string;
  readonly contentHash: string;
  readonly licenseCode?: string;
  readonly retentionPolicy: ArtifactRetentionPolicy;
  readonly rawStorageKey?: string;
  readonly retrievedAt: string;
  readonly sourceObservedAt?: string;
  readonly expiresAt?: string;
  readonly metadata?: JsonValue;
}

export interface AppendObservationInput {
  readonly placeId: string;
  readonly artifactId?: string;
  readonly featureKey: FeatureKey;
  readonly state: ObservationState;
  readonly value?: JsonValue;
  readonly confidence: number;
  readonly sourceWeight: number;
  readonly independenceKey: string;
  readonly timeScope?: JsonValue;
  readonly observedAt: string;
  readonly expiresAt?: string;
  readonly extractorVersion: string;
  readonly dedupeKey: string;
}

export interface ExperienceEvidenceSnapshot {
  readonly placeId: string;
  readonly features: readonly ResolvedPlaceFeatureRow[];
}

/** Typed persistence boundary for evidence ingestion and materialization. */
export class EvidenceRepo {
  constructor(private readonly client: SupabaseClient<Database>) {}

  async upsertPlaceIdentity(input: UpsertPlaceIdentityInput): Promise<PlaceRow> {
    const [longitude, latitude] = input.coordinates;
    assertCoordinate(longitude, latitude);
    const identityConfidence = input.identityConfidence ?? 0.5;
    assertProbability(identityConfidence, "identityConfidence");
    const { data, error } = await this.client.rpc("upsert_place_identity", {
      p_provider: requiredText(input.provider, "provider"),
      p_external_id: requiredText(input.externalId, "externalId"),
      p_canonical_name: requiredText(input.canonicalName, "canonicalName"),
      p_longitude: longitude,
      p_latitude: latitude,
      p_basic_category: input.basicCategory ?? null,
      p_identity_confidence: identityConfidence,
      p_metadata: input.metadata ?? null,
    });
    if (error) throw new Error(`upsertPlaceIdentity failed: ${error.message}`);
    if (!data) throw new Error("upsertPlaceIdentity failed: database returned no place");
    return data;
  }

  async registerSourceArtifact(input: RegisterSourceArtifactInput): Promise<SourceArtifactRow> {
    if (
      input.rawStorageKey !== undefined &&
      input.retentionPolicy !== "cacheable_content" &&
      input.retentionPolicy !== "first_party"
    ) {
      throw new Error(`${input.retentionPolicy} artifacts cannot retain raw content`);
    }
    assertTimestamp(input.retrievedAt, "retrievedAt");
    if (input.sourceObservedAt) assertTimestamp(input.sourceObservedAt, "sourceObservedAt");
    if (input.expiresAt) assertTimestamp(input.expiresAt, "expiresAt");
    const row: Database["public"]["Tables"]["source_artifacts"]["Insert"] = {
      provider: requiredText(input.provider, "provider"),
      external_ref: requiredText(input.externalRef, "externalRef"),
      source_url: input.sourceUrl ?? null,
      content_hash: requiredText(input.contentHash, "contentHash"),
      license_code: input.licenseCode ?? null,
      retention_policy: input.retentionPolicy,
      raw_storage_key: input.rawStorageKey ?? null,
      retrieved_at: input.retrievedAt,
      source_observed_at: input.sourceObservedAt ?? null,
      expires_at: input.expiresAt ?? null,
      metadata: input.metadata ?? null,
    };
    const { data, error } = await this.client
      .from("source_artifacts")
      .upsert(row, { onConflict: "provider,external_ref,content_hash" })
      .select("*")
      .single();
    if (error) throw new Error(`registerSourceArtifact failed: ${error.message}`);
    return data;
  }

  async attachExternalRef(input: {
    readonly placeId: string;
    readonly provider: string;
    readonly externalId: string;
    readonly metadata?: JsonValue;
    readonly seenAt?: string;
  }): Promise<void> {
    const seenAt = input.seenAt ?? new Date().toISOString();
    assertTimestamp(seenAt, "seenAt");
    const row: Database["public"]["Tables"]["place_external_refs"]["Insert"] = {
      place_id: requiredText(input.placeId, "placeId"),
      provider: requiredText(input.provider, "provider"),
      external_id: requiredText(input.externalId, "externalId"),
      last_seen_at: seenAt,
      metadata: input.metadata ?? null,
    };
    const inserted = await this.client
      .from("place_external_refs")
      .upsert(row, { onConflict: "provider,external_id", ignoreDuplicates: true })
      .select("*")
      .maybeSingle();
    if (inserted.error) throw new Error(`attachExternalRef failed: ${inserted.error.message}`);
    if (inserted.data) return;

    const existing = await this.client
      .from("place_external_refs")
      .select("*")
      .eq("provider", input.provider)
      .eq("external_id", input.externalId)
      .single();
    if (existing.error)
      throw new Error(`attachExternalRef lookup failed: ${existing.error.message}`);
    if (existing.data.place_id !== input.placeId) {
      throw new Error(
        `external identity conflict: ${input.provider}:${input.externalId} already belongs to another place`,
      );
    }
    const updated = await this.client
      .from("place_external_refs")
      .update({
        last_seen_at: seenAt,
        retired_at: null,
        metadata: input.metadata ?? existing.data.metadata,
      })
      .eq("id", existing.data.id);
    if (updated.error) throw new Error(`attachExternalRef update failed: ${updated.error.message}`);
  }

  async appendObservation(input: AppendObservationInput): Promise<PlaceObservationRow> {
    assertProbability(input.confidence, "confidence");
    assertProbability(input.sourceWeight, "sourceWeight");
    assertTimestamp(input.observedAt, "observedAt");
    if (input.expiresAt) assertTimestamp(input.expiresAt, "expiresAt");
    if (input.state === "observed" && input.value === undefined) {
      throw new Error("observed evidence requires a value");
    }
    const row: Database["public"]["Tables"]["place_observations"]["Insert"] = {
      place_id: requiredText(input.placeId, "placeId"),
      artifact_id: input.artifactId ?? null,
      feature_key: requiredText(input.featureKey, "featureKey"),
      state: input.state,
      value: input.value ?? null,
      confidence: input.confidence,
      source_weight: input.sourceWeight,
      independence_key: requiredText(input.independenceKey, "independenceKey"),
      time_scope: input.timeScope ?? null,
      observed_at: input.observedAt,
      expires_at: input.expiresAt ?? null,
      extractor_version: requiredText(input.extractorVersion, "extractorVersion"),
      dedupe_key: requiredText(input.dedupeKey, "dedupeKey"),
    };
    const { data, error } = await this.client
      .from("place_observations")
      .upsert(row, { onConflict: "dedupe_key", ignoreDuplicates: true })
      .select("*")
      .maybeSingle();
    if (error) throw new Error(`appendObservation failed: ${error.message}`);
    if (data) return data;

    const existing = await this.client
      .from("place_observations")
      .select("*")
      .eq("dedupe_key", input.dedupeKey)
      .single();
    if (existing.error)
      throw new Error(`appendObservation lookup failed: ${existing.error.message}`);
    return existing.data;
  }

  async listObservations(placeId: string, featureKey: FeatureKey): Promise<PlaceObservationRow[]> {
    const { data, error } = await this.client
      .from("place_observations")
      .select("*")
      .eq("place_id", placeId)
      .eq("feature_key", featureKey)
      .order("observed_at", { ascending: false });
    if (error) throw new Error(`listObservations failed: ${error.message}`);
    return data ?? [];
  }

  async materializeFeature(
    placeId: string,
    featureKey: FeatureKey,
    now?: string,
  ): Promise<ResolvedPlaceFeature> {
    const rows = await this.listObservations(placeId, featureKey);
    const observations = rows.map(rowToObservation);
    const resolution = resolveFeature({ placeId, featureKey, observations, now });
    const row = resolutionToRow(resolution);
    const { error } = await this.client
      .from("resolved_place_features")
      .upsert(row, { onConflict: "place_id,feature_key" });
    if (error) throw new Error(`materializeFeature failed: ${error.message}`);
    return resolution;
  }

  async getResolvedFeatures(placeId: string): Promise<ResolvedPlaceFeatureRow[]> {
    const { data, error } = await this.client
      .from("resolved_place_features")
      .select("*")
      .eq("place_id", placeId);
    if (error) throw new Error(`getResolvedFeatures failed: ${error.message}`);
    return data ?? [];
  }

  async linkExperience(input: {
    readonly experienceId: string;
    readonly placeId: string;
    readonly confidence: number;
    readonly method: string;
  }): Promise<ExperiencePlaceLinkRow> {
    assertProbability(input.confidence, "confidence");
    const { data, error } = await this.client
      .from("experience_place_links")
      .upsert(
        {
          experience_id: requiredText(input.experienceId, "experienceId"),
          place_id: requiredText(input.placeId, "placeId"),
          confidence: input.confidence,
          method: requiredText(input.method, "method"),
        },
        { onConflict: "experience_id" },
      )
      .select("*")
      .single();
    if (error) throw new Error(`linkExperience failed: ${error.message}`);
    return data;
  }

  async getSnapshotsForExperiences(
    experienceIds: readonly string[],
  ): Promise<ReadonlyMap<string, ExperienceEvidenceSnapshot>> {
    if (experienceIds.length === 0) return new Map();
    const linksResult = await this.client
      .from("experience_place_links")
      .select("*")
      .in("experience_id", [...new Set(experienceIds)]);
    if (linksResult.error) {
      throw new Error(`getFeaturesForExperiences links failed: ${linksResult.error.message}`);
    }
    const links = linksResult.data ?? [];
    if (links.length === 0) return new Map();
    const placeIds = [...new Set(links.map((link) => link.place_id))];
    const featuresResult = await this.client
      .from("resolved_place_features")
      .select("*")
      .in("place_id", placeIds);
    if (featuresResult.error) {
      throw new Error(`getFeaturesForExperiences features failed: ${featuresResult.error.message}`);
    }
    const byPlace = new Map<string, ResolvedPlaceFeatureRow[]>();
    for (const feature of featuresResult.data ?? []) {
      const list = byPlace.get(feature.place_id) ?? [];
      list.push(feature);
      byPlace.set(feature.place_id, list);
    }
    const result = new Map<string, ExperienceEvidenceSnapshot>();
    for (const link of links) {
      result.set(link.experience_id, {
        placeId: link.place_id,
        features: byPlace.get(link.place_id) ?? [],
      });
    }
    return result;
  }
}

function rowToObservation(row: PlaceObservationRow): EvidenceObservation {
  const base = {
    id: row.id,
    placeId: row.place_id,
    featureKey: row.feature_key,
    state: row.state,
    confidence: row.confidence,
    sourceWeight: row.source_weight,
    independenceKey: row.independence_key,
    observedAt: row.observed_at,
    ...(row.expires_at ? { expiresAt: row.expires_at } : {}),
  } as const;
  return row.state === "observed" ? { ...base, value: row.value } : base;
}

function resolutionToRow(resolution: ResolvedPlaceFeature): ResolvedPlaceFeatureRow {
  return {
    place_id: resolution.placeId,
    feature_key: resolution.featureKey,
    value: resolution.value ?? null,
    status: resolution.status,
    confidence: resolution.confidence,
    latest_observed_at: resolution.latestObservedAt ?? null,
    fresh_until: resolution.freshUntil ?? null,
    supporting_observation_ids: [...resolution.supportingObservationIds],
    conflicting_observation_ids: [...resolution.conflictingObservationIds],
    conflict_details: conflictDetailsToJson(resolution),
    resolver_version: resolution.resolverVersion,
    resolution_fingerprint: resolution.resolutionFingerprint,
    resolved_at: resolution.resolvedAt,
  };
}

function conflictDetailsToJson(resolution: ResolvedPlaceFeature): JsonValue {
  if (!resolution.conflictDetails) return null;
  const alternatives: JsonValue[] = resolution.conflictDetails.alternatives.map((alternative) => ({
    value: alternative.value,
    weight: alternative.weight,
    observationIds: [...alternative.observationIds],
  }));
  return { alternatives };
}

function requiredText(value: string, label: string): string {
  const trimmed = value.trim();
  if (!trimmed) throw new Error(`${label} is required`);
  return trimmed;
}

function assertProbability(value: number, label: string): void {
  if (!Number.isFinite(value) || value < 0 || value > 1) {
    throw new Error(`${label} must be between 0 and 1`);
  }
}

function assertCoordinate(longitude: number, latitude: number): void {
  if (
    !Number.isFinite(longitude) ||
    !Number.isFinite(latitude) ||
    longitude < -180 ||
    longitude > 180 ||
    latitude < -90 ||
    latitude > 90
  ) {
    throw new Error("coordinates must be valid WGS-84 [longitude, latitude]");
  }
}

function assertTimestamp(value: string, label: string): void {
  if (!Number.isFinite(Date.parse(value)))
    throw new Error(`${label} must be a valid ISO timestamp`);
}
