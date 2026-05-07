/**
 * CompletionsRepo — anonymous-user check-ins.
 *
 * Phase-2 web flow: an opaque cookie ID identifies a "user". We store one
 * `users` row per cookie (handle = `anon_<short>`) and one `completions`
 * row per (user, experience).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database, CompletionRow, UserRow } from "./db";

export interface UserProfile {
  readonly id: string;
  readonly handle: string;
  readonly publicProfile: boolean;
  readonly createdAt: string;
}

export interface CompletionWithExperienceId {
  readonly id: string;
  readonly experienceId: string;
  readonly completedAt: string;
  readonly rating: number | null;
  readonly note: string | null;
}

export interface RecordCheckinParams {
  /** Opaque cookie ID — never a real identity. */
  readonly anonUserId: string;
  /** Experience that was completed. */
  readonly experienceId: string;
  /** Optional 1–5 rating. */
  readonly rating?: number;
}

export interface RecordCheckinResult {
  /** Whether a new completion was inserted (false = already existed). */
  readonly created: boolean;
}

export class CompletionsRepo {
  /** Service-role client — bypasses RLS so it can write `users` + `completions`. */
  constructor(private readonly client: SupabaseClient<Database>) {}

  /**
   * Insert a completion for an anonymous cookie user. Idempotent — re-running
   * for the same (anonUserId, experienceId) updates the rating in place.
   */
  async record(params: RecordCheckinParams): Promise<RecordCheckinResult> {
    const { anonUserId, experienceId, rating } = params;

    // Upsert anonymous user. The handle column is unique → use it as the key.
    const handle = `anon_${anonUserId.slice(0, 12)}`;
    // Supabase typed client's .upsert() chain resolves Insert type to `never`.
    // This is a known Supabase-js typing limitation — the runtime API works correctly.
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data: userRow, error: userErr } = await (this.client as any)
      .from("users")
      .upsert({ handle }, { onConflict: "handle" })
      .select("id")
      .single();
    if (userErr || !userRow) throw new Error(`anon user upsert failed: ${userErr?.message}`);

    // Insert completion. Unique (user_id, experience_id) → handle conflict by update.
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { error: insErr, count } = await (this.client as any).from("completions").upsert(
      {
        user_id: userRow.id,
        experience_id: experienceId,
        rating: rating ?? null,
      },
      { onConflict: "user_id,experience_id", ignoreDuplicates: false, count: "exact" },
    );
    if (insErr) throw new Error(`completion upsert failed: ${insErr.message}`);

    return { created: (count ?? 0) > 0 };
  }

  /** Look up a user by their display handle. Returns null if not found. */
  async getProfile(handle: string): Promise<UserProfile | null> {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data, error } = await (this.client as any)
      .from("users")
      .select("id, handle, public_profile, created_at")
      .eq("handle", handle)
      .maybeSingle();
    if (error) throw new Error(`getProfile failed: ${error.message}`);
    if (!data) return null;
    const row = data as UserRow;
    return {
      id: row.id,
      handle: row.handle,
      publicProfile: row.public_profile,
      createdAt: row.created_at,
    };
  }

  /** Fetch all completions for a user, optionally filtered to a city (by experience id prefix). */
  async findByHandle(handle: string, cityCode?: string): Promise<CompletionWithExperienceId[]> {
    const profile = await this.getProfile(handle);
    if (!profile) return [];

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    let query = (this.client as any)
      .from("completions")
      .select("id, experience_id, completed_at, rating, note")
      .eq("user_id", profile.id)
      .order("completed_at", { ascending: true });

    if (cityCode) {
      // Experience IDs follow the pattern exp_<cityCode>_<slug>
      query = query.like("experience_id", `exp_${cityCode}_%`);
    }

    const { data, error } = await query;
    if (error) throw new Error(`findByHandle failed: ${error.message}`);
    if (!data) return [];

    return (data as CompletionRow[]).map((row) => ({
      id: row.id,
      experienceId: row.experience_id,
      completedAt: row.completed_at,
      rating: row.rating,
      note: row.note,
    }));
  }
}
