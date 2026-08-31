import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database, RefreshJobRow } from "./db";
import type { FeatureKey, JsonValue } from "./evidence";
import {
  calculateRefreshPriority,
  makeRefreshIdempotencyKey,
  type RefreshPriorityInput,
  type RefreshReason,
} from "./refresh-policy";

export interface EnqueueRefreshInput extends RefreshPriorityInput {
  readonly placeId?: string;
  readonly featureKeys: readonly FeatureKey[];
  readonly query?: JsonValue;
  readonly reason: RefreshReason;
  readonly providerHint?: string;
  readonly budgetClass: string;
  readonly notBefore?: string;
  readonly maxAttempts?: number;
  readonly bucketSeconds?: number;
  readonly now?: string;
}

/** Durable queue boundary. Claiming is atomic through a SKIP LOCKED RPC. */
export class RefreshQueueRepo {
  constructor(private readonly client: SupabaseClient<Database>) {}

  async enqueue(input: EnqueueRefreshInput): Promise<RefreshJobRow> {
    const now = input.now ?? new Date().toISOString();
    const idempotencyKey = makeRefreshIdempotencyKey({
      placeId: input.placeId,
      featureKeys: input.featureKeys,
      reason: input.reason,
      bucketSeconds: input.bucketSeconds,
      now,
    });
    const priority = calculateRefreshPriority(input);
    const row: Database["public"]["Tables"]["refresh_jobs"]["Insert"] = {
      place_id: input.placeId ?? null,
      feature_keys: [...new Set(input.featureKeys)].sort(),
      query: input.query ?? null,
      reason: input.reason,
      urgency: input.urgency,
      priority,
      provider_hint: input.providerHint ?? null,
      budget_class: requiredText(input.budgetClass, "budgetClass"),
      idempotency_key: idempotencyKey,
      demand_score: input.demandScore,
      decision_impact: input.decisionImpact,
      uncertainty: input.uncertainty,
      staleness: input.staleness,
      estimated_cost: input.estimatedCost,
      not_before: input.notBefore ?? now,
      max_attempts: input.maxAttempts ?? 5,
    };
    const insert = await this.client
      .from("refresh_jobs")
      .upsert(row, { onConflict: "idempotency_key", ignoreDuplicates: true })
      .select("*")
      .maybeSingle();
    if (insert.error) throw new Error(`enqueue refresh failed: ${insert.error.message}`);
    if (insert.data) return insert.data;

    const existing = await this.client
      .from("refresh_jobs")
      .select("*")
      .eq("idempotency_key", idempotencyKey)
      .single();
    if (existing.error) throw new Error(`enqueue refresh lookup failed: ${existing.error.message}`);
    return existing.data;
  }

  async claim(worker: string, batchSize = 10, leaseSeconds = 120): Promise<RefreshJobRow[]> {
    const { data, error } = await this.client.rpc("claim_refresh_jobs", {
      p_worker: requiredText(worker, "worker"),
      p_batch_size: Math.max(1, Math.min(100, Math.trunc(batchSize))),
      p_lease_seconds: Math.max(30, Math.trunc(leaseSeconds)),
    });
    if (error) throw new Error(`claim refresh jobs failed: ${error.message}`);
    return data ?? [];
  }

  async succeed(jobId: string, worker: string, result?: JsonValue): Promise<RefreshJobRow> {
    const { data, error } = await this.client
      .from("refresh_jobs")
      .update({
        status: "succeeded",
        completed_at: new Date().toISOString(),
        lease_expires_at: null,
        result: result ?? null,
      })
      .eq("id", jobId)
      .eq("claimed_by", worker)
      .eq("status", "running")
      .select("*")
      .maybeSingle();
    if (error) throw new Error(`complete refresh job failed: ${error.message}`);
    if (!data) throw new Error("complete refresh job failed: lease is no longer owned by worker");
    return data;
  }

  async fail(jobId: string, worker: string, cause: unknown): Promise<RefreshJobRow> {
    const current = await this.client
      .from("refresh_jobs")
      .select("*")
      .eq("id", jobId)
      .eq("claimed_by", worker)
      .eq("status", "running")
      .maybeSingle();
    if (current.error)
      throw new Error(`load refresh job for retry failed: ${current.error.message}`);
    if (!current.data)
      throw new Error("fail refresh job failed: lease is no longer owned by worker");
    const deadLetter = current.data.attempts >= current.data.max_attempts;
    const retryDelaySeconds = Math.min(60 * 60, 30 * 2 ** Math.max(0, current.data.attempts - 1));
    const update: Database["public"]["Tables"]["refresh_jobs"]["Update"] = {
      status: deadLetter ? "dead_letter" : "queued",
      claimed_by: null,
      claimed_at: null,
      lease_expires_at: null,
      last_error: errorMessage(cause),
      not_before: deadLetter
        ? current.data.not_before
        : new Date(Date.now() + retryDelaySeconds * 1000).toISOString(),
      completed_at: deadLetter ? new Date().toISOString() : null,
    };
    const result = await this.client
      .from("refresh_jobs")
      .update(update)
      .eq("id", jobId)
      .eq("claimed_by", worker)
      .eq("status", "running")
      .select("*")
      .maybeSingle();
    if (result.error) throw new Error(`fail refresh job failed: ${result.error.message}`);
    if (!result.data) throw new Error("fail refresh job failed: lease changed during update");
    return result.data;
  }
}

function errorMessage(cause: unknown): string {
  const value = cause instanceof Error ? cause.message : String(cause);
  return value.slice(0, 2_000);
}

function requiredText(value: string, label: string): string {
  const trimmed = value.trim();
  if (!trimmed) throw new Error(`${label} is required`);
  return trimmed;
}
