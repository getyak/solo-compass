/**
 * CompletionsRepo — anonymous-user check-ins.
 *
 * Phase-2 web flow: an opaque cookie ID identifies a "user". We store one
 * `users` row per cookie (handle = `anon_<short>`) and one `completions`
 * row per (user, experience).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Experience } from "@solo-compass/core";
import { rowToExperience, type Database, type ExperienceRow } from "./db";

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

export interface CompletionEntry {
  readonly experience: Experience;
  readonly completedAt: string;
  readonly rating: number | null;
  readonly note: string | null;
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
    const { data: userRow, error: userErr } = await (this.client as any)
      .from("users")
      .upsert({ handle }, { onConflict: "handle" })
      .select("id")
      .single();
    if (userErr || !userRow) throw new Error(`anon user upsert failed: ${userErr?.message}`);

    // Insert completion. Unique (user_id, experience_id) → handle conflict by update.
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

  /**
   * List recent completions for an anonymous cookie user, newest first.
   * Returns an empty array if the user has never checked in.
   */
  async listByAnonId(params: {
    readonly anonUserId: string;
    readonly limit?: number;
  }): Promise<readonly CompletionEntry[]> {
    const { anonUserId, limit = 100 } = params;
    const handle = `anon_${anonUserId.slice(0, 12)}`;

    // Resolve the anon user. If they've never checked in, the row won't exist.
    const { data: userRow, error: userErr } = await (this.client as any)
      .from("users")
      .select("id")
      .eq("handle", handle)
      .maybeSingle();
    if (userErr) throw new Error(`anon user lookup failed: ${userErr.message}`);
    if (!userRow) return [];

    // Join completions → experiences. PostgREST embedded select syntax.
    const { data, error } = await (this.client as any)
      .from("completions")
      .select("completed_at, rating, note, experience:experiences(*)")
      .eq("user_id", userRow.id)
      .order("completed_at", { ascending: false })
      .limit(limit);
    if (error) throw new Error(`completions list failed: ${error.message}`);

    const rows = (data ?? []) as Array<{
      completed_at: string;
      rating: number | null;
      note: string | null;
      experience: ExperienceRow | null;
    }>;

    const entries: CompletionEntry[] = [];
    for (const row of rows) {
      if (!row.experience) continue; // dangling completion → skip
      entries.push({
        experience: rowToExperience(row.experience),
        completedAt: row.completed_at,
        rating: row.rating,
        note: row.note,
      });
    }
    return entries;
  }
}
