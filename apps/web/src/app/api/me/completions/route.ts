/**
 * GET /api/me/completions
 *
 * Returns the current anon cookie user's check-in history, newest first.
 * Empty array when the cookie is absent (= never checked in).
 *
 * Falls back to `{ entries: [] }` when SUPABASE_* env is missing (local dev).
 */

import { NextResponse } from "next/server";
import type { CompletionEntry } from "@solo-compass/data";
import { readAnonId } from "@/lib/anon-cookie";
import { getCompletionsRepo } from "@/lib/repos";
import { DEV_FALLBACK_EXPERIENCES } from "@/lib/dev-fallback";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export interface CompletionsResponse {
  readonly entries: readonly CompletionEntry[];
}

export async function GET(): Promise<NextResponse<CompletionsResponse | { error: string }>> {
  const anonId = await readAnonId();
  if (!anonId) {
    return NextResponse.json({ entries: [] });
  }

  try {
    const repo = getCompletionsRepo();
    const entries = await repo.listByAnonId({ anonUserId: anonId, limit: 100 });
    return NextResponse.json({ entries });
  } catch (err) {
    const missingEnv =
      err instanceof Error && err.message.includes("Invalid server environment configuration");
    if (missingEnv) {
      return NextResponse.json({ entries: buildDevTimeline() });
    }
    // eslint-disable-next-line no-console
    console.error("listByAnonId failed", err);
    return NextResponse.json({ error: "completions lookup failed" }, { status: 502 });
  }
}

/**
 * Build a synthetic footprint timeline anchored to *now* so every recency
 * bucket (Today / This week / Last week / Earlier this month) gets at least
 * one entry. Dev-only — only the missingEnv branch calls this.
 */
function buildDevTimeline(): CompletionEntry[] {
  const exps = DEV_FALLBACK_EXPERIENCES;
  if (exps.length === 0) return [];
  const now = Date.now();
  const HOUR = 3_600_000;
  const DAY = 24 * HOUR;
  // Offsets chosen to land entries in each visual bucket regardless of which
  // weekday the viewer opens the page.
  const offsets: ReadonlyArray<{ ms: number; rating: number | null; note: string | null }> = [
    { ms: 2 * HOUR, rating: 5, note: "Came back twice." },
    { ms: 1 * DAY + 4 * HOUR, rating: 4, note: null },
    { ms: 3 * DAY, rating: null, note: "Will return at sunset." },
    { ms: 9 * DAY, rating: 3, note: null },
    { ms: 12 * DAY, rating: 4, note: "Quiet on a Tuesday." },
    { ms: 22 * DAY, rating: 5, note: null },
    { ms: 40 * DAY, rating: null, note: null },
  ];
  const entries: CompletionEntry[] = [];
  for (let i = 0; i < offsets.length && i < exps.length; i++) {
    const o = offsets[i]!;
    const exp = exps[i]!;
    entries.push({
      experience: exp,
      completedAt: new Date(now - o.ms).toISOString(),
      rating: o.rating,
      note: o.note,
    });
  }
  return entries;
}
