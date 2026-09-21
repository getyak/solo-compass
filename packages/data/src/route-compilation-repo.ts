import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database, RouteCompilationRow, RouteCompilationStatus } from "./db";
import type { JsonValue } from "./evidence";

export interface PutRouteCompilationInput {
  readonly userId: string;
  readonly cacheKey: string;
  readonly requestFingerprint: string;
  readonly inputFingerprint: string;
  readonly status: RouteCompilationStatus;
  readonly planPayload: JsonValue;
  readonly expiresAt: string;
}

/** Server-side persistence boundary for deterministic route compiler output. */
export class RouteCompilationRepo {
  constructor(private readonly client: SupabaseClient<Database>) {}

  async findFresh(
    userId: string,
    cacheKey: string,
    now = new Date().toISOString(),
  ): Promise<RouteCompilationRow | null> {
    const { data, error } = await this.client
      .from("route_compilations")
      .select("*")
      .eq("user_id", requiredText(userId, "userId"))
      .eq("cache_key", requiredText(cacheKey, "cacheKey"))
      .gt("expires_at", validTimestamp(now, "now"))
      .maybeSingle();
    if (error) throw new Error(`findFresh route compilation failed: ${error.message}`);
    return data;
  }

  async put(input: PutRouteCompilationInput): Promise<RouteCompilationRow> {
    const row: Database["public"]["Tables"]["route_compilations"]["Insert"] = {
      user_id: requiredText(input.userId, "userId"),
      cache_key: requiredText(input.cacheKey, "cacheKey"),
      request_fingerprint: requiredText(input.requestFingerprint, "requestFingerprint"),
      input_fingerprint: requiredText(input.inputFingerprint, "inputFingerprint"),
      status: input.status,
      plan_payload: input.planPayload,
      expires_at: validTimestamp(input.expiresAt, "expiresAt"),
      updated_at: new Date().toISOString(),
    };
    const { data, error } = await this.client
      .from("route_compilations")
      .upsert(row, { onConflict: "user_id,cache_key" })
      .select("*")
      .single();
    if (error) throw new Error(`put route compilation failed: ${error.message}`);
    return data;
  }

  async consumeQuota(userId: string, limit = 30): Promise<boolean> {
    if (!Number.isInteger(limit) || limit < 1 || limit > 1_000) {
      throw new Error("route compilation quota limit must be an integer from 1 through 1000");
    }
    const { data, error } = await this.client.rpc("consume_route_compile_quota", {
      p_user_id: requiredText(userId, "userId"),
      p_limit: limit,
    });
    if (error) throw new Error(`consume route compilation quota failed: ${error.message}`);
    return data;
  }

  async pruneExpired(before = new Date().toISOString()): Promise<number> {
    const { data, error } = await this.client
      .from("route_compilations")
      .delete()
      .lt("expires_at", validTimestamp(before, "before"))
      .select("id");
    if (error) throw new Error(`prune route compilations failed: ${error.message}`);
    const quotas = await this.client
      .from("route_compile_quotas")
      .delete()
      .lt("bucket_start", new Date(Date.parse(before) - 2 * 24 * 60 * 60 * 1_000).toISOString())
      .select("user_id");
    if (quotas.error) throw new Error(`prune route compile quotas failed: ${quotas.error.message}`);
    return (data?.length ?? 0) + (quotas.data?.length ?? 0);
  }
}

function requiredText(value: string, name: string): string {
  const normalized = value.trim();
  if (!normalized) throw new Error(`${name} must not be empty`);
  return normalized;
}

function validTimestamp(value: string, name: string): string {
  if (Number.isNaN(Date.parse(value))) throw new Error(`${name} must be an ISO timestamp`);
  return value;
}
