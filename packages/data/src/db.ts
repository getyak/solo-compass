import { createClient } from "@supabase/supabase-js";
import type { Experience, ExperienceId } from "@solo-compass/core";
import type { JsonValue } from "./evidence";

// ─── Database row shapes ────────────────────────────────────────────────────────
// These mirror the SQL schema, not the TS domain types.
// The repository layer translates between the two.

// Row interfaces need `[key: string]: unknown` so they satisfy
// `Record<string, unknown>` as required by @supabase/postgrest-js GenericTable.Row.
// This is a Supabase v2 convention — the index signature doesn't widen the
// known typed fields, it just makes the structural check pass.

export interface ExperienceRow {
  [key: string]: unknown;
  id: string;
  title: string;
  one_liner: string;
  why_it_matters: string;
  category: string;
  // PostGIS geography returned as GeoJSON by Supabase
  location: { type: "Point"; coordinates: [number, number] };
  city_code: string;
  address_hint: string | null;
  place_name_local: string | null;
  place_name_romanized: string | null;
  best_times: unknown;
  duration_min: number;
  duration_max: number;
  how_to: unknown;
  real_inconveniences: unknown;
  solo_score: unknown;
  sources: unknown;
  confidence: unknown;
  nearby_experience_ids: string[];
  completion_count: number;
  average_rating: number;
  last_completed_at: string | null;
  status: string;
  created_at: string;
  updated_at: string;
}

export interface UserRow {
  [key: string]: unknown;
  id: string;
  handle: string;
  created_at: string;
}

export interface CompletionRow {
  [key: string]: unknown;
  id: string;
  user_id: string;
  experience_id: string;
  completed_at: string;
  rating: number | null;
  note: string | null;
}

export interface TrafficPingRow {
  [key: string]: unknown;
  experience_id: string;
  anon_id: string;
  pinged_at: string;
}

export type PlaceOperatingStatus =
  | "unknown"
  | "active"
  | "temporarily_closed"
  | "permanently_closed";
export type ArtifactRetentionPolicy =
  | "metadata_only"
  | "derived_only"
  | "cacheable_content"
  | "first_party";
export type RefreshJobStatus =
  | "queued"
  | "running"
  | "succeeded"
  | "failed"
  | "dead_letter"
  | "cancelled";
export type WorkSessionOutcome = "completed" | "partially_completed" | "abandoned";
export type WorkSessionFailureReason =
  | "place_closed"
  | "no_seat"
  | "wifi_unreliable"
  | "too_noisy"
  | "no_power"
  | "video_call_not_allowed"
  | "long_stay_pressure"
  | "minimum_spend"
  | "other";
export type RouteCompilationStatus = "solved" | "unsatisfiable";

export interface PlaceRow {
  [key: string]: unknown;
  id: string;
  canonical_name: string;
  basic_category: string | null;
  location: { type: "Point"; coordinates: [number, number] };
  operating_status: PlaceOperatingStatus;
  identity_confidence: number;
  created_at: string;
  updated_at: string;
}

export interface PlaceExternalRefRow {
  [key: string]: unknown;
  id: string;
  place_id: string;
  provider: string;
  external_id: string;
  first_seen_at: string;
  last_seen_at: string;
  retired_at: string | null;
  metadata: JsonValue | null;
}

export interface SourceArtifactRow {
  [key: string]: unknown;
  id: string;
  provider: string;
  external_ref: string;
  source_url: string | null;
  content_hash: string;
  license_code: string | null;
  retention_policy: ArtifactRetentionPolicy;
  raw_storage_key: string | null;
  retrieved_at: string;
  source_observed_at: string | null;
  expires_at: string | null;
  metadata: JsonValue | null;
  created_at: string;
}

export interface PlaceObservationRow {
  [key: string]: unknown;
  id: string;
  place_id: string;
  artifact_id: string | null;
  feature_key: string;
  state: "observed" | "reported_unknown" | "not_applicable";
  value: JsonValue | null;
  confidence: number;
  source_weight: number;
  independence_key: string;
  time_scope: JsonValue | null;
  observed_at: string;
  expires_at: string | null;
  extractor_version: string;
  dedupe_key: string;
  created_at: string;
}

export interface ResolvedPlaceFeatureRow {
  [key: string]: unknown;
  place_id: string;
  feature_key: string;
  value: JsonValue | null;
  status: "resolved" | "unknown" | "conflicted" | "stale";
  confidence: number;
  latest_observed_at: string | null;
  fresh_until: string | null;
  supporting_observation_ids: string[];
  conflicting_observation_ids: string[];
  conflict_details: JsonValue | null;
  resolver_version: string;
  resolution_fingerprint: string;
  resolved_at: string;
}

export interface ExperiencePlaceLinkRow {
  [key: string]: unknown;
  experience_id: string;
  place_id: string;
  confidence: number;
  method: string;
  linked_at: string;
}

export interface RefreshJobRow {
  [key: string]: unknown;
  id: string;
  place_id: string | null;
  feature_keys: string[];
  query: JsonValue | null;
  reason:
    | "coverage_gap"
    | "soft_stale"
    | "hard_constraint"
    | "user_report"
    | "source_release"
    | "manual";
  urgency: "background" | "interactive";
  priority: number;
  provider_hint: string | null;
  budget_class: string;
  idempotency_key: string;
  status: RefreshJobStatus;
  demand_score: number;
  decision_impact: number;
  uncertainty: number;
  staleness: number;
  estimated_cost: number;
  not_before: string;
  claimed_by: string | null;
  claimed_at: string | null;
  lease_expires_at: string | null;
  attempts: number;
  max_attempts: number;
  last_error: string | null;
  result: JsonValue | null;
  created_at: string;
  updated_at: string;
  completed_at: string | null;
}

export interface WorkSessionRow {
  [key: string]: unknown;
  id: string;
  user_id: string;
  experience_id: string;
  place_id: string;
  planned_task_kind: string;
  started_at: string;
  ended_at: string;
  outcome: WorkSessionOutcome;
  failure_reason: WorkSessionFailureReason | null;
  place_was_open: boolean | null;
  wifi_reliability: number | null;
  noise_level: number | null;
  power_available: boolean | null;
  video_call_worked: boolean | null;
  long_stay_accepted: boolean | null;
  minimum_spend_amount: number | null;
  minimum_spend_currency: string | null;
  idempotency_key: string;
  created_at: string;
}

export interface RouteCompilationRow {
  [key: string]: unknown;
  id: string;
  user_id: string;
  cache_key: string;
  request_fingerprint: string;
  input_fingerprint: string;
  status: RouteCompilationStatus;
  plan_payload: JsonValue;
  expires_at: string;
  created_at: string;
  updated_at: string;
}

export interface RouteCompileQuotaRow {
  [key: string]: unknown;
  user_id: string;
  bucket_start: string;
  attempts: number;
  updated_at: string;
}

export interface Database {
  public: {
    Tables: {
      experiences: {
        Row: ExperienceRow;
        Insert: Omit<ExperienceRow, "created_at" | "updated_at"> & {
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<ExperienceRow>;
        Relationships: never[];
      };
      users: {
        Row: UserRow;
        Insert: Omit<UserRow, "id" | "created_at"> & { id?: string; created_at?: string };
        Update: Partial<UserRow>;
        Relationships: never[];
      };
      completions: {
        Row: CompletionRow;
        Insert: Omit<CompletionRow, "id" | "completed_at"> & {
          id?: string;
          completed_at?: string;
        };
        Update: Partial<CompletionRow>;
        Relationships: never[];
      };
      traffic_pings: {
        Row: TrafficPingRow;
        Insert: Omit<TrafficPingRow, "pinged_at"> & { pinged_at?: string };
        Update: Partial<TrafficPingRow>;
        Relationships: never[];
      };
      places: {
        Row: PlaceRow;
        Insert: Omit<PlaceRow, "id" | "created_at" | "updated_at" | "location"> & {
          id?: string;
          location: string | PlaceRow["location"];
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Omit<PlaceRow, "location">> & {
          location?: string | PlaceRow["location"];
        };
        Relationships: never[];
      };
      place_external_refs: {
        Row: PlaceExternalRefRow;
        Insert: Omit<
          PlaceExternalRefRow,
          "id" | "first_seen_at" | "last_seen_at" | "retired_at"
        > & {
          id?: string;
          first_seen_at?: string;
          last_seen_at?: string;
          retired_at?: string | null;
        };
        Update: Partial<PlaceExternalRefRow>;
        Relationships: never[];
      };
      source_artifacts: {
        Row: SourceArtifactRow;
        Insert: Omit<SourceArtifactRow, "id" | "created_at"> & {
          id?: string;
          created_at?: string;
        };
        Update: Partial<SourceArtifactRow>;
        Relationships: never[];
      };
      place_observations: {
        Row: PlaceObservationRow;
        Insert: Omit<PlaceObservationRow, "id" | "created_at"> & {
          id?: string;
          created_at?: string;
        };
        Update: Partial<PlaceObservationRow>;
        Relationships: never[];
      };
      resolved_place_features: {
        Row: ResolvedPlaceFeatureRow;
        Insert: ResolvedPlaceFeatureRow;
        Update: Partial<ResolvedPlaceFeatureRow>;
        Relationships: never[];
      };
      experience_place_links: {
        Row: ExperiencePlaceLinkRow;
        Insert: Omit<ExperiencePlaceLinkRow, "linked_at"> & { linked_at?: string };
        Update: Partial<ExperiencePlaceLinkRow>;
        Relationships: never[];
      };
      refresh_jobs: {
        Row: RefreshJobRow;
        Insert: Omit<
          RefreshJobRow,
          | "id"
          | "status"
          | "claimed_by"
          | "claimed_at"
          | "lease_expires_at"
          | "attempts"
          | "last_error"
          | "result"
          | "created_at"
          | "updated_at"
          | "completed_at"
        > & {
          id?: string;
          status?: RefreshJobStatus;
          claimed_by?: string | null;
          claimed_at?: string | null;
          lease_expires_at?: string | null;
          attempts?: number;
          last_error?: string | null;
          result?: JsonValue | null;
          created_at?: string;
          updated_at?: string;
          completed_at?: string | null;
        };
        Update: Partial<RefreshJobRow>;
        Relationships: never[];
      };
      work_sessions: {
        Row: WorkSessionRow;
        Insert: Omit<WorkSessionRow, "id" | "created_at"> & {
          id?: string;
          created_at?: string;
        };
        Update: never;
        Relationships: never[];
      };
      route_compilations: {
        Row: RouteCompilationRow;
        Insert: Omit<RouteCompilationRow, "id" | "created_at" | "updated_at"> & {
          id?: string;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<
          Pick<RouteCompilationRow, "status" | "plan_payload" | "expires_at" | "updated_at">
        >;
        Relationships: never[];
      };
      route_compile_quotas: {
        Row: RouteCompileQuotaRow;
        Insert: Omit<RouteCompileQuotaRow, "attempts" | "updated_at"> & {
          attempts?: number;
          updated_at?: string;
        };
        Update: Partial<Pick<RouteCompileQuotaRow, "attempts" | "updated_at">>;
        Relationships: never[];
      };
    };
    // Required by @supabase/postgrest-js GenericSchema — keep empty if unused.
    Views: Record<string, never>;
    Functions: {
      upsert_place_identity: {
        Args: {
          p_provider: string;
          p_external_id: string;
          p_canonical_name: string;
          p_longitude: number;
          p_latitude: number;
          p_basic_category?: string | null;
          p_identity_confidence?: number;
          p_metadata?: JsonValue | null;
        };
        Returns: PlaceRow;
      };
      claim_refresh_jobs: {
        Args: {
          p_worker: string;
          p_batch_size?: number;
          p_lease_seconds?: number;
        };
        Returns: RefreshJobRow[];
      };
      consume_route_compile_quota: {
        Args: {
          p_user_id: string;
          p_limit?: number;
        };
        Returns: boolean;
      };
    };
  };
}

// ─── Client factory ────────────────────────────────────────────────────────────

function requireEnv(key: string): string {
  const v = process.env[key];
  if (!v) throw new Error(`Missing required env var: ${key}`);
  return v;
}

/** Anon client — subject to RLS. Use in web/bot request handlers. */
export function createAnonClient() {
  return createClient<Database>(requireEnv("SUPABASE_URL"), requireEnv("SUPABASE_KEY"));
}

/** Service-role client — bypasses RLS. Use only in server-side scripts. */
export function createServiceClient() {
  return createClient<Database>(
    requireEnv("SUPABASE_URL"),
    requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
  );
}

// ─── Row ↔ Domain mappers ──────────────────────────────────────────────────────

export function rowToExperience(row: ExperienceRow): Experience {
  return {
    id: row.id as ExperienceId,
    title: row.title,
    oneLiner: row.one_liner,
    whyItMatters: row.why_it_matters,
    category: row.category as Experience["category"],
    location: {
      coordinates: row.location.coordinates as [number, number],
      cityCode: row.city_code,
      addressHint: row.address_hint ?? undefined,
      placeNameLocal: row.place_name_local ?? undefined,
      placeNameRomanized: row.place_name_romanized ?? undefined,
    },
    bestTimes: row.best_times as Experience["bestTimes"],
    durationMinutes: { min: row.duration_min, max: row.duration_max },
    howTo: row.how_to as Experience["howTo"],
    realInconveniences: row.real_inconveniences as Experience["realInconveniences"],
    soloScore: row.solo_score as Experience["soloScore"],
    sources: row.sources as Experience["sources"],
    confidence: row.confidence as Experience["confidence"],
    nearbyExperienceIds: row.nearby_experience_ids as ExperienceId[],
    stats: {
      completionCount: row.completion_count,
      averageRating: Number(row.average_rating),
      lastCompletedAt: row.last_completed_at ?? undefined,
    },
    status: row.status as Experience["status"],
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}
