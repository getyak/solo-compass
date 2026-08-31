import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database, WorkSessionFailureReason, WorkSessionOutcome, WorkSessionRow } from "./db";
import { FEATURE_KEYS, type FeatureKey, type JsonValue } from "./evidence";
import { EvidenceRepo, type AppendObservationInput } from "./evidence-repo";

export interface RecordWorkSessionInput {
  readonly userId: string;
  readonly experienceId: string;
  readonly placeId: string;
  readonly plannedTaskKind: string;
  readonly startedAt: string;
  readonly endedAt: string;
  readonly outcome: WorkSessionOutcome;
  readonly failureReason?: WorkSessionFailureReason;
  readonly placeWasOpen?: boolean;
  /** 1 (unreliable) through 5 (very reliable). */
  readonly wifiReliability?: number;
  /** 1 (quiet) through 5 (very noisy). */
  readonly noiseLevel?: number;
  readonly powerAvailable?: boolean;
  readonly videoCallWorked?: boolean;
  readonly longStayAccepted?: boolean;
  readonly minimumSpend?: { readonly amount: number; readonly currency: string };
  readonly idempotencyKey: string;
}

export interface RecordWorkSessionResult {
  readonly session: WorkSessionRow;
  readonly materializedFeatureKeys: readonly FeatureKey[];
}

export class WorkSessionRateLimitError extends Error {
  override readonly name = "WorkSessionRateLimitError";
}

export class WorkSessionValidationError extends Error {
  override readonly name = "WorkSessionValidationError";
}

const MAX_SESSIONS_PER_USER_PER_DAY = 12;

/** Server-side write boundary: stores the private session, then derives shared evidence. */
export class WorkSessionRepo {
  constructor(
    private readonly client: SupabaseClient<Database>,
    private readonly evidence: EvidenceRepo,
  ) {}

  async record(input: RecordWorkSessionInput): Promise<RecordWorkSessionResult> {
    const now = new Date();
    validateInput(input, now.getTime());
    const userId = requiredText(input.userId, "userId");
    const idempotencyKey = requiredText(input.idempotencyKey, "idempotencyKey");
    const replay = await this.client
      .from("work_sessions")
      .select("*")
      .eq("user_id", userId)
      .eq("idempotency_key", idempotencyKey)
      .maybeSingle();
    if (replay.error)
      throw new Error(`recordWorkSession replay lookup failed: ${replay.error.message}`);
    if (replay.data) return this.materialize(replay.data);

    const recent = await this.client
      .from("work_sessions")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .gte("created_at", new Date(now.getTime() - 24 * 60 * 60 * 1_000).toISOString());
    if (recent.error)
      throw new Error(`recordWorkSession rate lookup failed: ${recent.error.message}`);
    if ((recent.count ?? 0) >= MAX_SESSIONS_PER_USER_PER_DAY) {
      throw new WorkSessionRateLimitError("work session daily limit reached");
    }

    const row: Database["public"]["Tables"]["work_sessions"]["Insert"] = {
      user_id: userId,
      experience_id: requiredText(input.experienceId, "experienceId"),
      place_id: requiredText(input.placeId, "placeId"),
      planned_task_kind: requiredText(input.plannedTaskKind, "plannedTaskKind"),
      started_at: input.startedAt,
      ended_at: input.endedAt,
      outcome: input.outcome,
      failure_reason: input.failureReason ?? null,
      place_was_open: input.placeWasOpen ?? null,
      wifi_reliability: input.wifiReliability ?? null,
      noise_level: input.noiseLevel ?? null,
      power_available: input.powerAvailable ?? null,
      video_call_worked: input.videoCallWorked ?? null,
      long_stay_accepted: input.longStayAccepted ?? null,
      minimum_spend_amount: input.minimumSpend?.amount ?? null,
      minimum_spend_currency: input.minimumSpend?.currency.toUpperCase() ?? null,
      idempotency_key: idempotencyKey,
    };
    const inserted = await this.client
      .from("work_sessions")
      .upsert(row, { onConflict: "user_id,idempotency_key", ignoreDuplicates: true })
      .select("*")
      .maybeSingle();
    if (inserted.error) throw new Error(`recordWorkSession failed: ${inserted.error.message}`);
    let session = inserted.data;
    if (!session) {
      const existing = await this.client
        .from("work_sessions")
        .select("*")
        .eq("user_id", input.userId)
        .eq("idempotency_key", input.idempotencyKey)
        .single();
      if (existing.error) {
        throw new Error(`recordWorkSession lookup failed: ${existing.error.message}`);
      }
      session = existing.data;
    }

    return this.materialize(session);
  }

  private async materialize(session: WorkSessionRow): Promise<RecordWorkSessionResult> {
    const observations = deriveWorkSessionObservations(session);
    for (const observation of observations) await this.evidence.appendObservation(observation);
    const featureKeys = [...new Set(observations.map((observation) => observation.featureKey))];
    for (const featureKey of featureKeys) {
      await this.evidence.materializeFeature(session.place_id, featureKey);
    }
    return { session, materializedFeatureKeys: featureKeys };
  }
}

export function deriveWorkSessionObservations(session: WorkSessionRow): AppendObservationInput[] {
  const values = new Map<FeatureKey, JsonValue>();
  if (session.place_was_open !== null) {
    values.set(FEATURE_KEYS.openOnArrival, session.place_was_open);
  }
  if (session.wifi_reliability !== null) {
    values.set(FEATURE_KEYS.wifiReliability, session.wifi_reliability);
  }
  if (session.noise_level !== null) values.set(FEATURE_KEYS.noiseLevel, session.noise_level);
  if (session.power_available !== null) {
    values.set(FEATURE_KEYS.powerOutlets, session.power_available);
  }
  if (session.video_call_worked !== null) {
    values.set(FEATURE_KEYS.videoCallFit, session.video_call_worked);
  }
  if (session.long_stay_accepted !== null) {
    values.set(FEATURE_KEYS.longStayPolicy, session.long_stay_accepted);
  }
  if (session.minimum_spend_amount !== null && session.minimum_spend_currency !== null) {
    values.set(FEATURE_KEYS.minimumSpend, {
      amount: session.minimum_spend_amount,
      currency: session.minimum_spend_currency,
    });
  }
  addFailureSignal(values, session.failure_reason);

  const confidence =
    session.outcome === "completed"
      ? 0.95
      : session.outcome === "partially_completed"
        ? 0.85
        : 0.75;
  return [...values.entries()].map(([featureKey, value]) => ({
    placeId: session.place_id,
    featureKey,
    state: "observed" as const,
    value,
    confidence,
    // One traveler is one independent source even after repeated sessions.
    // The pseudonymous key prevents session spam from manufacturing consensus
    // without placing the raw user id into shared evidence.
    sourceWeight: 0.6,
    independenceKey: `work-session-user:${fnv1a(session.user_id)}`,
    timeScope: {
      plannedTaskKind: session.planned_task_kind,
      outcome: session.outcome,
    },
    observedAt: session.ended_at,
    extractorVersion: "work-session-signals-v1",
    dedupeKey: `work-session:${session.id}:${featureKey}:v1`,
  }));
}

function addFailureSignal(
  values: Map<FeatureKey, JsonValue>,
  reason: WorkSessionFailureReason | null,
): void {
  if (!reason) return;
  switch (reason) {
    case "place_closed":
      if (!values.has(FEATURE_KEYS.openOnArrival)) values.set(FEATURE_KEYS.openOnArrival, false);
      break;
    case "no_seat":
      values.set(FEATURE_KEYS.seatAvailability, false);
      break;
    case "wifi_unreliable":
      if (!values.has(FEATURE_KEYS.wifiReliability)) values.set(FEATURE_KEYS.wifiReliability, 1);
      break;
    case "too_noisy":
      if (!values.has(FEATURE_KEYS.noiseLevel)) values.set(FEATURE_KEYS.noiseLevel, 5);
      break;
    case "no_power":
      if (!values.has(FEATURE_KEYS.powerOutlets)) values.set(FEATURE_KEYS.powerOutlets, false);
      break;
    case "video_call_not_allowed":
      if (!values.has(FEATURE_KEYS.videoCallFit)) values.set(FEATURE_KEYS.videoCallFit, false);
      break;
    case "long_stay_pressure":
      if (!values.has(FEATURE_KEYS.longStayPolicy)) values.set(FEATURE_KEYS.longStayPolicy, false);
      break;
    case "minimum_spend":
    case "other":
      break;
  }
}

function validateInput(input: RecordWorkSessionInput, nowMs: number): void {
  const startedAt = Date.parse(input.startedAt);
  const endedAt = Date.parse(input.endedAt);
  if (!Number.isFinite(startedAt) || !Number.isFinite(endedAt)) {
    throw new WorkSessionValidationError("startedAt and endedAt must be valid ISO 8601 timestamps");
  }
  if (endedAt < startedAt || endedAt > startedAt + 24 * 60 * 60 * 1_000) {
    throw new WorkSessionValidationError("work session duration must be between 0 and 24 hours");
  }
  if (endedAt > nowMs + 5 * 60 * 1_000 || endedAt < nowMs - 7 * 24 * 60 * 60 * 1_000) {
    throw new WorkSessionValidationError(
      "endedAt must be within the last 7 days and not in the future",
    );
  }
  assertScale(input.wifiReliability, "wifiReliability");
  assertScale(input.noiseLevel, "noiseLevel");
  if (input.minimumSpend) {
    if (!Number.isFinite(input.minimumSpend.amount) || input.minimumSpend.amount < 0) {
      throw new WorkSessionValidationError("minimumSpend.amount cannot be negative");
    }
    if (!/^[A-Za-z]{3}$/.test(input.minimumSpend.currency)) {
      throw new WorkSessionValidationError("minimumSpend.currency must be an ISO 4217 code");
    }
  }
}

function fnv1a(value: string): string {
  let hash = 0x811c9dc5;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(16).padStart(8, "0");
}

function assertScale(value: number | undefined, label: string): void {
  if (value !== undefined && (!Number.isInteger(value) || value < 1 || value > 5)) {
    throw new WorkSessionValidationError(`${label} must be an integer from 1 through 5`);
  }
}

function requiredText(value: string, label: string): string {
  const trimmed = value.trim();
  if (!trimmed) throw new Error(`${label} is required`);
  return trimmed;
}
